## Coordinates Realmz application within application startup and host integration.

class_name RealmzApplication
extends Control

## Composes the application and translates host input into typed game operations.

const DEVELOPMENT_PREVIEW_HOST_PATH := "res://tools/development_preview_application_host.gd"
const RUNTIME_TESTING_READINESS := preload("res://src/app/platform/runtime_testing_readiness.gd")
const IMPORTED_SCENARIO_WORKFLOW := preload("res://src/app/composition/imported_scenario_workflow.gd")
const CAMPAIGN_CATALOG_WORKFLOW := preload("res://src/app/composition/campaign_catalog_workflow.gd")

@onready var _status_label: Label = $GameShell/BottomRegion/BottomRow/NarrativeWell/NarrativeColumn/Facts/Status
@onready var _smoke_button: Button = $GameShell/SmokeAction
@onready var _map_presenter: ClassicMapPresenter = %ExplorationMap
@onready var battlefield_presenter: ClassicBattlefieldPresenter = %BattlefieldMap
@onready var interaction_presenter: InteractionPresenter = %InteractionPanel
@onready var shell_presenter: GameShell = $GameShell
@onready var _audio_presenter: ClassicAudioPresenter = %ClassicAudio

var session_controller: GameSessionController
var presentation_coordinator: PresentationCoordinator
var presentation_media: PresentationMediaController
var settings_repository: SettingsRepository
var _active_content: RealmzContent
var _presentation_settings: PresentationSettings
var dungeon_presenter: DungeonMap3DPresenter
var _package_host: PackageHostController
var _imported_scenario_workflow: ImportedScenarioWorkflow
var _campaign_catalog: CampaignCatalogWorkflow
var _campaign_preparation: CampaignPreparationWorkflow
var _campaign_publication: CampaignPresentationHost
var _save_host: SaveHostController
var _pending_package_seed: int = 1
var _pending_package_path: String = ""
var _last_package_operation_key: String = ""
var _pending_prepared_package: PreparedPackage
var held_movement: HeldMovementController
var _combat_host := ApplicationCombatHost.new()
var _quit_operation: Callable
var debug_tools: DebugToolsHost
var _input_router: ApplicationInputRouter
var _controller_input: ControllerInputOwner
var controller_input: ControllerInputOwner:
	get: return _controller_input
var _controller_resume_required: bool = false
var _settings_controller: ApplicationSettingsController
var lifecycle_host := ApplicationLifecycleHost.new()
var character_files: ApplicationCharacterFilesHost
var character_art: ApplicationCharacterArtHost
var adventure_storage: ApplicationAdventureStorageHost
var _spatial_layout: ApplicationSpatialLayout
var _runtime_testing_host: RuntimeTestingHost
var click_to_move: ClickToMoveCoordinator


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
	character_art.bind(shell_presenter.character_art, presentation_media)
	_bind_shell_and_settings()
	dungeon_presenter.pointer_input_gate = func() -> bool: return accepts_exploration_input() and not shell_presenter.navigation_overlay_active
	click_to_move = ClickToMoveCoordinator.new(session_controller, presentation_coordinator, shell_presenter, _map_presenter, battlefield_presenter, held_movement, accepts_exploration_input, has_exploration_task, func() -> bool: return dungeon_presenter.is_active(), submit_intent, func(response: InteractionResponse) -> SessionStep:
		response.body = ApplicationCombatPolicy.body_with_preferences(response.body as InteractionResponse.CombatBody, _presentation_settings)
		return submit_response(response)
	)
	click_to_move.combat_input_available = func() -> bool: return not session_controller.is_busy() and not lifecycle_host.has_active_interaction() and not debug_tools.is_open() and interaction_presenter.combat.accepts_spatial_input()
	if RuntimeTestingHost.live_requested() or has_meta(&"runtime_testing_fixture"):
		_runtime_testing_host = RuntimeTestingHost.new()
		add_child(_runtime_testing_host)
		var fixture_request := get_meta(&"runtime_testing_fixture") as RuntimeTestingFixtureRequest if has_meta(&"runtime_testing_fixture") else null
		var status := _runtime_testing_host.bind(session_controller, func() -> RealmzContent: return _active_content, func() -> Dictionary: return RUNTIME_TESTING_READINESS.fields(self, session_controller, presentation_coordinator, lifecycle_host, _combat_host.continuation, battlefield_presenter), self, fixture_request)
		if status != OK:
			printerr("Runtime testing endpoint unavailable: %s" % error_string(status))
	_finish_startup()
func _build_dependencies() -> void:
	var preview_request := get_meta(&"development_preview_request") as DevelopmentPreviewRequest if has_meta(&"development_preview_request") else null
	var preview_state_root := preview_request.result_path.get_basename() + "-session" if preview_request != null else ""
	var fixture := get_meta(&"runtime_testing_fixture") as RuntimeTestingFixtureRequest if has_meta(&"runtime_testing_fixture") else null
	var scratch_root := fixture.scratch_root if fixture != null else preview_state_root
	_package_host = PackageHostController.new(null, scratch_root.path_join("packages")) if fixture != null else PackageHostController.new()
	if _save_host == null:
		_save_host = _create_save_host(scratch_root)
	settings_repository = SettingsRepository.new(scratch_root.path_join("settings.json")) if not scratch_root.is_empty() else SettingsRepository.new()
	_presentation_settings = PresentationSettings.new() if not scratch_root.is_empty() else settings_repository.load_settings()
	session_controller = GameSessionController.new()
	presentation_coordinator = PresentationCoordinator.new()
	presentation_media = PresentationMediaController.new()
	dungeon_presenter = DungeonMap3DPresenter.new()
	held_movement = HeldMovementController.new()
	_input_router = ApplicationInputRouter.new(self)
	_controller_input = ControllerInputOwner.new()
	_controller_input.configure(_presentation_settings.controller)
	add_child(session_controller)
	add_child(presentation_coordinator)
	add_child(dungeon_presenter)
	move_child(dungeon_presenter, shell_presenter.get_index())
	add_child(held_movement)
	add_child(_controller_input)
	debug_tools = DebugToolsHost.new()
	add_child(debug_tools)
	debug_tools.bind(session_controller, self, func() -> RealmzContent: return _active_content)
	character_art = ApplicationCharacterArtHost.new(CharacterArtRepository.new(scratch_root.path_join("character-art"))) if not scratch_root.is_empty() else ApplicationCharacterArtHost.new()
	character_files = ApplicationCharacterFilesHost.new(
		_package_host,
		session_controller,
		presentation_coordinator,
		presentation_media,
		shell_presenter,
		CharacterVaultController.new(CharacterVaultRepository.new(scratch_root.path_join("characters"))) if fixture != null else null,
		character_art
	)
	adventure_storage = ApplicationAdventureStorageHost.new(_save_host, session_controller, shell_presenter, _combat_host.invalidate, _map_presenter.save_map_preview_jpeg, _package_host, character_files, func() -> RealmzContent: return _active_content, character_art)
	_spatial_layout = ApplicationSpatialLayout.new(_map_presenter, battlefield_presenter, dungeon_presenter, interaction_presenter, shell_presenter, session_controller, presentation_coordinator)
	lifecycle_host.bind(session_controller, presentation_coordinator, shell_presenter, held_movement, func(slot_id: String) -> bool: return adventure_storage.save(_active_content, slot_id), func() -> void: adventure_storage.refresh(_active_content), _present_step_status, _complete_closed_session, _quit_application)
	_combat_host.configure(session_controller, presentation_coordinator, shell_presenter, interaction_presenter.combat, func() -> StringName:
		if presentation_coordinator == null or presentation_coordinator.is_combat_playback_active(): return &"combat-playback"
		if presentation_coordinator.drawn_revision != session_controller.view().revision: return &"presentation-awaiting-draw"
		if lifecycle_host.has_active_interaction(): return &"lifecycle-dialog"
		if shell_presenter.pause_active: return &"pause-menu"
		if _controller_resume_required: return &"controller-suspended"
		if interaction_presenter.controller.blocks_automatic_progress(): return &"interaction-overlay"
		return &"", _present_step_status, lifecycle_host.has_active_interaction)


func _create_save_host(scratch_root: String) -> SaveHostController:
	if scratch_root.is_empty():
		return SaveHostController.new()
	var packages := scratch_root.path_join("packages")
	var half_truth := packages.path_join(HalfTruthMediaSaveUpdate.CAMPAIGN_ID).path_join(HalfTruthMediaSaveUpdate.OLD_PACKAGE_HASH + ".realmz2")
	return SaveHostController.new(SaveRepository.new(scratch_root.path_join("saves")), HalfTruthMediaSaveUpdate.new(half_truth), ShopSaveUpdate.new(packages), MarkerSaveUpdate.new(packages), PaymentSaveUpdate.new(packages), ProgramSaveUpdate.new(packages), CompressionSaveUpdate.new(packages), CompleteRecordSaveUpdate.new(packages))


func _bind_debug_and_movement() -> void:
	_controller_input.action_pressed.connect(func(action_id: StringName, repeated: bool) -> void:
		if not repeated and action_id in [&"realmz_controller_action_radial", &"realmz_controller_workspace_radial", &"realmz_controller_top_menu", &"realmz_controller_system"]:
			var context := &"action" if action_id == &"realmz_controller_action_radial" else &"workspace" if action_id == &"realmz_controller_workspace_radial" else &"top_menu" if action_id == &"realmz_controller_top_menu" else &"system"
			shell_presenter.controller.show_prompts(_controller_input.prompt_family(), context)
		if action_id in ControllerInputOwner.DIRECTION_ACTIONS:
			return
		_input_router.handle_controller_action(action_id, true, repeated)
	)
	_controller_input.action_released.connect(func(action_id: StringName) -> void:
		if action_id not in ControllerInputOwner.DIRECTION_ACTIONS:
			_input_router.handle_controller_action(action_id, false)
	)
	_controller_input.direction_changed.connect(func(direction: Vector2i, repeated: bool) -> void:
		_input_router.handle_controller_direction(direction, repeated)
	)
	_controller_input.input_suspended.connect(func(reason: String) -> void:
		_controller_resume_required = true
		_input_router.clear_controller_state()
		held_movement.stop()
		shell_presenter.status.set_status(reason, true)
	)
	_controller_input.input_resumed.connect(func() -> void:
		_controller_resume_required = false
		shell_presenter.status.set_status("Controller input restored.")
		_combat_host.continuation.request()
	)
	_controller_input.binding_captured.connect(func(action_id: StringName, descriptor: Dictionary) -> void: shell_presenter.controller.receive_binding(action_id, descriptor))
	_controller_input.binding_capture_cancelled.connect(shell_presenter.controller.cancel_binding_capture)
	_controller_input.input_observed.connect(shell_presenter.controller.set_live_input)
	debug_tools.status_changed.connect(
		func(message: String, failed: bool) -> void:
			shell_presenter.status.set_status(message, failed)
	)
	held_movement.set_speed_percent(_presentation_settings.exploration_speed_percent)
	held_movement.movement_requested.connect(_on_held_movement_requested)
	_map_presenter.movement_hold_started.connect(func(direction: Vector2i) -> void: held_movement.start(&"mouse", direction))
	_map_presenter.movement_hold_updated.connect(func(direction: Vector2i) -> void: held_movement.update(&"mouse", direction))
	_map_presenter.movement_hold_stopped.connect(func() -> void: held_movement.stop(&"mouse"))
	dungeon_presenter.turn_requested.connect(
		func(delta: int) -> void:
			submit_intent(ExplorationIntents.dungeon_turn(delta))
	)
	dungeon_presenter.movement_requested.connect(submit_movement)
	dungeon_presenter.movement_hold_started.connect(
		func(direction: Vector2i) -> void:
			held_movement.start(&"keyboard", direction)
	)
	dungeon_presenter.movement_hold_stopped.connect(
		func() -> void:
			held_movement.stop(&"keyboard")
	)


func _bind_combat_and_interactions() -> void:
	presentation_coordinator.bind(
		session_controller,
		_map_presenter,
		battlefield_presenter,
		dungeon_presenter,
		interaction_presenter,
		shell_presenter,
		_audio_presenter,
		presentation_media
	)
	presentation_coordinator.playback_step_settled.connect(_on_playback_step_settled)
	interaction_presenter.response_submitted.connect(submit_response)
	interaction_presenter.combat.inspected_combatant_changed.connect(func(id: String) -> void: battlefield_presenter.interaction.inspected_combatant_id = id)
	interaction_presenter.combat.targeting_requested.connect(_on_combat_targeting_requested)
	interaction_presenter.combat.targeting_confirm_requested.connect(battlefield_presenter.interaction.confirm_targeting)
	interaction_presenter.combat.targeting_cancel_requested.connect(battlefield_presenter.interaction.cancel_targeting)
	interaction_presenter.combat.targeting_rotate_requested.connect(battlefield_presenter.interaction.rotate_targeting)
	interaction_presenter.combat.combatant_focus_requested.connect(_on_combatant_focus_requested)
	interaction_presenter.combat.reveal_friends_requested.connect(_on_reveal_friends_requested)
	interaction_presenter.combat.move_to_requested.connect(func() -> void: battlefield_presenter.movement_preview.toggle())
	interaction_presenter.presentation_sound_requested.connect(presentation_media.present_interaction_sound)
	interaction_presenter.presentation_status_requested.connect(shell_presenter.status.set_status)
	battlefield_presenter.interaction.combat_body_submitted.connect(_on_battlefield_action_requested)
	battlefield_presenter.interaction.combatant_inspected.connect(_on_battlefield_combatant_inspected)
	battlefield_presenter.interaction.combatant_hovered.connect(func(id: String) -> void: interaction_presenter.combat.open_combatant_inspection(id, false))
	battlefield_presenter.interaction.targeting_changed.connect(interaction_presenter.combat.update_targeting)
	battlefield_presenter.interaction.invalid_target_requested.connect(func() -> void: presentation_media.present_interaction_sound(143, true))
	battlefield_presenter.interaction.targeting_cancelled.connect(interaction_presenter.combat.targeting_cancelled)


func _bind_shell_and_settings() -> void:
	shell_presenter.pause_changed.connect(func(active: bool) -> void:
		interaction_presenter.pause_background_active = active
		held_movement.stop()
		_input_router.clear_controller_state()
		_controller_input.clear_held_input()
		if active:
			if click_to_move != null: click_to_move.cancel("Move To cancelled.")
			presentation_coordinator.skip_combat_playback()
	)

	shell_presenter.start_package_requested.connect(_begin_package_start)
	shell_presenter.cancel_package_requested.connect(_package_host.cancel)
	var campaign_library := shell_presenter.navigator.setup_controller.campaign_library
	_campaign_catalog = CAMPAIGN_CATALOG_WORKFLOW.new(_package_host, campaign_library, character_files, _presentation_settings, shell_presenter.status)
	shell_presenter.refresh_campaigns_requested.connect(_campaign_catalog.refresh)
	_imported_scenario_workflow = IMPORTED_SCENARIO_WORKFLOW.new(_package_host, campaign_library, character_files, shell_presenter.status)
	_imported_scenario_workflow.campaign_refresh_requested.connect(_campaign_catalog.refresh)
	_imported_scenario_workflow.bind()
	_campaign_publication = CampaignPresentationHost.new(_package_host, character_files, adventure_storage, presentation_media, presentation_coordinator, shell_presenter, _presentation_settings, settings_repository, func(content: RealmzContent) -> void: _active_content = content, _combat_host.invalidate)
	_campaign_preparation = CampaignPreparationWorkflow.new(_package_host, session_controller, character_files, _save_host, adventure_storage, shell_presenter.navigator, _presentation_settings, _imported_scenario_workflow, _campaign_publication.publish_adventure, _campaign_publication.publish_setup)
	shell_presenter.intent_submitted.connect(submit_intent)
	shell_presenter.combat_inventory_response_submitted.connect(_on_battlefield_action_requested)
	shell_presenter.save_requested.connect(func(slot_id: String) -> void: adventure_storage.save(_active_content, slot_id))
	shell_presenter.save_and_quit_requested.connect(lifecycle_host.save_and_quit)
	shell_presenter.load_requested.connect(func(slot_id: String) -> void: adventure_storage.load(_active_content, slot_id))
	shell_presenter.load_backup_requested.connect(func(slot_id: String) -> void: adventure_storage.load(_active_content, slot_id, true))
	shell_presenter.legacy_save_load_requested.connect(func(slot_id: String, backup: bool, target_slot_id: String) -> void: adventure_storage.load(_active_content, slot_id, backup, target_slot_id))
	shell_presenter.update_save_requested.connect(func(slot_id: String, backup: bool) -> void: adventure_storage.update_save(_active_content, slot_id, backup))
	shell_presenter.refresh_saves_requested.connect(func() -> void: adventure_storage.refresh(_active_content))
	shell_presenter.end_adventure_requested.connect(lifecycle_host.request_end_adventure)
	shell_presenter.quit_requested.connect(lifecycle_host.request_quit)
	shell_presenter.route_changed.connect(lifecycle_host.route_changed)
	shell_presenter.layout_changed.connect(func(workspace_rect: Rect2, profile: UiLayoutProfile) -> void:
		if _settings_controller != null: _settings_controller.apply_interface_profile(profile)
		_spatial_layout.apply(workspace_rect, profile)
		_spatial_layout.sync_display_world_region(get_viewport().get_parent() as DisplayCompositor, _presentation_settings)
	)
	presentation_coordinator.spatial_visibility_changed.connect(func() -> void: _spatial_layout.sync_display_world_region(get_viewport().get_parent() as DisplayCompositor, _presentation_settings))
	shell_presenter.route_changed.connect(held_movement.stop.unbind(1))
	shell_presenter.route_changed.connect(presentation_coordinator.set_active_route)
	shell_presenter.vault_archive_requested.connect(func(character_id: String) -> void: character_files.archive_character(_active_content, character_id))
	shell_presenter.vault_maintenance_requested.connect(character_files.request_maintenance)
	shell_presenter.vault_restore_requested.connect(func(character_id: String, revision_hash: String) -> void: character_files.restore_character(_active_content, character_id, revision_hash))
	shell_presenter.standalone_character_creation_requested.connect(func() -> void: character_files.begin_creation(_active_content))
	shell_presenter.standalone_character_creation_cancelled.connect(func() -> void: character_files.cancel_creation(_active_content))
	shell_presenter.character_selection_completed.connect(interaction_presenter.submit_character_selection)
	shell_presenter.navigator.content_presenter.system_preferences.cancel_binding_capture = _controller_input.cancel_binding_capture
	shell_presenter.controller_binding_capture_requested.connect(func(action_id: StringName) -> void: _controller_input.begin_binding_capture(action_id))
	_audio_presenter.music_state_changed.connect(shell_presenter.set_music_playback_state)
	_settings_controller = ApplicationSettingsController.new(self, _presentation_settings, settings_repository, shell_presenter, _map_presenter, interaction_presenter, _audio_presenter, presentation_coordinator, dungeon_presenter, held_movement, debug_tools, _spatial_layout, get_viewport().get_parent() as DisplayCompositor, session_controller.view)
	if not has_meta(&"development_preview_request"):
		_settings_controller.bind()
	_settings_controller.apply_initial_settings()


func _finish_startup() -> void:
	if has_meta(&"runtime_testing_fixture"):
		_runtime_testing_host.prepare_fixture(presentation_coordinator, presentation_media, shell_presenter, func(content: RealmzContent) -> void: _active_content = content, character_files)
		return
	var preview_request := get_meta(&"development_preview_request") as DevelopmentPreviewRequest if has_meta(&"development_preview_request") else null
	if preview_request != null:
		_status_label.text = "Preparing isolated Providence preview"
		var preview_host_script := load(DEVELOPMENT_PREVIEW_HOST_PATH) as Script
		if preview_host_script == null:
			_status_label.text = "Preview failed • developer host is unavailable"
			shell_presenter.status.set_status(_status_label.text, true)
			return
		var preview_host := preview_host_script.new() as Node
		add_child(preview_host)
		preview_host.call("launch", preview_request, session_controller, presentation_coordinator, presentation_media, shell_presenter, func(content: RealmzContent) -> void: _active_content = content)
		return
	shell_presenter.navigator.setup_controller.character_creation.set_standalone_character_creation_available(false, "Loading the built-in Classic definitions…")
	Callable(character_files, "begin_library_load").call_deferred()
	_status_label.text = "Pure session boundary online"
	_campaign_catalog.refresh()
	character_files.refresh_vault_views(_active_content)
	set_process(true)


func _process(_delta: float) -> void:
	session_controller.poll_combat_work()
	if adventure_storage != null and adventure_storage.party_import != null: adventure_storage.party_import.poll()
	lifecycle_host.poll()
	shell_presenter.controller.pause.poll()
	adventure_storage.poll()
	if click_to_move != null: click_to_move.poll(_delta)
	_combat_host.poll()
	var library_completed := character_files.poll_library_load(_active_content)
	character_files.poll_repair(_active_content)
	if library_completed and _pending_prepared_package != null:
		var pending := _pending_prepared_package
		_pending_prepared_package = null
		_complete_package_install(pending, _pending_package_seed, _pending_package_path)
		_pending_package_path = ""
	_campaign_catalog.prewarm_if_ready(not bool(get_meta(&"startup_splash_suppressed", false)) or bool(get_meta(&"startup_front_door_revealed", false)))
	if held_movement != null and held_movement.is_active():
		if not accepts_exploration_input():
			held_movement.stop()
		elif held_movement.active_source() == &"mouse" and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			held_movement.stop(&"mouse")
	_poll_package_operation()


func _poll_package_operation() -> void:
	if _package_host == null:
		return
	var operation := _package_host.operation_view()
	if _campaign_preparation != null and character_files.library_ready():
		_campaign_preparation.accept_setup(_package_host.take_setup())
	if operation.state == PackageOperationView.IDLE:
		return
	var operation_key := "%s:%s:%d:%d:%s" % [operation.state, operation.phase, operation.completed, operation.total, operation.message]
	if operation_key != _last_package_operation_key:
		_last_package_operation_key = operation_key
		shell_presenter.navigator.setup_controller.campaign_library.set_package_operation(operation)
		shell_presenter.status.set_status(operation.message, operation.state == PackageOperationView.FAILED)
		_campaign_preparation.progress(operation)
	if operation.is_running():
		return
	var prepared := _package_host.take_prepared_package()
	if _campaign_preparation.active and operation.operation_name != &"import_scenario":
		_last_package_operation_key = ""
		if operation.state == PackageOperationView.SUCCEEDED:
			shell_presenter.navigator.setup_controller.campaign_library.set_package_operation(PackageOperationView.new())
		_campaign_preparation.accept_package(prepared, operation.package_path)
		return
	if _imported_scenario_workflow.complete_operation(operation, prepared):
		_last_package_operation_key = ""
		var current_view := session_controller.view()
		if operation.state == PackageOperationView.SUCCEEDED and prepared != null and prepared.is_ok() and (not current_view.session_started or current_view.party_setup_available):
			_complete_package_install(prepared, 1)
		return
	if operation.state != PackageOperationView.FAILED:
		shell_presenter.navigator.setup_controller.campaign_library.set_package_operation(PackageOperationView.new())
	_last_package_operation_key = ""
	if operation.state == PackageOperationView.CANCELLED:
		shell_presenter.status.set_status("Campaign preparation cancelled.")
		return
	if prepared == null or not prepared.is_ok():
		_complete_package_install(prepared, _pending_package_seed, operation.package_path)
		return
	if not character_files.library_ready():
		_pending_prepared_package = prepared
		_pending_package_path = operation.package_path
		shell_presenter.status.set_status("Campaign ready • finishing the built-in Classic definitions…")
		return
	_complete_package_install(prepared, _pending_package_seed)


func _exit_tree() -> void:
	_trace_shutdown("application tree exit started")
	if character_files != null: character_files.shutdown()
	_combat_host.release()
	if held_movement != null:
		held_movement.stop()
	if _package_host != null:
		_package_host.close()
	_trace_shutdown("application tree exit finished")


func _on_smoke_action_pressed() -> void:
	_smoke_button.release_focus()
	if not session_controller.view().session_started:
		_status_label.text = "MCP input verified • no package loaded"
		return
	var step := submit_intent(ExplorationIntents.search())
	if step == null or step.state == SessionStep.State.FAILED:
		return
	var roll: int = step.events[0].payload.get("roll", 0)
	var current_view := session_controller.view()
	_status_label.text = "Search committed • roll %d • day %d %02d:%02d" % [roll, current_view.realmz_day, current_view.realmz_hour, current_view.realmz_minute]


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if click_to_move != null: click_to_move.cancel("Move To cancelled • application focus changed.")
		if held_movement != null:
			held_movement.stop()
		if interaction_presenter != null:
			interaction_presenter.combat.set_fast_spell_dock_held(false)
		if _controller_input != null and _controller_input.active_device() >= 0:
			_controller_input.suspend("Application focus changed. Center the controller, then press a button to continue.")
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if shell_presenter != null and shell_presenter.navigator.draft_dialog.defer_if_dirty(shell_presenter.navigator.content_presenter.system_preferences, lifecycle_host.request_quit):
			return
		lifecycle_host.request_quit()


func start_package(package_path: String, initial_seed: int) -> SessionStep:
	var current_view := session_controller.view()
	if current_view.session_started and not current_view.party_setup_available:
		return SessionStep.failed(session_controller.view().revision, &"session_already_started", "End the active adventure before starting another campaign.")
	return _complete_package_install(_package_host.install_sync(package_path), initial_seed, package_path)


func _begin_package_start(package_path: String, initial_seed: int) -> void:
	held_movement.stop()
	var current_view := session_controller.view()
	if current_view.session_started and not current_view.party_setup_available:
		shell_presenter.status.set_status("End the active adventure before starting another campaign.", true)
		return
	_pending_package_seed = initial_seed
	_pending_package_path = package_path
	if not _campaign_preparation.begin_setup(package_path, initial_seed):
		shell_presenter.status.set_status(_package_host.operation_view().message, true)
		return
	shell_presenter.navigator.setup_controller.campaign_library.set_package_operation(_package_host.operation_view())
	shell_presenter.status.set_status("Preparing campaign…")


func _complete_package_install(prepared: PreparedPackage, initial_seed: int, source_path: String = "") -> SessionStep:
	var step := _imported_scenario_workflow.prepare_party(prepared, session_controller, initial_seed)
	if step.state == SessionStep.State.FAILED:
		presentation_coordinator.refresh()
		_present_package_failure(step.error_message, step.error_code, source_path)
		return step
	_smoke_button.text = "Search area"
	_campaign_catalog.refresh()
	_status_label.text = _campaign_publication.publish_installed_setup(prepared, session_controller.view(), initial_seed)
	return step


func _present_package_failure(message: String, error_code: StringName = &"", package_path: String = "") -> void:
	shell_presenter.status.set_status(message, true)
	shell_presenter.navigator.setup_controller.campaign_library.set_package_operation(PackageOperationView.new(PackageOperationView.FAILED, &"", 0, 0, message, error_code, package_path, &"install_scenario"))


func _input(event: InputEvent) -> void:
	if _controller_input != null and _controller_input.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if shell_presenter != null and ((event is InputEventKey and (event as InputEventKey).pressed) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)):
		shell_presenter.controller.hide_prompts()
	if _input_router != null:
		_input_router.handle_input(event)


func accepts_route_input() -> bool:
	if lifecycle_host.has_active_interaction() or presentation_coordinator == null or interaction_presenter == null:
		return false
	if presentation_coordinator.is_combat_playback_active() or presentation_coordinator.party_effect_playback.is_active() or interaction_presenter.has_blocking_request():
		return false
	return GameShellAvailability.route_change_reason(session_controller.view()).is_empty()


func accepts_exploration_input() -> bool:
	return has_exploration_task() and (_audio_presenter == null or not _audio_presenter.is_input_blocking())


func has_exploration_task() -> bool:
	if session_controller.is_busy(): return false
	if lifecycle_host.has_active_interaction() or debug_tools != null and debug_tools.is_open() or presentation_coordinator == null or interaction_presenter == null or shell_presenter == null:
		return false
	var view := session_controller.view()
	return not presentation_coordinator.is_combat_playback_active() and not interaction_presenter.has_blocking_request() and view != null and view.session_started and view.pending_interaction == null and shell_presenter.accepts_exploration_input()


func handle_field_fast_spell(slot_index: int, use_spell: bool) -> void:
	var binding := shell_presenter.commands.selected_fast_spell(slot_index)
	if binding.is_empty() or String(binding.get("spellId", "")).is_empty():
		shell_presenter.status.set_status("Fast Spell %s • Undefined Spell" % ("0" if slot_index == 9 else str(slot_index + 1)))
		_audio_presenter.present_sound(143, presentation_media.catalog())
		return
	var summary := "Fast Spell %s • %s P%d • %s" % ["0" if slot_index == 9 else str(slot_index + 1), binding["spellName"], binding["power"], binding["characterName"]]
	if not use_spell:
		shell_presenter.status.set_status(summary)
		_audio_presenter.present_sound(145, presentation_media.catalog())
		return
	if not bool(binding.get("enabled", false)):
		shell_presenter.status.set_status("%s • %s" % [summary, binding.get("reason", "Unavailable")], true)
		_audio_presenter.present_sound(143, presentation_media.catalog())
		return
	submit_intent(MagicIntents.cast(binding["spellId"], binding["characterId"], "", binding["power"]))


func _on_held_movement_requested(direction: Vector2i) -> void:
	if not submit_movement(direction): held_movement.stop()


func _on_battlefield_action_requested(body: InteractionResponse.CombatBody) -> void:
	if body == null:
		return
	var view := session_controller.view()
	if view == null:
		return
	var pending := view.pending_interaction
	if pending != null and pending.kind == InteractionRequest.COMBAT:
		interaction_presenter.combat.submit_body(ApplicationCombatPolicy.body_with_preferences(body, _presentation_settings))
		return
	if view.combat_view == null or view.combat_view.outcome != &"active":
		return
	var request_id := view.combat_action_request.request_id if view.combat_action_request != null else ""
	if request_id.is_empty():
		shell_presenter.status.set_status("The battle inventory request is no longer available.", true)
		return
	submit_response(InteractionResponse.new(request_id, InteractionRequest.COMBAT, ApplicationCombatPolicy.body_with_preferences(body, _presentation_settings)))


func _on_battlefield_combatant_inspected(combatant_id: String) -> void:
	interaction_presenter.combat.open_combatant_inspection(combatant_id)


func _on_combat_targeting_requested(request: CombatTargetingRequest) -> void:
	battlefield_presenter.interaction.immediate_single_target_actions = _presentation_settings.immediate_single_target_actions
	if not battlefield_presenter.interaction.begin_targeting(request):
		shell_presenter.status.set_status("Battlefield targeting is unavailable for this action.", true)


func _on_combatant_focus_requested(combatant_id: String, play_sound: bool) -> void:
	battlefield_presenter.interaction.focus_combatant(combatant_id)
	interaction_presenter.combat.inspect_combatant(combatant_id)
	if play_sound:
		_audio_presenter.present_sound(147, presentation_media.catalog())


func _on_reveal_friends_requested() -> void:
	battlefield_presenter.interaction.toggle_reveal_friends()
	_audio_presenter.present_sound(137, presentation_media.catalog())


func submit_movement(direction: Vector2i) -> bool:
	return ApplicationMovementInput.submit(self, direction)


func submit_intent(intent: PlayerIntent) -> SessionStep:
	if presentation_coordinator.party_effect_playback.is_active():
		return SessionStep.failed(session_controller.view().revision, &"presentation_busy", "Wait for the current effect to finish.")
	if intent != null and intent.kind == PlayerIntent.Kind.BEGIN_ADVENTURE and _campaign_preparation != null and _campaign_preparation.owns_party_setup():
		return _campaign_preparation.request_play()
	if session_controller.view().party_setup_available and shell_presenter.navigator.setup_controller.campaign_library.blocks_party_editing():
		return SessionStep.failed(session_controller.view().revision, &"campaign_preparing", "Wait for scenario preparation to finish.")
	if character_files.creator_active():
		return character_files.submit_creator_intent(intent)
	var debug_step := debug_tools.noclip_step(intent) if debug_tools != null else null
	if debug_step != null:
		_present_step_status(debug_step)
		return debug_step
	if _combat_host.queue_auto(intent): return null
	if _combat_host.resolves_combat() and intent != null:
		var submission := _combat_host.enqueue_intent(intent)
		return submission.rejection
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
	if intent != null and intent.kind == PlayerIntent.Kind.BEGIN_ADVENTURE and step.state != SessionStep.State.FAILED and _active_content != null:
		_presentation_settings.last_campaign_id = _active_content.campaign_id
		settings_repository.save_settings(_presentation_settings)
	var committed_view := session_controller.view()
	if held_movement != null and (step.state != SessionStep.State.COMPLETED or committed_view == null or committed_view.pending_interaction != null or committed_view.combat_view != null):
		held_movement.stop()
	_present_step_status(step)
	return step


func submit_response(response: InteractionResponse) -> SessionStep:
	match ApplicationLifecycleHost.response_owner(lifecycle_host.has_active_interaction(), character_files.creator_active()):
		&"host":
			lifecycle_host.respond(response)
			return null
		&"standalone-creator":
			character_files.respond_to_creator(response)
			return null
	if presentation_coordinator.party_effect_playback.is_active():
		return SessionStep.failed(session_controller.view().revision, &"presentation_busy", "Wait for the current effect to finish.")
	var current_view := session_controller.view()
	var journal_count_before := current_view.journal_entries.size()
	if current_view.pending_interaction == null and current_view.combat_action_request != null and response.request_id == current_view.combat_action_request.request_id and response.kind == InteractionRequest.COMBAT:
		var direct_intent := ApplicationCombatPolicy.direct_intent(response.body as InteractionResponse.CombatBody)
		if direct_intent == null:
			shell_presenter.status.set_status("The combat command was invalid.", true)
			presentation_coordinator.refresh()
			return null
		var direct_step := submit_intent(direct_intent)
		if direct_step != null and direct_step.state == SessionStep.State.COMPLETED and direct_step.events.is_empty() and session_controller.view().pending_interaction == null:
			shell_presenter.status.set_status("")
		return direct_step
	if _combat_host.resolves_combat():
		return _combat_host.enqueue_response(response).rejection
	var step := session_controller.respond(response)
	_present_step_status(step)
	if step.state != SessionStep.State.FAILED and session_controller.view().journal_entries.size() > journal_count_before:
		shell_presenter.status.show_activity_indicator(&"journal")
	if step.state == SessionStep.State.COMPLETED and step.events.is_empty() and session_controller.view().pending_interaction == null:
		shell_presenter.status.set_status("")
	return step


func abort_full_party_auto(skip_playback: bool) -> bool:
	return _combat_host.abort_auto(skip_playback)


func _quit_application() -> void:
	_combat_host.invalidate()
	session_controller.shutdown_worker()
	_trace_shutdown("quit accepted; closing package workers")
	if _package_host != null:
		_package_host.close()
	_trace_shutdown("package workers closed; requesting engine exit")
	if _quit_operation.is_valid(): _quit_operation.call()
	else: get_tree().quit()


func _trace_shutdown(stage: String) -> void:
	if OS.is_debug_build():
		print("Realmz shutdown | pid=%d | ticks_ms=%d | %s" % [OS.get_process_id(), Time.get_ticks_msec(), stage])


func _complete_closed_session() -> void:
	_combat_host.invalidate()
	_active_content = null
	presentation_media.set_package_media(character_files.library_media())
	adventure_storage.refresh(_active_content)
	character_files.refresh_vault_views(_active_content)
	_campaign_catalog.refresh()
	shell_presenter.show_splash()
	shell_presenter.status.set_status("Adventure ended • main menu")


func _on_playback_step_settled(step: SessionStep) -> void:
	if lifecycle_host.playback_step_settled(step):
		return
	_combat_host.continuation.request()


func _present_step_status(step: SessionStep) -> void:
	if step == null: return
	if step.state == SessionStep.State.FAILED:
		_status_label.text = "Action failed • %s" % step.error_message
		shell_presenter.status.set_status(_status_label.text, true)
		return
	for event: DomainEvent in step.events:
		if event.kind == &"session_ended":
			lifecycle_host.handles_terminal_step(step, presentation_coordinator.is_combat_playback_active() or presentation_coordinator.party_effect_playback.is_active())
			return
		if event.kind == &"character_publication_requested":
			character_files.publish_campaign_character(_active_content, String(event.payload.get("characterId", "")))
		else:
			var status_text := ApplicationStepStatusText.for_event(event)
			if not status_text.is_empty(): _status_label.text = status_text
	if step.state == SessionStep.State.WAITING_FOR_INTERACTION:
		_status_label.text = ApplicationStepStatusText.for_interaction(step.interaction)
