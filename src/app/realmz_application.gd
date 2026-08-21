class_name RealmzApplication
extends Control

const GameSessionControllerScript := preload("res://src/app/game_session_controller.gd")
const PresentationCoordinatorScript := preload("res://src/presentation/presentation_coordinator.gd")
const PackageHostControllerScript := preload("res://src/app/controllers/package_host_controller.gd")
const SaveHostControllerScript := preload("res://src/app/controllers/save_host_controller.gd")
const CharacterVaultControllerScript := preload("res://src/app/controllers/character_vault_controller.gd")
const CharacterCreationHostControllerScript := preload("res://src/app/controllers/character_creation_host_controller.gd")
const SettingsRepositoryScript := preload("res://src/infrastructure/settings/settings_repository.gd")
const DungeonMap3DPresenterScript := preload("res://src/presentation/dungeon_map_3d_presenter.gd")
const ApplicationLifecycleScript := preload("res://src/app/application_lifecycle.gd")
const HeldMovementControllerScript := preload("res://src/presentation/held_movement_controller.gd")
const CLASSIC_CHARACTER_LIBRARY_PATH := "res://src/infrastructure/characters/realmz-classic-character-library.realmz2"
const CLASSIC_CHARACTER_LIBRARY_ID := "realmz-classic-character-library"
const CLASSIC_CHARACTER_LIBRARY_HASH := "d134c8f552d4e5893dcf82ea25bd21504c45a1e0cffb84bf4061a1b83ec00b49"

@onready var _status_label: Label = $ClassicShell/BottomRegion/BottomRow/NarrativeWell/NarrativeColumn/Facts/Status
@onready var _smoke_button: Button = $ClassicShell/SmokeAction
@onready var _map_presenter: ClassicMapPresenter = %ExplorationMap
@onready var _battlefield_presenter: ClassicBattlefieldPresenter = %BattlefieldMap
@onready var _interaction_presenter: InteractionPresenter = %InteractionPanel
@onready var _shell_presenter: ClassicApplicationShell = $ClassicShell
@onready var _classic_shell: ClassicApplicationShell = $ClassicShell
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
var _character_creation_host: CharacterCreationHostController
var _session_close_waits_for_playback: bool = false
var _held_movement: HeldMovementControllerScript


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	UiInputActions.ensure_defaults()
	_package_host = PackageHostControllerScript.new()
	_save_host = SaveHostControllerScript.new()
	_vault_host = CharacterVaultControllerScript.new()
	_character_creation_host = CharacterCreationHostControllerScript.new()
	settings_repository = SettingsRepositoryScript.new()
	_presentation_settings = settings_repository.load_settings()
	session_controller = GameSessionControllerScript.new()
	presentation_coordinator = PresentationCoordinatorScript.new()
	_dungeon_presenter = DungeonMap3DPresenterScript.new()
	_held_movement = HeldMovementControllerScript.new()
	add_child(session_controller)
	add_child(presentation_coordinator)
	add_child(_dungeon_presenter)
	add_child(_held_movement)
	_held_movement.set_speed_percent(_presentation_settings.exploration_speed_percent)
	_held_movement.movement_requested.connect(_on_held_movement_requested)
	presentation_coordinator.bind(session_controller, _map_presenter, _battlefield_presenter, _dungeon_presenter, _interaction_presenter, _shell_presenter, _audio_presenter)
	presentation_coordinator.playback_step_settled.connect(_on_playback_step_settled)
	_interaction_presenter.response_submitted.connect(_on_interaction_response_submitted)
	_interaction_presenter.combat_targeting_requested.connect(_on_combat_targeting_requested)
	_interaction_presenter.combat_targeting_confirm_requested.connect(_battlefield_presenter.confirm_targeting)
	_interaction_presenter.combat_targeting_cancel_requested.connect(_battlefield_presenter.cancel_targeting)
	_interaction_presenter.combatant_focus_requested.connect(_on_combatant_focus_requested)
	_interaction_presenter.reveal_friends_requested.connect(_on_reveal_friends_requested)
	_interaction_presenter.presentation_sound_requested.connect(_on_interaction_sound_requested)
	_interaction_presenter.presentation_status_requested.connect(_shell_presenter.set_status)
	_map_presenter.movement_hold_started.connect(func(direction: Vector2i) -> void: _held_movement.start(&"mouse", direction))
	_map_presenter.movement_hold_updated.connect(func(direction: Vector2i) -> void: _held_movement.update(&"mouse", direction))
	_map_presenter.movement_hold_stopped.connect(func() -> void: _held_movement.stop(&"mouse"))
	_battlefield_presenter.combat_body_submitted.connect(_on_battlefield_action_requested)
	_battlefield_presenter.combatant_inspected.connect(_on_battlefield_combatant_inspected)
	_battlefield_presenter.targeting_changed.connect(_interaction_presenter.update_combat_targeting)
	_battlefield_presenter.targeting_cancelled.connect(_interaction_presenter.combat_targeting_cancelled)
	_shell_presenter.start_package_requested.connect(_begin_package_start)
	_shell_presenter.cancel_package_requested.connect(_cancel_package_start)
	_shell_presenter.refresh_campaigns_requested.connect(_refresh_campaigns)
	_shell_presenter.intent_submitted.connect(_submit_intent)
	_shell_presenter.save_requested.connect(save_active_session)
	_shell_presenter.load_requested.connect(load_active_session)
	_shell_presenter.load_backup_requested.connect(load_backup_session)
	_shell_presenter.refresh_saves_requested.connect(_refresh_save_previews)
	_shell_presenter.end_adventure_requested.connect(_on_end_adventure_requested)
	_shell_presenter.quit_requested.connect(_on_quit_requested)
	_shell_presenter.topology_debug_changed.connect(_on_topology_debug_changed)
	_shell_presenter.dungeon_3d_changed.connect(_on_dungeon_3d_changed)
	_shell_presenter.master_volume_changed.connect(_on_master_volume_changed)
	_shell_presenter.text_scale_changed.connect(_on_text_scale_changed)
	_shell_presenter.typography_mode_changed.connect(_on_typography_mode_changed)
	_shell_presenter.ui_scale_mode_changed.connect(_on_ui_scale_mode_changed)
	_shell_presenter.window_mode_changed.connect(_on_window_mode_changed)
	_shell_presenter.reduced_motion_changed.connect(_on_reduced_motion_changed)
	_shell_presenter.auto_switch_to_melee_changed.connect(_on_auto_switch_to_melee_changed)
	_shell_presenter.exploration_speed_changed.connect(_on_exploration_speed_changed)
	_shell_presenter.exploration_minimap_changed.connect(_on_exploration_minimap_changed)
	_shell_presenter.autojournal_changed.connect(_on_autojournal_changed)
	_shell_presenter.layout_changed.connect(_on_shell_layout_changed)
	_shell_presenter.route_changed.connect(_on_route_changed)
	_shell_presenter.vault_archive_requested.connect(_archive_vault_character)
	_shell_presenter.vault_restore_requested.connect(_restore_vault_revision)
	_shell_presenter.standalone_character_creation_requested.connect(_begin_standalone_character_creation)
	_shell_presenter.standalone_character_creation_cancelled.connect(_cancel_standalone_character_creation)
	_shell_presenter.character_selection_completed.connect(_interaction_presenter.submit_character_selection)
	_shell_presenter.apply_settings(_presentation_settings)
	presentation_coordinator.set_reduced_motion(_presentation_settings.reduced_motion)
	_apply_application_theme()
	_interaction_presenter.set_text_scale(_presentation_settings.text_scale)
	_interaction_presenter.set_autojournal_enabled(_presentation_settings.autojournal_enabled)
	_map_presenter.set_travel_preview_visible(_presentation_settings.show_exploration_minimap)
	_apply_window_mode(_presentation_settings.window_mode)
	_audio_presenter.set_master_volume(_presentation_settings.master_volume)
	_on_topology_debug_changed(_presentation_settings.topology_debug)
	_on_dungeon_3d_changed(_presentation_settings.dungeon_3d)
	_load_classic_character_library()
	_status_label.text = "Pure session boundary online"
	_refresh_campaigns()
	_refresh_vault_views()
	set_process(true)


func _process(_delta: float) -> void:
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
	var step := _submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	if step.state == SessionStep.State.FAILED:
		return
	var roll: int = step.events[0].payload.get("roll", 0)
	var current_view := session_controller.view()
	_status_label.text = "Search committed • roll %d • day %d %02d:%02d" % [roll, current_view.realmz_day, current_view.realmz_hour, current_view.realmz_minute]


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _held_movement != null:
		_held_movement.stop()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_quit_requested()


func _on_quit_requested() -> void:
	_held_movement.stop()
	if _host_interaction != null:
		return
	var current_view := session_controller.view()
	var combat_view := current_view.combat_view
	var in_combat := combat_view != null and combat_view.outcome == &"active"
	_host_interaction = ApplicationLifecycleScript.quit_application_request(current_view.session_started, in_combat)
	presentation_coordinator.present_host_interaction(_host_interaction)
	_shell_presenter.set_status("Confirm whether to quit Realmz Rebuilt.")


func _on_end_adventure_requested() -> void:
	_held_movement.stop()
	if not session_controller.view().session_started:
		_shell_presenter.show_campaign_selection()
		return
	var pending := session_controller.view().active_interaction_request()
	if pending != null and pending.kind != InteractionRequest.COMBAT:
		_shell_presenter.set_status("Resolve the current interaction before ending the adventure.", true)
		return
	if _host_interaction != null:
		return
	var combat_view := session_controller.view().combat_view
	var in_combat := combat_view != null and combat_view.outcome == &"active"
	_host_interaction = ApplicationLifecycleScript.end_adventure_request(in_combat)
	presentation_coordinator.present_host_interaction(_host_interaction)
	_shell_presenter.set_status("Choose how to end the active adventure.")


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
	var step := session_controller.start(prepared.content, initial_seed)
	if step.state == SessionStep.State.FAILED:
		_status_label.text = "Session start failed • %s" % step.error_message
		_shell_presenter.set_status(_status_label.text, true)
		return step
	_active_content = prepared.content
	_package_host.promote(prepared)
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
	var released_direction := UiInputActions.released_movement_direction(event)
	if released_direction != Vector2i.ZERO and _held_movement != null and _held_movement.active_direction() == released_direction:
		_held_movement.stop(&"keyboard")
	if presentation_coordinator != null and presentation_coordinator.is_combat_playback_active():
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_SPACE:
			presentation_coordinator.skip_combat_playback()
		get_viewport().set_input_as_handled()
		return
	var pending := session_controller.view().active_interaction_request()
	var combat_pending := pending != null and pending.kind == InteractionRequest.COMBAT
	if combat_pending and event.is_action_pressed(&"realmz_inspect_movement"):
		_battlefield_presenter.set_movement_costs_visible(true)
		get_viewport().set_input_as_handled()
		return
	if combat_pending and event.is_action_released(&"realmz_inspect_movement"):
		_battlefield_presenter.set_movement_costs_visible(false)
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed():
		return
	if combat_pending and _battlefield_presenter.dismiss_reveal_friends():
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"realmz_back"):
		if combat_pending and _battlefield_presenter.cancel_targeting():
			get_viewport().set_input_as_handled()
			return
		if _interaction_presenter.has_blocking_request():
			_shell_presenter.set_status("Choose a response before leaving this interaction.")
			get_viewport().set_input_as_handled()
			return
		if _interaction_presenter.dismiss_passive_text() or _shell_presenter.handle_back():
			get_viewport().set_input_as_handled()
			return
	if _host_interaction != null:
		return
	if pending != null:
		if pending.kind == InteractionRequest.COMBAT:
			var combat_fast_spell := UiInputActions.fast_spell_slot(event)
			if combat_fast_spell >= 0 and _interaction_presenter.handle_fast_spell(combat_fast_spell, UiInputActions.fast_spell_use_requested(event)):
				get_viewport().set_input_as_handled()
				return
			var combat_direction := UiInputActions.movement_direction(event)
			if combat_direction != Vector2i.ZERO and _interaction_presenter.accepts_combat_spatial_input() and _battlefield_presenter.submit_movement_direction(combat_direction):
				get_viewport().set_input_as_handled()
		return
	if accepts_route_input() and _shell_presenter.handle_route_shortcut(event):
		get_viewport().set_input_as_handled()
		return
	if not accepts_exploration_input():
		return
	var fast_spell_slot := UiInputActions.fast_spell_slot(event)
	if fast_spell_slot >= 0:
		_handle_field_fast_spell(fast_spell_slot, UiInputActions.fast_spell_use_requested(event))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"realmz_search"):
		_submit_intent(PlayerIntent.toggle_search())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"realmz_camp"):
		_submit_intent(PlayerIntent.camp())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"realmz_rest"):
		_submit_intent(PlayerIntent.rest())
		get_viewport().set_input_as_handled()
		return
	var direction := UiInputActions.movement_direction(event)
	if direction != Vector2i.ZERO:
		if not event is InputEventKey or not (event as InputEventKey).echo:
			_held_movement.start(&"keyboard", direction)
		get_viewport().set_input_as_handled()


func accepts_route_input() -> bool:
	if _host_interaction != null or presentation_coordinator == null or _interaction_presenter == null:
		return false
	if presentation_coordinator.is_combat_playback_active() or _interaction_presenter.has_blocking_request():
		return false
	return ClassicApplicationShell.route_change_reason(session_controller.view()).is_empty()


func accepts_exploration_input() -> bool:
	if _host_interaction != null or presentation_coordinator == null or _interaction_presenter == null or _shell_presenter == null:
		return false
	if presentation_coordinator.is_combat_playback_active() or _interaction_presenter.has_blocking_request():
		return false
	var view := session_controller.view()
	return view != null and view.session_started and view.pending_interaction == null and _shell_presenter.accepts_exploration_input()


func _handle_field_fast_spell(slot_index: int, use_spell: bool) -> void:
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
	_submit_intent(PlayerIntent.cast_spell(binding["spellId"], binding["characterId"], "", binding["power"]))


func _on_held_movement_requested(direction: Vector2i) -> void:
	if not _submit_movement(direction):
		_held_movement.stop()


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
	_interaction_presenter.inspect_combatant(combatant_id)


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
	var step := _submit_intent(PlayerIntent.move(direction))
	var after := session_controller.view()
	if step.state == SessionStep.State.FAILED or after == null or after.pending_interaction != null or after.combat_view != null:
		return false
	for event: DomainEvent in step.events:
		if event.kind in [&"movement_blocked", &"map_transitioned", &"trigger_fired", &"timed_encounter_triggered", &"random_region_triggered", &"random_door_triggered", &"random_encounter_triggered"]:
			return false
	return before.party_map_id == after.party_map_id and before.party_coordinate != after.party_coordinate and accepts_exploration_input()


func _submit_intent(intent: PlayerIntent) -> SessionStep:
	if _character_creation_host.is_active():
		var creator_step: SessionStep = _character_creation_host.submit(intent)
		_present_standalone_character_step(creator_step)
		return creator_step
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
	if current_view.pending_interaction == null and current_view.combat_action_request != null and response.request_id == current_view.combat_action_request.request_id and response.kind == InteractionRequest.COMBAT:
		var direct_intent := direct_combat_intent(response.body as InteractionResponse.CombatBody)
		if direct_intent == null:
			_shell_presenter.set_status("The combat command was invalid.", true)
			presentation_coordinator.refresh()
			return
		var direct_step := _submit_intent(direct_intent)
		if direct_step.state == SessionStep.State.COMPLETED and direct_step.events.is_empty() and session_controller.view().pending_interaction == null:
			_shell_presenter.set_status("")
		return
	var step := session_controller.respond(response)
	_present_step_status(step)
	if step.state == SessionStep.State.COMPLETED and step.events.is_empty() and session_controller.view().pending_interaction == null:
		_shell_presenter.set_status("")


static func interaction_response_owner(has_host_interaction: bool, standalone_creator_active: bool) -> StringName:
	if has_host_interaction:
		return &"host"
	if standalone_creator_active:
		return &"standalone-creator"
	return &"session"


static func direct_combat_intent(body: InteractionResponse.CombatBody) -> PlayerIntent:
	if body == null or not body.is_valid():
		return null
	match body.action:
		&"set_auto":
			return PlayerIntent.set_combat_auto(body.actor_id, body.enabled)
		&"move", &"retreat_edge":
			if not body.has_destination:
				return null
			return PlayerIntent.combat_move(body.actor_id, body.destination, body.auto_switch_to_melee)
		&"cast_spell":
			if body.spell_id.is_empty():
				return null
			if body.has_target_coordinate:
				return PlayerIntent.cast_spell_at(body.spell_id, body.actor_id, body.target_coordinate, body.power, body.rotation)
			if not body.target_ids.is_empty():
				return PlayerIntent.cast_spell_at_targets(body.spell_id, body.actor_id, body.target_ids, body.power)
			return PlayerIntent.cast_spell(body.spell_id, body.actor_id, body.target_id, body.power)
		&"use_item":
			if body.item_instance_id.is_empty():
				return null
			return PlayerIntent.use_item_on_target(body.item_instance_id, body.actor_id, body.target_id, body.target_ids, body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE, body.rotation)
		&"use_scroll":
			if body.scroll_slot < 0:
				return null
			return PlayerIntent.use_scroll_on_target(body.actor_id, body.scroll_slot, body.target_id, body.target_ids, body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE, body.rotation)
	return PlayerIntent.combat_action(body.action, body.actor_id, body.target_id)


func _respond_host_interaction(response: InteractionResponse) -> void:
	var action := ApplicationLifecycleScript.response_action(_host_interaction, response)
	if action.is_empty():
		_shell_presenter.set_status("The lifecycle response was invalid.", true)
		presentation_coordinator.present_host_interaction(_host_interaction)
		return
	var host_body := _host_interaction.body as InteractionRequest.LifecycleRequestBody
	var operation := host_body.operation if host_body != null else &""
	if operation == &"quit-application":
		_respond_quit_interaction(action)
		return
	if operation != &"end-adventure":
		_shell_presenter.set_status("The lifecycle operation was invalid.", true)
		presentation_coordinator.present_host_interaction(_host_interaction)
		return
	var result := ApplicationLifecycleScript.execute_end_adventure(
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
	var has_active_session := session_controller.view().session_started
	var result_state := ApplicationLifecycleScript.execute_quit(
		action,
		func() -> bool: return save_active_session("quick") if has_active_session else false,
		_quit_application
	)
	if result_state == &"cancelled":
		_host_interaction = null
		presentation_coordinator.refresh()
		_shell_presenter.set_status("Quit cancelled.")
		return
	if result_state == &"save-failed":
		presentation_coordinator.present_host_interaction(_host_interaction)
		return
	if result_state != &"quit-requested":
		_shell_presenter.set_status("Quit failed • the application remains open.", true)
		presentation_coordinator.present_host_interaction(_host_interaction)


func _quit_application() -> void:
	if _package_host != null:
		_package_host.close()
	get_tree().quit()


func _complete_closed_session() -> void:
	_session_close_waits_for_playback = false
	_host_interaction = null
	_active_content = null
	presentation_coordinator.set_package_media(_character_library_media)
	_refresh_save_previews()
	_refresh_vault_views()
	_refresh_campaigns()
	_shell_presenter.show_campaign_selection()
	_status_label.text = "Adventure ended • choose a campaign"
	_shell_presenter.set_status(_status_label.text)


func _on_playback_step_settled(step: SessionStep) -> void:
	if _session_close_waits_for_playback and step_ends_session(step):
		_complete_closed_session()


static func should_defer_session_close(step: SessionStep, playback_active: bool) -> bool:
	return playback_active and step_ends_session(step)


static func step_ends_session(step: SessionStep) -> bool:
	if step == null:
		return false
	return step.events.any(func(event: DomainEvent) -> bool: return event.kind == &"session_ended")


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
		match event.kind:
			&"character_draft_generated":
				_status_label.text = "Classic character roll ready for review"
			&"character_draft_spells_changed":
				_status_label.text = "%d starting-spell points remain" % event.payload.get("remaining", 0)
			&"character_spell_confirmation_requested":
				_status_label.text = "%d starting-spell points remain • confirm acceptance" % event.payload.get("remaining", 0)
			&"character_spell_confirmation_declined":
				_status_label.text = "Choose more starting spells or accept the remaining points"
			&"character_draft_cancelled":
				_status_label.text = "Character creation cancelled"
			&"character_finalized":
				_status_label.text = "Character added to party setup"
			&"character_vault_confirmation_requested":
				_status_label.text = "Character added • choose whether to publish a reusable vault revision"
			&"character_publication_requested":
				_publish_character_revision(String(event.payload.get("characterId", "")))
			&"character_publication_declined":
				_status_label.text = "Character kept in this campaign party only"
			&"vault_character_imported":
				_status_label.text = "Vault character added to party setup"
			&"party_member_removed":
				_status_label.text = "Character removed from party setup"
			&"party_created":
				_status_label.text = "Party assembled • the adventure begins"
			&"character_age_changed":
				_status_label.text = "%s entered a new age group" % event.payload.get("characterName", "A party member")
			&"message_shown":
				_status_label.text = "Scenario text" if event.payload.has("classicClick") else event.payload.get("text", "Message")
			&"map_transitioned":
				_status_label.text = "Entered %s" % event.payload.get("targetMapId", "map")
			&"movement_blocked":
				_status_label.text = "Blocked • %s" % event.payload.get("reason", "unknown")
	if step.state == SessionStep.State.WAITING_FOR_INTERACTION:
		var acknowledge := step.interaction.body as InteractionRequest.AcknowledgeBody
		if step.interaction.kind == &"acknowledge" and acknowledge != null and acknowledge.presentation == &"classic-textbox":
			_status_label.text = "Scenario text • continue when ready"
		else:
			var prompt := step.interaction.body.prompt_text()
			_status_label.text = prompt if not prompt.is_empty() else "Choose an option"


func _publish_character_revision(character_id: String) -> bool:
	if _active_content == null or character_id.is_empty():
		_status_label.text = "Vault publication failed • no active character or campaign"
		return false
	var boundary := session_controller.session().snapshot()
	if boundary == null:
		_status_label.text = "Vault publication failed • the session is not at a committed boundary"
		return false
	var source_character := boundary.game_state.party.character_by_id(character_id)
	if source_character == null:
		_status_label.text = "Vault publication failed • the character is unavailable"
		return false
	var character := CharacterState.from_data(source_character.to_data())
	if character == null:
		_status_label.text = "Vault publication failed • the character state is invalid"
		return false
	if not _vault_host.publish(character, _active_content.rules_version, _active_content.campaign_id, _active_content.package_hash, "character-creation"):
		_status_label.text = "Vault publication failed • %s" % _vault_host.last_error()
		return false
	_refresh_vault_views()
	_status_label.text = "Published %s to the character vault" % character.name
	return true


func _refresh_vault_views() -> void:
	_classic_shell.set_vault_revisions(_vault_host.revisions(_active_content, _character_library_content))


func _load_classic_character_library() -> void:
	var prepared := _package_host.load_bundled(CLASSIC_CHARACTER_LIBRARY_PATH, CLASSIC_CHARACTER_LIBRARY_ID, CLASSIC_CHARACTER_LIBRARY_HASH)
	if not prepared.is_ok():
		_classic_shell.set_standalone_character_creation_available(false, prepared.error_message)
		_shell_presenter.set_status("Character Files creation unavailable • %s" % prepared.error_message, true)
		return
	_character_library_content = prepared.content
	_character_library_media = prepared.media
	presentation_coordinator.set_package_media(_character_library_media)
	_classic_shell.set_standalone_character_creation_available(true)


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
	_classic_shell.begin_standalone_character_creation()
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
	_classic_shell.finish_standalone_character_creation()
	presentation_coordinator.set_package_media(_character_library_media)
	presentation_coordinator.refresh()
	_refresh_vault_views()
	_classic_shell.show_campaign_selection()
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
	_status_label.text = "Loaded %s %s" % ["backup" if backup else "save", slot_id] if step.state != SessionStep.State.FAILED else "Load failed • %s" % step.error_message
	_shell_presenter.set_status(_status_label.text, step.state == SessionStep.State.FAILED)
	return step


func _refresh_save_previews() -> void:
	_shell_presenter.set_save_previews(_save_host.previews(_active_content))


func _refresh_campaigns() -> void:
	if _package_host != null and _package_host.operation_view().is_running():
		return
	_shell_presenter.set_campaigns(_package_host.discover_campaigns(["user://packages"]))


func _on_topology_debug_changed(enabled: bool) -> void:
	_map_presenter.show_debug_facts = enabled
	_map_presenter.queue_redraw()
	if _presentation_settings != null:
		_presentation_settings.topology_debug = enabled
		settings_repository.save_settings(_presentation_settings)


func _on_dungeon_3d_changed(enabled: bool) -> void:
	presentation_coordinator.set_dungeon_3d_enabled(enabled)
	if _presentation_settings != null:
		_presentation_settings.dungeon_3d = enabled
		settings_repository.save_settings(_presentation_settings)


func _on_master_volume_changed(value: float) -> void:
	_audio_presenter.set_master_volume(value)
	_presentation_settings.master_volume = value
	settings_repository.save_settings(_presentation_settings)


func _on_text_scale_changed(value: float) -> void:
	_presentation_settings.text_scale = value
	_apply_application_theme()
	_interaction_presenter.set_text_scale(value)
	_shell_presenter.apply_settings(_presentation_settings)
	settings_repository.save_settings(_presentation_settings)


func _on_ui_scale_mode_changed(value: String) -> void:
	_presentation_settings.ui_scale_mode = value
	_shell_presenter.apply_settings(_presentation_settings)
	settings_repository.save_settings(_presentation_settings)


func _on_window_mode_changed(value: String) -> void:
	_presentation_settings.window_mode = value
	_apply_window_mode(value)
	settings_repository.save_settings(_presentation_settings)


func _apply_window_mode(value: String) -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if value == PresentationSettings.BORDERLESS_FULLSCREEN else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)


func _apply_application_theme() -> void:
	var base_theme := load("res://src/presentation/classic_ui_theme.tres") as Theme
	theme = ClassicTypography.themed_copy(base_theme, _presentation_settings)


func _on_typography_mode_changed(value: String) -> void:
	if value not in [PresentationSettings.TYPOGRAPHY_CLASSIC, PresentationSettings.TYPOGRAPHY_READABLE]:
		return
	_presentation_settings.typography_mode = value
	_apply_application_theme()
	_shell_presenter.apply_settings(_presentation_settings)
	settings_repository.save_settings(_presentation_settings)


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
	var textbox_rect := classic_textbox_rect(workspace_rect, _profile.bottom_height, size.x)
	_interaction_presenter.set_classic_regions(content_rect, textbox_rect, classic_combat_rect(size, _profile.bottom_height))


static func classic_textbox_rect(workspace_rect: Rect2, bottom_height: float, full_width: float = 0.0) -> Rect2:
	var width := full_width if full_width > 0.0 else workspace_rect.size.x
	return Rect2(0.0 if full_width > 0.0 else workspace_rect.position.x, workspace_rect.end.y, width, bottom_height)


static func classic_combat_rect(viewport_size: Vector2, bottom_height: float) -> Rect2:
	return Rect2(0.0, maxf(0.0, viewport_size.y - bottom_height), viewport_size.x, minf(bottom_height, viewport_size.y))


func _on_reduced_motion_changed(enabled: bool) -> void:
	_presentation_settings.reduced_motion = enabled
	presentation_coordinator.set_reduced_motion(enabled)
	settings_repository.save_settings(_presentation_settings)


func _on_auto_switch_to_melee_changed(enabled: bool) -> void:
	_presentation_settings.auto_switch_to_melee = enabled
	settings_repository.save_settings(_presentation_settings)


func _on_exploration_speed_changed(percent: int) -> void:
	_presentation_settings.exploration_speed_percent = clampi(snappedi(percent, 25), 25, 400)
	_held_movement.set_speed_percent(_presentation_settings.exploration_speed_percent)
	settings_repository.save_settings(_presentation_settings)


func _on_exploration_minimap_changed(enabled: bool) -> void:
	_presentation_settings.show_exploration_minimap = enabled
	_map_presenter.set_travel_preview_visible(enabled)
	settings_repository.save_settings(_presentation_settings)


func _on_autojournal_changed(enabled: bool) -> void:
	_presentation_settings.autojournal_enabled = enabled
	_interaction_presenter.set_autojournal_enabled(enabled)
	settings_repository.save_settings(_presentation_settings)


func _on_route_changed(route_id: StringName) -> void:
	_held_movement.stop()
	presentation_coordinator.set_active_route(route_id)
