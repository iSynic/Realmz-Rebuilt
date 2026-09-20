## Owns the scene-backed application frame and coordinates its UI collaborators.
class_name GameShell
extends Control


signal start_package_requested(path: String, seed: int)
signal cancel_package_requested
signal refresh_campaigns_requested
signal intent_submitted(intent: PlayerIntent)
signal save_requested(slot_id: String)
signal save_and_quit_requested(slot_id: String)
signal load_requested(slot_id: String)
signal load_backup_requested(slot_id: String)
signal update_save_requested(slot_id: String, backup: bool)
signal refresh_saves_requested
signal end_adventure_requested
signal quit_requested
signal topology_debug_changed(enabled: bool)
signal dungeon_3d_changed(enabled: bool)
signal master_volume_changed(value: float)
signal sound_volume_changed(value: float)
signal music_volume_changed(value: float)
signal music_enabled_changed(enabled: bool)
signal music_playlist_mode_changed(playlist_id: int, mode: int)
signal text_scale_changed(value: float)
signal typography_mode_changed(value: String)
signal ui_scale_mode_changed(value: String)
signal display_scaling_mode_changed(value: String)
signal world_zoom_changed(value: int)
signal pixel_art_smoothing_changed(value: String)
signal crt_enabled_changed(enabled: bool)
signal crt_shader_changed(value: String)
signal crt_area_changed(value: String)
signal window_mode_changed(value: String)
signal reduced_motion_changed(enabled: bool)
signal reduced_sound_changed(enabled: bool)
signal auto_switch_to_melee_changed(enabled: bool)
signal exploration_speed_changed(percent: int)
signal combat_playback_speed_changed(percent: int)
signal hurry_spell_resolution_changed(enabled: bool)
signal exploration_minimap_changed(enabled: bool)
signal classic_exploration_visibility_changed(enabled: bool)
signal custom_fog_tile_changed(enabled: bool)
signal autojournal_changed(enabled: bool)
signal controller_preferences_changed(value: ControllerPreferences)
signal controller_binding_capture_requested(action_id: StringName)
signal layout_changed(workspace_rect: Rect2, profile: UiLayoutProfile)
signal route_changed(route_id: StringName)
signal play_stage_visibility_changed(visible: bool)
signal vault_archive_requested(character_id: String)
signal vault_restore_requested(character_id: String, revision_hash: String)
signal presentation_sound_requested(sound_id: int, wait_for_completion: bool, stop_existing: bool, reduced_sound_eligible: bool)
signal standalone_character_creation_requested
signal standalone_character_creation_cancelled
signal character_selection_completed(character_ids: Array[String])
signal combat_spell_cast_requested(option: InteractionRequestValue.CastOption)
signal combat_spellbook_back_requested

const SCROLL_ARROW_STEP := 32.0
const SCROLL_ARROW_INITIAL_DELAY := 0.34
const SCROLL_ARROW_REPEAT_INTERVAL := 0.065
const COMMAND_CONTROLLER_SCRIPT := preload("res://src/ui/shell/game_shell_command_controller.gd")
const MENU_CONTROLLER_SCRIPT := preload("res://src/ui/shell/game_shell_menu_controller.gd")

@export var party_effect_slot_scene: PackedScene

@onready var _menu_strip: PanelContainer = %MenuStrip
@onready var _menu_row: HBoxContainer = %MenuRow
@onready var _compact_menu: MenuButton = %CompactMenu
@onready var _package_status: Label = %PackageStatus
@onready var _stage_frame: NinePatchRect = %StageFrame
@onready var _picture_stage: Control = %PictureStage
@onready var _party_roster: ClassicPartyRoster = %PartyRoster
@onready var _bottom_region: PanelContainer = %BottomRegion
@onready var _bottom_row: BoxContainer = %BottomRow
@onready var _narrative: RichTextLabel = %NarrativeText
@onready var _status_label: Label = %Status
@onready var _facts: GridContainer = %Facts
@onready var _coordinates_label: Label = %Coordinates
@onready var _fatigue_label: Label = %Fatigue
@onready var _fatigue_bar: ProgressBar = %FatigueBar
@onready var _light_label: Label = %Light
@onready var _clock_label: Label = %Clock
@onready var _gold_label: Label = %Gold
@onready var _world_command_panel: PanelContainer = %WorldCommandPanel
@onready var _world_command_column: VBoxContainer = $BottomRegion/BottomRow/WorldCommandPanel/WorldCommandColumn
@onready var _world_command_grid: GridContainer = %WorldCommandGrid
@onready var _narrative_well: PanelContainer = %NarrativeWell
@onready var _command_panel: PanelContainer = %CommandPanel
@onready var _party_effects_row: BoxContainer = %PartyEffectsRow
@onready var _party_command_column: VBoxContainer = %PartyCommandColumn
@onready var _command_grid: GridContainer = %CommandGrid
@onready var _effects_panel: PanelContainer = %EffectsPanel
@onready var _effects_grid: GridContainer = %EffectsGrid
@onready var _navigator: ScreenNavigator = %ScreenNavigator
@onready var _smoke_action: Button = %SmokeAction
@onready var _activity_indicator: PanelContainer = %ActivityIndicator
@onready var _activity_icon: TextureRect = %ActivityIcon
@onready var _music_dialog: MusicPlaylistDialog = %MusicPlaylistDialog
@onready var _controller_prompts: ControllerPromptStrip = %ControllerPromptStrip
@onready var _controller_radial: ControllerRadialOverlay = %ControllerRadialOverlay
@onready var _controller_keyboard: ControllerQwertyEditor = %ControllerQwertyEditor

var _current_view: GameView
var last_picture_media_diagnostic: Dictionary = {}
var _presentation_settings := PresentationSettings.new()
var _profile: UiLayoutProfile
var _media: ClassicMediaCatalog
var _selected_character_id: String = ""
var _command_controller: GameShellCommandController
var _menu_controller: GameShellMenuController
var _picture_presenter: GameShellPicturePresenter
var _layout_controller: GameShellLayoutController
var _status_controller: GameShellStatusController
var _party_effects: GameShellPartyEffectsPresenter
var _music_playlist_id: int = 0
var _music_title: String = ""
var _music_playing: bool = false
var _controller_radial_kind: StringName = &""
var _controller_radial_activation := Callable()
var controller: ControllerAccess:
	get: return ControllerAccess.new(self)

var navigator: ScreenNavigator:
	get: return _navigator
var status: GameShellStatusController:
	get: return _status_controller
var commands: GameShellCommandController:
	get: return _command_controller
var roster: ClassicPartyRoster:
	get: return _party_roster
var settings: PresentationSettings:
	get: return _presentation_settings
var picture_stage: Control:
	get: return _picture_stage


class ControllerAccess:
	extends RefCounted
	var _shell: Variant
	func _init(shell: Variant) -> void: _shell = shell
	func show_prompts(family: String, context: StringName = &"") -> void:
		_shell._controller_prompts.present(family, context, _shell._presentation_settings.controller)
	func hide_prompts() -> void:
		_shell._controller_prompts.hide_prompts()
	func show_detail(value: String) -> void: _shell._controller_prompts.set_detail(value)
	func select_relative_character(delta: int) -> bool: return _shell._party_roster.controller_select_relative(delta)
	func cycle_section(delta: int) -> bool: return _shell._navigator.content_presenter.navigate_section(_shell._navigator.current_screen(), &"", delta)
	func receive_binding(action_id: StringName, descriptor: Dictionary) -> void: _shell._navigator.content_presenter.receive_controller_binding(action_id, descriptor)
	func cancel_binding_capture() -> void: _shell._navigator.content_presenter.cancel_controller_binding_capture()
	func set_live_input(value: String) -> void: _shell._navigator.content_presenter.set_controller_live_input(value)
	func radial_is_open() -> bool: return _shell._controller_radial.is_open()
	func top_menu_is_open() -> bool: return _shell._menu_controller.controller_is_open()
	func open_top_menu() -> bool: return _shell._menu_controller.controller_open()
	func move_top_menu(direction: Vector2i, repeated: bool = false) -> bool: return _shell._menu_controller.controller_direction(direction, repeated)
	func confirm_top_menu() -> bool: return _shell._menu_controller.controller_confirm()
	func back_top_menu() -> bool: return _shell._menu_controller.controller_back()
	func selected_top_menu_label() -> String: return _shell._menu_controller.controller_selected_label()
	func close_top_menu_for_pointer() -> void: _shell._menu_controller.controller_pointer_takeover()
	func text_editor_is_open() -> bool: return _shell._controller_keyboard.is_open()
	func open_text_editor() -> bool:
		var focused: Control = _shell.get_viewport().gui_get_focus_owner()
		return _shell._controller_keyboard.open_for(focused) if focused is LineEdit or focused is TextEdit else false
	func move_text_editor(direction: Vector2i) -> void: _shell._controller_keyboard.move_direction(Vector2(direction))
	func confirm_text_editor() -> void: _shell._controller_keyboard.confirm_focused()
	func cancel_text_editor() -> void: _shell._controller_keyboard.cancel()
	func page_text_editor(delta: int) -> void:
		if delta < 0: _shell._controller_keyboard.previous_page()
		else: _shell._controller_keyboard.next_page()
	func edit_text(action_id: StringName) -> void:
		match action_id:
			&"realmz_controller_action_radial": _shell._controller_keyboard.backspace()
			&"realmz_controller_workspace_radial": _shell._controller_keyboard.next_page()
			&"realmz_controller_character_previous": _shell._controller_keyboard.caret_left()
			&"realmz_controller_character_next": _shell._controller_keyboard.caret_right()
	func open_action_radial() -> bool:
		var entries: Array[ControllerRadialEntry] = _shell._command_controller.controller_entries()
		if entries.is_empty(): return false
		_open_radial(&"action", "ACTIONS", entries)
		return true
	func open_interaction_radial(entries: Array[ControllerRadialEntry], activation: Callable) -> bool:
		if entries.is_empty() or not activation.is_valid(): return false
		_open_radial(&"interaction", "ACTIONS", entries)
		_shell._controller_radial_activation = activation
		return true
	func open_workspace_radial() -> bool:
		var entries: Array[ControllerRadialEntry] = []
		var route_reason := GameShellAvailability.route_change_reason(_shell._current_view)
		var definitions: Array[Dictionary] = [
			{"id": &"inventory", "label": "Items", "icon": &"inventory"},
			{"id": &"spells", "label": "Spells", "icon": &"spells"},
			{"id": &"journal", "label": "Maps / Notes", "icon": &"maps"},
			{"id": &"character", "label": "Characters", "symbol": "♟"},
			{"id": &"services", "label": "Money", "icon": &"money"},
			{"id": &"workspace_preferences", "label": "Preferences", "icon": &"settings"},
			{"id": &"workspace_save_load", "label": "Save & Load", "icon": &"save"},
			{"id": &"exploration", "label": "Explore", "symbol": "✥"},
			{"id": &"vault", "label": "Character Files", "symbol": "▣"},
			{"id": &"allies", "label": "Allies", "symbol": "♙"},
			{"id": &"bestiary", "label": "Bestiary", "symbol": "♜"},
			{"id": &"workspace_music", "label": "Music", "symbol": "♫"},
			{"id": &"workspace_diagnostics", "label": "Diagnostics", "symbol": "◇"},
			{"id": &"workspace_top_menu", "label": "Top Menu", "symbol": "☰"},
		]
		for definition: Dictionary in definitions:
			var reason := route_reason
			if definition["id"] == &"allies" and reason.is_empty():
				reason = GameShellAvailability.allies_reason(_shell._current_view)
			var icon: Texture2D = _shell._command_controller.controller_icon(StringName(definition.get("icon", &"")))
			entries.append(ControllerRadialEntry.new(StringName(definition["id"]), String(definition["label"]), reason.is_empty(), reason, icon, String(definition.get("symbol", ""))))
		_open_radial(&"workspace", "WORKSPACES", entries)
		return true
	func move_radial(direction: Vector2i) -> void: _shell._controller_radial.move_direction(Vector2(direction))
	func page_radial(delta: int) -> void:
		if delta < 0: _shell._controller_radial.previous_page()
		else: _shell._controller_radial.next_page()
	func scroll_radial(direction: Vector2i) -> void: _shell._controller_radial.scroll_reason(direction)
	func confirm_radial() -> void: _shell._controller_radial.confirm_selected()
	func release_controller_hold() -> void: _shell._command_controller.release_controller_hold()
	func cancel_radial() -> bool:
		if not _shell._controller_radial.is_open(): return false
		_shell._controller_radial.cancel()
		_clear_radial_owner()
		return true
	func on_radial_selected(command_id: StringName) -> void:
		var kind: StringName = _shell._controller_radial_kind
		var activation: Callable = _shell._controller_radial_activation
		_clear_radial_owner()
		if kind == &"action": _shell._command_controller.activate_controller(command_id)
		elif kind == &"workspace": _activate_workspace(command_id)
		elif kind == &"interaction" and activation.is_valid(): activation.call(command_id)
	func _activate_workspace(command_id: StringName) -> void:
		match command_id:
			&"workspace_preferences": _shell._navigator.open_screen(&"system", true, &"Display")
			&"workspace_save_load": _shell._navigator.open_screen(&"system", true, &"Save & Load")
			&"workspace_music": _shell._navigator.open_screen(&"system", true, &"Audio")
			&"workspace_diagnostics": _shell._navigator.open_screen(&"system", true, &"Diagnostics")
			&"workspace_top_menu": _shell._menu_controller.controller_open()
			_: _shell._navigator.open_screen(command_id)
	func _open_radial(kind: StringName, title: String, entries: Array[ControllerRadialEntry]) -> void:
		_shell._controller_radial_kind = kind
		_shell._controller_radial_activation = Callable()
		_shell._controller_radial.set_title(title)
		_shell._controller_radial.open(entries)
	func _clear_radial_owner() -> void:
		_shell._controller_radial_kind = &""
		_shell._controller_radial_activation = Callable()


func _ready() -> void:
	# The shell is structural; only its concrete controls should participate in
	# GUI hit testing. A full-window PASS control masks earlier root siblings.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().node_added.connect(_on_tree_node_added)
	ClassicScrollArrowController.configure_descendants(self, SCROLL_ARROW_STEP, SCROLL_ARROW_INITIAL_DELAY, SCROLL_ARROW_REPEAT_INTERVAL)
	_command_controller = COMMAND_CONTROLLER_SCRIPT.new(self)
	_command_controller.initialize()
	_menu_controller = MENU_CONTROLLER_SCRIPT.new(self)
	_picture_presenter = GameShellPicturePresenter.new(self)
	_layout_controller = GameShellLayoutController.new(self)
	_status_controller = GameShellStatusController.new()
	_status_controller.initialize(self, _status_label, _narrative, _narrative_well, _package_status, _coordinates_label, _fatigue_label, _fatigue_bar, _light_label, _clock_label, _gold_label, _activity_indicator, _activity_icon, _navigator.setup_controller)
	_party_effects = GameShellPartyEffectsPresenter.new()
	_layout_controller.set_effect_slots(_party_effects.initialize(self, _effects_grid, _effects_panel, party_effect_slot_scene))
	_music_dialog.music_enabled_changed.connect(func(enabled: bool) -> void: music_enabled_changed.emit(enabled))
	_music_dialog.music_volume_changed.connect(func(value: float) -> void: music_volume_changed.emit(value))
	_music_dialog.playlist_mode_changed.connect(func(playlist_id: int, mode: int) -> void: music_playlist_mode_changed.emit(playlist_id, mode))
	_controller_radial.command_selected.connect(_handle_controller_radial_selection)
	_navigator.start_requested.connect(func(path: String, seed: int) -> void: start_package_requested.emit(path, seed))
	_navigator.cancel_package_requested.connect(func() -> void: cancel_package_requested.emit())
	_navigator.refresh_requested.connect(func() -> void: refresh_campaigns_requested.emit())
	_navigator.intent_submitted.connect(func(intent: PlayerIntent) -> void: intent_submitted.emit(intent))
	_navigator.vault_archive_requested.connect(func(character_id: String) -> void: vault_archive_requested.emit(character_id))
	_navigator.vault_restore_requested.connect(func(character_id: String, revision_hash: String) -> void: vault_restore_requested.emit(character_id, revision_hash))
	_navigator.presentation_sound_requested.connect(func(sound_id: int, wait_for_completion: bool, stop_existing: bool, reduced_sound_eligible: bool) -> void: presentation_sound_requested.emit(sound_id, wait_for_completion, stop_existing, reduced_sound_eligible))
	_navigator.standalone_character_creation_requested.connect(func() -> void: standalone_character_creation_requested.emit())
	_navigator.standalone_character_creation_cancelled.connect(func() -> void: standalone_character_creation_cancelled.emit())
	_navigator.screen_changed.connect(_on_screen_changed)
	_navigator.system_action_requested.connect(handle_system_action_requested)
	_navigator.presentation_setting_changed.connect(_on_presentation_setting_changed)
	_navigator.controller_binding_capture_requested.connect(func(action_id: StringName) -> void: controller_binding_capture_requested.emit(action_id))
	_party_roster.character_selected.connect(_on_character_selected)
	_party_roster.character_activated.connect(_on_character_activated)
	_party_roster.combat_auto_changed.connect(_on_combat_auto_changed)
	_party_roster.character_selection_completed.connect(func(character_ids: Array[String]) -> void: character_selection_completed.emit(character_ids))
	_party_roster.combat_spell_cast_requested.connect(func(option: InteractionRequestValue.CastOption) -> void: combat_spell_cast_requested.emit(option))
	_party_roster.combat_spellbook_back_requested.connect(func() -> void: combat_spellbook_back_requested.emit())
	_smoke_action.pressed.connect(_on_smoke_pressed)
	resized.connect(_apply_layout)
	_build_menus()
	_status_controller.set_status("Choose a validated Realmz campaign")
	_apply_layout()


func _on_tree_node_added(node: Node) -> void:
	if node is ScrollContainer:
		ClassicScrollArrowController.bind(node as ScrollContainer, SCROLL_ARROW_STEP, SCROLL_ARROW_INITIAL_DELAY, SCROLL_ARROW_REPEAT_INTERVAL)


func present(game_view: GameView) -> void:
	var previous_view := _current_view
	var previous_campaign_id := _current_view.campaign_id if _current_view != null and _current_view.session_started else ""
	var contextual_service_closed := _current_view != null and _current_view.pending_interaction != null and _current_view.pending_interaction.kind in [InteractionRequest.SHOP, InteractionRequest.TEMPLE, InteractionRequest.BANK] and game_view != null and game_view.pending_interaction == null
	var ordinary_exploration_update: bool = previous_view != null and game_view != null and not game_view.change_set.complete_refresh and game_view.domain_revisions.is_ordinary_exploration_update_from(previous_view.domain_revisions)
	var ordinary_party_update: bool = ordinary_exploration_update and game_view.domain_revisions.party != previous_view.domain_revisions.party
	_current_view = game_view
	if ordinary_exploration_update:
		_present_ordinary_exploration_shell(game_view, ordinary_party_update)
		return
	_command_controller.present(game_view)
	if game_view == null or not game_view.session_started:
		_status_controller.present_inactive()
		_party_effects.present(game_view)
		_party_roster.present(game_view)
		_navigator.present(game_view)
		_set_play_regions_visible(false)
		_build_menus()
		_update_command_availability()
		return
	if previous_campaign_id != game_view.campaign_id:
		_status_controller.reset_classic_text()
	_status_controller.present_world_facts(game_view)
	_party_effects.present(game_view)
	_apply_exploration_mode()
	_status_controller.set_campaign_title(game_view.campaign_summary.title if game_view.campaign_summary != null else game_view.campaign_id)
	if not game_view.party_members.any(func(character: CharacterView) -> bool: return character.id == _selected_character_id):
		_on_character_selected(game_view.party_members[0].id if not game_view.party_members.is_empty() else "")
	# Party setup owns its six-slot assembly pane and covers the persistent
	# gameplay roster. Rebuilding that hidden roster after every import added a
	# second set of rows and portrait work with no visible result.
	if not game_view.party_setup_available:
		_party_roster.present(game_view, _selected_character_id)
	_navigator.present(game_view)
	var play_regions_visible := not _navigator.full_stage_overlay_visible
	_set_play_regions_visible(play_regions_visible)
	var automatic_route := GameShellRoutePolicy.automatic_route(_navigator.current_screen(), game_view, contextual_service_closed)
	if automatic_route != _navigator.current_screen():
		_navigator.open_screen(automatic_route, false)
	_build_menus()
	_rebuild_command_deck()


func _present_ordinary_exploration_shell(game_view: GameView, party_update: bool = false) -> void:
	_status_controller.present_world_facts(game_view, false)
	_party_effects.present(game_view)
	if party_update:
		var affected_character_ids: Array[String] = game_view.change_set.affected_character_ids()
		if not affected_character_ids.is_empty():
			_party_roster.present_ordinary_exploration(game_view, _selected_character_id, affected_character_ids)
		_update_command_availability()
func set_package_media(media: ClassicMediaCatalog) -> void:
	if _media == media:
		return
	_media = media
	_party_effects.set_media(media)
	_party_roster.set_media_catalog(media)
	_navigator.set_media_catalog(media)
	_party_effects.present(_current_view)


func present_media_events(events: Array[DomainEvent], media: ClassicMediaCatalog) -> void:
	set_package_media(media)
	if media == null:
		return
	for event: DomainEvent in events:
		if event.kind == &"character_effect_requested":
			_party_roster.play_character_effect(String(event.payload.get("characterId", "")), int(event.payload.get("firstResourceId", 0)), int(event.payload.get("frameCount", 0)))
	_picture_presenter.present(events, media)
	last_picture_media_diagnostic = _picture_presenter.last_media_diagnostic


func present_combat_playback_frame(frame: CombatPlaybackFrame) -> void:
	if frame != null:
		_party_roster.present_playback_health(frame.combatant_health)


func apply_settings(settings: PresentationSettings) -> void:
	if settings == null:
		return
	_presentation_settings = settings
	var base_theme := load("res://src/ui/shared/style/classic_ui_theme.tres") as Theme
	theme = ClassicTypography.themed_copy(base_theme, settings)
	_narrative.add_theme_font_size_override("normal_font_size", int(round(17.0 * settings.text_scale)))
	_navigator.set_presentation_settings(settings)
	if _music_dialog != null and _music_dialog.visible:
		_music_dialog.open(settings, _music_playlist_id, _music_title, _music_playing)
	_apply_layout()


func set_music_playback_state(playlist_id: int, title: String, playing: bool) -> void:
	_music_playlist_id = playlist_id
	_music_title = title
	_music_playing = playing
	if _music_dialog != null:
		_music_dialog.set_playback_state(playlist_id, title, playing)
	_build_menus()


func accepts_exploration_input() -> bool:
	return (_music_dialog == null or not _music_dialog.visible) and _navigator.accepts_exploration_input()


func handle_back() -> bool:
	if _music_dialog != null and _music_dialog.visible:
		_music_dialog.close()
		return true
	if accepts_exploration_input():
		_navigator.open_screen(&"system")
		return true
	var handled := _navigator.handle_back()
	if handled:
		var play_regions_visible := _current_view != null and _current_view.session_started and not _navigator.full_stage_overlay_visible
		_set_play_regions_visible(play_regions_visible)
	return handled


func open_system_workspace() -> void:
	_navigator.open_screen(&"system")


func _handle_controller_radial_selection(command_id: StringName) -> void:
	controller.on_radial_selected(command_id)


func handle_route_shortcut(event: InputEvent) -> bool:
	for definition: UiRouteDefinition in UiRouteCatalog.routes():
		var shortcut := definition.shortcut
		if not shortcut.is_empty() and event.is_action_pressed(shortcut):
			if not GameShellAvailability.route_change_reason(_current_view).is_empty():
				return true
			_navigator.open_screen(definition.route_id)
			return true
	return false


func show_campaign_selection(load_after_selection: bool = false) -> void:
	_navigator.show_campaign_selection(load_after_selection)
	_set_play_regions_visible(false)
	_build_menus()


func show_vault_from_splash() -> void:
	_navigator.show_vault_from_splash()
	_set_play_regions_visible(false)
	_build_menus()


func show_splash() -> void:
	_navigator.show_splash()
	_set_play_regions_visible(false)
	_build_menus()


func _apply_layout() -> void:
	if not is_node_ready():
		return
	_profile = _layout_controller.apply(size, _presentation_settings, _current_view)
	_build_menus()
	_rebuild_command_deck()
	layout_changed.emit(_layout_controller.workspace_rect, _profile)


func refresh_layout() -> void:
	_apply_layout()


func _apply_exploration_mode() -> void:
	if not is_node_ready():
		return
	_world_command_panel.theme_type_variation = &"ClassicSharedStone"
	_command_panel.theme_type_variation = &"ClassicSharedStone"


func _build_menus() -> void:
	if not is_node_ready():
		return
	_menu_controller.rebuild(_current_view, _presentation_settings, _music_title, _music_playing)


func _rebuild_command_deck() -> void:
	_command_controller.rebuild()


func _update_command_availability() -> void:
	_command_controller.update_availability()


func _presentation_command_definition(definition: Dictionary) -> Dictionary:
	return _command_controller.presentation_definition(definition)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_command_controller.release()


func _on_screen_changed(screen_id: StringName) -> void:
	var play_regions_visible := _current_view != null and _current_view.session_started and not _navigator.full_stage_overlay_visible
	_set_play_regions_visible(play_regions_visible)
	_apply_layout()
	_status_controller.set_status(String(screen_id).replace("_", " ").capitalize())
	_build_menus()
	_rebuild_command_deck()
	route_changed.emit(screen_id)


func _set_play_regions_visible(visible: bool) -> void:
	var play_route := visible and _navigator.current_screen() in [&"exploration", &"combat", &"spells"]
	_stage_frame.visible = play_route
	_bottom_region.visible = play_route and _navigator.current_screen() in [&"exploration", &"spells"]
	_party_roster.visible = play_route
	play_stage_visibility_changed.emit(play_route)


func handle_system_action_requested(action_id: StringName, value: Variant) -> void:
	match action_id:
		&"save": save_requested.emit("quick" if value == null else String(value))
		&"save_and_quit": save_and_quit_requested.emit("quick" if value == null else String(value))
		&"load": load_requested.emit("quick" if value == null else String(value))
		&"load_backup": load_backup_requested.emit("quick" if value == null else String(value))
		&"update_save": update_save_requested.emit(String(value.get("slotId", "")), bool(value.get("backup", false)))
		&"refresh_saves": refresh_saves_requested.emit()
		&"end_adventure": end_adventure_requested.emit()
		&"campaigns": show_campaign_selection()
		&"music_toggle": music_enabled_changed.emit(not _presentation_settings.music_enabled)
		&"music_playlist": _music_dialog.open(_presentation_settings, _music_playlist_id, _music_title, _music_playing)
		&"quit": quit_requested.emit()


func _on_presentation_setting_changed(setting_id: StringName, value: Variant) -> void:
	match setting_id:
		&"topology_debug": topology_debug_changed.emit(bool(value))
		&"dungeon_3d": dungeon_3d_changed.emit(bool(value))
		&"master_volume": master_volume_changed.emit(float(value))
		&"sound_volume": sound_volume_changed.emit(float(value))
		&"music_volume": music_volume_changed.emit(float(value))
		&"music_enabled": music_enabled_changed.emit(bool(value))
		&"text_scale": text_scale_changed.emit(float(value))
		&"typography_mode": typography_mode_changed.emit(String(value))
		&"ui_scale_mode": ui_scale_mode_changed.emit(String(value))
		&"display_scaling_mode": display_scaling_mode_changed.emit(String(value))
		&"world_zoom": world_zoom_changed.emit(int(value))
		&"pixel_art_smoothing": pixel_art_smoothing_changed.emit(String(value))
		&"crt_enabled": crt_enabled_changed.emit(bool(value))
		&"crt_shader": crt_shader_changed.emit(String(value))
		&"crt_area": crt_area_changed.emit(String(value))
		&"window_mode": window_mode_changed.emit(String(value))
		&"reduced_motion": reduced_motion_changed.emit(bool(value))
		&"reduced_sound": reduced_sound_changed.emit(bool(value))
		&"auto_switch_to_melee": auto_switch_to_melee_changed.emit(bool(value))
		&"exploration_speed_percent": exploration_speed_changed.emit(int(value))
		&"combat_playback_speed_percent": combat_playback_speed_changed.emit(int(value))
		&"hurry_spell_resolution": hurry_spell_resolution_changed.emit(bool(value))
		&"show_exploration_minimap": exploration_minimap_changed.emit(bool(value))
		&"classic_exploration_visibility": classic_exploration_visibility_changed.emit(bool(value))
		&"custom_fog_tile_enabled": custom_fog_tile_changed.emit(bool(value))
		&"autojournal_enabled": autojournal_changed.emit(bool(value))
		&"controller_preferences": controller_preferences_changed.emit(value as ControllerPreferences)


func _on_character_selected(character_id: String) -> void:
	_selected_character_id = character_id
	if _navigator.current_screen() == &"inventory" and _navigator.content_presenter.select_inventory_character(character_id):
		_navigator.refresh_current_workspace()
		return
	if _navigator.content_presenter.select_character(character_id) and _navigator.current_screen() == &"character":
		_navigator.refresh_current_workspace()


func _on_character_activated(character_id: String) -> void:
	_on_character_selected(character_id)
	if _navigator.current_screen() == &"inventory":
		return
	_navigator.open_screen(&"character")


func _on_combat_auto_changed(character_id: String, enabled: bool) -> void:
	if _current_view == null or _current_view.combat_view == null or _current_view.combat_view.outcome != &"active":
		return
	intent_submitted.emit(CombatIntents.set_auto(character_id, enabled))


func _on_smoke_pressed() -> void:
	_smoke_action.release_focus()
	if _current_view == null or not _current_view.session_started:
		_status_controller.set_status("Input verified • no package loaded")
		return
	intent_submitted.emit(ExplorationIntents.search())
