class_name ClassicApplicationShell
extends ClassicShellPresenter

const MUTED := Color("9aa0a8")

@onready var _status_label: Label = %Status
@onready var _clock_label: Label = %Clock
@onready var _gold_label: Label = %Gold
@onready var _chronicle: RichTextLabel = %Chronicle
@onready var _scenario_text: Label = %ScenarioText
@onready var _router: ClassicScreenRouter = %ScreenRouter
@onready var _smoke_action: Button = %SmokeAction

var _current_view: GameView
var _presentation_settings: PresentationSettings = PresentationSettings.new()
var _media: PackageMediaCatalog


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_party_list = %PartyList
	_picture = %Picture
	_picture_caption = %PictureCaption
	_router.start_requested.connect(_on_start_requested)
	_router.refresh_requested.connect(func() -> void: refresh_campaigns_requested.emit())
	_router.intent_submitted.connect(_on_intent_submitted)
	_router.screen_changed.connect(_on_screen_changed)
	_smoke_action.pressed.connect(_on_smoke_pressed)
	$BottomBar/CommandRow/Search.pressed.connect(func() -> void: intent_submitted.emit(PlayerIntent.new(PlayerIntent.Kind.SEARCH)))
	$BottomBar/CommandRow/Camp.pressed.connect(func() -> void: intent_submitted.emit(PlayerIntent.camp()))
	$BottomBar/CommandRow/Character.pressed.connect(func() -> void: _router.open_screen(&"character"))
	$BottomBar/CommandRow/Inventory.pressed.connect(func() -> void: _router.open_screen(&"inventory"))
	$BottomBar/CommandRow/Spells.pressed.connect(func() -> void: _router.open_screen(&"spells"))
	$BottomBar/CommandRow/Save.pressed.connect(func() -> void: save_requested.emit("quick"))
	$BottomBar/CommandRow/Load.pressed.connect(func() -> void: load_requested.emit("quick"))
	$BottomBar/CommandRow/Settings.pressed.connect(func() -> void: _router.open_screen(&"system"))
	$BottomBar/CommandRow/Campaigns.pressed.connect(show_campaign_selection)
	set_status("Choose a validated Realmz campaign")


func present(game_view: GameView) -> void:
	_current_view = game_view
	if game_view == null or not game_view.session_started:
		_clock_label.text = "No active session"
		_gold_label.text = "Gold —"
		_clear_party()
		_router.present(game_view)
		return
	_clock_label.text = "Day %d • %02d:00" % [game_view.realmz_day, game_view.realmz_hour]
	_gold_label.text = "Gold %d" % game_view.pooled_gold
	_rebuild_party()
	_router.present(game_view)


func present_step(step: SessionStep) -> void:
	if step == null:
		return
	if step.state == SessionStep.State.FAILED:
		set_status("Action failed • %s" % step.error_message, true)
		_append_chronicle("Error: %s" % step.error_message)
		return
	for event: DomainEvent in step.events:
		_present_event(event)


func present_media_events(events: Array[DomainEvent], media: PackageMediaCatalog) -> void:
	_media = media
	if media == null:
		return
	for event: DomainEvent in events:
		if event.kind != &"picture_requested":
			continue
		var picture_id := int(event.payload.get("pictureId", 0))
		var asset := media.picture_by_resource_id(picture_id)
		if asset == null:
			_picture.texture = null
			_picture_caption.text = "Picture %d" % picture_id
			continue
		var image := _decode_image(asset, media.read_bytes(asset))
		_picture.texture = ImageTexture.create_from_image(image) if image != null else null
		_picture_caption.text = asset.label


func apply_settings(settings: PresentationSettings) -> void:
	if settings == null:
		return
	_presentation_settings = settings
	var shell_theme := Theme.new()
	shell_theme.default_font_size = int(round(15.0 * settings.text_scale))
	theme = shell_theme


func accepts_exploration_input() -> bool:
	return _router.accepts_exploration_input()


func set_status(text: String, is_error: bool = false) -> void:
	_status_label.text = text
	_status_label.modulate = Color("e88782") if is_error else Color("d8d9d5")


func set_campaigns(campaigns: Array[PackageDiscoveryResult]) -> void:
	_router.set_campaigns(campaigns)


func set_vault_records(records: Array[CharacterVaultRecord]) -> void:
	_router.set_vault_records(records)


func show_campaign_selection() -> void:
	_router.show_campaign_selection()


func _on_start_requested(package_path: String, seed: int) -> void:
	start_package_requested.emit(package_path, seed)


func _on_intent_submitted(intent: PlayerIntent) -> void:
	intent_submitted.emit(intent)


func _on_screen_changed(screen_id: StringName) -> void:
	_status_label.text = "Realmz • %s" % String(screen_id).capitalize()


func _on_smoke_pressed() -> void:
	_smoke_action.release_focus()
	if _current_view == null or not _current_view.session_started:
		set_status("MCP input verified • no package loaded")
		return
	intent_submitted.emit(PlayerIntent.new(PlayerIntent.Kind.SEARCH))


func _rebuild_party() -> void:
	_clear_party()
	if _current_view == null:
		return
	for character: CharacterView in _current_view.party_members:
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s\nHP %d/%d • SP %d/%d" % [character.name, character.current_health, character.maximum_health, character.spell_points, character.maximum_spell_points]
		button.tooltip_text = "Level %d • %s" % [character.level, character.caste_id]
		button.pressed.connect(_open_character.bind(character))
		_party_list.add_child(button)


func _clear_party() -> void:
	for child: Node in _party_list.get_children():
		child.queue_free()


func _open_character(character: CharacterView) -> void:
	_router.open_screen(&"character")
	set_status("Character • %s" % character.name)


func _present_event(event: DomainEvent) -> void:
	match event.kind:
		&"message_shown":
			var text := String(event.payload.get("text", "Message"))
			_scenario_text.text = text
			set_status("Scenario text • continue when ready" if bool(event.payload.get("classicClick", false)) else text)
			_append_chronicle(text)
		&"party_created":
			set_status("Party created • the adventure begins")
			_append_chronicle("The party enters the realm.")
		&"party_moved":
			set_status("%s • %d,%d" % [_current_view.party_map_id if _current_view != null else "Map", int(event.payload.get("x", 0)), int(event.payload.get("y", 0))])
		&"movement_blocked":
			set_status("That way is blocked")
		&"search_completed":
			_append_chronicle("The party searches the area.")
		&"party_camped":
			_append_chronicle("The party camps and recovers.")
		&"door_opened":
			_append_chronicle("A door opens.")
		&"secret_discovered":
			_append_chronicle("A secret is revealed.")
		&"battle_started":
			_append_chronicle("Battle begins.")
		&"battle_completed":
			_append_chronicle("Battle completed • %s" % event.payload.get("outcome", "resolved"))
		_:
			pass


func _append_chronicle(text: String) -> void:
	_chronicle.append_text("• %s\n" % text)
	_chronicle.scroll_to_line(_chronicle.get_line_count())


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
