class_name ClassicApplicationShell
extends Control

signal start_package_requested(path: String, seed: int)
signal refresh_campaigns_requested
signal intent_submitted(intent: PlayerIntent)
signal save_requested(slot_id: String)
signal load_requested(slot_id: String)
signal quit_requested
signal topology_debug_changed(enabled: bool)
signal dungeon_3d_changed(enabled: bool)
signal master_volume_changed(value: float)
signal text_scale_changed(value: float)
signal ui_scale_mode_changed(value: String)
signal window_mode_changed(value: String)
signal reduced_motion_changed(enabled: bool)
signal layout_changed(workspace_rect: Rect2, profile: UiLayoutProfile)
signal route_changed(route_id: StringName)

const MUTED := Color("9aa4a5")
const ERROR := Color("ef7770")
const TEXT := Color("d8d9d2")

@onready var _menu_strip: PanelContainer = %MenuStrip
@onready var _menu_row: HBoxContainer = %MenuRow
@onready var _compact_menu: MenuButton = %CompactMenu
@onready var _package_status: Label = %PackageStatus
@onready var _stage_frame: NinePatchRect = %StageFrame
@onready var _picture_stage: PanelContainer = %PictureStage
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
@onready var _clock_label: Label = %Clock
@onready var _gold_label: Label = %Gold
@onready var _command_panel: PanelContainer = %CommandPanel
@onready var _command_grid: GridContainer = %CommandGrid
@onready var _router: ClassicScreenRouter = %ScreenRouter
@onready var _smoke_action: Button = %SmokeAction

var _current_view: GameView
var _presentation_settings := PresentationSettings.new()
var _profile: UiLayoutProfile
var _media: PackageMediaCatalog
var _selected_character_id: String = ""
var _latest_classic_text: String = ""
var _simulation_buttons: Dictionary = {}
var _menu_actions: Dictionary = {}
var _menus_connected: Dictionary = {}


func _ready() -> void:
	# The shell is structural; only its concrete controls should participate in
	# GUI hit testing. A full-window PASS control masks earlier root siblings.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_router.start_requested.connect(func(path: String, seed: int) -> void: start_package_requested.emit(path, seed))
	_router.refresh_requested.connect(func() -> void: refresh_campaigns_requested.emit())
	_router.intent_submitted.connect(func(intent: PlayerIntent) -> void: intent_submitted.emit(intent))
	_router.screen_changed.connect(_on_screen_changed)
	_router.system_action_requested.connect(_on_system_action_requested)
	_router.presentation_setting_changed.connect(_on_presentation_setting_changed)
	_party_roster.character_selected.connect(_on_character_selected)
	_smoke_action.pressed.connect(_on_smoke_pressed)
	resized.connect(_apply_layout)
	_build_menus()
	set_status("Choose a validated Realmz campaign")
	_apply_layout()


func present(game_view: GameView) -> void:
	var previous_campaign_id := _current_view.campaign_id if _current_view != null and _current_view.session_started else ""
	_current_view = game_view
	if game_view == null or not game_view.session_started:
		_latest_classic_text = ""
		_package_status.text = "No campaign"
		_clock_label.text = "Day —"
		_gold_label.text = "Gold —"
		_coordinates_label.text = "Map —"
		_fatigue_label.text = "Fatigue —"
		_party_roster.present(game_view)
		_router.present(game_view)
		_stage_frame.visible = false
		_bottom_region.visible = false
		_update_command_availability()
		return
	if previous_campaign_id != game_view.campaign_id:
		_latest_classic_text = ""
	_clock_label.text = "Day %d • %02d:00" % [game_view.realmz_day, game_view.realmz_hour]
	_gold_label.text = "Gold %d" % game_view.pooled_gold
	_coordinates_label.text = "%s • %d,%d" % [game_view.party_map_id, game_view.party_coordinate.x, game_view.party_coordinate.y]
	_fatigue_label.text = "Fatigue %d" % game_view.party_fatigue
	_package_status.text = game_view.campaign_summary.title if game_view.campaign_summary != null else game_view.campaign_id
	if _selected_character_id.is_empty() and not game_view.party_members.is_empty():
		_selected_character_id = game_view.party_members[0].id
	_party_roster.present(game_view, _selected_character_id)
	_router.present(game_view)
	var play_regions_visible := not _router.full_stage_overlay_visible()
	_stage_frame.visible = play_regions_visible
	_bottom_region.visible = play_regions_visible
	if game_view.combat_view != null and _router.current_screen() == &"exploration":
		_router.open_screen(&"combat")
	elif game_view.pending_interaction != null and game_view.pending_interaction.kind in [InteractionRequest.SHOP, InteractionRequest.TEMPLE, InteractionRequest.BANK] and _router.current_screen() == &"exploration":
		_router.open_screen(&"services")
	_build_menus()
	_rebuild_command_deck()


func present_step(step: SessionStep) -> void:
	if step == null:
		return
	if step.state == SessionStep.State.FAILED:
		set_status("Action failed • %s" % step.error_message, true)
		_append_narrative("Action failed: %s" % step.error_message)
		return
	_picture_stage.visible = false
	for event: DomainEvent in step.events:
		_present_event(event)


func latest_classic_text() -> String:
	return _latest_classic_text


func set_package_media(media: PackageMediaCatalog) -> void:
	_media = media
	_party_roster.set_media_catalog(media)
	_router.set_media_catalog(media)


func present_media_events(events: Array[DomainEvent], media: PackageMediaCatalog) -> void:
	set_package_media(media)
	if media == null:
		return
	for event: DomainEvent in events:
		if event.kind != &"picture_requested":
			continue
		var picture_id := int(event.payload.get("pictureId", 0))
		var asset := media.asset_by_resource("PICT", picture_id)
		if asset == null:
			_picture.texture = null
			_picture_caption.text = "PICT %d unavailable" % picture_id
			_picture_stage.visible = true
			continue
		var image := _decode_image(asset, media.read_bytes(asset))
		_picture.texture = ImageTexture.create_from_image(image) if image != null else null
		_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_picture_caption.text = asset.label
		_picture_stage.visible = true


func apply_settings(settings: PresentationSettings) -> void:
	if settings == null:
		return
	_presentation_settings = settings
	var base_theme: Theme = load("res://src/presentation/classic_ui_theme.tres")
	var shell_theme := base_theme.duplicate(true) as Theme
	shell_theme.default_font_size = int(round(15.0 * settings.text_scale))
	theme = shell_theme
	_narrative.add_theme_font_size_override("normal_font_size", int(round(18.0 * settings.text_scale)))
	_router.set_presentation_settings(settings)
	_apply_layout()


func accepts_exploration_input() -> bool:
	return not _picture_stage.visible and _router.accepts_exploration_input()


func handle_back() -> bool:
	if _picture_stage.visible:
		_picture_stage.visible = false
		return true
	var handled := _router.handle_back()
	if handled:
		var play_regions_visible := _current_view != null and _current_view.session_started and not _router.full_stage_overlay_visible()
		_stage_frame.visible = play_regions_visible
		_bottom_region.visible = play_regions_visible
	return handled


func handle_route_shortcut(event: InputEvent) -> bool:
	for definition: Dictionary in UiRouteCatalog.ROUTES:
		if event.is_action_pressed(StringName(definition["shortcut"])):
			_router.open_screen(StringName(definition["id"]))
			return true
	return false


func set_status(text: String, is_error: bool = false) -> void:
	_status_label.text = text
	_status_label.modulate = ERROR if is_error else TEXT


func set_campaigns(campaigns: Array[PackageDiscoveryResult]) -> void:
	_router.set_campaigns(campaigns)


func set_vault_records(records: Array[CharacterVaultRecord]) -> void:
	_router.set_vault_records(records)


func show_campaign_selection() -> void:
	_router.show_campaign_selection()
	_stage_frame.visible = false
	_bottom_region.visible = false


func _apply_layout() -> void:
	if not is_node_ready():
		return
	# The root Control can differ from the viewport's logical size when a gallery,
	# embedded window, or stretch transform supplies the final presentation area.
	# Lay out siblings in their shared Control coordinate space.
	var viewport_size := size
	_profile = UiLayoutProfile.for_viewport(viewport_size, _presentation_settings.ui_scale_mode)
	var stage_width := maxf(320.0, viewport_size.x - _profile.party_width)
	var stage_height := maxf(220.0, viewport_size.y - _profile.menu_height - _profile.bottom_height)
	var stage_rect := Rect2(0.0, _profile.menu_height, stage_width, stage_height)
	_menu_strip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_menu_strip.position = Vector2.ZERO
	_menu_strip.size = Vector2(viewport_size.x, _profile.menu_height)
	_stage_frame.position = stage_rect.position
	_stage_frame.size = stage_rect.size
	_party_roster.position = Vector2(stage_width, _profile.menu_height)
	_party_roster.size = Vector2(_profile.party_width, viewport_size.y - _profile.menu_height)
	var stacked_bottom := _profile.id == UiLayoutProfile.COMPACT and stage_width < 520.0
	_bottom_row.vertical = stacked_bottom
	_facts.columns = 2 if stacked_bottom else 5
	var command_width := stage_width if stacked_bottom else minf(_profile.command_width, stage_width * (0.46 if _profile.id == UiLayoutProfile.COMPACT else 0.5))
	_command_panel.custom_minimum_size.x = 0.0 if stacked_bottom else command_width
	_command_panel.custom_minimum_size.y = minf(108.0 * _profile.ui_scale, _profile.bottom_height * 0.48) if stacked_bottom else 0.0
	_command_grid.columns = maxi(2, floori(command_width / (108.0 if _profile.bitmap_scale == 2 else 58.0)))
	# Orientation and child minima must settle before shrinking the outer panel;
	# otherwise Control retains the previous wider profile's minimum-clamped size.
	_bottom_region.position = Vector2(0.0, viewport_size.y - _profile.bottom_height)
	_bottom_region.size = Vector2(stage_width, _profile.bottom_height)
	var picture_size := Vector2(minf(560.0 * _profile.ui_scale, stage_rect.size.x - 48.0), minf(360.0 * _profile.ui_scale, stage_rect.size.y - 48.0))
	_picture_stage.position = stage_rect.position + (stage_rect.size - picture_size) * 0.5
	_picture_stage.size = picture_size
	_menu_row.visible = _profile.id != UiLayoutProfile.COMPACT
	_compact_menu.visible = _profile.id == UiLayoutProfile.COMPACT
	_router.set_layout_profile(_profile, viewport_size)
	_build_menus()
	_rebuild_command_deck()
	layout_changed.emit(stage_rect, _profile)


func _build_menus() -> void:
	if not is_node_ready():
		return
	_fill_menu($MenuStrip/MenuRow/InfoMenu, [
		{"label": "About Realmz 2", "route": &"system"},
		{"label": "Package identity and readiness", "route": &"system"},
		{"label": "Diagnostics", "route": &"system"},
	])
	_fill_menu($MenuStrip/MenuRow/GameMenu, [
		{"label": "Campaigns…", "system": &"campaigns"},
		{"label": "Quick Save", "system": &"save", "disabled_reason": _session_reason()},
		{"label": "Quick Load", "system": &"load", "disabled_reason": _session_reason()},
		{"label": "Return to Selection", "system": &"campaigns"},
		{"label": "Quit", "system": &"quit"},
	])
	_fill_menu($MenuStrip/MenuRow/AdventureMenu, [
		{"label": "Explore", "route": &"exploration"},
		{"label": "Search", "command": &"search", "disabled_reason": _availability_reason(&"search")},
		{"label": "Camp", "command": &"camp", "disabled_reason": _availability_reason(&"camp")},
	])
	_fill_menu($MenuStrip/MenuRow/CharacterMenu, [
		{"label": "Characters", "route": &"character"},
		{"label": "Inventory", "route": &"inventory"},
		{"label": "Spells", "route": &"spells"},
		{"label": "Vault", "route": &"vault"},
	])
	_fill_menu($MenuStrip/MenuRow/MapsMenu, [
		{"label": "Maps and Notes", "route": &"journal"},
		{"label": "Acquired Maps", "route": &"journal"},
	])
	_fill_menu($MenuStrip/MenuRow/PreferencesMenu, [
		{"label": "Display, Audio, and Access", "route": &"system"},
		{"label": "Save and Package Diagnostics", "route": &"system"},
	])
	var compact_entries: Array[Dictionary] = [
		{"label": "Adventure — Explore", "route": &"exploration"},
		{"label": "Adventure — Search", "command": &"search", "disabled_reason": _availability_reason(&"search")},
		{"label": "Adventure — Camp", "command": &"camp", "disabled_reason": _availability_reason(&"camp")},
		{"label": "Character — Characters", "route": &"character"},
		{"label": "Character — Inventory", "route": &"inventory"},
		{"label": "Character — Spells", "route": &"spells"},
		{"label": "Character — Vault", "route": &"vault"},
		{"label": "Maps / Notes", "route": &"journal"},
		{"label": "Game — Quick Save", "system": &"save", "disabled_reason": _session_reason()},
		{"label": "Game — Quick Load", "system": &"load", "disabled_reason": _session_reason()},
		{"label": "Game — Campaigns", "system": &"campaigns"},
		{"label": "Preferences", "route": &"system"},
		{"label": "Info / Diagnostics", "route": &"system"},
		{"label": "Quit", "system": &"quit"},
	]
	_fill_menu(_compact_menu, compact_entries)


func _fill_menu(menu: MenuButton, entries: Array[Dictionary]) -> void:
	var popup := menu.get_popup()
	popup.clear()
	var actions: Dictionary = {}
	for index: int in entries.size():
		var entry := entries[index]
		popup.add_item(String(entry["label"]), index)
		actions[index] = entry
		var reason := String(entry.get("disabled_reason", ""))
		if not reason.is_empty():
			popup.set_item_disabled(index, true)
			popup.set_item_tooltip(index, reason)
	_menu_actions[menu.get_instance_id()] = actions
	if not _menus_connected.has(menu.get_instance_id()):
		popup.id_pressed.connect(_on_menu_item_pressed.bind(menu))
		_menus_connected[menu.get_instance_id()] = true


func _on_menu_item_pressed(item_id: int, menu: MenuButton) -> void:
	var entry: Dictionary = _menu_actions.get(menu.get_instance_id(), {}).get(item_id, {})
	if entry.is_empty():
		return
	if entry.has("route"):
		_router.open_screen(StringName(entry["route"]))
	elif entry.has("command"):
		_activate_command(StringName(entry["command"]))
	elif entry.has("system"):
		_on_system_action_requested(StringName(entry["system"]), null)


func _rebuild_command_deck() -> void:
	if not is_node_ready() or _profile == null:
		return
	for child: Node in _command_grid.get_children():
		_command_grid.remove_child(child)
		child.queue_free()
	_simulation_buttons.clear()
	var context := &"encounter" if _current_view != null and _current_view.pending_interaction != null else _router.current_screen()
	for definition: Dictionary in ClassicCommandCatalog.for_context(context):
		var asset_id := StringName(definition.get("asset_id", &""))
		var button: BaseButton
		if not asset_id.is_empty() and ClassicUiAssetCatalog.texture(asset_id) != null:
			var bitmap := ClassicBitmapButton.new()
			bitmap.configure(definition, _profile.bitmap_scale)
			bitmap.command_requested.connect(_activate_command)
			button = bitmap
		else:
			var text_button := Button.new()
			text_button.text = String(definition.get("label", "Command"))
			text_button.custom_minimum_size = Vector2(54.0, 54.0)
			text_button.tooltip_text = String(definition.get("tooltip", ""))
			text_button.pressed.connect(_activate_command.bind(StringName(definition["id"])))
			button = text_button
		button.set_meta("focus_key", "command:%s" % definition["id"])
		_command_grid.add_child(button)
		_simulation_buttons[StringName(definition["id"])] = button
	_update_command_availability()


func _update_command_availability() -> void:
	for command_id: StringName in _simulation_buttons:
		var button := _simulation_buttons[command_id] as BaseButton
		var definition := ClassicCommandCatalog.command(command_id)
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
		button.disabled = not reason.is_empty()
		button.tooltip_text = reason if not reason.is_empty() else String(definition.get("tooltip", ""))
		button.queue_redraw()


func _activate_command(command_id: StringName) -> void:
	match command_id:
		&"search": intent_submitted.emit(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
		&"camp": intent_submitted.emit(PlayerIntent.camp())
		&"inventory": _router.open_screen(&"inventory")
		&"spells": _router.open_screen(&"spells")
		&"maps": _router.open_screen(&"journal")
		&"settings": _router.open_screen(&"system")
		&"save": save_requested.emit("quick")


func _on_screen_changed(screen_id: StringName) -> void:
	var play_regions_visible := _current_view != null and _current_view.session_started
	_stage_frame.visible = play_regions_visible
	_bottom_region.visible = play_regions_visible
	set_status(String(screen_id).replace("_", " ").capitalize())
	_rebuild_command_deck()
	route_changed.emit(screen_id)


func _on_system_action_requested(action_id: StringName, value: Variant) -> void:
	match action_id:
		&"save": save_requested.emit("quick" if value == null else String(value))
		&"load": load_requested.emit("quick" if value == null else String(value))
		&"campaigns": show_campaign_selection()
		&"quit": quit_requested.emit()


func _on_presentation_setting_changed(setting_id: StringName, value: Variant) -> void:
	match setting_id:
		&"topology_debug": topology_debug_changed.emit(bool(value))
		&"dungeon_3d": dungeon_3d_changed.emit(bool(value))
		&"master_volume": master_volume_changed.emit(float(value))
		&"text_scale": text_scale_changed.emit(float(value))
		&"ui_scale_mode": ui_scale_mode_changed.emit(String(value))
		&"window_mode": window_mode_changed.emit(String(value))
		&"reduced_motion": reduced_motion_changed.emit(bool(value))


func _on_character_selected(character_id: String) -> void:
	_selected_character_id = character_id
	_router.open_screen(&"character")


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
		&"party_camped": _append_narrative("The party camps and recovers.")
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
	return "" if _current_view != null and _current_view.session_started else "Begin a campaign first."


func _decode_image(asset: PackageMediaAsset, bytes: PackedByteArray) -> Image:
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
