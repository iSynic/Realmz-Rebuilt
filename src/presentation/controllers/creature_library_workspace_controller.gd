class_name CreatureLibraryWorkspaceController
extends RefCounted

const GOLD := Color("d5b45d")
const MUTED := Color("9aa0a8")
const TEXT := Color("e0e2e5")

var _selected_ally_id: String = ""


func reset() -> void:
	_selected_ally_id = ""


func present_allies(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	if parent == null or view == null:
		return
	if view.party_allies.is_empty():
		_add_empty_state(parent, "No current allies", "Allies gained through the scenario appear here while they travel with the party.", text_scale)
		return
	var selected := _selected_ally(view.party_allies)
	if selected == null:
		selected = view.party_allies[0]
		_selected_ally_id = selected.id
	var columns := HBoxContainer.new()
	columns.name = "AlliesColumns"
	columns.add_theme_constant_override("separation", 10)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(columns)
	var list_panel := PanelContainer.new()
	list_panel.name = "AlliesListPane"
	list_panel.theme_type_variation = &"ClassicInset"
	list_panel.custom_minimum_size.x = 220.0
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_stretch_ratio = 0.85
	columns.add_child(list_panel)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list_panel.add_child(list)
	for ally: MonsterView in view.party_allies:
		var button := Button.new()
		button.text = "%s  •  %d/%d ST" % [ally.name, ally.current_health, ally.maximum_health]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = ally.id == selected.id
		button.pressed.connect(_select_ally.bind(ally.id, parent, view, media, text_scale))
		list.add_child(button)
	var detail_panel := PanelContainer.new()
	detail_panel.name = "AllyDetailPane"
	detail_panel.theme_type_variation = &"ClassicInset"
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_stretch_ratio = 1.35
	columns.add_child(detail_panel)
	_render_ally(detail_panel, selected, media, text_scale)


func _selected_ally(allies: Array[MonsterView]) -> MonsterView:
	for ally: MonsterView in allies:
		if ally.id == _selected_ally_id:
			return ally
	return null


func _select_ally(ally_id: String, parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	_selected_ally_id = ally_id
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
	present_allies(parent, view, media, text_scale)


func _render_ally(parent: PanelContainer, ally: MonsterView, media: ClassicMediaCatalog, text_scale: float) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	parent.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	var icon := TextureRect.new()
	icon.name = "AllyIcon"
	icon.custom_minimum_size = Vector2(64.0, 64.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if media != null and ally.icon_id != 0:
		var asset := media.asset_by_resource(ally.icon_resource_type, ally.icon_id)
		if asset != null:
			icon.texture = media.image_texture(asset)
	icon.tooltip_text = "CICN %d unavailable." % ally.icon_id if icon.texture == null else ally.name
	header.add_child(icon)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(identity)
	_add_label(identity, ally.name, GOLD, 20, text_scale)
	_add_label(identity, "Classic monster %d  •  %d Hit Dice" % [ally.classic_id, ally.hit_dice], MUTED, 13, text_scale)
	var facts := GridContainer.new()
	facts.columns = 2
	facts.add_theme_constant_override("h_separation", 16)
	facts.add_theme_constant_override("v_separation", 4)
	column.add_child(facts)
	_add_fact(facts, "Stamina", "%d / %d" % [ally.current_health, ally.maximum_health], text_scale)
	_add_fact(facts, "Spell Points", "%d / %d" % [ally.spell_points, ally.maximum_spell_points], text_scale)
	_add_fact(facts, "Armor", str(ally.armor), text_scale)
	_add_fact(facts, "Magic Resistance", "%d%%" % ally.magic_resistance, text_scale)
	_add_fact(facts, "Movement", str(ally.movement_maximum), text_scale)
	_add_fact(facts, "Attacks", str(ally.attack_count), text_scale)
	_add_fact(facts, "Weapon", ally.weapon_name, text_scale)
	_add_fact(facts, "Allegiance", "Friendly", text_scale)
	_add_list(column, "Conditions", ally.conditions, "None", text_scale)
	_add_list(column, "Immunities", ally.immunities, "None", text_scale)
	_add_list(column, "Vulnerabilities", ally.vulnerabilities, "None", text_scale)


func _add_fact(parent: GridContainer, label_text: String, value_text: String, text_scale: float) -> void:
	_add_label(parent, label_text, MUTED, 13, text_scale)
	_add_label(parent, value_text, TEXT, 13, text_scale)


func _add_list(parent: VBoxContainer, title: String, values: Array[String], empty_text: String, text_scale: float) -> void:
	_add_label(parent, title, GOLD, 15, text_scale)
	_add_label(parent, empty_text if values.is_empty() else " • ".join(values), TEXT, 13, text_scale)


func _add_empty_state(parent: VBoxContainer, title: String, detail: String, text_scale: float) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	panel.add_child(column)
	_add_label(column, title, GOLD, 18, text_scale)
	_add_label(column, detail, MUTED, 13, text_scale)
	parent.add_child(panel)


func _add_label(parent: Container, value: String, color: Color, size: int, text_scale: float) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * text_scale)))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label
