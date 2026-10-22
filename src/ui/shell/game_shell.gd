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
signal legacy_save_load_requested(slot_id: String, backup: bool, target_slot_id: String)
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
signal music_transition_changed(value: String)
signal interface_text_scale_changed(value: float)
signal narrative_text_scale_changed(value: float)
signal font_choice_changed(role: StringName, identity: String)
signal pause_changed(active: bool)
signal show_overworld_command_titles_changed(enabled: bool)
signal integer_fit_hidden_commands_changed(enabled: bool)
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
signal immediate_single_target_actions_changed(enabled: bool)
signal click_to_move_enabled_changed(enabled: bool)
signal classic_keyboard_shortcuts_changed(enabled: bool)
signal exploration_move_to_requested
signal combat_log_requested
signal exploration_speed_changed(percent: int)
signal combat_playback_speed_changed(percent: int)
signal hurry_spell_resolution_changed(enabled: bool)
signal exploration_minimap_changed(enabled: bool)
signal classic_exploration_visibility_changed(enabled: bool)
signal custom_fog_tile_changed(enabled: bool)
signal indoor_party_icon_changed(index: int)
signal autojournal_changed(enabled: bool)
signal controller_preferences_changed(value: ControllerPreferences)
signal controller_binding_capture_requested(action_id: StringName)
signal layout_changed(workspace_rect: Rect2, profile: UiLayoutProfile)
signal route_changed(route_id: StringName)
signal play_stage_visibility_changed(visible: bool)
signal vault_archive_requested(character_id: String)
signal vault_restore_requested(character_id: String, revision_hash: String)
signal vault_maintenance_requested(operation: StringName)
signal presentation_sound_requested(sound_id: int, wait_for_completion: bool, stop_existing: bool, reduced_sound_eligible: bool)
signal standalone_character_creation_requested
signal standalone_character_creation_cancelled
signal character_selection_completed(character_ids: Array[String])
signal combat_spell_cast_requested(option: InteractionRequestValue.CastOption)
signal combat_spellbook_back_requested
signal combat_bandage_target_selected(character_id: String)
signal combat_inventory_response_submitted(body: InteractionResponse.CombatBody)
signal combat_inventory_item_use_requested(character_id: String, instance_id: String)

const SCROLL_ARROW_STEP := 32.0
const SCROLL_ARROW_INITIAL_DELAY := 0.34
const SCROLL_ARROW_REPEAT_INTERVAL := 0.065

@export var party_effect_slot_scene: PackedScene

@onready var _package_status: Label = $PauseMenu.get_node("%PackageStatus")
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
@onready var _world_command_lower_grid: GridContainer = %WorldCommandLowerGrid
@onready var _narrative_well: PanelContainer = %NarrativeWell
@onready var _command_panel: PanelContainer = %CommandPanel
@onready var _party_effects_row: BoxContainer = %PartyEffectsRow
@onready var _party_command_column: VBoxContainer = %PartyCommandColumn
@onready var _command_grid: GridContainer = %CommandGrid
@onready var _effects_panel: PanelContainer = %EffectsPanel
@onready var _effects_grid: GridContainer = %EffectsGrid
@onready var _torch_dock: PanelContainer = %TorchDock
@onready var _navigator: ScreenNavigator = %ScreenNavigator
@onready var _smoke_action: Button = %SmokeAction
@onready var _activity_indicator: PanelContainer = %ActivityIndicator
@onready var _activity_icon: TextureRect = %ActivityIcon
@onready var music_workspace: MusicPlaylistDialog = %MusicPlaylistDialog
@onready var font_picker: FontPickerDialog = %FontPickerDialog
@onready var character_art: CharacterArtDialog = %CharacterArtDialog
@onready var _controller_prompts: ControllerPromptStrip = %ControllerPromptStrip
@onready var _controller_radial: ControllerRadialOverlay = %ControllerRadialOverlay
@onready var _controller_keyboard: ControllerQwertyEditor = %ControllerQwertyEditor
@onready var hud: ModularHud = %ModularHud
@onready var hud_arrange: HudArrangeOverlay = %HudArrangeOverlay

var _current_view: GameView
var last_picture_media_diagnostic: Dictionary = {}
var _presentation_settings := PresentationSettings.new()
var _theme_metrics: Array = []
var font_resolver := FontResolver.new()
var menu_input_blocked: Callable
var _media: ClassicMediaCatalog
var _selected_character_id: String = ""
var _selected_combat_battle_id: String = ""
var _selected_combat_actor_id: String = ""
var _command_controller: GameShellCommandController
var _pause_controller: GameShellPauseController
var _picture_presenter: GameShellPicturePresenter
var _layout_controller: GameShellLayoutController
var _status_controller: GameShellStatusController
var _party_effects: GameShellPartyEffectsPresenter
var _music_playlist_id: int = 0
var _music_title: String = ""
var _music_playing: bool = false
var _controller_radials := GameShellControllerRadials.new(self)
var exploration_move_to_available: Callable
var controller: GameShellControllerAccess:
	get: return GameShellControllerAccess.new(self)

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
var click_to_move_enabled: bool:
	get: return _presentation_settings.click_to_move_enabled
var picture_stage: Control:
	get: return _picture_stage
var pause_active: bool:
	get: return _pause_controller != null and _pause_controller.is_active()
## Read-only collaborators for the shell's helper controllers, which may not reach private fields.
var current_view: GameView:
	get: return _current_view
var layout_profile: UiLayoutProfile:
	get: return _layout_controller.applied_profile if _layout_controller != null else null
var media: ClassicMediaCatalog:
	get: return _media
var pause_controller: GameShellPauseController:
	get: return _pause_controller
var controller_prompts: ControllerPromptStrip:
	get: return _controller_prompts
var controller_radial: ControllerRadialOverlay:
	get: return _controller_radial
var controller_radials: GameShellControllerRadials:
	get: return _controller_radials
var controller_keyboard: ControllerQwertyEditor:
	get: return _controller_keyboard
var command_grid: GridContainer:
	get: return _command_grid
var world_command_panel: PanelContainer:
	get: return _world_command_panel
var world_command_grid: GridContainer:
	get: return _world_command_grid
var world_command_lower_grid: GridContainer:
	get: return _world_command_lower_grid
var torch_dock: PanelContainer:
	get: return _torch_dock
var selected_character_id: String:
	get: return _selected_character_id
var navigation_overlay_active: bool:
	get: return character_art.visible or font_picker.visible or (music_workspace != null and music_workspace.visible) or _pause_controller.is_active() or _controller_radial.is_open() or _controller_keyboard.is_open() or _navigator.draft_dialog.visible or hud.focus_root() != null


func _ready() -> void:
	# The shell is structural; only its concrete controls should participate in
	# GUI hit testing. A full-window PASS control masks earlier root siblings.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().node_added.connect(_on_tree_node_added)
	ClassicScrollArrowController.configure_descendants(self, SCROLL_ARROW_STEP, SCROLL_ARROW_INITIAL_DELAY, SCROLL_ARROW_REPEAT_INTERVAL)
	_command_controller = GameShellCommandController.new(self)
	_command_controller.initialize()
	_pause_controller = GameShellPauseController.new(self)
	_picture_presenter = GameShellPicturePresenter.new(self)
	_layout_controller = GameShellLayoutController.new(self)
	_status_controller = GameShellStatusController.new()
	_status_controller.initialize(self, _status_label, _narrative, _narrative_well, _package_status, _coordinates_label, _fatigue_label, _fatigue_bar, _light_label, _clock_label, _gold_label, _activity_indicator, _activity_icon, _navigator.setup_controller)
	hud.initialize(self)
	_party_effects = GameShellPartyEffectsPresenter.new()
	_layout_controller.set_effect_slots(_party_effects.initialize(self, _effects_grid, _effects_panel, party_effect_slot_scene))
	font_picker.applied.connect(func(role: StringName, identity: String) -> void:
		_navigator.content_presenter.system_preferences.stage_setting(StringName(String(role) + "_font"), identity)
	)
	_navigator.setup_controller.set_character_art_dialog(character_art)
	_navigator.content_presenter.characters.character_art_dialog = character_art
	_controller_radial.command_selected.connect(_handle_controller_radial_selection)
	_navigator.start_requested.connect(func(path: String, seed: int) -> void: start_package_requested.emit(path, seed))
	_navigator.cancel_package_requested.connect(func() -> void: cancel_package_requested.emit())
	_navigator.refresh_requested.connect(func() -> void: refresh_campaigns_requested.emit())
	_navigator.intent_submitted.connect(func(intent: PlayerIntent) -> void: intent_submitted.emit(intent))
	_navigator.vault_archive_requested.connect(func(character_id: String) -> void: vault_archive_requested.emit(character_id))
	_navigator.vault_maintenance_requested.connect(func(operation: StringName) -> void: vault_maintenance_requested.emit(operation))
	_navigator.vault_restore_requested.connect(func(character_id: String, revision_hash: String) -> void: vault_restore_requested.emit(character_id, revision_hash))
	_navigator.presentation_sound_requested.connect(func(sound_id: int, wait_for_completion: bool, stop_existing: bool, reduced_sound_eligible: bool) -> void: presentation_sound_requested.emit(sound_id, wait_for_completion, stop_existing, reduced_sound_eligible))
	_navigator.standalone_character_creation_requested.connect(func() -> void: standalone_character_creation_requested.emit())
	_navigator.standalone_character_creation_cancelled.connect(func() -> void: standalone_character_creation_cancelled.emit())
	_navigator.screen_changed.connect(_on_screen_changed)
	_navigator.system_action_requested.connect(handle_system_action_requested)
	_navigator.content_presenter.save_previews_changed.connect(_refresh_pause_menu)
	_navigator.presentation_setting_changed.connect(_on_presentation_setting_changed)
	_navigator.combat_inventory_response_submitted.connect(func(body: InteractionResponse.CombatBody) -> void: combat_inventory_response_submitted.emit(body))
	_navigator.combat_inventory_item_use_requested.connect(func(character_id: String, instance_id: String) -> void: combat_inventory_item_use_requested.emit(character_id, instance_id))
	_navigator.controller_binding_capture_requested.connect(func(action_id: StringName) -> void: controller_binding_capture_requested.emit(action_id))
	_party_roster.character_selected.connect(_on_character_selected)
	_party_roster.character_activated.connect(_on_character_activated)
	_party_roster.combat_auto_changed.connect(_on_combat_auto_changed)
	_party_roster.character_selection_completed.connect(func(character_ids: Array[String]) -> void: character_selection_completed.emit(character_ids))
	_party_roster.combat_spell_cast_requested.connect(func(option: InteractionRequestValue.CastOption) -> void: combat_spell_cast_requested.emit(option))
	_party_roster.combat_spellbook_back_requested.connect(func() -> void: combat_spellbook_back_requested.emit())
	_party_roster.combat_bandage_target_selected.connect(func(character_id: String) -> void: combat_bandage_target_selected.emit(character_id))
	_smoke_action.pressed.connect(_on_smoke_pressed)
	resized.connect(_apply_layout)
	_bottom_region.minimum_size_changed.connect(_layout_controller.queue_footer_layout)
	_refresh_pause_menu()
	_status_controller.set_status("Choose a validated Realmz campaign")
	_apply_layout()


func _on_tree_node_added(node: Node) -> void:
	if is_ancestor_of(node) or (get_parent().is_ancestor_of(node) and (node.scene_file_path.begins_with("res://src/ui/shared/interactions/") or node.scene_file_path == "res://src/ui/combat/fast_spell_dock.tscn")):
		UiSizing.bind_added.call_deferred(node.get_instance_id())
	if node is ScrollContainer:
		ClassicScrollArrowController.bind(node as ScrollContainer, SCROLL_ARROW_STEP, SCROLL_ARROW_INITIAL_DELAY, SCROLL_ARROW_REPEAT_INTERVAL)


func present(game_view: GameView) -> void:
	var previous_view := _current_view
	var previous_campaign_id := _current_view.campaign_id if _current_view != null and _current_view.session_started else ""
	var contextual_service_closed := _current_view != null and _current_view.pending_interaction != null and _current_view.pending_interaction.kind in [InteractionRequest.SHOP, InteractionRequest.TEMPLE, InteractionRequest.BANK] and game_view != null and game_view.pending_interaction == null
	var ordinary_exploration_update: bool = previous_view != null and game_view != null and not game_view.change_set.complete_refresh and game_view.domain_revisions.is_ordinary_exploration_update_from(previous_view.domain_revisions)
	var ordinary_party_update: bool = ordinary_exploration_update and game_view.domain_revisions.party != previous_view.domain_revisions.party
	_current_view = game_view
	hud.observe(previous_view, game_view)
	_sync_combat_roster_selection(game_view)
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
		_refresh_pause_menu()
		_command_controller.update_availability()
		return
	if previous_campaign_id != game_view.campaign_id:
		_status_controller.reset_classic_text()
	_status_controller.present_world_facts(game_view)
	_party_effects.present(game_view)
	_status_controller.set_campaign_title(game_view.campaign_summary.title if game_view.campaign_summary != null else game_view.campaign_id)
	if (game_view.combat_view == null or game_view.combat_view.outcome != &"active") and not game_view.party_members.any(func(character: CharacterView) -> bool: return character.id == _selected_character_id):
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
	_refresh_pause_menu()
	_rebuild_command_deck()


func _sync_combat_roster_selection(view: GameView) -> void:
	var combat := view.combat_view if view != null else null
	if combat == null or combat.outcome != &"active":
		_selected_combat_battle_id = ""
		_selected_combat_actor_id = ""
		return
	if combat.battle_id == _selected_combat_battle_id and combat.active_actor_id == _selected_combat_actor_id:
		return
	_selected_combat_battle_id = combat.battle_id
	_selected_combat_actor_id = combat.active_actor_id
	_selected_character_id = combat.active_actor_id if view.party_members.any(func(character: CharacterView) -> bool: return character.id == combat.active_actor_id) else ""


func _present_ordinary_exploration_shell(game_view: GameView, party_update: bool = false) -> void:
	_status_controller.present_world_facts(game_view, false)
	_party_effects.present(game_view)
	if party_update:
		var affected_character_ids: Array[String] = game_view.change_set.affected_character_ids()
		if not affected_character_ids.is_empty():
			_party_roster.present_ordinary_exploration(game_view, _selected_character_id, affected_character_ids)
		_command_controller.update_availability()
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
	UiSizing.font_size(_narrative, &"normal_font_size", 17)
	_navigator.set_presentation_settings(settings)
	if music_workspace != null and music_workspace.visible:
		music_workspace.open(settings, _music_playlist_id, _music_title, _music_playing)
	_apply_layout()
	_refresh_pause_menu()


func set_music_playback_state(playlist_id: int, title: String, playing: bool) -> void:
	_music_playlist_id = playlist_id
	_music_title = title
	_music_playing = playing
	if music_workspace != null:
		music_workspace.set_playback_state(playlist_id, title, playing)
	_refresh_pause_menu()


func accepts_exploration_input() -> bool:
	return not navigation_overlay_active and _navigator.accepts_exploration_input()


func handle_back() -> bool:
	if hud_arrange.visible:
		hud_arrange.cancel()
		return true
	if character_art.visible:
		character_art.dismiss()
		return true
	if music_workspace != null and music_workspace.visible:
		music_workspace.close()
		return true
	if pause_active: return _pause_controller.back()
	if hud.release_panel_focus(): return true
	if accepts_exploration_input(): return _pause_controller.open()
	var handled := _navigator.handle_back()
	if handled:
		var play_regions_visible := _current_view != null and _current_view.session_started and not _navigator.full_stage_overlay_visible
		_set_play_regions_visible(play_regions_visible)
	return handled


func open_system_workspace() -> void:
	_pause_controller.open()


func _handle_controller_radial_selection(command_id: StringName) -> void:
	controller.radial.on_selected(command_id)


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
	_refresh_pause_menu()


func show_vault_from_splash() -> void:
	_navigator.show_vault_from_splash()
	_set_play_regions_visible(false)
	_refresh_pause_menu()


func show_splash() -> void:
	_navigator.show_splash()
	_set_play_regions_visible(false)
	_refresh_pause_menu()


func _apply_layout() -> void:
	if not is_node_ready():
		return
	var sizing_profile := UiLayoutProfile.for_viewport(size, _presentation_settings.ui_scale_mode, _presentation_settings.display_scaling_mode, _presentation_settings.interface_text_scale, _presentation_settings.narrative_text_scale)
	var theme_metrics: Array = [sizing_profile.ui_scale, _presentation_settings.interface_text_scale, _presentation_settings.narrative_text_scale, _presentation_settings.interface_font, _presentation_settings.narrative_font]
	if _theme_metrics != theme_metrics:
		_theme_metrics = theme_metrics
		theme = ClassicTypography.themed_copy(load("res://src/ui/shared/style/classic_ui_theme.tres") as Theme, _presentation_settings, sizing_profile.ui_scale, font_resolver)
	UiSizing.apply(self, sizing_profile)
	_layout_controller.apply(size, _presentation_settings, _current_view)
	_refresh_pause_menu()
	_rebuild_command_deck()
	_layout_controller.apply(size, _presentation_settings, _current_view)
	layout_changed.emit(_layout_controller.workspace_rect, _layout_controller.applied_profile)


func refresh_layout() -> void:
	_apply_layout()


func _refresh_pause_menu() -> void:
	if not is_node_ready():
		return
	_pause_controller.rebuild()


func _rebuild_command_deck() -> void:
	_command_controller.rebuild()
	_layout_controller.queue_footer_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_command_controller.release()


func _on_screen_changed(screen_id: StringName) -> void:
	var play_regions_visible := _current_view != null and _current_view.session_started and not _navigator.full_stage_overlay_visible
	_set_play_regions_visible(play_regions_visible)
	_apply_layout()
	_status_controller.set_status(String(screen_id).replace("_", " ").capitalize())
	_refresh_pause_menu()
	_rebuild_command_deck()
	route_changed.emit(screen_id)


func _set_play_regions_visible(visible: bool) -> void:
	var menu_over_adventure := _pause_controller != null and _pause_controller.is_active() and _current_view != null and _current_view.session_started
	var play_route := visible and (_navigator.current_screen() in [&"exploration", &"combat", &"spells", &"save_load"] or menu_over_adventure)
	_stage_frame.visible = play_route
	_bottom_region.visible = play_route and (_navigator.current_screen() in [&"exploration", &"spells", &"save_load"] or menu_over_adventure)
	_party_roster.visible = play_route
	if hud.active:
		hud.visible = play_route
		_bottom_region.hide()
	play_stage_visibility_changed.emit(play_route)


func handle_system_action_requested(action_id: StringName, value: Variant) -> void:
	if action_id in [&"end_adventure", &"campaigns", &"quit", &"load", &"load_backup", &"load_legacy_into_slot"] and _navigator.draft_dialog.defer_if_dirty(_navigator.content_presenter.system_preferences, handle_system_action_requested.bind(action_id, value)): return
	match action_id:
		&"arrange_hud": hud_arrange.open(self)
		&"save": save_requested.emit("quick" if value == null else String(value))
		&"save_and_quit": save_and_quit_requested.emit("quick" if value == null else String(value))
		&"load": load_requested.emit("quick" if value == null else String(value))
		&"load_backup": load_backup_requested.emit("quick" if value == null else String(value))
		&"load_legacy_into_slot": legacy_save_load_requested.emit(String(value.get("slotId", "")), bool(value.get("backup", false)), String(value.get("targetSlotId", "")))
		&"update_save": update_save_requested.emit(String(value.get("slotId", "")), bool(value.get("backup", false)))
		&"refresh_saves": refresh_saves_requested.emit()
		&"end_adventure": end_adventure_requested.emit()
		&"campaigns": show_campaign_selection()
		&"cancel_preferences": _navigator.handle_back()
		&"music_toggle": music_enabled_changed.emit(not _presentation_settings.music_enabled)
		&"music_playlist":
			if not _navigator.draft_dialog.defer_if_dirty(_navigator.content_presenter.system_preferences, handle_system_action_requested.bind(&"music_playlist", null)):
				music_workspace.open(_presentation_settings, _music_playlist_id, _music_title, _music_playing)
		&"choose_interface_font": font_picker.open(&"interface", _navigator.content_presenter.system_preferences.draft_settings())
		&"character_art": character_art.open_library()
		&"choose_narrative_font": font_picker.open(&"narrative", _navigator.content_presenter.system_preferences.draft_settings())
		&"click_to_move_toggle": click_to_move_enabled_changed.emit(not _presentation_settings.click_to_move_enabled)
		&"combat_log": combat_log_requested.emit()
		&"quit": quit_requested.emit()


func _on_presentation_setting_changed(setting_id: StringName, value: Variant) -> void:
	GameShellPreferenceSignals.emit_change(self, setting_id, value)


func _on_character_selected(character_id: String) -> void:
	_selected_character_id = character_id
	if _navigator.current_screen() == &"inventory" and _navigator.content_presenter.select_inventory_character(character_id):
		_navigator.refresh_current_workspace()
		return
	if _navigator.content_presenter.select_character(character_id) and _navigator.current_screen() == &"character":
		_navigator.refresh_current_workspace()


func _on_character_activated(character_id: String) -> void:
	_on_character_selected(character_id)
	if _navigator.current_screen() != &"inventory":
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
