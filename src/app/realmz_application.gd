class_name RealmzApplication
extends Control

const GameSessionControllerScript := preload("res://src/app/game_session_controller.gd")
const PresentationCoordinatorScript := preload("res://src/presentation/presentation_coordinator.gd")
const PackageRepositoryScript := preload("res://src/infrastructure/packages/package_repository.gd")
const SaveRepositoryScript := preload("res://src/infrastructure/saves/save_repository.gd")
const CharacterVaultRepositoryScript := preload("res://src/infrastructure/characters/character_vault_repository.gd")
const SettingsRepositoryScript := preload("res://src/infrastructure/settings/settings_repository.gd")
const DungeonMap3DPresenterScript := preload("res://src/presentation/dungeon_map_3d_presenter.gd")

@onready var _status_label: Label = $ClassicShell/BottomRegion/BottomRow/NarrativeWell/NarrativeColumn/Facts/Status
@onready var _smoke_button: Button = $ClassicShell/SmokeAction
@onready var _map_presenter: ClassicMapPresenter = %ExplorationMap
@onready var _interaction_presenter: InteractionPresenter = %InteractionPanel
@onready var _shell_presenter: ClassicApplicationShell = $ClassicShell
@onready var _classic_shell: ClassicApplicationShell = $ClassicShell
@onready var _audio_presenter: ClassicAudioPresenter = %ClassicAudio

var session_controller: GameSessionController
var presentation_coordinator: PresentationCoordinator
var package_repository: PackageRepository
var save_repository: SaveRepository
var character_vault_repository: CharacterVaultRepository
var settings_repository: SettingsRepository
var _active_content: RealmzContent
var _presentation_settings: PresentationSettings
var _dungeon_presenter: DungeonMap3DPresenter


func _ready() -> void:
	UiInputActions.ensure_defaults()
	package_repository = PackageRepositoryScript.new()
	save_repository = SaveRepositoryScript.new()
	character_vault_repository = CharacterVaultRepositoryScript.new()
	settings_repository = SettingsRepositoryScript.new()
	_presentation_settings = settings_repository.load_settings()
	session_controller = GameSessionControllerScript.new()
	presentation_coordinator = PresentationCoordinatorScript.new()
	_dungeon_presenter = DungeonMap3DPresenterScript.new()
	add_child(session_controller)
	add_child(presentation_coordinator)
	add_child(_dungeon_presenter)
	presentation_coordinator.bind(session_controller, _map_presenter, _dungeon_presenter, _interaction_presenter, _shell_presenter, _audio_presenter)
	_interaction_presenter.response_submitted.connect(_on_interaction_response_submitted)
	_map_presenter.movement_requested.connect(_on_map_movement_requested)
	_shell_presenter.start_package_requested.connect(start_package)
	_shell_presenter.refresh_campaigns_requested.connect(_refresh_campaigns)
	_shell_presenter.intent_submitted.connect(_submit_intent)
	_shell_presenter.save_requested.connect(save_active_session)
	_shell_presenter.load_requested.connect(load_active_session)
	_shell_presenter.quit_requested.connect(_on_quit_requested)
	_shell_presenter.topology_debug_changed.connect(_on_topology_debug_changed)
	_shell_presenter.dungeon_3d_changed.connect(_on_dungeon_3d_changed)
	_shell_presenter.master_volume_changed.connect(_on_master_volume_changed)
	_shell_presenter.text_scale_changed.connect(_on_text_scale_changed)
	_shell_presenter.ui_scale_mode_changed.connect(_on_ui_scale_mode_changed)
	_shell_presenter.window_mode_changed.connect(_on_window_mode_changed)
	_shell_presenter.reduced_motion_changed.connect(_on_reduced_motion_changed)
	_shell_presenter.layout_changed.connect(_on_shell_layout_changed)
	_shell_presenter.route_changed.connect(presentation_coordinator.set_active_route)
	_shell_presenter.apply_settings(_presentation_settings)
	_apply_application_theme(_presentation_settings.text_scale)
	_interaction_presenter.set_text_scale(_presentation_settings.text_scale)
	_apply_window_mode(_presentation_settings.window_mode)
	_audio_presenter.set_master_volume(_presentation_settings.master_volume)
	_on_topology_debug_changed(_presentation_settings.topology_debug)
	_on_dungeon_3d_changed(_presentation_settings.dungeon_3d)
	_status_label.text = "Pure session boundary online"
	_refresh_campaigns()
	_classic_shell.set_vault_records(character_vault_repository.list_current_records())


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
	_status_label.text = "Search committed • roll %d • day %d %02d:00" % [roll, current_view.realmz_day, current_view.realmz_hour]


func _on_quit_requested() -> void:
	get_tree().quit()


func start_package(package_path: String, initial_seed: int) -> SessionStep:
	var installation := package_repository.install_package(package_path)
	if not installation.is_ok():
		_status_label.text = "Package rejected • %s" % installation.error_message
		_shell_presenter.set_status(_status_label.text, true)
		return SessionStep.failed(0, installation.error_code, installation.error_message)
	var package_result := installation.package
	presentation_coordinator.set_package_media(package_result.media)
	var step := session_controller.start(package_result.content, initial_seed)
	if step.state == SessionStep.State.FAILED:
		_status_label.text = "Session start failed • %s" % step.error_message
		_shell_presenter.set_status(_status_label.text, true)
		return step
	_active_content = package_result.content
	_smoke_button.text = "Search area"
	var current_view := session_controller.view()
	_status_label.text = "Loaded %s • %s %d,%d • seed %d" % [_active_content.campaign_id, current_view.party_map_id, current_view.party_coordinate.x, current_view.party_coordinate.y, initial_seed]
	_shell_presenter.set_status(_status_label.text)
	_refresh_campaigns()
	return step


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action_pressed(&"realmz_back"):
		if _interaction_presenter.has_blocking_request():
			_shell_presenter.set_status("Choose a response before leaving this interaction.")
			get_viewport().set_input_as_handled()
			return
		if _interaction_presenter.dismiss_passive_text() or _shell_presenter.handle_back():
			get_viewport().set_input_as_handled()
			return
	if session_controller.view().pending_interaction != null:
		return
	if _shell_presenter.handle_route_shortcut(event):
		get_viewport().set_input_as_handled()
		return
	if not session_controller.view().session_started:
		return
	if not _shell_presenter.accepts_exploration_input():
		return
	if event.is_action_pressed(&"realmz_search"):
		_submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"realmz_camp"):
		_submit_intent(PlayerIntent.camp())
		get_viewport().set_input_as_handled()
		return
	var direction := UiInputActions.movement_direction(event)
	if direction != Vector2i.ZERO:
		_submit_movement(direction)
		get_viewport().set_input_as_handled()


func _on_map_movement_requested(direction: Vector2i) -> void:
	_submit_movement(direction)


func _submit_movement(direction: Vector2i) -> void:
	if not _shell_presenter.accepts_exploration_input() or not session_controller.view().session_started or session_controller.view().pending_interaction != null:
		return
	var map_view := session_controller.view().map_view
	if MapTopology.is_diagonal_direction(direction) and (map_view == null or map_view.level_type != &"land"):
		return
	_submit_intent(PlayerIntent.move(direction))


func _submit_intent(intent: PlayerIntent) -> SessionStep:
	if intent != null and intent.kind == PlayerIntent.Kind.IMPORT_VAULT_CHARACTER:
		var record := character_vault_repository.load_revision(intent.target_id, intent.revision_hash)
		if record == null:
			var failed := SessionStep.failed(session_controller.view().revision, &"vault_load_failed", character_vault_repository.last_error if not character_vault_repository.last_error.is_empty() else "The requested vault revision is unavailable.")
			_present_step_status(failed)
			return failed
		intent = PlayerIntent.import_vault_character(record.character_id, record.revision_hash, record.state.to_data(), record.source_campaign_id, record.source_package_hash)
	var step := session_controller.submit_intent(intent)
	_present_step_status(step)
	return step


func _on_interaction_response_submitted(response: InteractionResponse) -> void:
	var step := session_controller.respond(response)
	_present_step_status(step)


func _present_step_status(step: SessionStep) -> void:
	if step.state == SessionStep.State.FAILED:
		_status_label.text = "Action failed • %s" % step.error_message
		_shell_presenter.set_status(_status_label.text, true)
		return
	for event: DomainEvent in step.events:
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
		if step.interaction.kind == &"acknowledge" and step.interaction.payload.get("presentation") == "classic-textbox":
			_status_label.text = "Scenario text • continue when ready"
		else:
			_status_label.text = String(step.interaction.payload.get("prompt", "Choose an option"))


func save_active_session(slot_id: String) -> bool:
	if _active_content == null:
		_status_label.text = "Save failed • no package loaded"
		_shell_presenter.set_status(_status_label.text, true)
		return false
	var saved := save_repository.save(_active_content.campaign_id, slot_id, session_controller.session().snapshot())
	_status_label.text = "Saved %s" % slot_id if saved else "Save failed • %s" % save_repository.last_error
	_shell_presenter.set_status(_status_label.text, not saved)
	return saved


func load_active_session(slot_id: String) -> SessionStep:
	if _active_content == null:
		_status_label.text = "Load failed • no package loaded"
		_shell_presenter.set_status(_status_label.text, true)
		return SessionStep.failed(0, "no_package_loaded", "Load a package before restoring a save.")
	var envelope := save_repository.load(_active_content.campaign_id, slot_id, _active_content.package_hash)
	if envelope == null:
		_status_label.text = "Load failed • %s" % save_repository.last_error
		_shell_presenter.set_status(_status_label.text, true)
		return SessionStep.failed(session_controller.view().revision, "save_load_failed", save_repository.last_error)
	var step := session_controller.restore(_active_content, envelope)
	_status_label.text = "Loaded save %s" % slot_id if step.state != SessionStep.State.FAILED else "Load failed • %s" % step.error_message
	_shell_presenter.set_status(_status_label.text, step.state == SessionStep.State.FAILED)
	return step


func _refresh_campaigns() -> void:
	_shell_presenter.set_campaigns(package_repository.discover_campaigns(["user://packages"]))


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
	_apply_application_theme(value)
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


func _apply_application_theme(text_scale: float) -> void:
	var base_theme := load("res://src/presentation/classic_ui_theme.tres") as Theme
	var application_theme := base_theme.duplicate(true) as Theme
	application_theme.default_font_size = int(round(15.0 * text_scale))
	theme = application_theme


func _on_shell_layout_changed(workspace_rect: Rect2, _profile: UiLayoutProfile) -> void:
	var inset := 8.0
	var content_rect := workspace_rect.grow(-inset)
	_map_presenter.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_map_presenter.position = content_rect.position
	_map_presenter.size = content_rect.size
	if _dungeon_presenter != null:
		_dungeon_presenter.position = content_rect.position
		_dungeon_presenter.size = content_rect.size
	var textbox_rect := classic_textbox_rect(workspace_rect, _profile.bottom_height)
	_interaction_presenter.set_classic_regions(content_rect, textbox_rect)


static func classic_textbox_rect(workspace_rect: Rect2, bottom_height: float) -> Rect2:
	return Rect2(workspace_rect.position.x, workspace_rect.end.y, workspace_rect.size.x, bottom_height)


func _on_reduced_motion_changed(enabled: bool) -> void:
	_presentation_settings.reduced_motion = enabled
	settings_repository.save_settings(_presentation_settings)
