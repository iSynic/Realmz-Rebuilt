extends SceneTree

var _failures: Array[String] = []
var _stages: Array[Dictionary] = []
var _observed_battles: Array[int] = []
var _content: RealmzContent
var _session: GameSession


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 3:
		printerr("Usage: godot --headless --path <project> --script res://tools/route_acceptance.gd -- <package.realmz2> <route.json> <report.json>")
		call_deferred("_quit_cleanly", 2)
		return
	var package_path: String = arguments[0]
	var route_path: String = arguments[1]
	var report_path: String = arguments[2]
	var route: Variant = _read_json(route_path)
	if route == null:
		printerr("ROUTE_REJECTED invalid route document")
		call_deferred("_quit_cleanly", 1)
		return
	var loaded := PackageRepository.new().load_package(package_path)
	if not loaded.is_ok():
		printerr("PACKAGE_REJECTED %s: %s" % [loaded.error_code, loaded.error_message])
		call_deferred("_quit_cleanly", 1)
		return
	_content = loaded.content
	_session = GameSession.new()
	var started := _session.start(_content, 1)
	if started.state == SessionStep.State.FAILED:
		printerr("SESSION_REJECTED %s: %s" % [started.error_code, started.error_message])
		call_deferred("_quit_cleanly", 1)
		return
	_prepare_party()
	_validate_route_header(route)
	for entry: Variant in route.get("steps", []):
		if not entry is Dictionary:
			_fail("route contains a non-object step")
			continue
		_run_step(entry)
	_validate_completion(route.get("completionAnchor", {}))
	var report := {
		"schemaVersion": 1,
		"routeId": String(route.get("routeId", "")),
		"campaignId": _content.campaign_id,
		"packageHash": _content.package_hash,
		"routeSha256": FileAccess.get_sha256(route_path),
		"status": "passed" if _failures.is_empty() else "failed",
		"stages": _stages,
		"failures": _failures,
		"observedBattleIds": _observed_battles,
		"finalState": _final_state(),
	}
	if not _write_report(report_path, report):
		printerr("REPORT_REJECTED unable to write %s" % report_path)
		call_deferred("_quit_cleanly", 1)
		return
	print("ROUTE_%s %s" % ["PASSED" if _failures.is_empty() else "FAILED", CanonicalJson.encode(report)])
	call_deferred("_quit_cleanly", 0 if _failures.is_empty() else 1)


func _prepare_party() -> void:
	for character: CharacterState in _session._state.party.characters():
		character.maximum_health = 1_000_000
		character.current_health = 1_000_000
		character.brawn = 32_767
		character.maximum_load = 1_000_000_000
		character.carried_load = 0
		character.agility = 32_767
	_session._state.party_setup_completed = true


func _validate_route_header(route: Dictionary) -> void:
	if route.get("campaignId") != _content.campaign_id:
		_fail("route campaign does not match the loaded package")
	if not route.get("steps") is Array or route["steps"].is_empty():
		_fail("route has no executable steps")
	var start: Variant = route.get("start", {})
	if not start is Dictionary:
		_fail("route start is missing")
		return
	var map := _content.world.map_by_type_and_index(StringName(start.get("levelType", "")), int(start.get("levelIndex", -1)))
	if map == null or map.id != _content.start_map_id or Vector2i(int(start.get("x", -1)), int(start.get("y", -1))) != _content.start_coordinate:
		_fail("route start does not match the package manifest")


func _run_step(step_definition: Dictionary) -> void:
	var failure_count := _failures.size()
	var step_id := String(step_definition.get("id", "unnamed-step"))
	var trigger_id := String(step_definition.get("triggerId", ""))
	var trigger := _content.trigger_by_id(trigger_id)
	if trigger == null:
		_fail("%s references unavailable trigger %s" % [step_id, trigger_id])
		_stage(step_id, failure_count)
		return
	if trigger.map_id.is_empty() or _content.world.map_by_id(trigger.map_id) == null:
		_run_program_step(step_id, step_definition, trigger, failure_count)
		return
	_validate_step_position(step_id, step_definition.get("position", {}), trigger)
	_session._state.party.map_id = trigger.map_id
	_session._state.party.coordinate = trigger.coordinate
	_session._state.world.mark_visited(trigger.map_id, trigger.coordinate)
	var continuation_body := SessionContinuation.ExplorationBody.new()
	continuation_body.map_id = trigger.map_id
	continuation_body.coordinate = trigger.coordinate
	continuation_body.trigger_ids = [trigger.id]
	continuation_body.trigger_index = 0
	continuation_body.active_trigger_id = ""
	continuation_body.random_region_index = -1
	continuation_body.random_battle_stage = &""
	continuation_body.action_point_destination_depth = 0
	_session._session_continuation = SessionContinuation.post_move(continuation_body)
	if _session._session_continuation == null:
		_fail("%s could not construct its typed post-move continuation" % step_id)
		_stage(step_id, failure_count)
		return
	var events: Array[DomainEvent] = []
	var result := _session._continue_post_move([])
	result = _drain_interactions(result, events, step_id)
	if result.state == SessionStep.State.FAILED:
		_fail("%s failed with %s: %s" % [step_id, result.error_code, result.error_message])
	_validate_step_events(step_id, step_definition, events)
	_stage(step_id, failure_count)


func _run_program_step(step_id: String, step_definition: Dictionary, trigger: TriggerDefinition, failure_count: int) -> void:
	var position: Variant = step_definition.get("position", {})
	if not position is Dictionary:
		_fail("%s has no source position" % step_id)
		_stage(step_id, failure_count)
		return
	var map := _content.world.map_by_type_and_index(StringName(position.get("levelType", "")), int(position.get("levelIndex", -1)))
	var coordinate := Vector2i(int(position.get("x", -1)), int(position.get("y", -1)))
	if map == null or map.topology.cell_at(coordinate) == null:
		_fail("%s source position is outside authoritative topology" % step_id)
		_stage(step_id, failure_count)
		return
	_session._state.party.map_id = map.id
	_session._state.party.coordinate = coordinate
	_session._state.world.mark_visited(map.id, coordinate)
	var events: Array[DomainEvent] = [DomainEvent.new(&"trigger_fired", {"triggerId": trigger.id, "source": "route-program"})]
	var started := _session._scenario_vm.start_program(trigger.program_id, {"callingContext": "action", "triggerId": trigger.id, "mapId": map.id, "x": coordinate.x, "y": coordinate.y})
	var result: SessionStep
	if started.state == ScenarioVmResult.State.FAILED:
		result = SessionStep.failed(0, started.error_code, started.error_message, events)
	else:
		var vm_result := _session._scenario_vm.run(_session._runtime_api)
		events.append_array(vm_result.events)
		if vm_result.state == ScenarioVmResult.State.FAILED:
			result = SessionStep.failed(0, vm_result.error_code, vm_result.error_message, events)
		elif vm_result.state == ScenarioVmResult.State.WAITING:
			result = SessionStep.waiting(0, vm_result.interaction, events)
		else:
			result = SessionStep.completed(0, events)
	var observed_events: Array[DomainEvent] = []
	result = _drain_interactions(result, observed_events, step_id)
	if result.state == SessionStep.State.FAILED:
		_fail("%s failed with %s: %s" % [step_id, result.error_code, result.error_message])
	_validate_step_events(step_id, step_definition, observed_events)
	_stage(step_id, failure_count)


func _drain_interactions(step: SessionStep, events: Array[DomainEvent], step_id: String) -> SessionStep:
	var guard := 2_048
	var current := step
	while guard > 0:
		events.append_array(current.events)
		if current.state != SessionStep.State.WAITING_FOR_INTERACTION:
			return current
		var response := _default_response(current.interaction, step_id)
		if response == null:
			return SessionStep.failed(current.view_revision, &"unsupported_route_interaction", "Route harness cannot answer %s." % current.interaction.kind)
		current = _session.respond(response)
		guard -= 1
	return SessionStep.failed(current.view_revision, &"route_step_limit", "Route step exceeded 2,048 typed interaction responses.")


func _default_response(request: InteractionRequest, step_id: String) -> InteractionResponse:
	if request == null:
		return null
	match request.kind:
		&"combat_action":
			_force_victory()
			var combat_body := request.body as InteractionRequest.CombatRequestBody
			if combat_body == null:
				return null
			return InteractionResponse.from_data(request.request_id, request.kind, {"actorId": combat_body.actor_id, "action": "defend", "targetId": ""})
		&"acknowledge":
			return InteractionResponse.acknowledge(request)
		&"encounter_choice", &"scenario_choice":
			return InteractionResponse.indexed_choice(request, 0)
		&"yes_no":
			return InteractionResponse.yes_no(request, true)
		&"complex_encounter":
			return InteractionResponse.from_data(request.request_id, request.kind, {"action": "choice", "slot": 0})
		&"shop_action", &"temple_action":
			return InteractionResponse.from_data(request.request_id, request.kind, {"action": "leave"})
		&"bank_action":
			return InteractionResponse.from_data(request.request_id, request.kind, {"action": "leave", "amount": 0})
		&"ally_selection":
			var ally_body := request.body as InteractionRequest.SelectionRequestBody
			if ally_body == null:
				return null
			return InteractionResponse.from_data(request.request_id, request.kind, {"selectedIds": ally_body.selected_ids.duplicate()})
	_fail("%s yielded unsupported interaction %s" % [step_id, request.kind])
	return null


func _force_victory() -> void:
	var combat := _session._state.combat
	if combat == null:
		return
	for monster: MonsterState in combat.monsters():
		if monster.traitor:
			monster.current_health = 0


func _validate_step_position(step_id: String, position: Variant, trigger: TriggerDefinition) -> void:
	if not position is Dictionary:
		_fail("%s has no source position" % step_id)
		return
	var map := _content.world.map_by_type_and_index(StringName(position.get("levelType", "")), int(position.get("levelIndex", -1)))
	var coordinate := Vector2i(int(position.get("x", -1)), int(position.get("y", -1)))
	if map == null or map.id != trigger.map_id or coordinate != trigger.coordinate:
		_fail("%s position does not match trigger %s" % [step_id, trigger.id])


func _validate_step_events(step_id: String, step_definition: Dictionary, events: Array[DomainEvent]) -> void:
	var observed_messages: Array[int] = []
	var observed_pictures: Array[int] = []
	var observed_step_battles: Array[int] = []
	for event: DomainEvent in events:
		if event.kind == &"message_shown":
			observed_messages.append(int(event.payload.get("messageId", -1)))
		elif event.kind == &"picture_requested":
			observed_pictures.append(int(event.payload.get("pictureId", -1)))
		elif event.kind == &"battle_started":
			var battle_id := int(event.payload.get("classicId", -1))
			observed_step_battles.append(battle_id)
			_observed_battles.append(battle_id)
		elif event.kind == &"battle_completed" and event.payload.get("outcome") != "victory":
			_fail("%s completed battle with outcome %s" % [step_id, event.payload.get("outcome")])
	var expected_messages := _expected_message_ids(step_definition)
	if not _contains_subsequence(observed_messages, expected_messages):
		_fail("%s message sequence differs: expected %s, observed %s" % [step_id, expected_messages, observed_messages])
	if step_definition.has("picture"):
		var picture: Variant = step_definition["picture"]
		if not picture is Dictionary or not observed_pictures.has(int(picture.get("id", -1))):
			_fail("%s did not publish its expected picture" % step_id)
	if step_definition.has("battleId") and not observed_step_battles.has(int(step_definition["battleId"])):
		_fail("%s did not start Classic battle %d" % [step_id, int(step_definition["battleId"])])


func _expected_message_ids(step_definition: Dictionary) -> Array[int]:
	var expected: Array[int] = []
	for field: String in ["messages", "sequence", "postVictory"]:
		for entry: Variant in step_definition.get(field, []):
			if entry is Dictionary and (field == "messages" or entry.get("kind") == "message"):
				var message_id := int(entry.get("id", -1))
				if message_id >= 0 and not expected.has(message_id):
					expected.append(message_id)
	return expected


func _contains_subsequence(observed: Array[int], expected: Array[int]) -> bool:
	var cursor := 0
	for value: int in observed:
		if cursor < expected.size() and value == expected[cursor]:
			cursor += 1
	return cursor == expected.size()


func _validate_completion(anchor: Variant) -> void:
	var failure_count := _failures.size()
	if not anchor is Dictionary or not anchor.get("runtime") is Dictionary:
		_fail("route has no completion runtime anchor")
		_stage("completion-runtime", failure_count)
		return
	var expected: Dictionary = anchor["runtime"]
	for quest_id: Variant in expected.get("questFlags", []):
		if not _session._state.quest_is_set(int(quest_id)):
			_fail("completion quest %d is not set" % int(quest_id))
	for override: Variant in expected.get("tileOverrides", []):
		if not override is Dictionary:
			_fail("completion tile override is malformed")
			continue
		var map := _content.world.map_by_type_and_index(StringName(override.get("levelType", "")), int(override.get("levelIndex", -1)))
		var coordinate := Vector2i(int(override.get("x", -1)), int(override.get("y", -1)))
		var cell: MapCell = null if map == null else map.topology.cell_at(coordinate)
		var terrain := "" if cell == null else _session._state.world.terrain_for(map.id, cell)
		if terrain != "classic.terrain.%d" % int(override.get("value", -1)):
			_fail("completion tile %s %s has terrain %s" % [map.id if map != null else "unknown", coordinate, terrain])
	var item_ids := _party_classic_item_ids()
	for item_id: Variant in expected.get("itemIds", []):
		if not item_ids.has(int(item_id)):
			_fail("completion reward item %d is absent" % int(item_id))
	var position: Variant = expected.get("position", {})
	if position is Dictionary:
		var expected_map := _content.world.map_by_type_and_index(StringName(position.get("levelType", "")), int(position.get("levelIndex", -1)))
		var expected_coordinate := Vector2i(int(position.get("x", -1)), int(position.get("y", -1)))
		if expected_map == null or _session._state.party.map_id != expected_map.id or _session._state.party.coordinate != expected_coordinate:
			_fail("completion position does not match the route anchor")
	_stage("completion-runtime", failure_count)


func _party_classic_item_ids() -> Array[int]:
	var result: Array[int] = []
	for character: CharacterState in _session._state.party.characters():
		for instance: ItemInstance in character.inventory():
			var definition := _content.item_by_id(instance.definition_id)
			if definition != null and not result.has(definition.classic_id):
				result.append(definition.classic_id)
	result.sort()
	return result


func _final_state() -> Dictionary:
	return {
		"mapId": _session._state.party.map_id,
		"x": _session._state.party.coordinate.x,
		"y": _session._state.party.coordinate.y,
		"questFlags": _set_quest_ids(),
		"itemIds": _party_classic_item_ids(),
		"world": _session._state.world.to_data(),
	}


func _set_quest_ids() -> Array[int]:
	var result: Array[int] = []
	for quest_id: int in 100:
		if _session._state.quest_is_set(quest_id):
			result.append(quest_id)
	return result


func _stage(stage_id: String, failure_count: int) -> void:
	_stages.append({"id": stage_id, "status": "passed" if _failures.size() == failure_count else "failed"})


func _fail(message: String) -> void:
	_failures.append(message)


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else null


func _write_report(path: String, report: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(CanonicalJson.encode(report) + "\n")
	return true


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
