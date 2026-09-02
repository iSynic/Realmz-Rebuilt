class_name CreatureLibraryWorkspaceController
extends RefCounted

const GOLD := Color("d5b45d")
const MUTED := Color("9aa0a8")
const TEXT := Color("e0e2e5")

var _selected_ally_id: String = ""
var _selected_bestiary_id: String = ""
var _layout_profile: StringName = UiLayoutProfile.WIDE


func reset() -> void:
	_selected_ally_id = ""
	_selected_bestiary_id = ""


func set_layout_profile(profile_id: StringName) -> void:
	_layout_profile = profile_id


func present_allies(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	if parent == null or view == null:
		return
	if view.party_allies.is_empty():
		_add_empty_state(parent, "No current allies", "No allies are currently with the party.", text_scale)
		return
	var selected := _selected_ally(view.party_allies)
	if selected == null:
		selected = view.party_allies[0]
		_selected_ally_id = selected.id
	var compact := _layout_profile == UiLayoutProfile.COMPACT
	var columns := BoxContainer.new()
	columns.name = "AlliesColumns"
	columns.vertical = compact
	columns.add_theme_constant_override("separation", 10)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(columns)
	var list_panel := PanelContainer.new()
	list_panel.name = "AlliesListPane"
	list_panel.theme_type_variation = &"ClassicInset"
	list_panel.custom_minimum_size = Vector2(248.0, 150.0 if compact else 0.0)
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_stretch_ratio = 0.72
	columns.add_child(list_panel)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list_panel.add_child(list)
	_add_label(list, "Current Allies  •  %d" % view.party_allies.size(), GOLD, 16, text_scale)
	for ally: MonsterView in view.party_allies:
		var button := Button.new()
		button.name = "AllyRow_%s" % ally.id.validate_node_name()
		button.text = "%s\n%d/%d ST  •  %d HD" % [ally.name, ally.current_health, ally.maximum_health, ally.hit_dice]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = ally.id == selected.id
		button.custom_minimum_size.y = 54.0
		button.icon = _ally_icon_texture(ally, media)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.expand_icon = true
		button.tooltip_text = "Inspect %s" % ally.name
		button.pressed.connect(_select_ally.bind(ally.id, parent, view, media, text_scale))
		list.add_child(button)
	var detail_panel := PanelContainer.new()
	detail_panel.name = "AllyDetailPane"
	detail_panel.theme_type_variation = &"ClassicInset"
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_stretch_ratio = 1.78
	columns.add_child(detail_panel)
	_render_ally(detail_panel, selected, media, text_scale, compact)


func present_bestiary(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	if parent == null or view == null:
		return
	if view.bestiary_entries.is_empty():
		_add_empty_state(parent, "Bestiary unavailable", "This package has no menu-visible monster records.", text_scale)
		return
	var selected := _selected_bestiary(view.bestiary_entries)
	if selected == null:
		selected = view.bestiary_entries[0]
		_selected_bestiary_id = selected.definition_id
	var compact := _layout_profile == UiLayoutProfile.COMPACT
	var columns := BoxContainer.new()
	columns.name = "BestiaryColumns"
	columns.vertical = compact
	columns.add_theme_constant_override("separation", 10)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(columns)
	var list_panel := PanelContainer.new()
	list_panel.name = "BestiaryListPane"
	list_panel.theme_type_variation = &"ClassicInset"
	list_panel.custom_minimum_size = Vector2(248.0, 150.0 if compact else 0.0)
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_stretch_ratio = 0.72
	columns.add_child(list_panel)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list_panel.add_child(list)
	_add_label(list, "Bestiary  •  %d" % view.bestiary_entries.size(), GOLD, 16, text_scale)
	for entry: MonsterCatalogEntryView in view.bestiary_entries:
		var button := Button.new()
		button.name = "BestiaryRow_%s" % entry.definition_id.validate_node_name()
		button.text = "%s\n%d HD  •  AC %d" % [entry.name, entry.hit_dice, entry.armor]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = entry.definition_id == selected.definition_id
		button.custom_minimum_size.y = 54.0
		button.icon = _catalog_icon_texture(entry, media)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.expand_icon = true
		button.tooltip_text = "Inspect %s" % entry.name
		button.pressed.connect(_select_bestiary.bind(entry.definition_id, parent, view, media, text_scale))
		list.add_child(button)
	var detail_panel := PanelContainer.new()
	detail_panel.name = "BestiaryDetailPane"
	detail_panel.theme_type_variation = &"ClassicInset"
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_stretch_ratio = 1.78
	columns.add_child(detail_panel)
	_render_bestiary(detail_panel, selected, media, text_scale, compact)


func _selected_ally(allies: Array[MonsterView]) -> MonsterView:
	for ally: MonsterView in allies:
		if ally.id == _selected_ally_id:
			return ally
	return null


func _selected_bestiary(entries: Array[MonsterCatalogEntryView]) -> MonsterCatalogEntryView:
	for entry: MonsterCatalogEntryView in entries:
		if entry.definition_id == _selected_bestiary_id:
			return entry
	return null


func _select_ally(ally_id: String, parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	_selected_ally_id = ally_id
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
	present_allies(parent, view, media, text_scale)


func _select_bestiary(definition_id: String, parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	_selected_bestiary_id = definition_id
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
	present_bestiary(parent, view, media, text_scale)


func _render_ally(parent: PanelContainer, ally: MonsterView, media: ClassicMediaCatalog, text_scale: float, compact: bool) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	var icon := TextureRect.new()
	icon.name = "AllyIcon"
	icon.custom_minimum_size = Vector2(80.0, 80.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = _ally_icon_texture(ally, media)
	icon.tooltip_text = "CICN %d unavailable." % ally.icon_id if icon.texture == null else ally.name
	header.add_child(icon)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(identity)
	_add_label(identity, ally.name, GOLD, 20, text_scale)
	_add_label(identity, "Classic monster %d" % ally.classic_id, MUTED, 13, text_scale)
	_add_label(identity, "%d Hit Dice" % ally.hit_dice, TEXT, 13, text_scale)
	column.add_child(HSeparator.new())
	var facts := GridContainer.new()
	facts.columns = 2 if compact else 4
	facts.add_theme_constant_override("h_separation", 16)
	facts.add_theme_constant_override("v_separation", 4)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(facts)
	_add_fact(facts, "Stamina", "%d / %d" % [ally.current_health, ally.maximum_health], text_scale)
	_add_fact(facts, "Spell Points", "%d / %d" % [ally.spell_points, ally.maximum_spell_points], text_scale)
	_add_fact(facts, "Armor", str(ally.armor), text_scale)
	_add_fact(facts, "Magic Resistance", "%d%%" % ally.magic_resistance, text_scale)
	_add_fact(facts, "Movement", str(ally.movement_maximum), text_scale)
	_add_fact(facts, "Attacks", str(ally.attack_count), text_scale)
	_add_fact(facts, "Weapon", ally.weapon_name, text_scale)
	_add_fact(facts, "Helpless", "Yes" if ally.helpless else "No", text_scale)
	var states := BoxContainer.new()
	states.name = "AllyStateCards"
	states.vertical = compact
	states.add_theme_constant_override("separation", 6)
	states.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(states)
	_add_state_card(states, "Conditions", ally.conditions, "None", text_scale)
	_add_state_card(states, "Immunities", ally.immunities, "None", text_scale)
	_add_state_card(states, "Vulnerabilities", ally.vulnerabilities, "None", text_scale)


func _render_bestiary(parent: PanelContainer, entry: MonsterCatalogEntryView, media: ClassicMediaCatalog, text_scale: float, compact: bool) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	var icon := TextureRect.new()
	icon.name = "BestiaryIcon"
	icon.custom_minimum_size = Vector2(80.0, 80.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = _catalog_icon_texture(entry, media)
	icon.tooltip_text = "CICN %d unavailable." % entry.icon_id if icon.texture == null else entry.name
	header.add_child(icon)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(identity)
	_add_label(identity, entry.name, GOLD, 20, text_scale)
	_add_label(identity, "Classic monster %d  •  name %d" % [entry.classic_id, entry.classic_name_id], MUTED, 13, text_scale)
	_add_label(identity, "%d Hit Dice" % entry.hit_dice, TEXT, 13, text_scale)
	column.add_child(HSeparator.new())
	_add_label(column, entry.description if not entry.description.is_empty() else "No description supplied.", TEXT, 13, text_scale)
	var facts := GridContainer.new()
	facts.columns = 2 if compact else 4
	facts.add_theme_constant_override("h_separation", 16)
	facts.add_theme_constant_override("v_separation", 4)
	column.add_child(facts)
	_add_fact(facts, "Armor", str(entry.armor), text_scale)
	_add_fact(facts, "Magic Resistance", "%d%%" % entry.magic_resistance, text_scale)
	_add_fact(facts, "Movement", str(entry.movement_maximum), text_scale)
	_add_fact(facts, "Weapon", entry.weapon_name, text_scale)
	_add_fact(facts, "Attacks", str(entry.attack_count), text_scale)
	_add_fact(facts, "Magic Attacks", str(entry.magic_attack_count), text_scale)
	var states := BoxContainer.new()
	states.name = "BestiaryStateCards"
	states.vertical = compact
	states.add_theme_constant_override("separation", 6)
	column.add_child(states)
	_add_state_card(states, "Attacks", entry.attack_rows, "None", text_scale)
	_add_state_card(states, "Immunities", entry.immunities, "None", text_scale)
	_add_state_card(states, "Vulnerabilities", entry.vulnerabilities, "None", text_scale)


func _ally_icon_texture(ally: MonsterView, media: ClassicMediaCatalog) -> Texture2D:
	if media == null or ally == null or ally.icon_id == 0:
		return null
	var asset := media.asset_by_resource(ally.icon_resource_type, ally.icon_id)
	return media.image_texture(asset) if asset != null else null


func _catalog_icon_texture(entry: MonsterCatalogEntryView, media: ClassicMediaCatalog) -> Texture2D:
	if media == null or entry == null or entry.icon_id == 0:
		return null
	var asset := media.asset_by_resource("cicn", entry.icon_id)
	return media.image_texture(asset) if asset != null else null


func _add_fact(parent: GridContainer, label_text: String, value_text: String, text_scale: float) -> void:
	var key := _add_label(parent, label_text, MUTED, 13, text_scale)
	key.custom_minimum_size.x = 104.0
	var value := _add_label(parent, value_text, TEXT, 13, text_scale)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _add_state_card(parent: BoxContainer, title: String, values: Array[String], empty_text: String, text_scale: float) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	panel.add_child(column)
	_add_label(column, title, GOLD, 14, text_scale)
	_add_label(column, empty_text if values.is_empty() else " • ".join(values), TEXT, 12, text_scale)
	parent.add_child(panel)


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
