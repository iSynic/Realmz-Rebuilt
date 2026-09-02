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
const DebugToolsHostScript := preload("res://src/app/debug_tools_host.gd")
const CLASSIC_CHARACTER_LIBRARY_PATH := "res://src/infrastructure/characters/realmz-classic-character-library.realmz2"
const CLASSIC_CHARACTER_LIBRARY_ID := "realmz-classic-character-library"
const CLASSIC_CHARACTER_LIBRARY_HASH := "c7e093f46bcca49d2382d68c2995ae5ff90c0e706dbd538682b613af9b80e0bd"

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
var _pending_package_seed: int = 1; var _last_package_operation_key: String = ""
var _character_library_content: RealmzContent; var _character_library_media: MediaSource
var _character_library_load_complete: bool = false; var _pending_prepared_package: PreparedPackage
var _character_creation_host: CharacterCreationHostController
var _session_close_waits_for_playback: bool = false
var _held_movement: HeldMovementControllerScript
var _queued_combat_auto_changes: Dictionary = {}
var _save_and_quit_pending: bool = false; var _quit_operation: Callable
var _debug_tools: DebugToolsHost; var _campaigns: Array[CampaignPackageView] = []; var _last_campaign_prewarm_requested: bool = false


func configure_lifecycle_host(save_host: SaveHostController, quit_operation: Callable = Callable()) -> void: assert(not is_node_ready(), "Lifecycle host dependencies must be configured before the application enters the scene tree"); _save_host = save_host; _quit_operation = quit_operation


func _ready() -> void:
	get_tree().set_auto_accept_quit(false); UiInputActions.ensure_defaults()
	_package_host = PackageHostControllerScript.new(); if _save_host == null: _save_host = SaveHostControllerScript.new()
	_vault_host = CharacterVaultControllerScript.new(); _character_creation_host = CharacterCreationHostControllerScript.new()
	settings_repository = SettingsRepositoryScript.new(); _presentation_settings = settings_repository.load_settings()
	session_controller = GameSessionControllerScript.new(); presentation_coordinator = PresentationCoordinatorScript.new()
	_dungeon_presenter = DungeonMap3DPresenterScript.new(); _held_movement = HeldMovementControllerScript.new()
	add_child(session_controller); add_child(presentation_coordinator)
	add_child(_dungeon_presenter); add_child(_held_movement)
	_debug_tools = DebugToolsHostScript.new(); add_child(_debug_tools)
	_debug_tools.bind(session_controller, self, func() -> RealmzContent: return _active_content)
	_debug_tools.status_changed.connect(func(message: String, failed: bool) -> void: _shell_presenter.set_status(message, failed))
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
	_dungeon_presenter.turn_requested.connect(func(delta: int) -> void: _submit_intent(PlayerIntent.dungeon_turn(delta))); _dungeon_presenter.movement_requested.connect(func(direction: Vector2i) -> void: _submit_movement(direction)); _dungeon_presenter.movement_hold_started.connect(func(direction: Vector2i) -> void: _held_movement.start(&"keyboard", direction)); _dungeon_presenter.movement_hold_stopped.connect(func() -> void: _held_movement.stop(&"keyboard"))
	_battlefield_presenter.combat_body_submitted.connect(_on_battlefield_action_requested)
	_battlefield_presenter.combatant_inspected.connect(_on_battlefield_combatant_inspected)
	_battlefield_presenter.targeting_changed.connect(_interaction_presenter.update_combat_targeting)
	_battlefield_presenter.targeting_cancelled.connect(_interaction_presenter.combat_targeting_cancelled)
	_shell_presenter.start_package_requested.connect(_begin_package_start)
	_shell_presenter.cancel_package_requested.connect(_cancel_package_start)
	_shell_presenter.refresh_campaigns_requested.connect(_refresh_campaigns)
	_shell_presenter.intent_submitted.connect(_submit_intent)
	_shell_presenter.save_requested.connect(save_active_session)
	_shell_presenter.save_and_quit_requested.connect(_on_save_and_quit_requested)
	_shell_presenter.load_requested.connect(load_active_session)
	_shell_presenter.load_backup_requested.connect(load_backup_session)
	_shell_presenter.refresh_saves_requested.connect(_refresh_save_previews)
	_shell_presenter.end_adventure_requested.connect(_on_end_adventure_requested)
	_shell_presenter.quit_requested.connect(_on_quit_requested)
	_shell_presenter.route_changed.connect(_on_shell_route_changed)
	_shell_presenter.topology_debug_changed.connect(_on_topology_debug_changed)
	_shell_presenter.dungeon_3d_changed.connect(_on_dungeon_3d_changed)
	_shell_presenter.master_volume_changed.connect(_on_master_volume_changed)
	_shell_presenter.sound_volume_changed.connect(_on_sound_volume_changed)
	_shell_presenter.music_volume_changed.connect(_on_music_volume_changed)
	_shell_presenter.music_enabled_changed.connect(_on_music_enabled_changed)
	_shell_presenter.music_playlist_mode_changed.connect(_on_music_playlist_mode_changed)
	_shell_presenter.text_scale_changed.connect(_on_text_scale_changed)
	_shell_presenter.typography_mode_changed.connect(_on_typography_mode_changed)
	_shell_presenter.ui_scale_mode_changed.connect(_on_ui_scale_mode_changed)
	_shell_presenter.window_mode_changed.connect(_on_window_mode_changed)
	_shell_presenter.reduced_motion_changed.connect(_on_reduced_motion_changed); _shell_presenter.reduced_sound_changed.connect(_on_reduced_sound_changed)
	_shell_presenter.auto_switch_to_melee_changed.connect(_on_auto_switch_to_melee_changed)
	_shell_presenter.exploration_speed_changed.connect(_on_exploration_speed_changed); _shell_presenter.combat_playback_speed_changed.connect(_on_combat_playback_speed_changed)
	_shell_presenter.exploration_minimap_changed.connect(_on_exploration_minimap_changed); _shell_presenter.classic_exploration_visibility_changed.connect(_on_classic_exploration_visibility_changed)
	_shell_presenter.autojournal_changed.connect(_on_autojournal_changed)
	_shell_presenter.layout_changed.connect(_on_shell_layout_changed)
	_shell_presenter.route_changed.connect(_on_route_changed)
	_shell_presenter.vault_archive_requested.connect(_archive_vault_character)
	_shell_presenter.vault_restore_requested.connect(_restore_vault_revision)
	_shell_presenter.standalone_character_creation_requested.connect(_begin_standalone_character_creation)
	_shell_presenter.standalone_character_creation_cancelled.connect(_cancel_standalone_character_creation)
	_shell_presenter.character_selection_completed.connect(_interaction_presenter.submit_character_selection)
	_audio_presenter.music_state_changed.connect(_shell_presenter.set_music_playback_state)
	_shell_presenter.apply_settings(_presentation_settings)
	presentation_coordinator.set_reduced_motion(_presentation_settings.reduced_motion); presentation_coordinator.set_combat_playback_speed_percent(_presentation_settings.combat_playback_speed_percent); presentation_coordinator.set_exploration_speed_percent(_presentation_settings.exploration_speed_percent)
	_apply_application_theme()
	_interaction_presenter.set_text_scale(_presentation_settings.text_scale)
	_interaction_presenter.set_autojournal_enabled(_presentation_settings.autojournal_enabled)
	_map_presenter.set_travel_preview_visible(_presentation_settings.show_exploration_minimap); _map_presenter.set_classic_exploration_visibility(_presentation_settings.classic_exploration_visibility)
	_apply_window_mode(_presentation_settings.window_mode)
	_audio_presenter.set_master_volume(_presentation_settings.master_volume)
	_audio_presenter.set_sound_volume(_presentation_settings.sound_volume); _audio_presenter.set_reduced_sound(_presentation_settings.reduced_sound)
	_audio_presenter.set_music_volume(_presentation_settings.music_volume)
	_on_topology_debug_changed(_presentation_settings.topology_debug)
	_on_dungeon_3d_changed(_presentation_settings.dungeon_3d)
	_classic_shell.set_standalone_character_creation_available(false, "Loading the built-in Classic definitions…"); call_deferred("_begin_classic_character_library_load")
	_status_label.text = "Pure session boundary online"
	_refresh_campaigns()
	_refresh_vault_views()
	set_process(true)


func _process(_delta: float) -> void:
	_poll_classic_character_library_load(); _try_prewarm_last_campaign(); if _held_movement != null and _held_movement.is_active():
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
		_pending_prepared_package = prepared; _shell_presenter.set_status("Campaign ready • finishing the built-in Classic definitions…"); return
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
	_host_interaction = ApplicationLifecycleScript.quit_application_request(current_view.session_started, in_combat)
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
	_host_interaction = ApplicationLifecycleScript.end_adventure_request(in_combat)
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
	_package_host.promote(prepared); if _presentation_settings.last_campaign_id != _active_content.campaign_id: _presentation_settings.last_campaign_id = _active_content.campaign_id; settings_repository.save_settings(_presentation_settings)
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
	if _debug_tools != null and _debug_tools.handle_input(event): get_viewport().set_input_as_handled(); return
	if _debug_tools != null and _debug_tools.is_open(): return
	if _interaction_presenter != null and _interaction_presenter.handle_global_pointer_acknowledgement(event): get_viewport().set_input_as_handled(); return
	var released_direction := UiInputActions.released_movement_direction(event)
	if released_direction != Vector2i.ZERO and _held_movement != null:
		if not (_dungeon_presenter.is_active() and _dungeon_presenter.handle_keyboard_release(released_direction)) and _held_movement.active_direction() == released_direction: _held_movement.stop(&"keyboard")
	var key_event := event as InputEventKey
	if presentation_coordinator != null and presentation_coordinator.is_combat_playback_active():
		if key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE and _abort_full_party_auto(true):
			get_viewport().set_input_as_handled()
			return
		if key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_SPACE:
			presentation_coordinator.skip_combat_playback()
			get_viewport().set_input_as_handled()
		return
	var pending := session_controller.view().active_interaction_request()
	var combat_pending := pending != null and pending.kind == InteractionRequest.COMBAT
	if combat_pending and key_event != null and not key_event.echo and (key_event.keycode == KEY_ALT or key_event.physical_keycode == KEY_ALT):
		var dock_available := _interaction_presenter.set_fast_spell_dock_held(key_event.pressed)
		if dock_available or not key_event.pressed:
			get_viewport().set_input_as_handled()
		return
	if combat_pending and key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE and _abort_full_party_auto(false):
		get_viewport().set_input_as_handled()
		return
	if combat_pending and event.is_action_pressed(&"realmz_inspect_movement"):
		_battlefield_presenter.set_movement_costs_visible(true)
		get_viewport().set_input_as_handled()
		return
	if combat_pending and event.is_action_released(&"realmz_inspect_movement"):
		_battlefield_presenter.set_movement_costs_visible(false)
		get_viewport().set_input_as_handled()
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null and mouse_button.button_index == MOUSE_BUTTON_LEFT and not mouse_button.pressed:
		_shell_presenter.release_held_commands()
	if not event.is_pressed():
		return
	if combat_pending and _battlefield_presenter.dismiss_reveal_friends():
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"realmz_back"):
		if combat_pending and _battlefield_presenter.cancel_targeting():
			get_viewport().set_input_as_handled()
			return
		if _interaction_presenter.handle_back_request():
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
			if _battlefield_presenter.targeting_active() and event.is_action_pressed(&"realmz_target") and _battlefield_presenter.target_with_keyboard():
				get_viewport().set_input_as_handled()
				return
			if _battlefield_presenter.targeting_active() and event.is_action_pressed(&"realmz_confirm_target") and _battlefield_presenter.confirm_targeting():
				get_viewport().set_input_as_handled()
				return
			var combat_fast_spell := UiInputActions.fast_spell_slot(event, true)
			var use_fast_spell := UiInputActions.combat_fast_spell_use_requested(event)
			if combat_fast_spell >= 0 and (_interaction_presenter.activate_fast_spell_from_dock(combat_fast_spell) if use_fast_spell and key_event.alt_pressed else _interaction_presenter.handle_fast_spell(combat_fast_spell, use_fast_spell)):
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
	if key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_SPACE and presentation_coordinator.toggle_dungeon_view(): get_viewport().set_input_as_handled(); return
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
	if event.is_action_pressed(&"realmz_heal"):
		_submit_intent(PlayerIntent.heal())
		get_viewport().set_input_as_handled()
		return
	var direction := UiInputActions.movement_direction(event)
	if direction != Vector2i.ZERO:
		if not event is InputEventKey or not (event as InputEventKey).echo:
			if _dungeon_presenter.is_active(): _dungeon_presenter.handle_keyboard_press(direction)
			else: _held_movement.start(&"keyboard", direction)
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
	var step := _submit_intent(PlayerIntent.overhead_dungeon_move(direction) if map_view != null and map_view.level_type == &"dungeon" and (_dungeon_presenter == null or not _dungeon_presenter.is_active()) else PlayerIntent.move(direction))
	var after := session_controller.view()
	if step.state == SessionStep.State.FAILED or after == null or after.pending_interaction != null or after.combat_view != null:
		return false
	var ordinary_blocked := false
	for event: DomainEvent in step.events:
		if event.kind == &"movement_blocked": ordinary_blocked = true; continue
		if event.kind in [&"map_transitioned", &"trigger_fired", &"timed_encounter_triggered", &"random_region_triggered", &"random_door_triggered", &"random_encounter_triggered"]: return false
	return ordinary_blocked or before.party_map_id == after.party_map_id and before.party_coordinate != after.party_coordinate and accepts_exploration_input()


func _submit_intent(intent: PlayerIntent) -> SessionStep:
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
		var direct_step := _submit_intent(direct_intent)
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
			if not body.target_coordinates.is_empty():
				return PlayerIntent.cast_spell_at_coordinates(body.spell_id, body.actor_id, body.target_coordinates, body.power)
			if body.has_target_coordinate:
				return PlayerIntent.cast_spell_at(body.spell_id, body.actor_id, body.target_coordinate, body.power, body.rotation)
			if not body.target_ids.is_empty():
				return PlayerIntent.cast_spell_at_targets(body.spell_id, body.actor_id, body.target_ids, body.power)
			return PlayerIntent.cast_spell(body.spell_id, body.actor_id, body.target_id, body.power)
		&"use_item":
			if body.item_instance_id.is_empty():
				return null
			return PlayerIntent.use_item_on_target(body.item_instance_id, body.actor_id, body.target_id, body.target_ids, body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE, body.rotation, body.target_coordinates)
		&"use_scroll":
			if body.scroll_slot < 0:
				return null
			if not body.target_coordinates.is_empty():
				return PlayerIntent.use_scroll_at_coordinates(body.actor_id, body.scroll_slot, body.target_coordinates)
			return PlayerIntent.use_scroll_on_target(body.actor_id, body.scroll_slot, body.target_id, body.target_ids, body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE, body.rotation)
	return PlayerIntent.combat_action(body.action, body.actor_id, body.target_id)


static func combat_auto_change_to_queue(intent: PlayerIntent, playback_active: bool) -> Dictionary:
	if not playback_active or intent == null or intent.kind != PlayerIntent.Kind.SET_COMBAT_AUTO or not intent.payload is PlayerIntent.CombatAutoPayload:
		return {}
	var payload := intent.payload as PlayerIntent.CombatAutoPayload
	return {"characterId": payload.character_id, "enabled": payload.enabled}


static func combat_auto_abort_ids(view: GameView, queued_changes: Dictionary = {}) -> Array[String]:
	var result: Array[String] = []
	if view != null and view.combat_view != null:
		result.assign(view.combat_view.auto_character_ids)
	for character_id: Variant in queued_changes:
		if bool(queued_changes[character_id]) and not result.has(String(character_id)):
			result.append(String(character_id))
	result.sort()
	return result


func _abort_full_party_auto(skip_playback: bool) -> bool:
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
	if view == null or view.combat_view == null or view.combat_view.outcome != &"active":
		return null
	var actor_id := view.combat_view.active_actor_id
	if actor_id.is_empty() or not view.combat_view.auto_character_ids.has(actor_id):
		return null
	var request := view.active_interaction_request()
	if request == null or request.kind != InteractionRequest.COMBAT:
		return null
	return InteractionResponse.new(request.request_id, request.kind, InteractionResponse.CombatBody.new(&"auto", actor_id))


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
	if action == ApplicationLifecycleScript.SAVE_AND_QUIT:
		_host_interaction = null
		presentation_coordinator.dismiss_host_interaction()
		_save_and_quit_pending = true
		_refresh_save_previews()
		_shell_presenter.show_save_and_quit_workspace()
		_shell_presenter.set_status("Choose a save slot, then Save and Quit.")
		return
	var has_active_session := session_controller.view().session_started
	var result_state := ApplicationLifecycleScript.execute_quit(
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
		_submit_intent(PlayerIntent.set_combat_auto(character_id, bool(changes[character_id])))


func _continue_persistent_auto_after_playback() -> void:
	# Reduced motion can settle playback before its battlefield draws. Let that
	# committed view reach the screen before another synchronous Auto activation.
	await RenderingServer.frame_post_draw
	if presentation_coordinator == null or presentation_coordinator.is_combat_playback_active() or not _queued_combat_auto_changes.is_empty() or _host_interaction != null: return
	var response := persistent_auto_response(session_controller.view())
	if response != null:
		_on_interaction_response_submitted(response)


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


func _begin_classic_character_library_load() -> void:
	if not _package_host.start_bundled_load(CLASSIC_CHARACTER_LIBRARY_PATH, CLASSIC_CHARACTER_LIBRARY_ID, CLASSIC_CHARACTER_LIBRARY_HASH):
		_character_library_load_complete = true; _classic_shell.set_standalone_character_creation_available(false, "The built-in Classic definitions could not start loading.")


func _poll_classic_character_library_load() -> void:
	if _character_library_load_complete or _package_host == null or _package_host.bundled_load_is_running():
		return
	var prepared := _package_host.take_bundled_package(CLASSIC_CHARACTER_LIBRARY_PATH)
	if prepared == null: return
	_character_library_load_complete = true
	if not prepared.is_ok():
		_classic_shell.set_standalone_character_creation_available(false, prepared.error_message); _shell_presenter.set_status("Character Files creation unavailable • %s" % prepared.error_message, true)
	else:
		_character_library_content = prepared.content; _character_library_media = prepared.media; _package_host.set_application_content(_character_library_content, _character_library_media.assets())
		presentation_coordinator.set_application_character_media(_character_library_media); presentation_coordinator.set_package_media(_character_library_media); _vault_host.seed_classic_starters_if_empty()
		_classic_shell.set_standalone_character_creation_available(true); _refresh_vault_views()
	if _pending_prepared_package != null:
		var pending := _pending_prepared_package; _pending_prepared_package = null; _complete_package_install(pending, _pending_package_seed)

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
	_campaigns = _package_host.discover_available_campaigns(); _shell_presenter.set_campaigns(_campaigns); _try_prewarm_last_campaign()


func _try_prewarm_last_campaign() -> void:
	if _last_campaign_prewarm_requested or _package_host == null or _character_library_content == null or _presentation_settings == null or _presentation_settings.last_campaign_id.is_empty() or bool(get_meta(&"startup_splash_suppressed", false)) and not bool(get_meta(&"startup_front_door_revealed", false)): return
	_last_campaign_prewarm_requested = true; _package_host.prewarm_last_campaign(_campaigns, _presentation_settings.last_campaign_id)


func _on_topology_debug_changed(enabled: bool) -> void:
	_map_presenter.show_debug_facts = enabled
	_map_presenter.queue_redraw()
	if _presentation_settings != null:
		_presentation_settings.topology_debug = enabled
		settings_repository.save_settings(_presentation_settings)


func _on_dungeon_3d_changed(enabled: bool) -> void:
	presentation_coordinator.set_dungeon_3d_enabled(enabled)
	if _presentation_settings != null: _presentation_settings.dungeon_3d = enabled; settings_repository.save_settings(_presentation_settings)


func _on_master_volume_changed(value: float) -> void:
	_audio_presenter.set_master_volume(value)
	_presentation_settings.master_volume = value
	settings_repository.save_settings(_presentation_settings)


func _on_sound_volume_changed(value: float) -> void:
	_audio_presenter.set_sound_volume(value)
	_presentation_settings.sound_volume = clampf(value, 0.0, 1.0)
	_shell_presenter.apply_settings(_presentation_settings)
	settings_repository.save_settings(_presentation_settings)


func _on_music_volume_changed(value: float) -> void:
	_audio_presenter.set_music_volume(value)
	_presentation_settings.music_volume = clampf(value, 0.0, 1.0)
	_shell_presenter.apply_settings(_presentation_settings)
	settings_repository.save_settings(_presentation_settings)


func _on_music_enabled_changed(enabled: bool) -> void:
	_presentation_settings.music_enabled = enabled
	_shell_presenter.apply_settings(_presentation_settings)
	settings_repository.save_settings(_presentation_settings)
	presentation_coordinator.refresh_music()


func _on_music_playlist_mode_changed(playlist_id: int, mode: int) -> void:
	if not _presentation_settings.set_music_mode(playlist_id, mode):
		return
	settings_repository.save_settings(_presentation_settings)
	presentation_coordinator.refresh_music()


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
	var projection_size := ClassicMapPresenter.projection_cells_for(_map_presenter.size, _map_presenter.map_origin.y, _map_presenter.cell_size); if session_controller.set_map_projection_size(projection_size): presentation_coordinator.refresh_spatial_projection()
	var canvas_rect := _profile.application_rect; var textbox_rect := Rect2(Vector2(canvas_rect.position.x, workspace_rect.end.y), Vector2(canvas_rect.size.x, _profile.bottom_height))
	var combat_rect := Rect2(Vector2(canvas_rect.position.x, canvas_rect.end.y - _profile.bottom_height), Vector2(canvas_rect.size.x, _profile.bottom_height))
	_interaction_presenter.set_classic_regions(content_rect, textbox_rect, combat_rect)
	call_deferred("_sync_interaction_narrative_region", content_rect, combat_rect)


func _sync_interaction_narrative_region(content_rect: Rect2, combat_rect: Rect2) -> void:
	await get_tree().process_frame; var narrative_rect := _shell_presenter.narrative_region()
	if narrative_rect.has_area():
		_interaction_presenter.set_classic_regions(content_rect, narrative_rect, combat_rect)


static func classic_textbox_rect(workspace_rect: Rect2, bottom_height: float, full_width: float = 0.0) -> Rect2:
	var width := full_width if full_width > 0.0 else workspace_rect.size.x
	return Rect2(0.0 if full_width > 0.0 else workspace_rect.position.x, workspace_rect.end.y, width, bottom_height)


static func classic_combat_rect(viewport_size: Vector2, bottom_height: float) -> Rect2:
	return Rect2(0.0, maxf(0.0, viewport_size.y - bottom_height), viewport_size.x, minf(bottom_height, viewport_size.y))


func _on_reduced_motion_changed(enabled: bool) -> void: _presentation_settings.reduced_motion = enabled; presentation_coordinator.set_reduced_motion(enabled); settings_repository.save_settings(_presentation_settings)


func _on_reduced_sound_changed(enabled: bool) -> void: _presentation_settings.reduced_sound = enabled; _audio_presenter.set_reduced_sound(enabled); settings_repository.save_settings(_presentation_settings)


func _on_auto_switch_to_melee_changed(enabled: bool) -> void:
	_presentation_settings.auto_switch_to_melee = enabled
	settings_repository.save_settings(_presentation_settings)


func _on_exploration_speed_changed(percent: int) -> void:
	_presentation_settings.exploration_speed_percent = clampi(snappedi(percent, 25), 25, 400); _held_movement.set_speed_percent(_presentation_settings.exploration_speed_percent); presentation_coordinator.set_exploration_speed_percent(_presentation_settings.exploration_speed_percent); settings_repository.save_settings(_presentation_settings)


func _on_combat_playback_speed_changed(percent: int) -> void: _presentation_settings.combat_playback_speed_percent = clampi(snappedi(percent, 25), 25, 200); presentation_coordinator.set_combat_playback_speed_percent(_presentation_settings.combat_playback_speed_percent); settings_repository.save_settings(_presentation_settings)


func _on_exploration_minimap_changed(enabled: bool) -> void:
	_presentation_settings.show_exploration_minimap = enabled; _map_presenter.set_travel_preview_visible(enabled); settings_repository.save_settings(_presentation_settings)


func _on_classic_exploration_visibility_changed(enabled: bool) -> void:
	_presentation_settings.classic_exploration_visibility = enabled; _map_presenter.set_classic_exploration_visibility(enabled); settings_repository.save_settings(_presentation_settings)


func _on_autojournal_changed(enabled: bool) -> void:
	_presentation_settings.autojournal_enabled = enabled
	_interaction_presenter.set_autojournal_enabled(enabled)
	settings_repository.save_settings(_presentation_settings)


func _on_route_changed(route_id: StringName) -> void:
	_held_movement.stop()
	presentation_coordinator.set_active_route(route_id)
