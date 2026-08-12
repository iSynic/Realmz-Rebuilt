class_name ClassicPartyRoster
extends PanelContainer

signal character_selected(character_id: String)

const MUTED := Color("9da8aa")

@onready var _party_list: VBoxContainer = %PartyList
@onready var _heading: Label = %Heading

var _media: ClassicMediaCatalog
var _selected_character_id: String = ""


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	_media = media


func present(view: GameView, selected_character_id: String = "") -> void:
	_selected_character_id = selected_character_id
	_clear()
	if view == null or not view.session_started:
		_heading.text = "Party"
		_add_empty("No active party")
		return
	_heading.text = "Party • %d / 6" % view.party_members.size()
	for character: CharacterView in view.party_members:
		_add_character(character)
	for index: int in maxi(0, 6 - view.party_members.size()):
		_add_empty("Empty position %d" % (view.party_members.size() + index + 1))


func _add_character(character: CharacterView) -> void:
	var row := Button.new()
	row.custom_minimum_size.y = 58.0
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_theme_constant_override("icon_max_width", 42)
	row.toggle_mode = true
	row.button_pressed = character.id == _selected_character_id
	var condition_text := _condition_summary(character.condition_values)
	var action_fact := "SP %d/%d" % [character.spell_points, character.maximum_spell_points] if character.maximum_spell_points > 0 else "Attacks %d" % character.normal_attacks
	row.text = "%s\n%s / %s  •  Stamina %d/%d\n%s  •  AR %d%s" % [
		character.name,
		character.race_name,
		character.caste_name,
		character.current_health,
		character.maximum_health,
		action_fact,
		character.armor,
		"  •  %s" % condition_text if not condition_text.is_empty() else "",
	]
	row.tooltip_text = "Level %d • Movement %d/%d" % [character.level, character.movement, character.maximum_movement]
	var portrait := _portrait_texture(character.portrait_id)
	if portrait != null:
		row.icon = portrait
	row.pressed.connect(func() -> void:
		_selected_character_id = character.id
		character_selected.emit(character.id)
	)
	_party_list.add_child(row)


func _add_empty(text: String) -> void:
	var label := Label.new()
	label.custom_minimum_size.y = 42.0
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", MUTED)
	_party_list.add_child(label)


func _portrait_texture(asset_id: String) -> Texture2D:
	if _media == null or asset_id.is_empty():
		return null
	var asset := _media.asset_by_id(asset_id)
	if asset == null or not asset.is_picture():
		return null
	var bytes := _media.read_bytes(asset)
	var image := Image.new()
	var error := ERR_UNAVAILABLE
	match asset.path.get_extension().to_lower():
		"png": error = image.load_png_from_buffer(bytes)
		"jpg", "jpeg": error = image.load_jpg_from_buffer(bytes)
		"webp": error = image.load_webp_from_buffer(bytes)
	return ImageTexture.create_from_image(image) if error == OK else null


func _condition_summary(values: Array[int]) -> String:
	var active: Array[String] = []
	for index: int in values.size():
		if values[index] != 0:
			active.append("Condition %d" % (index + 1))
		if active.size() == 2:
			break
	return ", ".join(active)


func _clear() -> void:
	for child: Node in _party_list.get_children():
		_party_list.remove_child(child)
		child.queue_free()
