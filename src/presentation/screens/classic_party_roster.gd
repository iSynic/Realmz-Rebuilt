class_name ClassicPartyRoster
extends PanelContainer

signal character_selected(character_id: String)
signal combat_auto_changed(character_id: String, enabled: bool)

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
	var combat_active := view.combat_view != null and view.combat_view.outcome == &"active"
	var auto_character_ids: Array[String] = []
	if combat_active:
		auto_character_ids.assign(view.combat_view.auto_character_ids)
	for character: CharacterView in view.party_members:
		_add_character(character, combat_active, auto_character_ids)
	for index: int in maxi(0, 6 - view.party_members.size()):
		_add_empty("Empty position %d" % (view.party_members.size() + index + 1))


func _add_character(character: CharacterView, combat_active: bool, auto_character_ids: Array[String]) -> void:
	var row_container := HBoxContainer.new()
	row_container.custom_minimum_size.y = 58.0
	row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_container.add_theme_constant_override("separation", 3)
	var row := Button.new()
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
	row_container.add_child(row)
	if combat_active:
		var auto_toggle := CheckButton.new()
		auto_toggle.name = "CombatAuto"
		auto_toggle.text = "Auto"
		auto_toggle.custom_minimum_size.x = 52.0
		var auto_available := character.current_health > 0 and not character.traitor
		auto_toggle.disabled = not auto_available
		auto_toggle.tooltip_text = "Persistent Auto for this character's next combat activation." if auto_available else "Persistent Auto requires a living loyal party character."
		auto_toggle.button_pressed = auto_character_ids.has(character.id)
		auto_toggle.toggled.connect(func(enabled: bool) -> void: combat_auto_changed.emit(character.id, enabled))
		row_container.add_child(auto_toggle)
	_party_list.add_child(row_container)


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
	return _media.image_texture(asset)


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
