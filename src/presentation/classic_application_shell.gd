class_name ClassicApplicationShell
extends Control

signal start_package_requested(path: String, seed: int)
signal cancel_package_requested
signal refresh_campaigns_requested
signal intent_submitted(intent: PlayerIntent)
signal save_requested(slot_id: String)
signal save_and_quit_requested(slot_id: String)
signal load_requested(slot_id: String)
signal load_backup_requested(slot_id: String)
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
signal window_mode_changed(value: String)
signal reduced_motion_changed(enabled: bool)
signal reduced_sound_changed(enabled: bool)
signal auto_switch_to_melee_changed(enabled: bool)
signal exploration_speed_changed(percent: int)
signal combat_playback_speed_changed(percent: int)
signal exploration_minimap_changed(enabled: bool)
signal classic_exploration_visibility_changed(enabled: bool)
signal autojournal_changed(enabled: bool)
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

const MUTED := Color("9aa4a5")
const ERROR := Color("ef7770")
const TEXT := Color("d8d9d2")
const SCROLL_ARROW_STEP := 32.0
const SCROLL_ARROW_INITIAL_DELAY := 0.34
const SCROLL_ARROW_REPEAT_INTERVAL := 0.065
const HELD_COMMAND_INTERVAL := 1.0 / 60.0
const PARTY_EFFECT_FRAME_COUNT := ClassicPartyEffects.FRAME_COUNT
const HELD_COMMAND_START_SOUND_IDS: Dictionary = {
	&"area_search": 6001,
	&"rest": 6001,
}
# Castle sounds the shared Shop/Temple/Encounter control before dispatching it.
const CONTEXTUAL_CONTROL_SOUND_ID := 141
const TORCH_BUTTON_SCRIPT := preload("res://src/presentation/classic_torch_command_button.gd")
const SEARCH_BUTTON_SCRIPT := preload("res://src/presentation/classic_search_command_button.gd")
const MUSIC_PLAYLIST_DIALOG_SCRIPT := preload("res://src/presentation/music_playlist_dialog.gd")
const SAVE_STATUS_TEXTURE_PATH := "res://src/presentation/assets/ui/status/save-status.png"
const JOURNAL_STATUS_TEXTURE_PATH := "res://src/presentation/assets/ui/status/journal-status.png"

@onready var _menu_strip: PanelContainer = %MenuStrip
@onready var _menu_row: HBoxContainer = %MenuRow
@onready var _compact_menu: MenuButton = %CompactMenu
@onready var _package_status: Label = %PackageStatus
@onready var _stage_frame: NinePatchRect = %StageFrame
@onready var _picture_stage: Control = %PictureStage
@onready var _picture: TextureRect = %Picture
@onready var _picture_caption: Label = %PictureCaption
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
@onready var _router: ClassicScreenRouter = %ScreenRouter
@onready var _smoke_action: Button = %SmokeAction
@onready var _activity_indicator: PanelContainer = %ActivityIndicator
@onready var _activity_icon: TextureRect = %ActivityIcon

var _current_view: GameView
var last_picture_media_diagnostic: Dictionary = {}
var _presentation_settings := PresentationSettings.new()
var _profile: UiLayoutProfile
var _media: ClassicMediaCatalog
var _selected_character_id: String = ""
var _latest_classic_text: String = ""
var _simulation_buttons: Dictionary = {}
var _menu_actions: Dictionary = {}
var _menus_connected: Dictionary = {}
var _held_command: StringName = &""
var _held_command_timer: Timer
var _effect_frame_timer: Timer
var _effect_frame_index: int = 0
var _effect_slots: Array[TextureRect] = []
var _effect_texture_cache: Dictionary = {}
var _music_dialog: MusicPlaylistDialog
var _music_playlist_id: int = 0
var _music_title: String = ""
var _music_playing: bool = false
var _activity_tween: Tween
var _field_time_playback: RefCounted = preload("res://src/presentation/classic_field_time_playback.gd").new()
var _save_status_texture: Texture2D = load(SAVE_STATUS_TEXTURE_PATH) as Texture2D
var _journal_status_texture: Texture2D = load(JOURNAL_STATUS_TEXTURE_PATH) as Texture2D


func _ready() -> void:
	# The shell is structural; only its concrete controls should participate in
	# GUI hit testing. A full-window PASS control masks earlier root siblings.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().node_added.connect(_on_tree_node_added)
	ClassicScrollArrowController.configure_descendants(self, SCROLL_ARROW_STEP, SCROLL_ARROW_INITIAL_DELAY, SCROLL_ARROW_REPEAT_INTERVAL)
	_held_command_timer = Timer.new()
	_held_command_timer.wait_time = HELD_COMMAND_INTERVAL
	_held_command_timer.timeout.connect(_on_held_command_timeout)
	add_child(_held_command_timer)
	_effect_slots = ClassicPartyEffects.build_slots(_effects_grid)
	_effect_frame_timer = Timer.new()
	_effect_frame_timer.wait_time = 0.12
	_effect_frame_timer.autostart = true
	_effect_frame_timer.timeout.connect(_advance_effect_frame)
	add_child(_effect_frame_timer)
	_music_dialog = MUSIC_PLAYLIST_DIALOG_SCRIPT.new()
	add_child(_music_dialog)
	_music_dialog.music_enabled_changed.connect(func(enabled: bool) -> void: music_enabled_changed.emit(enabled))
	_music_dialog.music_volume_changed.connect(func(value: float) -> void: music_volume_changed.emit(value))
	_music_dialog.playlist_mode_changed.connect(func(playlist_id: int, mode: int) -> void: music_playlist_mode_changed.emit(playlist_id, mode))
	_router.start_requested.connect(func(path: String, seed: int) -> void: start_package_requested.emit(path, seed))
	_router.cancel_package_requested.connect(func() -> void: cancel_package_requested.emit())
	_router.refresh_requested.connect(func() -> void: refresh_campaigns_requested.emit())
	_router.intent_submitted.connect(func(intent: PlayerIntent) -> void: intent_submitted.emit(intent))
	_router.vault_archive_requested.connect(func(character_id: String) -> void: vault_archive_requested.emit(character_id))
	_router.vault_restore_requested.connect(func(character_id: String, revision_hash: String) -> void: vault_restore_requested.emit(character_id, revision_hash))
	_router.presentation_sound_requested.connect(func(sound_id: int, wait_for_completion: bool, stop_existing: bool, reduced_sound_eligible: bool) -> void: presentation_sound_requested.emit(sound_id, wait_for_completion, stop_existing, reduced_sound_eligible))
	_router.standalone_character_creation_requested.connect(func() -> void: standalone_character_creation_requested.emit())
	_router.standalone_character_creation_cancelled.connect(func() -> void: standalone_character_creation_cancelled.emit())
	_router.screen_changed.connect(_on_screen_changed)
	_router.system_action_requested.connect(_on_system_action_requested)
	_router.presentation_setting_changed.connect(_on_presentation_setting_changed)
	_party_roster.character_selected.connect(_on_character_selected)
	_party_roster.character_activated.connect(_on_character_activated)
	_party_roster.combat_auto_changed.connect(_on_combat_auto_changed)
	_party_roster.character_selection_completed.connect(func(character_ids: Array[String]) -> void: character_selection_completed.emit(character_ids))
	_party_roster.combat_spell_cast_requested.connect(func(option: InteractionRequestValue.CastOption) -> void: combat_spell_cast_requested.emit(option))
	_party_roster.combat_spellbook_back_requested.connect(func() -> void: combat_spellbook_back_requested.emit())
	_smoke_action.pressed.connect(_on_smoke_pressed)
	resized.connect(_apply_layout)
	_build_menus()
	set_status("Choose a validated Realmz campaign")
	_apply_layout()


func _on_tree_node_added(node: Node) -> void:
	if node is ScrollContainer:
		ClassicScrollArrowController.bind(node as ScrollContainer, SCROLL_ARROW_STEP, SCROLL_ARROW_INITIAL_DELAY, SCROLL_ARROW_REPEAT_INTERVAL)


static func configure_scroll_container(scroll: ScrollContainer) -> void:
	ClassicScrollArrowController.configure(scroll, SCROLL_ARROW_STEP)


static func scrollbar_arrow_direction(bar: ScrollBar, position: Vector2, vertical: bool) -> int:
	return ClassicScrollArrowController.arrow_direction(bar, position, vertical)


func present(game_view: GameView) -> void:
	var previous_view := _current_view
	var previous_campaign_id := _current_view.campaign_id if _current_view != null and _current_view.session_started else ""
	var contextual_service_closed := _current_view != null and _current_view.pending_interaction != null and _current_view.pending_interaction.kind in [InteractionRequest.SHOP, InteractionRequest.TEMPLE, InteractionRequest.BANK] and game_view != null and game_view.pending_interaction == null
	var ordinary_exploration_update: bool = previous_view != null and game_view != null and game_view.domain_revisions.is_ordinary_exploration_update_from(previous_view.domain_revisions)
	var ordinary_party_update: bool = ordinary_exploration_update and game_view.domain_revisions.party != previous_view.domain_revisions.party
	_current_view = game_view
	if ordinary_exploration_update:
		_present_ordinary_exploration_shell(game_view, ordinary_party_update)
		return
	if not _held_command.is_empty() and (game_view == null or game_view.pending_interaction != null or not game_view.availability(_held_command).enabled):
		_stop_held_command()
	if game_view == null or not game_view.session_started:
		_latest_classic_text = ""
		_package_status.text = "No campaign"
		_clock_label.text = "Day —"
		_gold_label.text = "Gold —"
		_coordinates_label.text = "Map —"
		_fatigue_label.text = "Fatigue —"
		_fatigue_bar.value = 4.0
		_fatigue_bar.tooltip_text = "No active party fatigue."
		_light_label.text = "Light —"
		_effects_panel.visible = false
		_refresh_effect_slots()
		_party_roster.present(game_view)
		_router.present(game_view)
		_set_play_regions_visible(false)
		_build_menus()
		_update_command_availability()
		return
	if previous_campaign_id != game_view.campaign_id:
		_latest_classic_text = ""
	_clock_label.text = "Day %d • %02d:%02d" % [game_view.realmz_day, game_view.realmz_hour, game_view.realmz_minute]
	_gold_label.text = "Gold %d" % game_view.pooled_gold
	_coordinates_label.text = location_fact_text(game_view)
	_fatigue_label.text = "Fatigue %d" % game_view.party_fatigue
	_fatigue_bar.value = game_view.party_fatigue
	_fatigue_bar.tooltip_text = "Fatigue %d / 135" % game_view.party_fatigue
	_light_label.text = "Light %d" % game_view.party_summary.light_remaining if game_view.party_summary != null else "Light —"
	_refresh_effect_slots()
	_apply_exploration_mode()
	_package_status.text = game_view.campaign_summary.title if game_view.campaign_summary != null else game_view.campaign_id
	if not game_view.party_members.any(func(character: CharacterView) -> bool: return character.id == _selected_character_id):
		_on_character_selected(game_view.party_members[0].id if not game_view.party_members.is_empty() else "")
	# Party setup owns its six-slot assembly pane and covers the persistent
	# gameplay roster. Rebuilding that hidden roster after every import added a
	# second set of rows and portrait work with no visible result.
	if not game_view.party_setup_available:
		_party_roster.present(game_view, _selected_character_id)
	_router.present(game_view)
	var play_regions_visible := not _router.full_stage_overlay_visible()
	_set_play_regions_visible(play_regions_visible)
	var automatic_route := automatic_workflow_route(_router.current_screen(), game_view, contextual_service_closed)
	if automatic_route != _router.current_screen():
		_router.open_screen(automatic_route, false)
	_build_menus()
	_rebuild_command_deck()


func _present_ordinary_exploration_shell(game_view: GameView, party_update: bool = false) -> void:
	_clock_label.text = "Day %d • %02d:%02d" % [game_view.realmz_day, game_view.realmz_hour, game_view.realmz_minute]
	_coordinates_label.text = location_fact_text(game_view)
	_fatigue_label.text = "Fatigue %d" % game_view.party_fatigue
	_fatigue_bar.value = game_view.party_fatigue
	_fatigue_bar.tooltip_text = "Fatigue %d / 135" % game_view.party_fatigue
	_light_label.text = "Light %d" % game_view.party_summary.light_remaining if game_view.party_summary != null else "Light —"
	_refresh_effect_slots()
	if party_update:
		var affected_character_ids: Array[String] = game_view.change_set.affected_character_ids()
		if not affected_character_ids.is_empty():
			_party_roster.present_ordinary_exploration(game_view, _selected_character_id, affected_character_ids)
		_update_command_availability()


static func location_fact_text(game_view: GameView) -> String:
	if game_view == null or not game_view.session_started:
		return "Map —"
	var coordinates := "?,?" if game_view.map_view != null and game_view.map_view.coordinates_hidden else "%d,%d" % [game_view.party_coordinate.x, game_view.party_coordinate.y]
	var compass := ""
	if game_view.map_view != null and game_view.map_view.level_type == &"dungeon" and game_view.map_view.compass_enabled:
		compass = " • Compass %s" % ["N", "E", "S", "W"][clampi(game_view.map_view.dungeon_heading, 1, 4) - 1]
	return "%s • %s%s" % [game_view.party_map_id, coordinates, compass]


func set_save_previews(previews: Array[SaveSlotPreview]) -> void:
	_router.set_save_previews(previews)


func show_save_and_quit_workspace() -> void:
	_router.set_save_and_quit_mode(true)
	_router.open_screen(&"system")


func set_save_and_quit_mode(enabled: bool) -> void:
	_router.set_save_and_quit_mode(enabled)


func show_activity_indicator(kind: StringName) -> void:
	match kind:
		&"save":
			_activity_icon.texture = _save_status_texture
			_activity_indicator.tooltip_text = "Adventure saved"
		&"journal":
			_activity_icon.texture = _journal_status_texture
			_activity_indicator.tooltip_text = "Added to Journal"
		_:
			return
	_activity_icon.custom_minimum_size = _activity_icon.texture.get_size()
	if _activity_tween != null and _activity_tween.is_valid():
		_activity_tween.kill()
	_activity_indicator.modulate = Color.WHITE
	_activity_indicator.visible = true
	_activity_tween = create_tween()
	_activity_tween.tween_interval(1.15)
	_activity_tween.tween_property(_activity_indicator, "modulate:a", 0.0, 0.35)
	_activity_tween.tween_callback(func() -> void: _activity_indicator.visible = false)


func present_step(step: SessionStep) -> void:
	if step == null:
		return
	if step.state == SessionStep.State.FAILED:
		set_status("Action failed • %s" % step.error_message, true)
		_append_narrative("Action failed: %s" % step.error_message)
		return
	_picture_stage.visible = false; _field_time_playback.present(self, _clock_label, step.events)
	for event: DomainEvent in step.events:
		_present_event(event)


func latest_classic_text() -> String:
	return _latest_classic_text


func narrative_region() -> Rect2:
	if _narrative_well == null or not _narrative_well.is_inside_tree():
		return Rect2()
	var local_origin := get_global_transform().affine_inverse() * _narrative_well.global_position
	return Rect2(local_origin, _narrative_well.size)


func present_character_selection(request: InteractionRequest) -> void:
	_party_roster.present_character_selection(request)


func present_combat_spellbook(actor_id: String, options: Array[InteractionRequestValue.CastOption]) -> void:
	_party_roster.present_combat_spellbook(actor_id, options)
	_apply_layout()


func close_combat_spellbook() -> void:
	_party_roster.close_combat_spellbook()
	_apply_layout()


static func automatic_workflow_route(current_route: StringName, game_view: GameView, contextual_service_closed: bool = false) -> StringName:
	if game_view == null:
		return current_route
	if game_view.pending_interaction != null and game_view.pending_interaction.kind in [InteractionRequest.SHOP, InteractionRequest.TEMPLE, InteractionRequest.BANK]:
		return &"services"
	if game_view.combat_view != null:
		return &"combat"
	if game_view.pending_interaction != null:
		return &"exploration"
	if contextual_service_closed and current_route == &"services":
		return &"exploration"
	if game_view.combat_view == null and current_route == &"combat":
		return &"exploration"
	return current_route


func set_package_media(media: ClassicMediaCatalog) -> void:
	if _media == media:
		return
	_media = media
	_effect_texture_cache.clear()
	_party_roster.set_media_catalog(media)
	_router.set_media_catalog(media)
	_refresh_effect_slots()


func present_media_events(events: Array[DomainEvent], media: ClassicMediaCatalog) -> void:
	set_package_media(media)
	if media == null:
		return
	for event: DomainEvent in events:
		if event.kind == &"character_effect_requested":
			_party_roster.play_character_effect(String(event.payload.get("characterId", "")), int(event.payload.get("firstResourceId", 0)), int(event.payload.get("frameCount", 0)))
			continue
		if event.kind != &"picture_requested":
			continue
		var picture_id := int(event.payload.get("pictureId", 0))
		var asset := media.asset_by_resource("PICT", picture_id)
		if asset == null:
			last_picture_media_diagnostic = media.resolution_diagnostic("PICT", picture_id, "classic-picture")
			_picture.texture = null
			_picture.tooltip_text = "Scenario picture unavailable"
			_picture_caption.text = ""
			_picture_stage.visible = true
			continue
		var image := _decode_image(asset, media.read_bytes(asset))
		last_picture_media_diagnostic = media.resolution_diagnostic("PICT", picture_id, "classic-picture", "decoded" if image != null else "decode-failed")
		_picture.texture = ImageTexture.create_from_image(image) if image != null else null
		_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_picture.tooltip_text = "Scenario picture" if image != null else "Scenario picture unavailable"
		_picture_caption.text = ""
		_picture_stage.visible = true


func apply_settings(settings: PresentationSettings) -> void:
	if settings == null:
		return
	_presentation_settings = settings
	var base_theme := load("res://src/presentation/classic_ui_theme.tres") as Theme
	theme = ClassicTypography.themed_copy(base_theme, settings)
	_narrative.add_theme_font_size_override("normal_font_size", int(round(17.0 * settings.text_scale)))
	_router.set_presentation_settings(settings)
	if _music_dialog != null and _music_dialog.visible:
		_music_dialog.open(settings, _music_playlist_id, _music_title, _music_playing)
	_apply_layout()


func presentation_settings() -> PresentationSettings:
	return _presentation_settings


func set_music_playback_state(playlist_id: int, title: String, playing: bool) -> void:
	_music_playlist_id = playlist_id
	_music_title = title
	_music_playing = playing
	if _music_dialog != null:
		_music_dialog.set_playback_state(playlist_id, title, playing)
	_build_menus()


func accepts_exploration_input() -> bool:
	return (_music_dialog == null or not _music_dialog.visible) and _router.accepts_exploration_input()


func handle_back() -> bool:
	if _music_dialog != null and _music_dialog.visible:
		_music_dialog.close()
		return true
	if _router.current_screen() == &"exploration" and _current_view != null and _current_view.session_started:
		_router.open_screen(&"system")
		return true
	var handled := _router.handle_back()
	if handled:
		var play_regions_visible := _current_view != null and _current_view.session_started and not _router.full_stage_overlay_visible()
		_set_play_regions_visible(play_regions_visible)
	return handled


func handle_route_shortcut(event: InputEvent) -> bool:
	for definition: Dictionary in UiRouteCatalog.ROUTES:
		var shortcut := StringName(definition["shortcut"])
		if not shortcut.is_empty() and event.is_action_pressed(shortcut):
			if not route_change_reason(_current_view).is_empty():
				return true
			_router.open_screen(StringName(definition["id"]))
			return true
	return false


func selected_fast_spell(slot_index: int) -> Dictionary:
	if _current_view == null or slot_index < 0 or slot_index >= 10:
		return {}
	var character: CharacterView = null
	for candidate: CharacterView in _current_view.party_members:
		if candidate.id == _selected_character_id:
			character = candidate
			break
	if character == null and not _current_view.party_members.is_empty():
		character = _current_view.party_members[0]
	if character == null or slot_index >= character.fast_spells.size():
		return {}
	var binding := character.fast_spells[slot_index]
	return {
		"characterId": character.id,
		"characterName": character.name,
		"slot": slot_index,
		"spellId": binding.spell_id,
		"spellName": binding.spell_name,
		"power": binding.power,
		"enabled": binding.activation.enabled,
		"reason": binding.activation.reason,
	}


static func route_change_reason(game_view: GameView) -> String:
	if game_view == null or not game_view.session_started:
		return "Choose a campaign first."
	if game_view.party_setup_available:
		return "Begin the adventure first."
	if game_view != null and game_view.pending_interaction != null:
		return "Resolve the current interaction first."
	if game_view.combat_view != null and game_view.combat_view.outcome == &"active":
		return "Finish the current battle first."
	return ""


func set_status(text: String, is_error: bool = false) -> void:
	_status_label.text = text
	_status_label.modulate = ERROR if is_error else TEXT
	_router.present_party_setup_status(text, is_error)


func set_campaigns(campaigns: Array[CampaignPackageView]) -> void:
	_router.set_campaigns(campaigns)


func set_package_operation(status: RefCounted) -> void:
	_router.set_package_operation(status)


func set_vault_revisions(revisions: Array[CharacterVaultRevisionView]) -> void:
	_router.set_vault_revisions(revisions)


func set_standalone_character_creation_available(enabled: bool, reason: String = "") -> void:
	_router.set_standalone_character_creation_available(enabled, reason)


func begin_standalone_character_creation() -> void:
	_router.begin_standalone_character_creation()


func finish_standalone_character_creation() -> void:
	_router.finish_standalone_character_creation()


func show_campaign_selection(load_after_selection: bool = false) -> void:
	_router.show_campaign_selection(load_after_selection)
	_set_play_regions_visible(false)
	_build_menus()


func show_vault_from_splash() -> void:
	_router.show_vault_from_splash()
	_set_play_regions_visible(false)
	_build_menus()


func show_splash() -> void:
	_router.show_splash()
	_set_play_regions_visible(false)
	_build_menus()


func _apply_layout() -> void:
	if not is_node_ready():
		return
	# The root Control can differ from the viewport's logical size when a gallery,
	# embedded window, or stretch transform supplies the final presentation area.
	# Lay out siblings in their shared Control coordinate space.
	var window_size := size
	_profile = UiLayoutProfile.for_viewport(window_size, _presentation_settings.ui_scale_mode)
	var canvas_rect := _profile.application_rect
	var viewport_size := canvas_rect.size
	var origin := canvas_rect.position
	_menu_row.visible = _profile.id != UiLayoutProfile.COMPACT
	_compact_menu.visible = _profile.id == UiLayoutProfile.COMPACT
	# Classic typography can require more height than the historical 28-pixel
	# menu. Keep every play region below the menu's actual themed minimum.
	_profile.menu_height = maxf(_profile.menu_height, ceilf(_menu_strip.get_combined_minimum_size().y))
	var stage_width := maxf(320.0, viewport_size.x - _profile.party_width)
	var stage_height := maxf(220.0, viewport_size.y - _profile.menu_height - _profile.bottom_height)
	var stage_rect := Rect2(0.0, _profile.menu_height, stage_width, stage_height)
	_menu_strip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_menu_strip.position = origin
	_menu_strip.size = Vector2(viewport_size.x, _profile.menu_height)
	stage_rect.position += origin
	_stage_frame.position = stage_rect.position
	_stage_frame.size = stage_rect.size
	_activity_indicator.position = stage_rect.position + Vector2(10.0, 10.0)
	_activity_indicator.size = Vector2(40.0, 40.0)
	var roster_width := combat_spellbook_roster_width(viewport_size.x, _profile.party_width, _profile.ui_scale, _party_roster.combat_spellbook_active())
	var footer_width := exploration_footer_width(viewport_size, _profile, _router.current_screen())
	_party_roster.position = origin + Vector2(viewport_size.x - roster_width, _profile.menu_height)
	_party_roster.size = Vector2(roster_width, party_roster_height(viewport_size.y, _profile.menu_height, stage_height, _party_roster.combat_spellbook_active()))
	_party_roster.z_index = party_roster_z_index(_party_roster.combat_spellbook_active())
	_bottom_row.vertical = false
	_facts.columns = 3 if _profile.id == UiLayoutProfile.COMPACT else 6
	var command_width := minf(_profile.command_width, viewport_size.x * 0.26)
	_world_command_panel.visible = _profile.id != UiLayoutProfile.COMPACT
	_apply_exploration_mode()
	var side_command_width := maxf(300.0 * _profile.ui_scale, command_width)
	_world_command_panel.custom_minimum_size.x = side_command_width if _world_command_panel.visible else 0.0
	_world_command_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _world_command_panel.visible else Control.SIZE_SHRINK_BEGIN
	_world_command_panel.size_flags_stretch_ratio = 1.0
	_command_panel.visible = _router.current_screen() != &"spells"
	_effects_panel.visible = _command_panel.visible and _current_view != null and _current_view.session_started
	_command_panel.custom_minimum_size.x = side_command_width if _world_command_panel.visible else command_width
	_command_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _world_command_panel.visible else Control.SIZE_SHRINK_END
	_command_panel.size_flags_stretch_ratio = 1.0
	_command_panel.custom_minimum_size.y = 0.0
	_narrative_well.custom_minimum_size.x = minf(620.0 * _profile.ui_scale, maxf(360.0, footer_width - _world_command_panel.custom_minimum_size.x - _command_panel.custom_minimum_size.x - 12.0)) if _world_command_panel.visible else maxf(360.0, footer_width - (command_width if _command_panel.visible else 0.0) - 12.0)
	_narrative_well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_narrative_well.size_flags_stretch_ratio = 1.45 if _world_command_panel.visible else 1.0
	_world_command_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_party_effects_row.vertical = not _world_command_panel.visible
	_party_effects_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_party_command_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_world_command_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_world_command_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_command_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_command_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_world_command_grid.columns = 4
	_command_grid.columns = 2 if _world_command_panel.visible else maxi(2, floori(command_width / (108.0 if _profile.bitmap_scale == 2 else 58.0)))
	var effect_icon_size := party_effect_icon_size(_profile.bitmap_scale)
	var effect_slot_size := party_effect_slot_size(_profile.bitmap_scale)
	for icon: TextureRect in _effect_slots:
		icon.custom_minimum_size = Vector2(effect_icon_size, effect_icon_size)
		(icon.get_parent().get_parent() as Control).custom_minimum_size = Vector2(effect_slot_size, effect_slot_size)
	# Orientation and child minima must settle before shrinking the outer panel;
	# otherwise Control retains the previous wider profile's minimum-clamped size.
	_bottom_region.position = origin + Vector2(0.0, viewport_size.y - _profile.bottom_height)
	_bottom_region.size = Vector2(footer_width, _profile.bottom_height)
	var picture_size := Vector2(minf(560.0 * _profile.ui_scale, stage_rect.size.x - 48.0), minf(360.0 * _profile.ui_scale, stage_rect.size.y - 48.0))
	_picture_stage.position = stage_rect.position + (stage_rect.size - picture_size) * 0.5
	_picture_stage.size = picture_size
	_router.set_layout_profile(_profile, viewport_size, origin)
	_build_menus()
	_rebuild_command_deck()
	layout_changed.emit(Rect2(stage_rect.position, Vector2(combat_spellbook_stage_width(stage_rect.size.x, viewport_size.x, roster_width), stage_rect.size.y)), _profile)


static func party_effect_icon_size(bitmap_scale: int) -> float:
	return ClassicPartyEffects.icon_size(bitmap_scale)


static func party_effect_slot_size(bitmap_scale: int) -> float:
	return ClassicPartyEffects.slot_size(bitmap_scale)


func _advance_effect_frame() -> void:
	_effect_frame_index = (_effect_frame_index + 1) % PARTY_EFFECT_FRAME_COUNT
	_refresh_effect_slots()


func _refresh_effect_slots() -> void:
	var values: Array[int] = []
	if _current_view != null and _current_view.party_summary != null:
		values = _current_view.party_summary.condition_values
	for slot_index: int in _effect_slots.size():
		var active := values.size() > slot_index + 1 and values[slot_index + 1] != 0
		var texture := _party_effect_texture(slot_index + 1, _effect_frame_index) if active else null
		_effect_slots[slot_index].texture = texture
		_effect_slots[slot_index].modulate = Color.WHITE if active else Color(0.35, 0.35, 0.35, 0.35)


func _party_effect_texture(condition_index: int, frame_index: int) -> Texture2D:
	return ClassicPartyEffects.texture(_media, _effect_texture_cache, condition_index, frame_index)


static func party_effect_resource_id(condition_index: int, frame_index: int) -> int:
	return ClassicPartyEffects.resource_id(condition_index, frame_index)


static func party_roster_height(viewport_height: float, menu_height: float, stage_height: float, combat_spellbook_active: bool) -> float:
	return viewport_height - menu_height if combat_spellbook_active else stage_height


static func party_roster_z_index(combat_spellbook_active: bool) -> int:
	return 81 if combat_spellbook_active else 14


static func combat_spellbook_roster_width(viewport_width: float, party_width: float, ui_scale: float, combat_spellbook_active: bool) -> float:
	return maxf(party_width, minf(352.0 * ui_scale, viewport_width - 320.0 * ui_scale)) if combat_spellbook_active else party_width


static func combat_spellbook_stage_width(stage_width: float, viewport_width: float, roster_width: float) -> float:
	return minf(stage_width, viewport_width - roster_width)


static func exploration_footer_width(viewport_size: Vector2, profile: UiLayoutProfile, route_id: StringName) -> float:
	return ClassicScreenRouter.spell_workspace_rect_for(profile, viewport_size).position.x if route_id == &"spells" else viewport_size.x


func _apply_exploration_mode() -> void:
	if not is_node_ready():
		return
	_world_command_panel.theme_type_variation = &"ClassicSharedStone"
	_command_panel.theme_type_variation = &"ClassicSharedStone"


func _build_menus() -> void:
	if not is_node_ready():
		return
	var contextual_definition := _presentation_command_definition(ClassicCommandCatalog.command(&"contextual"))
	var contextual_label := String(contextual_definition.get("label", "Encounter"))
	var contextual_availability := StringName(contextual_definition.get("availability", &"contextual_encounter"))
	_fill_menu($MenuStrip/MenuRow/InfoMenu, [
		{"label": "About Realmz Rebuilt", "route": &"system"},
		{"label": "Package identity and readiness", "route": &"system"},
		{"label": "Diagnostics", "route": &"system"},
	])
	_fill_menu($MenuStrip/MenuRow/GameMenu, [
		{"label": "Campaigns…", "system": &"campaigns", "disabled_reason": _campaign_library_reason()},
		{"label": "Save & Load…", "route": &"system", "disabled_reason": _save_reason()}, {"label": "Quick Save 1", "system": &"save", "value": "quick", "disabled_reason": _save_reason()}, {"label": "Quick Save 2", "system": &"save", "value": "quick-2", "disabled_reason": _save_reason()},
		{"label": "Quick Load 1", "system": &"load", "value": "quick", "disabled_reason": _load_reason()}, {"label": "Quick Load 2", "system": &"load", "value": "quick-2", "disabled_reason": _load_reason()},
		{"label": "Main Menu…", "system": &"end_adventure", "disabled_reason": _end_adventure_reason()},
		{"label": "Quit", "system": &"quit"},
	])
	_fill_menu($MenuStrip/MenuRow/AdventureMenu, [
		{"label": "Explore", "route": &"exploration"},
		{"label": "Search", "command": &"search_mode", "disabled_reason": _availability_reason(&"toggle_search")},
		{"label": "Area Search", "command": &"area_search", "disabled_reason": _availability_reason(&"area_search")},
		{"label": "Torch", "command": &"torch", "disabled_reason": _availability_reason(&"use_torch")},
		{"label": "Camp", "command": &"camp", "disabled_reason": _availability_reason(&"camp")},
		{"label": "Rest", "command": &"rest", "disabled_reason": _availability_reason(&"rest")},
		{"label": "Heal", "command": &"heal", "disabled_reason": _availability_reason(&"heal")},
		{"label": contextual_label, "command": &"contextual", "disabled_reason": _availability_reason(contextual_availability)},
		{"label": "Money", "command": &"money", "disabled_reason": _availability_reason(&"money_action")},
	])
	_fill_menu($MenuStrip/MenuRow/CharacterMenu, [
		{"label": "Party Order", "route": &"character"},
		{"label": "Character Sheets", "route": &"character"},
		{"label": "Inventory", "route": &"inventory"},
		{"label": "Spells", "route": &"spells"},
		{"label": "Vault", "route": &"vault"},
	])
	_fill_menu($MenuStrip/MenuRow/AlliesMenu, [
		{"label": "Current Allies", "route": &"allies", "disabled_reason": _allies_reason()},
		{"label": "Bestiary", "route": &"bestiary"},
	])
	_fill_menu($MenuStrip/MenuRow/MapsMenu, [
		{"label": "Maps and Notes", "route": &"journal"},
		{"label": "Acquired Maps", "route": &"journal"},
	])
	_fill_menu($MenuStrip/MenuRow/PreferencesMenu, [
		{"label": "Display, Audio, and Access", "route": &"system"},
		{"label": "Save, Load, and Package Diagnostics", "route": &"system"},
	])
	_fill_menu($MenuStrip/MenuRow/MusicMenu, [
		{"label": "Now Playing: %s" % (_music_title if _music_playing else "Nothing"), "disabled_reason": "Current music title"},
		{"label": "Stop Music" if _presentation_settings.music_enabled else "Play Music", "system": &"music_toggle"},
		{"label": "Playlist…", "system": &"music_playlist"},
	])
	var compact_entries: Array[Dictionary] = [
		{"label": "Adventure — Explore", "route": &"exploration"},
		{"label": "Adventure — Search", "command": &"search_mode", "disabled_reason": _availability_reason(&"toggle_search")},
		{"label": "Adventure — Area Search", "command": &"area_search", "disabled_reason": _availability_reason(&"area_search")},
		{"label": "Adventure — Torch", "command": &"torch", "disabled_reason": _availability_reason(&"use_torch")},
		{"label": "Adventure — Camp", "command": &"camp", "disabled_reason": _availability_reason(&"camp")},
		{"label": "Adventure — Rest", "command": &"rest", "disabled_reason": _availability_reason(&"rest")},
		{"label": "Adventure — Heal", "command": &"heal", "disabled_reason": _availability_reason(&"heal")},
		{"label": "Adventure — %s" % contextual_label, "command": &"contextual", "disabled_reason": _availability_reason(contextual_availability)},
		{"label": "Adventure — Money", "command": &"money", "disabled_reason": _availability_reason(&"money_action")},
		{"label": "Character — Party Order", "route": &"character"},
		{"label": "Character — Character Sheets", "route": &"character"},
		{"label": "Character — Inventory", "route": &"inventory"},
		{"label": "Character — Spells", "route": &"spells"},
		{"label": "Character — Vault", "route": &"vault"},
		{"label": "Allies — Current Allies", "route": &"allies", "disabled_reason": _allies_reason()},
		{"label": "Allies — Bestiary", "route": &"bestiary"},
		{"label": "Maps / Notes", "route": &"journal"},
		{"label": "Game — Save & Load…", "route": &"system", "disabled_reason": _save_reason()}, {"label": "Game — Quick Save 1", "system": &"save", "value": "quick", "disabled_reason": _save_reason()}, {"label": "Game — Quick Save 2", "system": &"save", "value": "quick-2", "disabled_reason": _save_reason()},
		{"label": "Game — Quick Load 1", "system": &"load", "value": "quick", "disabled_reason": _load_reason()}, {"label": "Game — Quick Load 2", "system": &"load", "value": "quick-2", "disabled_reason": _load_reason()},
		{"label": "Game — Main Menu", "system": &"end_adventure", "disabled_reason": _end_adventure_reason()},
		{"label": "Game — Campaigns", "system": &"campaigns", "disabled_reason": _campaign_library_reason()},
		{"label": "Preferences", "route": &"system"},
		{"label": "Music — %s" % ("Stop" if _presentation_settings.music_enabled else "Play"), "system": &"music_toggle"},
		{"label": "Music — Playlist…", "system": &"music_playlist"},
		{"label": "Info / Diagnostics", "route": &"system"},
		{"label": "Quit", "system": &"quit"},
	]
	_fill_menu(_compact_menu, compact_entries)


func _fill_menu(menu: MenuButton, entries: Array[Dictionary]) -> void:
	var popup := menu.get_popup()
	popup.clear()
	var actions: Dictionary = {}
	var enabled_count := 0
	for index: int in entries.size():
		var entry := entries[index]
		popup.add_item(String(entry["label"]), index)
		var reason := String(entry.get("disabled_reason", ""))
		if reason.is_empty() and entry.has("route"):
			reason = route_change_reason(_current_view)
		if not reason.is_empty():
			entry["disabled_reason"] = reason
		actions[index] = entry
		if not reason.is_empty():
			popup.set_item_disabled(index, true)
			popup.set_item_tooltip(index, reason)
		else:
			enabled_count += 1
	_menu_actions[menu.get_instance_id()] = actions
	menu.disabled = enabled_count == 0
	if not _menus_connected.has(menu.get_instance_id()):
		popup.id_pressed.connect(_on_menu_item_pressed.bind(menu))
		_menus_connected[menu.get_instance_id()] = true


func _on_menu_item_pressed(item_id: int, menu: MenuButton) -> void:
	var entry: Dictionary = _menu_actions.get(menu.get_instance_id(), {}).get(item_id, {})
	if entry.is_empty() or not String(entry.get("disabled_reason", "")).is_empty():
		return
	if entry.has("route"):
		_router.open_screen(StringName(entry["route"]))
	elif entry.has("command"):
		_activate_command(StringName(entry["command"]))
	elif entry.has("system"):
		_on_system_action_requested(StringName(entry["system"]), entry.get("value"))


func _rebuild_command_deck() -> void:
	if not is_node_ready() or _profile == null:
		return
	for grid: GridContainer in [_world_command_grid, _command_grid]:
		for child: Node in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	_simulation_buttons.clear()
	# The typed interaction presenter owns encounter actions. Keep the route's
	# ordinary footer deck visible (and disabled where necessary) underneath a
	# blocking interaction instead of replacing Party commands with a second,
	# empty encounter command surface.
	var context := _router.current_screen()
	for definition: Dictionary in ClassicCommandCatalog.for_context(context):
		definition = _presentation_command_definition(definition)
		var button: BaseButton
		if bool(definition.get("search_animation", false)):
			var search_button := SEARCH_BUTTON_SCRIPT.new() as BaseButton
			search_button.command_requested.connect(_activate_command)
			search_button.set_meta("search_animation", true)
			button = search_button
		elif bool(definition.get("torch_meter", false)):
			var torch_button := TORCH_BUTTON_SCRIPT.new() as BaseButton
			torch_button.command_requested.connect(_activate_command)
			torch_button.set_meta("torch_meter", true)
			button = torch_button
		else:
			var bitmap := ClassicBitmapButton.new()
			bitmap.configure(definition, _profile.bitmap_scale)
			if bool(definition.get("hold_repeat", false)):
				bitmap.button_down.connect(_begin_held_command.bind(StringName(definition["id"])))
				bitmap.button_up.connect(_on_held_command_button_up)
			else:
				bitmap.command_requested.connect(_activate_command)
			button = bitmap
		button.set_meta("focus_key", "command:%s" % definition["id"])
		var group := StringName(definition.get("group", &"party"))
		var target_grid := _world_command_grid if group == &"world" and _world_command_panel.visible else _command_grid
		target_grid.add_child(button)
		_simulation_buttons[StringName(definition["id"])] = button
	_update_command_availability()


func _update_command_availability() -> void:
	for command_id: StringName in _simulation_buttons:
		var button := _simulation_buttons[command_id] as BaseButton
		var definition := _presentation_command_definition(ClassicCommandCatalog.command(command_id))
		var availability_id := StringName(definition.get("availability", &""))
		var reason := ""
		if _current_view == null or not _current_view.session_started:
			reason = "Begin a campaign first."
		elif _current_view.pending_interaction != null and not String(command_id).begins_with("encounter_"):
			reason = "Resolve the current interaction first."
		elif String(command_id).begins_with("encounter_"):
			reason = "Choose from the active encounter response controls."
		elif not availability_id.is_empty():
			reason = _availability_reason(availability_id)
		if bool(button.get_meta("search_animation", false)):
			var summary := _current_view.party_summary if _current_view != null else null
			button.call("sync_status",
				false if summary == null else summary.searching,
				reason.is_empty(),
				reason
			)
		elif bool(button.get_meta("torch_meter", false)):
			var summary := _current_view.party_summary if _current_view != null else null
			button.call("sync_status",
				0 if summary == null else summary.light_remaining,
				false if summary == null else summary.has_classic_torch,
				reason.is_empty(),
				reason
			)
		else:
			button.disabled = not reason.is_empty()
			button.tooltip_text = reason if not reason.is_empty() else "Break camp" if command_id == &"camp" and _current_view.party_summary != null and _current_view.party_summary.camping else String(definition.get("tooltip", ""))
			if button is ClassicBitmapButton:
				(button as ClassicBitmapButton).set_visual_pressed(_command_is_visually_pressed(command_id))
		button.queue_redraw()


func _command_is_visually_pressed(command_id: StringName) -> bool:
	var party_summary := _current_view.party_summary if _current_view != null else null
	if command_id == &"camp":
		return party_summary != null and party_summary.camping
	if command_id == _held_command:
		return true
	return command_route(command_id) == _router.current_screen()


static func command_route(command_id: StringName) -> StringName:
	return {
		&"money": &"services",
		&"inventory": &"inventory",
		&"spells": &"spells",
		&"maps": &"journal",
		&"settings": &"system",
	}.get(command_id, &"")


func _activate_command(command_id: StringName, held_repeat: bool = false) -> void:
	var start_sound_id := command_activation_sound_id(command_id, held_repeat)
	if start_sound_id > 0:
		presentation_sound_requested.emit(start_sound_id, false, false, false)
	match command_id:
		&"search_mode": intent_submitted.emit(PlayerIntent.toggle_search())
		&"area_search": intent_submitted.emit(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
		&"torch": intent_submitted.emit(PlayerIntent.use_torch())
		&"camp": intent_submitted.emit(PlayerIntent.camp())
		&"rest": intent_submitted.emit(PlayerIntent.rest())
		&"heal": intent_submitted.emit(PlayerIntent.heal())
		&"contextual":
			var service := _contextual_service()
			if service != null and not service.actions.is_empty():
				intent_submitted.emit(PlayerIntent.service_action(service.service_id, service.actions[0]))
			else:
				intent_submitted.emit(PlayerIntent.contextual_encounter())
		&"money": _router.open_screen(&"services")
		&"inventory": _router.open_screen(&"inventory")
		&"spells": _router.open_screen(&"spells")
		&"maps": _router.open_screen(&"journal")
		&"settings": _router.open_screen(&"system")
		&"save": save_requested.emit("quick")


func _presentation_command_definition(definition: Dictionary) -> Dictionary:
	var result := definition.duplicate()
	var command_id := StringName(definition.get("id", &""))
	if command_id == &"search_mode" and _current_view != null and _current_view.party_summary != null and _current_view.party_summary.searching:
		result["label"] = "Stop Search"
		result["tooltip"] = "Stop continuous secret searching"
		return result
	if command_id != &"contextual":
		return result
	var service := _contextual_service()
	if service == null:
		return result
	result["label"] = service.title
	result["tooltip"] = "Enter %s" % service.title
	result["availability"] = &"service_action"
	if service.service_kind == &"temple":
		result["asset_id"] = &"command.temple"
		result["art_region"] = [9, 2, 37, 34]
		result.erase("art_mask")
	elif service.service_kind == &"shop":
		result["asset_id"] = &""
		result["asset_path"] = "res://src/presentation/assets/ui/commands/shop.png"
		result.erase("art_region")
		result.erase("art_mask")
	else:
		result["asset_id"] = &""
		result.erase("art_region")
		result.erase("art_mask")
	return result


func _contextual_service() -> ServiceView:
	if _current_view == null:
		return null
	for service: ServiceView in _current_view.services:
		if service.service_kind in [&"shop", &"temple"] and not service.actions.is_empty():
			return service
	return null


func _begin_held_command(command_id: StringName) -> void:
	_held_command = command_id
	_activate_command(command_id)
	if not _held_command.is_empty():
		_held_command_timer.start()


static func command_activation_sound_id(command_id: StringName, held_repeat: bool) -> int:
	if held_repeat:
		return 0
	if command_id == &"contextual":
		return CONTEXTUAL_CONTROL_SOUND_ID
	return int(HELD_COMMAND_START_SOUND_IDS.get(command_id, 0))


func _stop_held_command() -> void:
	_held_command = &""
	if _held_command_timer != null:
		_held_command_timer.stop()
	_update_command_availability()


func _on_held_command_button_up() -> void:
	# A synchronous pulse may replace the footer while the pointer is still held.
	# Godot releases the removed BaseButton, but that is not a mouse release.
	if should_stop_held_command_on_button_up(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		_stop_held_command()


static func should_stop_held_command_on_button_up(left_mouse_pressed: bool) -> bool:
	return not left_mouse_pressed


func release_held_commands() -> void:
	_stop_held_command()


func _on_held_command_timeout() -> void:
	if _held_command.is_empty():
		_stop_held_command()
		return
	if _current_view == null or _current_view.pending_interaction != null or not _current_view.availability(_held_command).enabled:
		_stop_held_command()
		return
	if _field_time_playback.is_active(): return
	_activate_command(_held_command, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_stop_held_command()


func _on_screen_changed(screen_id: StringName) -> void:
	var play_regions_visible := _current_view != null and _current_view.session_started and not _router.full_stage_overlay_visible()
	_set_play_regions_visible(play_regions_visible)
	_apply_layout()
	set_status(String(screen_id).replace("_", " ").capitalize())
	_build_menus()
	_rebuild_command_deck()
	route_changed.emit(screen_id)


func _set_play_regions_visible(visible: bool) -> void:
	var play_route := visible and _router.current_screen() in [&"exploration", &"combat", &"spells"]
	_stage_frame.visible = play_route
	_bottom_region.visible = play_route and _router.current_screen() in [&"exploration", &"spells"]
	_party_roster.visible = play_route
	play_stage_visibility_changed.emit(play_route)


func _on_system_action_requested(action_id: StringName, value: Variant) -> void:
	match action_id:
		&"save": save_requested.emit("quick" if value == null else String(value))
		&"save_and_quit": save_and_quit_requested.emit("quick" if value == null else String(value))
		&"load": load_requested.emit("quick" if value == null else String(value))
		&"load_backup": load_backup_requested.emit("quick" if value == null else String(value))
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
		&"window_mode": window_mode_changed.emit(String(value))
		&"reduced_motion": reduced_motion_changed.emit(bool(value))
		&"reduced_sound": reduced_sound_changed.emit(bool(value))
		&"auto_switch_to_melee": auto_switch_to_melee_changed.emit(bool(value))
		&"exploration_speed_percent": exploration_speed_changed.emit(int(value))
		&"combat_playback_speed_percent": combat_playback_speed_changed.emit(int(value))
		&"show_exploration_minimap": exploration_minimap_changed.emit(bool(value))
		&"classic_exploration_visibility": classic_exploration_visibility_changed.emit(bool(value))
		&"autojournal_enabled": autojournal_changed.emit(bool(value))


func _on_character_selected(character_id: String) -> void:
	_selected_character_id = character_id
	_router.select_character(character_id)


func _on_character_activated(character_id: String) -> void:
	_on_character_selected(character_id)
	if _router.current_screen() == &"inventory" and _router.select_inventory_character(character_id):
		return
	_router.open_screen(&"character")


func _on_combat_auto_changed(character_id: String, enabled: bool) -> void:
	if _current_view == null or _current_view.combat_view == null or _current_view.combat_view.outcome != &"active":
		return
	intent_submitted.emit(PlayerIntent.set_combat_auto(character_id, enabled))


func _on_smoke_pressed() -> void:
	_smoke_action.release_focus()
	if _current_view == null or not _current_view.session_started:
		set_status("MCP input verified • no package loaded")
		return
	intent_submitted.emit(PlayerIntent.new(PlayerIntent.Kind.SEARCH))


func _present_event(event: DomainEvent) -> void:
	match event.kind:
		&"message_shown":
			var text := String(event.payload.get("text", "Message"))
			_latest_classic_text = text
			_append_narrative(text)
			set_status("Continue when ready" if bool(event.payload.get("classicClick", false)) else text)
		&"party_created":
			set_status("Party created • the adventure begins")
			_append_narrative("The party enters the realm.")
		&"party_moved": set_status("%s • %d,%d" % [_current_view.party_map_id if _current_view != null else "Map", int(event.payload.get("x", 0)), int(event.payload.get("y", 0))])
		&"movement_blocked": set_status("That way is blocked")
		&"search_completed": _append_narrative("The party searches the area.")
		&"camp_mode_changed":
			_append_narrative("The party makes camp." if bool(event.payload.get("camping", false)) else "The party breaks camp.")
		&"character_age_changed":
			var direction := int(event.payload.get("transition", 0))
			var age_group := int(event.payload.get("ageGroup", 0))
			var age_name := CharacterView._age_group_name(age_group)
			var text := "%s has grown into the %s age group." % [event.payload.get("characterName", "A party member"), age_name] if direction > 0 else "%s has returned to the %s age group." % [event.payload.get("characterName", "A party member"), age_name]
			set_status(text)
			_append_narrative(text)
		&"door_opened": _append_narrative("A door opens.")
		&"secret_discovered": _append_narrative("A secret is revealed.")
		&"battle_started": _append_narrative("Battle begins.")
		&"battle_completed": _append_narrative("Battle completed • %s" % event.payload.get("outcome", "resolved"))


func _append_narrative(text: String) -> void:
	if _narrative.text.is_empty() or _narrative.text == "Choose a validated Realmz campaign to begin.":
		_narrative.text = text
	else:
		_narrative.append_text("\n\n%s" % text)
	_narrative.scroll_to_line(_narrative.get_line_count())


func _availability_reason(action_id: StringName) -> String:
	if _current_view == null or not _current_view.session_started:
		return "Begin a campaign first."
	var availability := _current_view.availability(action_id)
	return "" if availability.enabled else availability.reason


func _session_reason() -> String:
	if _current_view == null or not _current_view.session_started:
		return "Choose a campaign first."
	if _current_view.party_setup_available:
		return "Begin the adventure first."
	return ""


func _save_reason() -> String:
	var session_reason := _session_reason()
	if not session_reason.is_empty():
		return session_reason
	if _current_view.combat_view != null and _current_view.combat_view.outcome == &"active":
		return "Saving is unavailable during battle."
	return ""


func _load_reason() -> String:
	var session_reason := _session_reason()
	if not session_reason.is_empty():
		return session_reason
	if _current_view.pending_interaction != null:
		return "Resolve the current interaction first."
	if _current_view.combat_view != null and _current_view.combat_view.outcome == &"active":
		return "Loading is unavailable during battle."
	return ""


func _campaign_library_reason() -> String:
	if _current_view == null or not _current_view.session_started:
		return ""
	return "Return to the Main Menu before choosing another campaign."


func _allies_reason() -> String:
	var reason := route_change_reason(_current_view)
	if not reason.is_empty():
		return reason
	if _current_view.party_allies.is_empty():
		return "No allies are currently traveling with the party."
	return ""


func _end_adventure_reason() -> String:
	if _current_view == null or not _current_view.session_started:
		return "Choose a campaign first."
	if _current_view.pending_interaction != null and _current_view.pending_interaction.kind != InteractionRequest.COMBAT:
		return "Resolve the current interaction first."
	return ""


func _decode_image(asset: MediaAsset, bytes: PackedByteArray) -> Image:
	if bytes.is_empty():
		return null
	var image := Image.new()
	var extension := asset.path.get_extension().to_lower()
	var error := ERR_UNAVAILABLE
	if asset.mime_type.to_lower() == "image/png" or extension == "png":
		error = image.load_png_from_buffer(bytes)
	elif asset.mime_type.to_lower() in ["image/jpeg", "image/jpg"] or extension in ["jpg", "jpeg"]:
		error = image.load_jpg_from_buffer(bytes)
	elif asset.mime_type.to_lower() == "image/webp" or extension == "webp":
		error = image.load_webp_from_buffer(bytes)
	return image if error == OK else null
