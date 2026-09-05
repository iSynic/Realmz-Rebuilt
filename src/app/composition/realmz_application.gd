## Coordinates Realmz application within application startup and host integration.

class_name RealmzApplication
extends Control

## Composes the application and translates host input into typed game operations.

@onready var _status_label: Label = $GameShell/BottomRegion/BottomRow/NarrativeWell/NarrativeColumn/Facts/Status
@onready var _smoke_button: Button = $GameShell/SmokeAction
@onready var _map_presenter: ClassicMapPresenter = %ExplorationMap
@onready var _battlefield_presenter: ClassicBattlefieldPresenter = %BattlefieldMap
@onready var _interaction_presenter: InteractionPresenter = %InteractionPanel
@onready var _shell_presenter: GameShell = $GameShell
@onready var _game_shell: GameShell = $GameShell
@onready var _audio_presenter: ClassicAudioPresenter = %ClassicAudio

var session_controller: GameSessionController
var presentation_coordinator: PresentationCoordinator
var presentation_media: PresentationMediaController
var settings_repository: SettingsRepository
var _active_content: RealmzContent
var _presentation_settings: PresentationSettings
var _dungeon_presenter: DungeonMap3DPresenter
var _package_host: PackageHostController
var _save_host: SaveHostController
var _pending_package_seed: int = 1
var _last_package_operation_key: String = ""
var _pending_prepared_package: PreparedPackage
var _held_movement: HeldMovementController
var _queued_combat_auto_changes: Dictionary = {}
var _quit_operation: Callable
var _debug_tools: DebugToolsHost
var _campaigns: Array[CampaignPackageView] = []
var _last_campaign_prewarm_requested: bool = false
var _input_router: ApplicationInputRouter
var _settings_controller: ApplicationSettingsController
var lifecycle_host := ApplicationLifecycleHost.new()
var character_files: ApplicationCharacterFilesHost
var adventure_storage: ApplicationAdventureStorageHost
var _spatial_layout: ApplicationSpatialLayout


func configure_lifecycle_host(save_host: SaveHostController, quit_operation: Callable = Callable()) -> void:
	assert(not is_node_ready(), "Lifecycle host dependencies must be configured before the application enters the scene tree")
	_save_host = save_host
	_quit_operation = quit_operation


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	UiInputActions.ensure_defaults()
	_build_dependencies()
	_bind_debug_and_movement()
	_bind_combat_and_interactions()
	_bind_shell_and_settings()
	_finish_startup()


func _build_dependencies() -> void:
	_package_host = PackageHostController.new()
	if _save_host == null: _save_host = SaveHostController.new()
	settings_repository = SettingsRepository.new()
	_presentation_settings = settings_repository.load_settings()
	session_controller = GameSessionController.new()
	presentation_coordinator = PresentationCoordinator.new()
	presentation_media = PresentationMediaController.new()
	_dungeon_presenter = DungeonMap3DPresenter.new()
	_held_movement = HeldMovementController.new()
	_input_router = ApplicationInputRouter.new(self)
	add_child(session_controller)
	add_child(presentation_coordinator)
	add_child(_dungeon_presenter)
	add_child(_held_movement)
	_debug_tools = DebugToolsHost.new()
	add_child(_debug_tools)
	_debug_tools.bind(session_controller, self, func() -> RealmzContent: return _active_content)
	character_files = ApplicationCharacterFilesHost.new(
		_package_host,
		session_controller,
		presentation_coordinator,
		presentation_media,
		_game_shell
	)
	adventure_storage = ApplicationAdventureStorageHost.new(_save_host, session_controller, _game_shell, func() -> void: _queued_combat_auto_changes.clear())
	_spatial_layout = ApplicationSpatialLayout.new(_map_presenter, _battlefield_presenter, _dungeon_presenter, _interaction_presenter, _shell_presenter, session_controller, presentation_coordinator)
	lifecycle_host.bind(session_controller, presentation_coordinator, _shell_presenter, _held_movement, func(slot_id: String) -> bool: return adventure_storage.save(_active_content, slot_id), func() -> void: adventure_storage.refresh(_active_content), _present_step_status, _complete_closed_session, _quit_application)


func _bind_debug_and_movement() -> void:
	_debug_tools.status_changed.connect(
		func(message: String, failed: bool) -> void:
			_shell_presenter.status.set_status(message, failed)
	)
	_held_movement.set_speed_percent(_presentation_settings.exploration_speed_percent)
	_held_movement.movement_requested.connect(_on_held_movement_requested)
	_map_presenter.movement_hold_started.connect(func(direction: Vector2i) -> void: _held_movement.start(&"mouse", direction))
	_map_presenter.movement_hold_updated.connect(func(direction: Vector2i) -> void: _held_movement.update(&"mouse", direction))
	_map_presenter.movement_hold_stopped.connect(func() -> void: _held_movement.stop(&"mouse"))
	_dungeon_presenter.turn_requested.connect(
		func(delta: int) -> void:
			submit_intent(ExplorationIntents.dungeon_turn(delta))
	)
	_dungeon_presenter.movement_requested.connect(
		func(direction: Vector2i) -> void:
			_submit_movement(direction)
	)
	_dungeon_presenter.movement_hold_started.connect(
		func(direction: Vector2i) -> void:
			_held_movement.start(&"keyboard", direction)
	)
	_dungeon_presenter.movement_hold_stopped.connect(
		func() -> void:
			_held_movement.stop(&"keyboard")
	)


func _bind_combat_and_interactions() -> void:
	presentation_coordinator.bind(
		session_controller,
		_map_presenter,
		_battlefield_presenter,
		_dungeon_presenter,
		_interaction_presenter,
		_shell_presenter,
		_audio_presenter,
		presentation_media
	)
	presentation_coordinator.playback_step_settled.connect(_on_playback_step_settled)
	_interaction_presenter.response_submitted.connect(_on_interaction_response_submitted)
	_interaction_presenter.combat.targeting_requested.connect(_on_combat_targeting_requested)
	_interaction_presenter.combat.targeting_confirm_requested.connect(_battlefield_presenter.interaction.confirm_targeting)
	_interaction_presenter.combat.targeting_cancel_requested.connect(_battlefield_presenter.interaction.cancel_targeting)
	_interaction_presenter.combat.targeting_rotate_requested.connect(_battlefield_presenter.interaction.rotate_targeting)
	_interaction_presenter.combat.combatant_focus_requested.connect(_on_combatant_focus_requested)
	_interaction_presenter.combat.reveal_friends_requested.connect(_on_reveal_friends_requested)
	_interaction_presenter.presentation_sound_requested.connect(_on_interaction_sound_requested)
	_interaction_presenter.presentation_status_requested.connect(_shell_presenter.status.set_status)
	_battlefield_presenter.interaction.combat_body_submitted.connect(_on_battlefield_action_requested)
	_battlefield_presenter.interaction.combatant_inspected.connect(_on_battlefield_combatant_inspected)
	_battlefield_presenter.interaction.targeting_changed.connect(_interaction_presenter.combat.update_targeting)
	_battlefield_presenter.interaction.targeting_cancelled.connect(_interaction_presenter.combat.targeting_cancelled)


func _bind_shell_and_settings() -> void:
	_shell_presenter.start_package_requested.connect(_begin_package_start)
	_shell_presenter.cancel_package_requested.connect(_cancel_package_start)
	_shell_presenter.refresh_campaigns_requested.connect(_refresh_campaigns)
	_shell_presenter.intent_submitted.connect(submit_intent)
	_shell_presenter.save_requested.connect(func(slot_id: String) -> void: adventure_storage.save(_active_content, slot_id))
	_shell_presenter.save_and_quit_requested.connect(lifecycle_host.save_and_quit)
	_shell_presenter.load_requested.connect(func(slot_id: String) -> void: adventure_storage.load(_active_content, slot_id))
	_shell_presenter.load_backup_requested.connect(func(slot_id: String) -> void: adventure_storage.load(_active_content, slot_id, true))
	_shell_presenter.refresh_saves_requested.connect(func() -> void: adventure_storage.refresh(_active_content))
	_shell_presenter.end_adventure_requested.connect(lifecycle_host.request_end_adventure)
	_shell_presenter.quit_requested.connect(lifecycle_host.request_quit)
	_shell_presenter.route_changed.connect(lifecycle_host.route_changed)
	_shell_presenter.layout_changed.connect(_on_shell_layout_changed)
	_shell_presenter.route_changed.connect(_on_route_changed)
	_shell_presenter.vault_archive_requested.connect(func(character_id: String) -> void: character_files.archive_character(_active_content, character_id))
	_shell_presenter.vault_restore_requested.connect(func(character_id: String, revision_hash: String) -> void: character_files.restore_character(_active_content, character_id, revision_hash))
	_shell_presenter.standalone_character_creation_requested.connect(func() -> void: character_files.begin_creation(_active_content))
	_shell_presenter.standalone_character_creation_cancelled.connect(func() -> void: character_files.cancel_creation(_active_content))
	_shell_presenter.character_selection_completed.connect(_interaction_presenter.submit_character_selection)
	_audio_presenter.music_state_changed.connect(_shell_presenter.set_music_playback_state)
	_settings_controller = ApplicationSettingsController.new(self, _presentation_settings, settings_repository, _shell_presenter, _map_presenter, _interaction_presenter, _audio_presenter, presentation_coordinator, _dungeon_presenter, _held_movement, _debug_tools)
	_settings_controller.bind()
	_settings_controller.apply_initial_settings()


func _finish_startup() -> void:
	_game_shell.navigator.setup_controller.character_creation.set_standalone_character_creation_available(false, "Loading the built-in Classic definitions…")
	Callable(character_files, "begin_library_load").call_deferred()
	_status_label.text = "Pure session boundary online"
	_refresh_campaigns()
	character_files.refresh_vault_views(_active_content)
	set_process(true)


func _process(_delta: float) -> void:
	var library_completed := character_files.poll_library_load(_active_content)
	if library_completed and _pending_prepared_package != null:
		var pending := _pending_prepared_package
		_pending_prepared_package = null
		_complete_package_install(pending, _pending_package_seed)
	_try_prewarm_last_campaign()
	if _held_movement != null and _held_movement.is_active():
		if not accepts_exploration_input():
			_held_movement.stop()
		elif _held_movement.active_source() == &"mouse" and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_held_movement.stop(&"mouse")
	if _package_host == null:
		return
	var operation := _package_host.operation_view()
	var operation_key := "%s:%s:%d:%d:%s" % [operation.state, operation.phase, operation.completed, operation.total, operation.message]
	if operation_key != _last_package_operation_key:
		_last_package_operation_key = operation_key
		_shell_presenter.navigator.setup_controller.campaign_library.set_package_operation(operation)
		_shell_presenter.status.set_status(operation.message, operation.state == PackageOperationView.FAILED)
	if operation.is_running() or operation.state == PackageOperationView.IDLE:
		return
	var prepared := _package_host.take_prepared_package()
	_shell_presenter.navigator.setup_controller.campaign_library.set_package_operation(PackageOperationView.new())
	_last_package_operation_key = ""
	if operation.state == PackageOperationView.CANCELLED:
		_shell_presenter.status.set_status("Campaign preparation cancelled.")
		return
	if not character_files.library_ready():
		_pending_prepared_package = prepared
		_shell_presenter.status.set_status("Campaign ready • finishing the built-in Classic definitions…")
		return
	_complete_package_install(prepared, _pending_package_seed)


func _exit_tree() -> void:
	if _held_movement != null:
		_held_movement.stop()
	if _package_host != null:
		_package_host.close()


func _on_smoke_action_pressed() -> void:
	_smoke_button.release_focus()
	if not session_controller.view().session_started:
		_status_label.text = "MCP input verified • no package loaded"
		return
	var step := submit_intent(ExplorationIntents.search())
	if step.state == SessionStep.State.FAILED:
		return
	var roll: int = step.events[0].payload.get("roll", 0)
	var current_view := session_controller.view()
	_status_label.text = "Search committed • roll %d • day %d %02d:%02d" % [roll, current_view.realmz_day, current_view.realmz_hour, current_view.realmz_minute]


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _held_movement != null:
			_held_movement.stop()
		if _interaction_presenter != null:
			_interaction_presenter.combat.set_fast_spell_dock_held(false)
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		lifecycle_host.request_quit()


func start_package(package_path: String, initial_seed: int) -> SessionStep:
	var current_view := session_controller.view()
	if current_view.session_started and not current_view.party_setup_available:
		return SessionStep.failed(session_controller.view().revision, &"session_already_started", "End the active adventure before starting another campaign.")
	return _complete_package_install(_package_host.install_sync(package_path), initial_seed)


func _begin_package_start(package_path: String, initial_seed: int) -> void:
	_held_movement.stop()
	var current_view := session_controller.view()
	if current_view.session_started and not current_view.party_setup_available:
		_shell_presenter.status.set_status("End the active adventure before starting another campaign.", true)
		return
	if _package_host.operation_view().is_running():
		return
	_pending_package_seed = initial_seed
	if not _package_host.start_install(package_path):
		_shell_presenter.status.set_status(_package_host.operation_view().message, true)
		return
	_shell_presenter.navigator.setup_controller.campaign_library.set_package_operation(_package_host.operation_view())
	_shell_presenter.status.set_status("Preparing campaign…")


func _cancel_package_start() -> void:
	if _package_host != null:
		_package_host.cancel()


func _complete_package_install(prepared: PreparedPackage, initial_seed: int) -> SessionStep:
	if prepared == null:
		_status_label.text = "Package rejected • package operation returned no result"
		_shell_presenter.status.set_status(_status_label.text, true)
		return SessionStep.failed(0, &"package_operation_failed", "Package operation returned no result.")
	if not prepared.is_ok():
		_status_label.text = "Package rejected • %s" % prepared.error_message
		_shell_presenter.status.set_status(_status_label.text, true)
		return SessionStep.failed(0, prepared.error_code, prepared.error_message)
	prepared.content.characters.install_application_catalog(character_files.library_content().characters)
	var step := session_controller.start(prepared.content, initial_seed)
	if step.state == SessionStep.State.FAILED:
		_status_label.text = "Session start failed • %s" % step.error_message
		_shell_presenter.status.set_status(_status_label.text, true)
		return step
	_queued_combat_auto_changes.clear()
	_active_content = prepared.content
	_package_host.promote(prepared)
	if _presentation_settings.last_campaign_id != _active_content.campaign_id: _presentation_settings.last_campaign_id = _active_content.campaign_id
	settings_repository.save_settings(_presentation_settings)
	presentation_media.set_package_media(prepared.media)
	presentation_coordinator.refresh()
	adventure_storage.refresh(_active_content)
	character_files.refresh_vault_views(_active_content)
	_smoke_button.text = "Search area"
	var current_view := session_controller.view()
	_status_label.text = "Loaded %s • %s %d,%d • seed %d" % [_active_content.campaign_id, current_view.party_map_id, current_view.party_coordinate.x, current_view.party_coordinate.y, initial_seed]
	_shell_presenter.status.set_status(_status_label.text)
	_refresh_campaigns()
	return step


func _input(event: InputEvent) -> void:
	if _input_router != null:
		_input_router.handle_input(event)


func accepts_route_input() -> bool:
	if lifecycle_host.has_active_interaction() or presentation_coordinator == null or _interaction_presenter == null:
		return false
	if presentation_coordinator.is_combat_playback_active() or _interaction_presenter.has_blocking_request():
		return false
	return GameShellAvailability.route_change_reason(session_controller.view()).is_empty()


func accepts_exploration_input() -> bool:
	if lifecycle_host.has_active_interaction() or presentation_coordinator == null or _interaction_presenter == null or _shell_presenter == null:
		return false
	if presentation_coordinator.is_combat_playback_active() or _interaction_presenter.has_blocking_request():
		return false
	var view := session_controller.view()
	return view != null and view.session_started and view.pending_interaction == null and _shell_presenter.accepts_exploration_input()


func handle_field_fast_spell(slot_index: int, use_spell: bool) -> void:
	var binding := _shell_presenter.commands.selected_fast_spell(slot_index)
	if binding.is_empty() or String(binding.get("spellId", "")).is_empty():
		_shell_presenter.status.set_status("Fast Spell %s • Undefined Spell" % ("0" if slot_index == 9 else str(slot_index + 1)))
		_audio_presenter.present_sound(143, presentation_media.catalog())
		return
	var summary := "Fast Spell %s • %s P%d • %s" % ["0" if slot_index == 9 else str(slot_index + 1), binding["spellName"], binding["power"], binding["characterName"]]
	if not use_spell:
		_shell_presenter.status.set_status(summary)
		_audio_presenter.present_sound(145, presentation_media.catalog())
		return
	if not bool(binding.get("enabled", false)):
		_shell_presenter.status.set_status("%s • %s" % [summary, binding.get("reason", "Unavailable")], true)
		_audio_presenter.present_sound(143, presentation_media.catalog())
		return
	submit_intent(MagicIntents.cast(binding["spellId"], binding["characterId"], "", binding["power"]))


func _on_held_movement_requested(direction: Vector2i) -> void:
	if not _submit_movement(direction): _held_movement.stop()


func _on_battlefield_action_requested(body: InteractionResponse.CombatBody) -> void:
	var pending := session_controller.view().active_interaction_request()
	if pending != null and pending.kind == InteractionRequest.COMBAT:
		_interaction_presenter.combat.submit_body(ApplicationCombatPolicy.body_with_preferences(body, _presentation_settings))


func _on_battlefield_combatant_inspected(combatant_id: String) -> void:
	_interaction_presenter.combat.open_combatant_inspection(combatant_id)


func _on_combat_targeting_requested(request: CombatTargetingRequest) -> void:
	if not _battlefield_presenter.interaction.begin_targeting(request):
		_shell_presenter.status.set_status("Battlefield targeting is unavailable for this action.", true)


func _on_combatant_focus_requested(combatant_id: String, play_sound: bool) -> void:
	_battlefield_presenter.interaction.focus_combatant(combatant_id)
	_interaction_presenter.combat.inspect_combatant(combatant_id)
	if play_sound:
		_audio_presenter.present_sound(147, presentation_media.catalog())


func _on_reveal_friends_requested() -> void:
	_battlefield_presenter.interaction.toggle_reveal_friends()
	_audio_presenter.present_sound(137, presentation_media.catalog())


func _on_interaction_sound_requested(sound_id: int) -> void:
	if sound_id > 0:
		_audio_presenter.present_sound(sound_id, presentation_media.catalog())


func _submit_movement(direction: Vector2i) -> bool:
	if not _shell_presenter.accepts_exploration_input() or not session_controller.view().session_started or session_controller.view().pending_interaction != null:
		return false
	var map_view := session_controller.view().map_view
	if MapTopology.is_diagonal_direction(direction) and (map_view == null or map_view.level_type != &"land"):
		return false
	var before := session_controller.view()
	var step := submit_intent(ExplorationIntents.overhead_dungeon_move(direction) if map_view != null and map_view.level_type == &"dungeon" and (_dungeon_presenter == null or not _dungeon_presenter.is_active()) else ExplorationIntents.move(direction))
	var after := session_controller.view()
	if step.state == SessionStep.State.FAILED or after == null or after.pending_interaction != null or after.combat_view != null:
		return false
	return HeldMovementController.continues_after_step(direction, before.party_map_id, before.party_coordinate, after.party_map_id, after.party_coordinate, step.events, accepts_exploration_input())


func submit_intent(intent: PlayerIntent) -> SessionStep:
	if character_files.creator_active():
		return character_files.submit_creator_intent(intent)
	var debug_step := _debug_tools.noclip_step(intent) if _debug_tools != null else null
	if debug_step != null:
		_present_step_status(debug_step)
		return debug_step
	var queued_auto := ApplicationCombatPolicy.auto_change_to_queue(intent, presentation_coordinator != null and presentation_coordinator.is_combat_playback_active())
	if not queued_auto.is_empty():
		_queued_combat_auto_changes[String(queued_auto["characterId"])] = bool(queued_auto["enabled"])
		_shell_presenter.status.set_status("Manual control queued after this Auto activation." if not bool(queued_auto["enabled"]) else "Auto queued after this activation.")
		if not bool(queued_auto["enabled"]):
			presentation_coordinator.skip_combat_playback()
		return SessionStep.completed(session_controller.view().revision)
	if intent != null and intent.kind == PlayerIntent.Kind.IMPORT_VAULT_CHARACTER:
		var vault_import := intent.payload as PartyIntentPayloads.VaultImport
		var import_intent := character_files.vault_import_intent(vault_import.character_id, vault_import.revision_hash)
		if import_intent == null:
			var message := character_files.vault_error() if not character_files.vault_error().is_empty() else "The requested vault revision is unavailable."
			var failed := SessionStep.failed(session_controller.view().revision, &"vault_load_failed", message)
			_present_step_status(failed)
			return failed
		intent = import_intent
	var step := session_controller.submit_intent(intent)
	var committed_view := session_controller.view()
	if _held_movement != null and (step.state != SessionStep.State.COMPLETED or committed_view == null or committed_view.pending_interaction != null or committed_view.combat_view != null):
		_held_movement.stop()
	_present_step_status(step)
	return step


func _on_interaction_response_submitted(response: InteractionResponse) -> void:
	match ApplicationLifecycleHost.response_owner(lifecycle_host.has_active_interaction(), character_files.creator_active()):
		&"host":
			lifecycle_host.respond(response)
			return
		&"standalone-creator":
			character_files.respond_to_creator(response)
			return
	var current_view := session_controller.view()
	var journal_count_before := current_view.journal_entries.size()
	if current_view.pending_interaction == null and current_view.combat_action_request != null and response.request_id == current_view.combat_action_request.request_id and response.kind == InteractionRequest.COMBAT:
		var direct_intent := ApplicationCombatPolicy.direct_intent(response.body as InteractionResponse.CombatBody)
		if direct_intent == null:
			_shell_presenter.status.set_status("The combat command was invalid.", true)
			presentation_coordinator.refresh()
			return
		var direct_step := submit_intent(direct_intent)
		if direct_step.state == SessionStep.State.COMPLETED and direct_step.events.is_empty() and session_controller.view().pending_interaction == null:
			_shell_presenter.status.set_status("")
		return
	var step := session_controller.respond(response)
	_present_step_status(step)
	if step.state != SessionStep.State.FAILED and session_controller.view().journal_entries.size() > journal_count_before:
		_shell_presenter.status.show_activity_indicator(&"journal")
	if step.state == SessionStep.State.COMPLETED and step.events.is_empty() and session_controller.view().pending_interaction == null:
		_shell_presenter.status.set_status("")


func abort_full_party_auto(skip_playback: bool) -> bool:
	var character_ids := ApplicationCombatPolicy.auto_abort_ids(session_controller.view(), _queued_combat_auto_changes)
	if character_ids.is_empty():
		return false
	for character_id: String in character_ids:
		_queued_combat_auto_changes[character_id] = false
	_shell_presenter.status.set_status("Full-party Auto cancelled. Manual control resumes at the next activation.")
	if skip_playback:
		presentation_coordinator.skip_combat_playback()
	else:
		_flush_queued_combat_auto_changes()
	return true


func _quit_application() -> void:
	if _package_host != null:
		_package_host.close()
	if _quit_operation.is_valid(): _quit_operation.call()
	else: get_tree().quit()


func _complete_closed_session() -> void:
	_queued_combat_auto_changes.clear()
	_active_content = null
	presentation_media.set_package_media(character_files.library_media())
	adventure_storage.refresh(_active_content)
	character_files.refresh_vault_views(_active_content)
	_refresh_campaigns()
	_shell_presenter.show_splash()
	_status_label.text = "Adventure ended • main menu"
	_shell_presenter.status.set_status(_status_label.text)


func _on_playback_step_settled(step: SessionStep) -> void:
	if lifecycle_host.playback_step_settled(step):
		return
	_flush_queued_combat_auto_changes()
	call_deferred("_continue_persistent_auto_after_playback")


func _flush_queued_combat_auto_changes() -> void:
	if _queued_combat_auto_changes.is_empty():
		return
	var changes := _queued_combat_auto_changes.duplicate()
	_queued_combat_auto_changes.clear()
	var character_ids: Array[String] = []
	character_ids.assign(changes.keys())
	character_ids.sort()
	for character_id: String in character_ids:
		submit_intent(CombatIntents.set_auto(character_id, bool(changes[character_id])))


func _continue_persistent_auto_after_playback() -> void:
	# Reduced motion can settle playback before its battlefield draws. Let that
	# committed view reach the screen before another synchronous Auto activation.
	await RenderingServer.frame_post_draw
	if presentation_coordinator == null or presentation_coordinator.is_combat_playback_active() or not _queued_combat_auto_changes.is_empty() or lifecycle_host.has_active_interaction(): return
	var response := ApplicationCombatPolicy.persistent_auto_response(session_controller.view())
	if response != null:
		_on_interaction_response_submitted(response)


func _present_step_status(step: SessionStep) -> void:
	if step.state == SessionStep.State.FAILED:
		_status_label.text = "Action failed • %s" % step.error_message
		_shell_presenter.status.set_status(_status_label.text, true)
		return
	for event: DomainEvent in step.events:
		if event.kind == &"session_ended":
			lifecycle_host.handles_terminal_step(step, presentation_coordinator.is_combat_playback_active())
			return
		if event.kind == &"character_publication_requested":
			character_files.publish_campaign_character(_active_content, String(event.payload.get("characterId", "")))
		else:
			var status_text := ApplicationStepStatusText.for_event(event)
			if not status_text.is_empty(): _status_label.text = status_text
	if step.state == SessionStep.State.WAITING_FOR_INTERACTION:
		_status_label.text = ApplicationStepStatusText.for_interaction(step.interaction)


func _refresh_campaigns() -> void:
	if _package_host != null and _package_host.operation_view().is_running():
		return
	_campaigns = _package_host.discover_available_campaigns()
	_shell_presenter.navigator.setup_controller.campaign_library.set_campaigns(_campaigns)
	_try_prewarm_last_campaign()


func _try_prewarm_last_campaign() -> void:
	if _last_campaign_prewarm_requested or _package_host == null or character_files.library_content() == null or _presentation_settings == null or _presentation_settings.last_campaign_id.is_empty() or bool(get_meta(&"startup_splash_suppressed", false)) and not bool(get_meta(&"startup_front_door_revealed", false)): return
	_last_campaign_prewarm_requested = true
	_package_host.prewarm_last_campaign(_campaigns, _presentation_settings.last_campaign_id)


func _on_shell_layout_changed(workspace_rect: Rect2, _profile: UiLayoutProfile) -> void:
	_spatial_layout.apply(workspace_rect, _profile)


func _on_route_changed(route_id: StringName) -> void:
	_held_movement.stop()
	presentation_coordinator.set_active_route(route_id)
