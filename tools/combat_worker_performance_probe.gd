## Measures real application worker handoff and input in an isolated rendered fixture.
extends SceneTree

class IncompleteSession:
	extends GameSession
	func submit_intent(_intent: PlayerIntent) -> SessionStep: return null

var _application: RealmzApplication
var _compositor: DisplayCompositor
var _session: GameSessionController
var _completed: CombatSessionJob
var _commits := 0
var _failures: Array[String] = []
var _measuring := false
var _last_frame := 0
var _max_frame_us := 0
var _quit_requests := 0


func _initialize() -> void:
	call_deferred("_run")


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _measuring and _last_frame > 0: _max_frame_us = maxi(_max_frame_us, now - _last_frame)
	_last_frame = now
	return false


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		printerr("Supply an absolute fixture config, native battle ID and new absolute output directory.")
		quit(2)
		return
	var config := FileAccess.open(args[0], FileAccess.READ)
	var request := RuntimeTestingFixtureRequest.decode(JSON.parse_string(config.get_as_text())) if config != null else null
	if request == null or not args[2].is_absolute_path() or DirAccess.dir_exists_absolute(args[2]):
		printerr("Invalid isolated fixture or existing output directory.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(args[2])
	_compositor = load("res://src/ui/shared/display_compositor.tscn").instantiate() as DisplayCompositor
	_compositor.get_node("Content/StartupFrontDoor").free()
	root.add_child(_compositor)
	await process_frame
	_application = load("res://src/ui/shell/realmz_application.tscn").instantiate() as RealmzApplication
	_application.set_meta(&"runtime_testing_fixture", request)
	_application.set_meta(&"startup_splash_suppressed", true)
	_application.set_meta(&"startup_front_door_revealed", true)
	_application.configure_lifecycle_host(null, func() -> void: _quit_requests += 1)
	DisplayServer.window_set_title("Realmz Rebuilt — TEST FIXTURE %s — Combat responsiveness" % request.fixture_id.left(8))
	_compositor.source_viewport().add_child(_application)
	_session = _application.session_controller
	_session.combat_work_completed.connect(func(job: CombatSessionJob) -> void: _completed = job)
	_session.step_committed.connect(func(_step: SessionStep) -> void: _commits += 1)
	if OS.get_environment("REALMZ_COMBAT_PROFILE") == "1":
		_profile_signal(_session.step_committed)
		_profile_signal(_session.combat_work_completed)
	var deadline := Time.get_ticks_msec() + 60000
	while not _application.character_files.library_ready() and Time.get_ticks_msec() < deadline: await process_frame
	_check(_application.character_files.library_ready(), "application library ready")
	var step := _session.apply_debug_command(SessionDebugCommand.start_battle(args[1].to_int()))
	_check(step.state != SessionStep.State.FAILED, "direct fixture battle: " + step.error_message)
	_application.presentation_coordinator.skip_combat_playback()
	await _settle()
	var initial := _session.session().snapshot()
	_check(initial != null and initial.game_state.combat != null, "combat snapshot")
	if initial == null or initial.game_state.combat == null:
		_finish(args[2], [])
		return
	var content := _application.get("_active_content") as RealmzContent
	var samples: Array[Dictionary] = []
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(800, 600)]:
		DisplayServer.window_set_size(size)
		root.size = size
		await _settle()
		for sample: int in range(7):
			_session.restore(content, initial)
			_application.presentation_coordinator.skip_combat_playback()
			await _settle()
			var actor := _session.view().combat_view.active_actor_id
			var intent := CombatIntents.choose_action(&"auto", actor)
			var response := InteractionResponse.new(_session.view().active_interaction_request().request_id, InteractionRequest.COMBAT, InteractionResponse.CombatBody.new(&"auto", actor))
			var baseline := GameSession.new()
			_check(baseline.restore(content, initial).state != SessionStep.State.FAILED, "synchronous restore")
			var expected_step := baseline.respond(response) if baseline.view().pending_interaction != null else baseline.submit_intent(intent)
			_check(expected_step.state != SessionStep.State.FAILED, "ordinary Auto command: " + expected_step.error_message)
			var expected := _outcome(baseline, expected_step)
			_completed = null
			var prior_view := _session.view()
			var prior_commits := _commits
			_max_frame_us = 0
			_last_frame = Time.get_ticks_usec()
			_measuring = true
			var started := Time.get_ticks_usec()
			_application.submit_response(response)
			var submit_us := Time.get_ticks_usec() - started
			_check(_session.is_busy() and _session.session() == null and _session.view() == prior_view, "exclusive worker and retained view")
			_check(not _session.enqueue_intent(intent).accepted(), "duplicate rejected")
			_check(_commits == prior_commits, "acceptance does not publish")
			deadline = Time.get_ticks_msec() + 10000
			while _session.is_busy() and Time.get_ticks_msec() < deadline: await process_frame
			await process_frame
			await process_frame
			_measuring = false
			_check(_completed != null and _commits == prior_commits + 1, "exactly one completion")
			_check(_completed != null and CanonicalJson.encode(expected) == CanonicalJson.encode(_outcome(_session.session(), _completed.step)), "complete sync/worker outcome")
			if _completed != null:
				samples.append({"size": [size.x, size.y], "sample": sample, "submissionMs": submit_us / 1000.0, "transactionMs": _completed.transaction_usec / 1000.0, "projectionMs": _completed.projection_usec / 1000.0, "publicationMs": _completed.publication_usec / 1000.0, "deferredProjectionMs": _completed.deferred_projection_usec / 1000.0, "maximumFrameMs": _max_frame_us / 1000.0})
			_check(submit_us < 50000 and _max_frame_us < 50000, "main-thread decision budget")
			_application.presentation_coordinator.skip_combat_playback()
			await _settle()
		await _escape_probe(content, initial, size, samples)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[2].path_join("combat-%dx%d.png" % [size.x, size.y]))
	await _continuous_auto_probe(content, initial, samples)
	await _initial_enable_escape_probe(content, initial)
	await _failure_probe()
	await _lifecycle_probe(content, initial)
	_finish(args[2], samples)


func _escape_probe(content: RealmzContent, initial: SessionSnapshot, size: Vector2i, samples: Array[Dictionary]) -> void:
	_session.restore(content, initial)
	_application.presentation_coordinator.skip_combat_playback()
	await _settle()
	var review := (_application.get_node("InteractionPanel") as InteractionPresenter).combat_log
	review.open()
	for character: CharacterView in _session.view().party_members:
		_session.submit_intent(CombatIntents.set_auto(character.id, true))
	_application.presentation_coordinator.skip_combat_playback()
	var actor := _session.view().combat_view.active_actor_id
	var response := InteractionResponse.new(_session.view().active_interaction_request().request_id, InteractionRequest.COMBAT, InteractionResponse.CombatBody.new(&"auto", actor))
	var baseline := GameSession.new()
	baseline.restore(content, initial)
	for character: CharacterView in _session.view().party_members:
		baseline.submit_intent(CombatIntents.set_auto(character.id, true))
	var expected_step := baseline.respond(response) if baseline.view().pending_interaction != null else baseline.submit_intent(CombatIntents.choose_action(&"auto", actor))
	var expected_events := expected_step.events.duplicate()
	var ids := _session.view().combat_view.auto_character_ids.duplicate()
	ids.sort()
	for id: String in ids:
		expected_step = baseline.submit_intent(CombatIntents.set_auto(id, false))
		expected_events.append_array(expected_step.events)
	expected_step.events = expected_events
	var actual_events: Array[DomainEvent] = []
	var record := func(step: SessionStep) -> void: actual_events.append_array(step.events)
	_session.step_committed.connect(record)
	await _settle()
	review.close()
	_max_frame_us = 0
	_last_frame = Time.get_ticks_usec()
	_measuring = true
	_application.submit_response(response)
	_check(_session.is_busy(), "Escape during resolution")
	var labels := _application.find_children("*", "Label", true, false)
	var started := Time.get_ticks_usec()
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	_compositor.source_viewport().push_input(event, true)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	_compositor.source_viewport().push_input(event, true)
	var acknowledged := labels.any(func(label: Node) -> bool: return (label as Label).text.begins_with("Full-party Auto cancelled."))
	await RenderingServer.frame_post_draw
	var ack_us := Time.get_ticks_usec() - started
	_check(acknowledged and ack_us < 100000, "actual Escape acknowledgement")
	while _session.is_busy(): await process_frame
	while (_application.get_node("InteractionPanel") as InteractionPresenter).combat_mount_pending: await process_frame
	await process_frame
	await process_frame
	_measuring = false
	_check(_max_frame_us < 50000, "queued Auto handoff frame budget")
	_session.step_committed.disconnect(record)
	_check(_session.view().combat_view.auto_character_ids.is_empty(), "queued Auto cleared before next activation")
	var actual_step := SessionStep.completed(_session.view().revision, actual_events)
	actual_step.state = expected_step.state
	_check(CanonicalJson.encode(_outcome(baseline, expected_step)) == CanonicalJson.encode(_outcome(_session.session(), actual_step)), "queued toggles preserve sequential outcomes")
	samples.append({"size": [size.x, size.y], "escapeAckMs": ack_us / 1000.0, "escapeMaximumFrameMs": _max_frame_us / 1000.0, "acknowledged": acknowledged})
	_application.presentation_coordinator.skip_combat_playback()
	await _settle()


func _continuous_auto_probe(content: RealmzContent, initial: SessionSnapshot, samples: Array[Dictionary]) -> void:
	_session.restore(content, initial)
	_application.presentation_coordinator.set_reduced_motion(true)
	await _settle()
	var counts: Dictionary = {}
	var events: Array[Dictionary] = []
	var record := func(step: SessionStep) -> void:
		_check(step.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_auto_started").size() <= 1, "queued Auto yields after each activation")
		for event: DomainEvent in step.events:
			counts[String(event.kind)] = int(counts.get(String(event.kind), 0)) + 1
			events.append(event.to_data())
	_session.step_committed.connect(record)
	for character: CharacterView in _session.view().party_members:
		_application.submit_intent(CombatIntents.set_auto(character.id, true))
	_check(_session.is_busy(), "initial roster Auto starts on worker")
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline and int(counts.get("combat_auto_completed", 0)) < 12:
		var combat := _session.view().combat_view
		if combat == null or combat.outcome != &"active": break
		await process_frame
	_application.abort_full_party_auto(true)
	while _session.is_busy(): await process_frame
	_application.presentation_coordinator.skip_combat_playback()
	await _settle()
	_session.step_committed.disconnect(record)
	var final_combat := _session.view().combat_view
	var terminal := final_combat == null or final_combat.outcome != &"active"
	_check(terminal or int(counts.get("combat_auto_completed", 0)) >= 12, "continuous Auto advances twelve activations or completes battle")
	_check(int(counts.get("combat_attack_resolved", 0)) + int(counts.get("combat_spell_cast", 0)) > 0, "continuous Auto performs attacks or spells")
	_check(not _session.resolution_failed, "continuous Auto stays executable")
	samples.append({"continuousAuto": counts, "round": final_combat.round_number if final_combat != null else -1, "terminal": terminal, "orderedEvents": events})
	_application.presentation_coordinator.set_reduced_motion(false)


func _initial_enable_escape_probe(content: RealmzContent, initial: SessionSnapshot) -> void:
	_session.restore(content, initial)
	_application.presentation_coordinator.skip_combat_playback()
	await _settle()
	var actor := _session.view().combat_view.active_actor_id
	var invalid_batch: Array[PlayerIntent] = [CombatIntents.set_auto(actor, true), CombatIntents.set_auto(actor, true)]
	_check(not _session.enqueue_auto_changes(invalid_batch).accepted(), "multi-enable batch rejected")
	var baseline := GameSession.new()
	baseline.restore(content, initial)
	var expected := baseline.submit_intent(CombatIntents.set_auto(actor, true))
	var expected_events := expected.events.duplicate()
	expected = baseline.submit_intent(CombatIntents.set_auto(actor, false))
	expected_events.append_array(expected.events)
	expected.events = expected_events
	var actual_events: Array[DomainEvent] = []
	var record := func(step: SessionStep) -> void: actual_events.append_array(step.events)
	_session.step_committed.connect(record)
	_application.submit_intent(CombatIntents.set_auto(actor, true))
	_check(_session.is_busy() and _session.view().combat_view.auto_character_ids.is_empty(), "initial enable remains uncommitted")
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	_compositor.source_viewport().push_input(event, true)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	_compositor.source_viewport().push_input(event, true)
	while _session.is_busy(): await process_frame
	while (_application.get_node("InteractionPanel") as InteractionPresenter).combat_mount_pending: await process_frame
	_session.step_committed.disconnect(record)
	_check(_session.view().combat_view.auto_character_ids.is_empty(), "Escape cancels in-flight initial enable")
	var actual := SessionStep.completed(_session.view().revision, actual_events)
	actual.state = expected.state
	_check(CanonicalJson.encode(_outcome(baseline, expected)) == CanonicalJson.encode(_outcome(_session.session(), actual)), "initial enable cancellation preserves complete outcome")
	_application.presentation_coordinator.skip_combat_playback()
	await _settle()


func _outcome(session: GameSession, step: SessionStep) -> Dictionary:
	if session == null or step == null: return {}
	var snapshot := session.snapshot()
	var events: Array[Dictionary] = []
	for event: DomainEvent in step.events: events.append(event.to_data())
	return {"snapshot": SaveEnvelope.from_snapshot(snapshot).to_data() if snapshot != null else null, "events": events, "rngTrace": session.rng_trace(), "scenarioTrace": session.scenario_trace(), "state": step.state, "error": String(step.error_code)}


func _failure_probe() -> void:
	var controller := GameSessionController.new()
	root.add_child(controller)
	controller.replace_session(IncompleteSession.new())
	var retained := controller.view()
	var command := CombatIntents.choose_action(&"auto", "fixture")
	_check(controller.enqueue_intent(command).accepted(), "incomplete-job submission")
	while controller.is_busy():
		controller.poll_combat_work()
		await process_frame
	_check(controller.resolution_failed and controller.session() == null and controller.view() == retained, "incomplete result quarantines session")
	_check(not controller.enqueue_intent(command).accepted(), "quarantine rejects new work")
	_check(controller.close().state == SessionStep.State.COMPLETED and not controller.view().session_started, "quarantined adventure can close")
	controller.replace_session(GameSession.new())
	_check(not controller.resolution_failed and controller.session() != null, "replacement releases quarantine")
	_check(controller.enqueue_intent(command).accepted(), "shutdown with outstanding job")
	controller.shutdown_worker()
	_check(not controller.is_busy(), "shutdown joins outstanding job")
	controller.queue_free()
	await process_frame


func _lifecycle_probe(content: RealmzContent, initial: SessionSnapshot) -> void:
	_session.restore(content, initial)
	_application.presentation_coordinator.skip_combat_playback()
	await _settle()
	var actor := _session.view().combat_view.active_actor_id
	var response := InteractionResponse.new(_session.view().active_interaction_request().request_id, InteractionRequest.COMBAT, InteractionResponse.CombatBody.new(&"auto", actor))
	_application.submit_response(response)
	_application.lifecycle_host.request_quit()
	_application.submit_response(InteractionResponse.new(ApplicationLifecycle.QUIT_APPLICATION_REQUEST_ID, InteractionRequest.SESSION_LIFECYCLE, InteractionResponse.LifecycleBody.new(ApplicationLifecycle.CANCEL)))
	_check(not _application.lifecycle_host.has_active_interaction() and _quit_requests == 0, "cancel pending quit")
	_application.lifecycle_host.request_quit()
	while _session.is_busy(): await process_frame
	_check(_application.lifecycle_host.has_active_interaction(), "completion retains lifecycle ownership")
	var presenter := _application.get_node("InteractionPanel") as InteractionPresenter
	var visible_request := presenter.get("_request") as InteractionRequest
	_check(visible_request != null and visible_request.request_id == ApplicationLifecycle.QUIT_APPLICATION_REQUEST_ID, "completion retains visible lifecycle prompt")
	_application.submit_response(InteractionResponse.new(ApplicationLifecycle.QUIT_APPLICATION_REQUEST_ID, InteractionRequest.SESSION_LIFECYCLE, InteractionResponse.LifecycleBody.new(ApplicationLifecycle.CANCEL)))
	_application.presentation_coordinator.skip_combat_playback()
	_session.restore(content, initial)
	_application.submit_response(response)
	_application.submit_intent(CombatIntents.set_auto(_session.view().party_members[1].id, true))
	var commits_before_quit := _commits
	_application.lifecycle_host.request_quit()
	_application.submit_response(InteractionResponse.new(ApplicationLifecycle.QUIT_APPLICATION_REQUEST_ID, InteractionRequest.SESSION_LIFECYCLE, InteractionResponse.LifecycleBody.new(ApplicationLifecycle.QUIT_WITHOUT_SAVING)))
	_check(_quit_requests == 0 and _session.is_busy(), "quit waits for transaction")
	while _session.is_busy(): await process_frame
	await process_frame
	_check(_quit_requests == 1, "deferred quit commits once")
	_check(_commits == commits_before_quit + 1, "quit precedes queued Auto activation")


func _settle() -> void:
	for frame: int in range(20): await process_frame


func _check(condition: bool, detail: String) -> void:
	if not condition:
		_failures.append(detail)
		printerr("COMBAT_WORKER_CHECK_FAILED: " + detail)


func _profile_signal(target: Signal) -> void:
	for connection: Dictionary in target.get_connections():
		var callback: Callable = connection["callable"]
		target.disconnect(callback)
		target.connect(func(value: Variant) -> void:
			var started := Time.get_ticks_usec()
			callback.call(value)
			print("COMBAT_SIGNAL_COST %s %.3f" % [callback, (Time.get_ticks_usec() - started) / 1000.0])
		)


func _finish(output: String, samples: Array[Dictionary]) -> void:
	var result := {"renderer": RenderingServer.get_current_rendering_method(), "samples": samples, "failures": _failures}
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t", true, true))
	file.close()
	var summary := result.duplicate(true)
	for sample: Dictionary in summary["samples"]: sample.erase("orderedEvents")
	print("COMBAT_WORKER_RESULT " + JSON.stringify(summary))
	_completed = null
	_session.shutdown_worker()
	_application.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)
