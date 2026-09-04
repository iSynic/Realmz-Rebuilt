## Coordinates Realmz application within application startup and host integration.

class_name RealmzApplication
extends Control

## Composes the application and translates host input into typed game operations.

const CLASSIC_CHARACTER_LIBRARY_PATH := "res://src/storage/characters/realmz-classic-character-library.realmz2"
const CLASSIC_CHARACTER_LIBRARY_ID := "realmz-classic-character-library"
const CLASSIC_CHARACTER_LIBRARY_HASH := "c7e093f46bcca49d2382d68c2995ae5ff90c0e706dbd538682b613af9b80e0bd"

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
var settings_repository: SettingsRepository
var _active_content: RealmzContent
var _presentation_settings: PresentationSettings
var _dungeon_presenter: DungeonMap3DPresenter
var _host_interaction: InteractionRequest
var _package_host: PackageHostController
var _save_host: SaveHostController
var _vault_host: CharacterVaultController
var _pending_package_seed: int = 1
var _last_package_operation_key: String = ""
var _character_library_content: RealmzContent
var _character_library_media: MediaSource
var _character_library_load_complete: bool = false
var _pending_prepared_package: PreparedPackage
var _character_creation_host: CharacterCreationHostController
var _session_close_waits_for_playback: bool = false
var _held_movement: HeldMovementController
var _queued_combat_auto_changes: Dictionary = {}
var _save_and_quit_pending: bool = false
var _quit_operation: Callable
var _debug_tools: DebugToolsHost
var _campaigns: Array[CampaignPackageView] = []
var _last_campaign_prewarm_requested: bool = false
var _input_router: ApplicationInputRouter
var _settings_controller: ApplicationSettingsController


func configure_lifecycle_host(save_host: SaveHostController, quit_operation: Callable = Callable()) -> void:
	assert(not is_node_ready(), "Lifecycle host dependencies must be configured before the application enters the scene tree")
	_save_host = save_host
	_quit_operation = quit_operation


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	UiInputActions.ensure_defaults()
	_package_host = PackageHostController.new()
	if _save_host == null: _save_host = SaveHostController.new()
	_vault_host = CharacterVaultController.new()
	_character_creation_host = CharacterCreationHostController.new()
	settings_repository = SettingsRepository.new()
	_presentation_settings = settings_repository.load_settings()
	session_controller = GameSessionController.new()
	presentation_coordinator = PresentationCoordinator.new()
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
	_debug_tools.status_changed.connect(
		func(message: String, failed: bool) -> void:
			_shell_presenter.set_status(message, failed)
	)
	_held_movement.set_speed_percent(_presentation_settings.exploration_speed_percent)
	_held_movement.movement_requested.connect(_on_held_movement_requested)
	presentation_coordinator.bind(session_controller, _map_presenter, _battlefield_presenter, _dungeon_presenter, _interaction_presenter, _shell_presenter, _audio_presenter)
	presentation_coordinator.playback_step_settled.connect(_on_playback_step_settled)
	_interaction_presenter.response_submitted.connect(_on_interaction_response_submitted)
	_interaction_presenter.combat_targeting_requested.connect(_on_combat_targeting_requested)
	_interaction_presenter.combat_targeting_confirm_requested.connect(_battlefield_presenter.confirm_targeting)
	_interaction_presenter.combat_targeting_cancel_requested.connect(_battlefield_presenter.cancel_targeting)
	_interaction_presenter.combat_targeting_rotate_requested.connect(_battlefield_presenter.rotate_targeting)
	_interaction_presenter.combatant_focus_requested.connect(_on_combatant_focus_requested)
	_interaction_presenter.reveal_friends_requested.connect(_on_reveal_friends_requested)
	_interaction_presenter.presentation_sound_requested.connect(_on_interaction_sound_requested)
	_interaction_presenter.presentation_status_requested.connect(_shell_presenter.set_status)
	_map_presenter.movement_hold_started.connect(func(direction: Vector2i) -> void: _held_movement.start(&"mouse", direction))
	_map_presenter.movement_hold_updated.connect(func(direction: Vector2i) -> void: _held_movement.update(&"mouse", direction))
	_map_presenter.movement_hold_stopped.connect(func() -> void: _held_movement.stop(&"mouse"))
	_dungeon_presenter.turn_requested.connect(
		func(delta: int) -> void:
			submit_intent(PlayerIntent.dungeon_turn(delta))
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
	_battlefield_presenter.combat_body_submitted.connect(_on_battlefield_action_requested)
	_battlefield_presenter.combatant_inspected.connect(_on_battlefield_combatant_inspected)
	_battlefield_presenter.targeting_changed.connect(_interaction_presenter.update_combat_targeting)
	_battlefield_presenter.targeting_cancelled.connect(_interaction_presenter.combat_targeting_cancelled)
	_shell_presenter.start_package_requested.connect(_begin_package_start)
	_shell_presenter.cancel_package_requested.connect(_cancel_package_start)
	_shell_presenter.refresh_campaigns_requested.connect(_refresh_campaigns)
	_shell_presenter.intent_submitted.connect(submit_intent)
	_shell_presenter.save_requested.connect(save_active_session)
	_shell_presenter.save_and_quit_requested.connect(_on_save_and_quit_requested)
	_shell_presenter.load_requested.connect(load_active_session)
	_shell_presenter.load_backup_requested.connect(load_backup_session)
	_shell_presenter.refresh_saves_requested.connect(_refresh_save_previews)
	_shell_presenter.end_adventure_requested.connect(_on_end_adventure_requested)
	_shell_presenter.quit_requested.connect(_on_quit_requested)
	_shell_presenter.route_changed.connect(_on_shell_route_changed)
	_shell_presenter.layout_changed.connect(_on_shell_layout_changed)
	_shell_presenter.route_changed.connect(_on_route_changed)
	_shell_presenter.vault_archive_requested.connect(_archive_vault_character)
	_shell_presenter.vault_restore_requested.connect(_restore_vault_revision)
	_shell_presenter.standalone_character_creation_requested.connect(_begin_standalone_character_creation)
	_shell_presenter.standalone_character_creation_cancelled.connect(_cancel_standalone_character_creation)
	_shell_presenter.character_selection_completed.connect(_interaction_presenter.submit_character_selection)
	_audio_presenter.music_state_changed.connect(_shell_presenter.set_music_playback_state)
	_settings_controller = ApplicationSettingsController.new(self, _presentation_settings, settings_repository, _shell_presenter, _map_presenter, _interaction_presenter, _audio_presenter, presentation_coordinator, _dungeon_presenter, _held_movement, _debug_tools)
	_settings_controller.bind()
	_settings_controller.apply_initial_settings()
	_game_shell.set_standalone_character_creation_available(false, "Loading the built-in Classic definitions…")
	call_deferred("_begin_classic_character_library_load")
	_status_label.text = "Pure session boundary online"
	_refresh_campaigns()
	_refresh_vault_views()
	set_process(true)


func _process(_delta: float) -> void:
	_poll_classic_character_library_load()
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
		_shell_presenter.set_package_operation(operation)
		_shell_presenter.set_status(operation.message, operation.state == PackageOperationView.FAILED)
	if operation.is_running() or operation.state == PackageOperationView.IDLE:
		return
	var prepared := _package_host.take_prepared_package()
	_shell_presenter.set_package_operation(PackageOperationView.new())
	_last_package_operation_key = ""
	if operation.state == PackageOperationView.CANCELLED:
		_shell_presenter.set_status("Campaign preparation cancelled.")
		return
	if not _character_library_load_complete:
		_pending_prepared_package = prepared
		_shell_presenter.set_status("Campaign ready • finishing the built-in Classic definitions…")
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
	var step := submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
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
			_interaction_presenter.set_fast_spell_dock_held(false)
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_quit_requested()


func _on_quit_requested() -> void:
	_held_movement.stop()
	if _host_interaction != null:
		return
	if _save_and_quit_pending:
		_save_and_quit_pending = false
		_shell_presenter.set_save_and_quit_mode(false)
	var current_view := session_controller.view()
	var combat_view := current_view.combat_view
	var in_combat := combat_view != null and combat_view.outcome == &"active"
	_host_interaction = ApplicationLifecycle.quit_application_request(current_view.session_started, in_combat)
	presentation_coordinator.present_host_interaction(_host_interaction)
	_shell_presenter.set_status("Confirm whether to quit Realmz Rebuilt.")


func _on_end_adventure_requested() -> void:
	_held_movement.stop()
	if not session_controller.view().session_started:
		_shell_presenter.show_splash()
		return
	var pending := session_controller.view().active_interaction_request()
	if pending != null and pending.kind != InteractionRequest.COMBAT:
		_shell_presenter.set_status("Resolve the current interaction before ending the adventure.", true)
		return
	if _host_interaction != null:
		return
	var combat_view := session_controller.view().combat_view
	var in_combat := combat_view != null and combat_view.outcome == &"active"
	_host_interaction = ApplicationLifecycle.end_adventure_request(in_combat)
	presentation_coordinator.present_host_interaction(_host_interaction)
	_shell_presenter.set_status("Choose how to return to the main menu.")


func start_package(package_path: String, initial_seed: int) -> SessionStep:
	var current_view := session_controller.view()
	if current_view.session_started and not current_view.party_setup_available:
		return SessionStep.failed(session_controller.view().revision, &"session_already_started", "End the active adventure before starting another campaign.")
	return _complete_package_install(_package_host.install_sync(package_path), initial_seed)


func _begin_package_start(package_path: String, initial_seed: int) -> void:
	_held_movement.stop()
	var current_view := session_controller.view()
	if current_view.session_started and not current_view.party_setup_available:
		_shell_presenter.set_status("End the active adventure before starting another campaign.", true)
		return
	if _package_host.operation_view().is_running():
		return
	_pending_package_seed = initial_seed
	if not _package_host.start_install(package_path):
		_shell_presenter.set_status(_package_host.operation_view().message, true)
		return
	_shell_presenter.set_package_operation(_package_host.operation_view())
	_shell_presenter.set_status("Preparing campaign…")


func _cancel_package_start() -> void:
	if _package_host != null:
		_package_host.cancel()


func _complete_package_install(prepared: PreparedPackage, initial_seed: int) -> SessionStep:
	if prepared == null:
		_status_label.text = "Package rejected • package operation returned no result"
		_shell_presenter.set_status(_status_label.text, true)
		return SessionStep.failed(0, &"package_operation_failed", "Package operation returned no result.")
	if not prepared.is_ok():
		_status_label.text = "Package rejected • %s" % prepared.error_message
		_shell_presenter.set_status(_status_label.text, true)
		return SessionStep.failed(0, prepared.error_code, prepared.error_message)
	prepared.content.set_application_appearance_catalog(_character_library_content)
	var step := session_controller.start(prepared.content, initial_seed)
	if step.state == SessionStep.State.FAILED:
		_status_label.text = "Session start failed • %s" % step.error_message
		_shell_presenter.set_status(_status_label.text, true)
		return step
	_queued_combat_auto_changes.clear()
	_active_content = prepared.content
	_package_host.promote(prepared)
	if _presentation_settings.last_campaign_id != _active_content.campaign_id: _presentation_settings.last_campaign_id = _active_content.campaign_id
	settings_repository.save_settings(_presentation_settings)
	presentation_coordinator.set_package_media(prepared.media)
	presentation_coordinator.refresh()
	_refresh_save_previews()
	_refresh_vault_views()
	_smoke_button.text = "Search area"
	var current_view := session_controller.view()
	_status_label.text = "Loaded %s • %s %d,%d • seed %d" % [_active_content.campaign_id, current_view.party_map_id, current_view.party_coordinate.x, current_view.party_coordinate.y, initial_seed]
	_shell_presenter.set_status(_status_label.text)
	_refresh_campaigns()
	return step


func _input(event: InputEvent) -> void:
	if _input_router != null:
		_input_router.handle_input(event)


func accepts_route_input() -> bool:
	if _host_interaction != null or presentation_coordinator == null or _interaction_presenter == null:
		return false
	if presentation_coordinator.is_combat_playback_active() or _interaction_presenter.has_blocking_request():
		return false
	return GameShellAvailability.route_change_reason(session_controller.view()).is_empty()


func accepts_exploration_input() -> bool:
	if _host_interaction != null or presentation_coordinator == null or _interaction_presenter == null or _shell_presenter == null:
		return false
	if presentation_coordinator.is_combat_playback_active() or _interaction_presenter.has_blocking_request():
		return false
	var view := session_controller.view()
	return view != null and view.session_started and view.pending_interaction == null and _shell_presenter.accepts_exploration_input()


func handle_field_fast_spell(slot_index: int, use_spell: bool) -> void:
	var binding := _shell_presenter.selected_fast_spell(slot_index)
	if binding.is_empty() or String(binding.get("spellId", "")).is_empty():
		_shell_presenter.set_status("Fast Spell %s • Undefined Spell" % ("0" if slot_index == 9 else str(slot_index + 1)))
		_audio_presenter.present_sound(143, presentation_coordinator.package_media())
		return
	var summary := "Fast Spell %s • %s P%d • %s" % ["0" if slot_index == 9 else str(slot_index + 1), binding["spellName"], binding["power"], binding["characterName"]]
	if not use_spell:
		_shell_presenter.set_status(summary)
		_audio_presenter.present_sound(145, presentation_coordinator.package_media())
		return
	if not bool(binding.get("enabled", false)):
		_shell_presenter.set_status("%s • %s" % [summary, binding.get("reason", "Unavailable")], true)
		_audio_presenter.present_sound(143, presentation_coordinator.package_media())
		return
	submit_intent(PlayerIntent.cast_spell(binding["spellId"], binding["characterId"], "", binding["power"]))


func _on_held_movement_requested(direction: Vector2i) -> void:
	if not _submit_movement(direction): _held_movement.stop()


func _on_battlefield_action_requested(body: InteractionResponse.CombatBody) -> void:
	var pending := session_controller.view().active_interaction_request()
	if pending != null and pending.kind == InteractionRequest.COMBAT:
		_interaction_presenter.submit_active_body(combat_body_with_preferences(body, _presentation_settings))


static func combat_body_with_preferences(body: InteractionResponse.CombatBody, settings: PresentationSettings) -> InteractionResponse.CombatBody:
	var result := body.duplicate_body()
	if result.action == &"move":
		result.auto_switch_to_melee = settings != null and settings.auto_switch_to_melee
	return result


func _on_battlefield_combatant_inspected(combatant_id: String) -> void:
	_interaction_presenter.open_combatant_inspection(combatant_id)


func _on_combat_targeting_requested(request: CombatTargetingRequest) -> void:
	if not _battlefield_presenter.begin_targeting(request):
		_shell_presenter.set_status("Battlefield targeting is unavailable for this action.", true)


func _on_combatant_focus_requested(combatant_id: String, play_sound: bool) -> void:
	_battlefield_presenter.focus_combatant(combatant_id)
	_interaction_presenter.inspect_combatant(combatant_id)
	if play_sound:
		_audio_presenter.present_sound(147, presentation_coordinator.package_media())


func _on_reveal_friends_requested() -> void:
	_battlefield_presenter.toggle_reveal_friends()
	_audio_presenter.present_sound(137, presentation_coordinator.package_media())


func _on_interaction_sound_requested(sound_id: int) -> void:
	if sound_id > 0:
		_audio_presenter.present_sound(sound_id, presentation_coordinator.package_media())


func _submit_movement(direction: Vector2i) -> bool:
	if not _shell_presenter.accepts_exploration_input() or not session_controller.view().session_started or session_controller.view().pending_interaction != null:
		return false
	var map_view := session_controller.view().map_view
	if MapTopology.is_diagonal_direction(direction) and (map_view == null or map_view.level_type != &"land"):
		return false
	var before := session_controller.view()
	var step := submit_intent(PlayerIntent.overhead_dungeon_move(direction) if map_view != null and map_view.level_type == &"dungeon" and (_dungeon_presenter == null or not _dungeon_presenter.is_active()) else PlayerIntent.move(direction))
	var after := session_controller.view()
	if step.state == SessionStep.State.FAILED or after == null or after.pending_interaction != null or after.combat_view != null:
		return false
	return HeldMovementController.continues_after_step(direction, before.party_map_id, before.party_coordinate, after.party_map_id, after.party_coordinate, step.events, accepts_exploration_input())


func submit_intent(intent: PlayerIntent) -> SessionStep:
	if _character_creation_host.is_active():
		var creator_step: SessionStep = _character_creation_host.submit(intent)
		_present_standalone_character_step(creator_step)
		return creator_step
	var debug_step := _debug_tools.noclip_step(intent) if _debug_tools != null else null
	if debug_step != null:
		_present_step_status(debug_step)
		return debug_step
	var queued_auto := combat_auto_change_to_queue(intent, presentation_coordinator != null and presentation_coordinator.is_combat_playback_active())
	if not queued_auto.is_empty():
		_queued_combat_auto_changes[String(queued_auto["characterId"])] = bool(queued_auto["enabled"])
		_shell_presenter.set_status("Manual control queued after this Auto activation." if not bool(queued_auto["enabled"]) else "Auto queued after this activation.")
		if not bool(queued_auto["enabled"]):
			presentation_coordinator.skip_combat_playback()
		return SessionStep.completed(session_controller.view().revision)
	if intent != null and intent.kind == PlayerIntent.Kind.IMPORT_VAULT_CHARACTER:
		var vault_import := intent.payload as PlayerIntent.VaultImportPayload
		var import_intent := _vault_host.import_intent(vault_import.character_id, vault_import.revision_hash)
		if import_intent == null:
			var message := _vault_host.last_error() if not _vault_host.last_error().is_empty() else "The requested vault revision is unavailable."
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
	match interaction_response_owner(_host_interaction != null, _character_creation_host.is_active()):
		&"host":
			_respond_host_interaction(response)
			return
		&"standalone-creator":
			_present_standalone_character_step(_character_creation_host.respond(response))
			return
	var current_view := session_controller.view()
	var journal_count_before := current_view.journal_entries.size()
	if current_view.pending_interaction == null and current_view.combat_action_request != null and response.request_id == current_view.combat_action_request.request_id and response.kind == InteractionRequest.COMBAT:
		var direct_intent := direct_combat_intent(response.body as InteractionResponse.CombatBody)
		if direct_intent == null:
			_shell_presenter.set_status("The combat command was invalid.", true)
			presentation_coordinator.refresh()
			return
		var direct_step := submit_intent(direct_intent)
		if direct_step.state == SessionStep.State.COMPLETED and direct_step.events.is_empty() and session_controller.view().pending_interaction == null:
			_shell_presenter.set_status("")
		return
	var step := session_controller.respond(response)
	_present_step_status(step)
	if step.state != SessionStep.State.FAILED and session_controller.view().journal_entries.size() > journal_count_before:
		_shell_presenter.show_activity_indicator(&"journal")
	if step.state == SessionStep.State.COMPLETED and step.events.is_empty() and session_controller.view().pending_interaction == null:
		_shell_presenter.set_status("")


static func interaction_response_owner(has_host_interaction: bool, standalone_creator_active: bool) -> StringName:
	if has_host_interaction:
		return &"host"
	if standalone_creator_active:
		return &"standalone-creator"
	return &"session"


static func direct_combat_intent(body: InteractionResponse.CombatBody) -> PlayerIntent:
	return ApplicationCombatPolicy.direct_intent(body)


static func combat_auto_change_to_queue(intent: PlayerIntent, playback_active: bool) -> Dictionary:
	return ApplicationCombatPolicy.auto_change_to_queue(intent, playback_active)


static func combat_auto_abort_ids(view: GameView, queued_changes: Dictionary = {}) -> Array[String]:
	return ApplicationCombatPolicy.auto_abort_ids(view, queued_changes)


func abort_full_party_auto(skip_playback: bool) -> bool:
	var character_ids := combat_auto_abort_ids(session_controller.view(), _queued_combat_auto_changes)
	if character_ids.is_empty():
		return false
	for character_id: String in character_ids:
		_queued_combat_auto_changes[character_id] = false
	_shell_presenter.set_status("Full-party Auto cancelled. Manual control resumes at the next activation.")
	if skip_playback:
		presentation_coordinator.skip_combat_playback()
	else:
		_flush_queued_combat_auto_changes()
	return true


static func persistent_auto_response(view: GameView) -> InteractionResponse:
	return ApplicationCombatPolicy.persistent_auto_response(view)


func _respond_host_interaction(response: InteractionResponse) -> void:
	var action := ApplicationLifecycle.response_action(_host_interaction, response)
	if action.is_empty():
		_shell_presenter.set_status("The lifecycle response was invalid.", true)
		presentation_coordinator.present_host_interaction(_host_interaction)
		return
	var host_body := _host_interaction.body as LifecycleRequestBody
	var operation := host_body.operation if host_body != null else &""
	if operation == &"quit-application":
		_respond_quit_interaction(action)
		return
	if operation != &"end-adventure":
		_shell_presenter.set_status("The lifecycle operation was invalid.", true)
		presentation_coordinator.present_host_interaction(_host_interaction)
		return
	var result := ApplicationLifecycle.execute_end_adventure(
		action,
		func() -> bool: return save_active_session("quick"),
		func() -> SessionStep: return session_controller.close()
	)
	var result_state := StringName(result.get("state", &"invalid"))
	if result_state == &"cancelled":
		_host_interaction = null
		presentation_coordinator.refresh()
		_shell_presenter.set_status("Adventure continues.")
		return
	if result_state == &"save-failed":
		presentation_coordinator.present_host_interaction(_host_interaction)
		return
	if result_state == &"close-failed":
		var failed_step: SessionStep = result.get("step")
		var error_message := failed_step.error_message if failed_step != null else "The session close operation is unavailable."
		_shell_presenter.set_status("End Adventure failed • %s" % error_message, true)
		presentation_coordinator.present_host_interaction(_host_interaction)
		return
	if result_state == &"pending":
		_host_interaction = null
		var pending_step: SessionStep = result.get("step")
		_present_step_status(pending_step)
		return
	if result_state != &"closed":
		_shell_presenter.set_status("The lifecycle response was invalid.", true)
		presentation_coordinator.present_host_interaction(_host_interaction)
		return
	_complete_closed_session()


func _respond_quit_interaction(action: StringName) -> void:
	if action == ApplicationLifecycle.SAVE_AND_QUIT:
		_host_interaction = null
		presentation_coordinator.dismiss_host_interaction()
		_save_and_quit_pending = true
		_refresh_save_previews()
		_shell_presenter.show_save_and_quit_workspace()
		_shell_presenter.set_status("Choose a save slot, then Save and Quit.")
		return
	var has_active_session := session_controller.view().session_started
	var result_state := ApplicationLifecycle.execute_quit(
		action,
		func() -> bool: return save_active_session("quick") if has_active_session else false,
		_quit_application
	)
	if result_state == &"cancelled":
		_host_interaction = null
		presentation_coordinator.dismiss_host_interaction()
		_shell_presenter.set_status("Quit cancelled.")
		return
	if result_state == &"save-failed":
		presentation_coordinator.present_host_interaction(_host_interaction)


func _on_save_and_quit_requested(slot_id: String) -> void:
	if not _save_and_quit_pending:
		return
	if not save_active_session(slot_id):
		return
	_save_and_quit_pending = false
	_shell_presenter.set_save_and_quit_mode(false)
	_quit_application()


func _on_shell_route_changed(route_id: StringName) -> void:
	if not _save_and_quit_pending or route_id == &"system":
		return
	_save_and_quit_pending = false
	_shell_presenter.set_save_and_quit_mode(false)
	_shell_presenter.set_status("Save and quit cancelled.")


func _quit_application() -> void:
	if _package_host != null:
		_package_host.close()
	if _quit_operation.is_valid(): _quit_operation.call()
	else: get_tree().quit()


func _complete_closed_session() -> void:
	_session_close_waits_for_playback = false
	_queued_combat_auto_changes.clear()
	_host_interaction = null
	presentation_coordinator.dismiss_host_interaction()
	_active_content = null
	presentation_coordinator.set_package_media(_character_library_media)
	_refresh_save_previews()
	_refresh_vault_views()
	_refresh_campaigns()
	_shell_presenter.show_splash()
	_status_label.text = "Adventure ended • main menu"
	_shell_presenter.set_status(_status_label.text)


func _on_playback_step_settled(step: SessionStep) -> void:
	if _session_close_waits_for_playback and step_ends_session(step):
		_complete_closed_session()
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
		submit_intent(PlayerIntent.set_combat_auto(character_id, bool(changes[character_id])))


func _continue_persistent_auto_after_playback() -> void:
	# Reduced motion can settle playback before its battlefield draws. Let that
	# committed view reach the screen before another synchronous Auto activation.
	await RenderingServer.frame_post_draw
	if presentation_coordinator == null or presentation_coordinator.is_combat_playback_active() or not _queued_combat_auto_changes.is_empty() or _host_interaction != null: return
	var response := persistent_auto_response(session_controller.view())
	if response != null:
		_on_interaction_response_submitted(response)


static func should_defer_session_close(step: SessionStep, playback_active: bool) -> bool:
	return ApplicationCombatPolicy.should_defer_session_close(step, playback_active)


static func step_ends_session(step: SessionStep) -> bool:
	return ApplicationCombatPolicy.step_ends_session(step)


func _present_step_status(step: SessionStep) -> void:
	if step.state == SessionStep.State.FAILED:
		_status_label.text = "Action failed • %s" % step.error_message
		_shell_presenter.set_status(_status_label.text, true)
		return
	for event: DomainEvent in step.events:
		if event.kind == &"session_ended":
			if should_defer_session_close(step, presentation_coordinator.is_combat_playback_active()):
				_session_close_waits_for_playback = true
				return
			_complete_closed_session()
			return
		if event.kind == &"character_publication_requested":
			_publish_character_revision(String(event.payload.get("characterId", "")))
		else:
			var status_text := ApplicationStepStatusText.for_event(event)
			if not status_text.is_empty(): _status_label.text = status_text
	if step.state == SessionStep.State.WAITING_FOR_INTERACTION:
		_status_label.text = ApplicationStepStatusText.for_interaction(step.interaction)


func _publish_character_revision(character_id: String) -> bool:
	var boundary := session_controller.session().snapshot()
	var character_name := _vault_host.publish_from_snapshot(boundary, _active_content, character_id)
	if character_name.is_empty():
		_status_label.text = "Vault publication failed • %s" % _vault_host.last_error()
		return false
	_refresh_vault_views()
	_status_label.text = "Published %s to the character vault" % character_name
	return true


func _refresh_vault_views() -> void:
	_game_shell.set_vault_revisions(_vault_host.revisions(_active_content, _character_library_content))


func _begin_classic_character_library_load() -> void:
	if not _package_host.start_bundled_load(CLASSIC_CHARACTER_LIBRARY_PATH, CLASSIC_CHARACTER_LIBRARY_ID, CLASSIC_CHARACTER_LIBRARY_HASH):
		_character_library_load_complete = true
		_game_shell.set_standalone_character_creation_available(false, "The built-in Classic definitions could not start loading.")


func _poll_classic_character_library_load() -> void:
	if _character_library_load_complete or _package_host == null or _package_host.bundled_load_is_running():
		return
	var prepared := _package_host.take_bundled_package(CLASSIC_CHARACTER_LIBRARY_PATH)
	if prepared == null: return
	_character_library_load_complete = true
	if not prepared.is_ok():
		_game_shell.set_standalone_character_creation_available(false, prepared.error_message)
		_shell_presenter.set_status("Character Files creation unavailable • %s" % prepared.error_message, true)
	else:
		_character_library_content = prepared.content
		_character_library_media = prepared.media
		_package_host.set_application_content(_character_library_content, _character_library_media.assets())
		presentation_coordinator.set_application_character_media(_character_library_media)
		presentation_coordinator.set_package_media(_character_library_media)
		_vault_host.seed_classic_starters_if_empty()
		_game_shell.set_standalone_character_creation_available(true)
		_refresh_vault_views()
	if _pending_prepared_package != null:
		var pending := _pending_prepared_package
		_pending_prepared_package = null
		_complete_package_install(pending, _pending_package_seed)

func _begin_standalone_character_creation() -> void:
	if _active_content != null or session_controller.view().session_started:
		_shell_presenter.set_status("Finish the current campaign setup before opening the general Character Files creator.", true)
		return
	if _character_library_content == null:
		_shell_presenter.set_status("Character Files creation is unavailable because the built-in Classic definitions did not load.", true)
		return
	var identity := _vault_host.next_character_file_identity()
	var step := _character_creation_host.start(_character_library_content, identity)
	if step.state == SessionStep.State.FAILED:
		_shell_presenter.set_status("Character Files creation failed • %s" % step.error_message, true)
		return
	presentation_coordinator.set_package_media(_character_library_media)
	presentation_coordinator.present_host_workflow(_character_creation_host.view(), step)
	_game_shell.begin_standalone_character_creation()
	_shell_presenter.set_status("Create a reusable character with the built-in Realmz races and classes.")


func _cancel_standalone_character_creation() -> void:
	if not _character_creation_host.is_active():
		return
	_finish_standalone_character_creation("Character creation cancelled.")


func _present_standalone_character_step(step: SessionStep) -> void:
	if not _character_creation_host.is_active():
		return
	if step.state == SessionStep.State.FAILED:
		presentation_coordinator.present_host_workflow(_character_creation_host.view(), step)
		_shell_presenter.set_status("Character creation failed • %s" % step.error_message, true)
		return
	presentation_coordinator.present_host_workflow(_character_creation_host.view(), step)
	for event: DomainEvent in step.events:
		if event.kind == &"character_publication_requested":
			_publish_standalone_character_revision()
			return


func _publish_standalone_character_revision() -> void:
	var character := _character_creation_host.completed_character()
	if character == null:
		_shell_presenter.set_status("Character File publication failed • the completed character is unavailable.", true)
		return
	if not _vault_host.publish(character, _character_library_content.rules_version, "", _character_library_content.package_hash, "classic-application"):
		_shell_presenter.set_status("Character File publication failed • %s" % _vault_host.last_error(), true)
		return
	_character_creation_host.publication_committed()
	_finish_standalone_character_creation("Created Character File for %s." % character.name)


func _finish_standalone_character_creation(status: String) -> void:
	_character_creation_host.finish()
	_game_shell.finish_standalone_character_creation()
	presentation_coordinator.set_package_media(_character_library_media)
	presentation_coordinator.refresh()
	_refresh_vault_views()
	_game_shell.show_campaign_selection()
	_shell_presenter.set_status(status)


func _archive_vault_character(character_id: String) -> void:
	if not _vault_host.archive(character_id):
		_status_label.text = "Vault archive failed • %s" % _vault_host.last_error()
		_shell_presenter.set_status(_status_label.text, true)
		return
	_refresh_vault_views()
	_status_label.text = "Character archived • immutable revisions remain recoverable"
	_shell_presenter.set_status(_status_label.text)


func _restore_vault_revision(character_id: String, revision_hash: String) -> void:
	if not _vault_host.restore(character_id, revision_hash):
		_status_label.text = "Vault restore failed • %s" % _vault_host.last_error()
		_shell_presenter.set_status(_status_label.text, true)
		return
	_refresh_vault_views()
	_status_label.text = "Character revision restored as current"
	_shell_presenter.set_status(_status_label.text)


func save_active_session(slot_id: String) -> bool:
	if _active_content == null:
		_status_label.text = "Save failed • no package loaded"
		_shell_presenter.set_status(_status_label.text, true)
		return false
	var saved := _save_host.save(_active_content, slot_id, session_controller.session().snapshot())
	_status_label.text = "Saved %s" % slot_id if saved else "Save failed • %s" % _save_host.last_error()
	_shell_presenter.set_status(_status_label.text, not saved)
	if saved:
		_refresh_save_previews()
		_shell_presenter.show_activity_indicator(&"save")
	return saved


func load_active_session(slot_id: String) -> SessionStep:
	return _load_session_record(slot_id, false)


func load_backup_session(slot_id: String) -> SessionStep:
	return _load_session_record(slot_id, true)


func _load_session_record(slot_id: String, backup: bool) -> SessionStep:
	if _active_content == null:
		_status_label.text = "Load failed • no package loaded"
		_shell_presenter.set_status(_status_label.text, true)
		return SessionStep.failed(0, "no_package_loaded", "Load a package before restoring a save.")
	var envelope := _save_host.load(_active_content, slot_id, backup)
	if envelope == null:
		_status_label.text = "Load failed • %s" % _save_host.last_error()
		_shell_presenter.set_status(_status_label.text, true)
		return SessionStep.failed(session_controller.view().revision, "save_load_failed", _save_host.last_error())
	var step := session_controller.restore(_active_content, envelope)
	if step.state != SessionStep.State.FAILED:
		_queued_combat_auto_changes.clear()
	_status_label.text = "Loaded %s %s" % ["backup" if backup else "save", slot_id] if step.state != SessionStep.State.FAILED else "Load failed • %s" % step.error_message
	_shell_presenter.set_status(_status_label.text, step.state == SessionStep.State.FAILED)
	return step


func _refresh_save_previews() -> void:
	_shell_presenter.set_save_previews(_save_host.previews(_active_content))


func _refresh_campaigns() -> void:
	if _package_host != null and _package_host.operation_view().is_running():
		return
	_campaigns = _package_host.discover_available_campaigns()
	_shell_presenter.set_campaigns(_campaigns)
	_try_prewarm_last_campaign()


func _try_prewarm_last_campaign() -> void:
	if _last_campaign_prewarm_requested or _package_host == null or _character_library_content == null or _presentation_settings == null or _presentation_settings.last_campaign_id.is_empty() or bool(get_meta(&"startup_splash_suppressed", false)) and not bool(get_meta(&"startup_front_door_revealed", false)): return
	_last_campaign_prewarm_requested = true
	_package_host.prewarm_last_campaign(_campaigns, _presentation_settings.last_campaign_id)


func _on_shell_layout_changed(workspace_rect: Rect2, _profile: UiLayoutProfile) -> void:
	var inset := 8.0
	var content_rect := workspace_rect.grow(-inset)
	_map_presenter.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_map_presenter.position = content_rect.position
	_map_presenter.size = content_rect.size
	_battlefield_presenter.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_battlefield_presenter.position = content_rect.position
	_battlefield_presenter.size = content_rect.size
	if _dungeon_presenter != null:
		_dungeon_presenter.position = content_rect.position
		_dungeon_presenter.size = content_rect.size
	var projection_size := MapPresentationGeometry.projection_cells_for(_map_presenter.size, _map_presenter.map_origin.y, _map_presenter.cell_size)
	if session_controller.set_map_projection_size(projection_size): presentation_coordinator.refresh_spatial_projection()
	var canvas_rect := _profile.application_rect
	var textbox_rect := Rect2(Vector2(canvas_rect.position.x, workspace_rect.end.y), Vector2(canvas_rect.size.x, _profile.bottom_height))
	var combat_rect := Rect2(Vector2(canvas_rect.position.x, canvas_rect.end.y - _profile.bottom_height), Vector2(canvas_rect.size.x, _profile.bottom_height))
	_interaction_presenter.set_classic_regions(content_rect, textbox_rect, combat_rect)
	call_deferred("_sync_interaction_narrative_region", content_rect, combat_rect)


func _sync_interaction_narrative_region(content_rect: Rect2, combat_rect: Rect2) -> void:
	await get_tree().process_frame
	var narrative_rect := _shell_presenter.narrative_region()
	if narrative_rect.has_area():
		_interaction_presenter.set_classic_regions(content_rect, narrative_rect, combat_rect)


static func classic_textbox_rect(workspace_rect: Rect2, bottom_height: float, full_width: float = 0.0) -> Rect2:
	var width := full_width if full_width > 0.0 else workspace_rect.size.x
	return Rect2(0.0 if full_width > 0.0 else workspace_rect.position.x, workspace_rect.end.y, width, bottom_height)


static func classic_combat_rect(viewport_size: Vector2, bottom_height: float) -> Rect2:
	return Rect2(0.0, maxf(0.0, viewport_size.y - bottom_height), viewport_size.x, minf(bottom_height, viewport_size.y))


func _on_route_changed(route_id: StringName) -> void:
	_held_movement.stop()
	presentation_coordinator.set_active_route(route_id)
