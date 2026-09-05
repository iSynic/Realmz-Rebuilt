## Binds detached ally and bestiary records to their shared authored workspace.
class_name CreatureLibraryScreenController
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


func present_allies(target: Control, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	var screen := target as CreatureLibraryScreen
	if screen == null or view == null:
		return
	screen.prepare_for_render(_layout_profile == UiLayoutProfile.COMPACT)
	_bind_list_title(screen, "Current Allies  •  %d" % view.party_allies.size(), text_scale)
	if view.party_allies.is_empty():
		_bind_empty(screen, "No current allies", "No allies are currently with the party.", text_scale)
		return
	var selected := _selected_ally(view.party_allies)
	if selected == null:
		selected = view.party_allies[0]
		_selected_ally_id = selected.id
	for ally: MonsterView in view.party_allies:
		var row := _add_row(screen)
		if row == null:
			return
		row.name = "AllyRow_%s" % ally.id.validate_node_name()
		row.text = "%s\n%d/%d ST  •  %d HD" % [ally.name, ally.current_health, ally.maximum_health, ally.hit_dice]
		row.button_pressed = ally.id == selected.id
		row.icon = _ally_icon_texture(ally, media)
		row.tooltip_text = "Inspect %s" % ally.name
		row.add_theme_font_size_override("font_size", int(round(14.0 * text_scale)))
		row.pressed.connect(_select_ally.bind(ally.id, screen, view, media, text_scale))
	_bind_ally_record(screen, selected, media, text_scale)


func present_bestiary(target: Control, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	var screen := target as CreatureLibraryScreen
	if screen == null or view == null:
		return
	screen.prepare_for_render(_layout_profile == UiLayoutProfile.COMPACT)
	_bind_list_title(screen, "Bestiary  •  %d" % view.bestiary_entries.size(), text_scale)
	if view.bestiary_entries.is_empty():
		_bind_empty(screen, "Bestiary unavailable", "This package has no menu-visible monster records.", text_scale)
		return
	var selected := _selected_bestiary(view.bestiary_entries)
	if selected == null:
		selected = view.bestiary_entries[0]
		_selected_bestiary_id = selected.definition_id
	for entry: MonsterCatalogEntryView in view.bestiary_entries:
		var row := _add_row(screen)
		if row == null:
			return
		row.name = "BestiaryRow_%s" % entry.definition_id.validate_node_name()
		row.text = "%s\n%d HD  •  AC %d" % [entry.name, entry.hit_dice, entry.armor]
		row.button_pressed = entry.definition_id == selected.definition_id
		row.icon = _catalog_icon_texture(entry, media)
		row.tooltip_text = "Inspect %s" % entry.name
		row.add_theme_font_size_override("font_size", int(round(14.0 * text_scale)))
		row.pressed.connect(_select_bestiary.bind(entry.definition_id, screen, view, media, text_scale))
	_bind_bestiary_record(screen, selected, media, text_scale)


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


func _select_ally(ally_id: String, screen: CreatureLibraryScreen, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	_selected_ally_id = ally_id
	present_allies(screen, view, media, text_scale)


func _select_bestiary(definition_id: String, screen: CreatureLibraryScreen, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	_selected_bestiary_id = definition_id
	present_bestiary(screen, view, media, text_scale)


func _add_row(screen: CreatureLibraryScreen) -> Button:
	if screen.creature_row_scene == null:
		push_error("Creature library screen has no row scene.")
		return null
	var row := screen.creature_row_scene.instantiate() as Button
	if row == null:
		push_error("Creature library row scene must instantiate a Button.")
		return null
	screen.list_rows().add_child(row)
	return row


func _bind_empty(screen: CreatureLibraryScreen, title: String, detail: String, text_scale: float) -> void:
	var empty := screen.empty_state()
	empty.visible = true
	_bind_label(empty.get_node("EmptyTitle") as Label, title, GOLD, 18, text_scale)
	_bind_label(empty.get_node("EmptyDetail") as Label, detail, MUTED, 13, text_scale)


func _bind_list_title(screen: CreatureLibraryScreen, title: String, text_scale: float) -> void:
	_bind_label(screen.list_title(), title, GOLD, 16, text_scale)


func _bind_ally_record(screen: CreatureLibraryScreen, ally: MonsterView, media: ClassicMediaCatalog, text_scale: float) -> void:
	_bind_record_identity(screen, ally.name, "Classic monster %d" % ally.classic_id, "%d Hit Dice" % ally.hit_dice, _ally_icon_texture(ally, media), "CICN %d unavailable." % ally.icon_id if ally.icon_id != 0 else ally.name, text_scale)
	_bind_description(screen, "", text_scale)
	_bind_facts(screen, [
		["Stamina", "%d / %d" % [ally.current_health, ally.maximum_health]],
		["Spell Points", "%d / %d" % [ally.spell_points, ally.maximum_spell_points]],
		["Armor", str(ally.armor)],
		["Magic Resistance", "%d%%" % ally.magic_resistance],
		["Movement", str(ally.movement_maximum)],
		["Attacks", str(ally.attack_count)],
		["Weapon", ally.weapon_name],
		["Helpless", "Yes" if ally.helpless else "No"],
	], text_scale)
	_bind_states(screen, [["Conditions", ally.conditions], ["Immunities", ally.immunities], ["Vulnerabilities", ally.vulnerabilities]], text_scale)


func _bind_bestiary_record(screen: CreatureLibraryScreen, entry: MonsterCatalogEntryView, media: ClassicMediaCatalog, text_scale: float) -> void:
	_bind_record_identity(screen, entry.name, "Classic monster %d  •  name %d" % [entry.classic_id, entry.classic_name_id], "%d Hit Dice" % entry.hit_dice, _catalog_icon_texture(entry, media), "CICN %d unavailable." % entry.icon_id if entry.icon_id != 0 else entry.name, text_scale)
	_bind_description(screen, entry.description if not entry.description.is_empty() else "No description supplied.", text_scale)
	_bind_facts(screen, [
		["Armor", str(entry.armor)],
		["Magic Resistance", "%d%%" % entry.magic_resistance],
		["Movement", str(entry.movement_maximum)],
		["Weapon", entry.weapon_name],
		["Attacks", str(entry.attack_count)],
		["Magic Attacks", str(entry.magic_attack_count)],
	], text_scale)
	_bind_states(screen, [["Attacks", entry.attack_rows], ["Immunities", entry.immunities], ["Vulnerabilities", entry.vulnerabilities]], text_scale)


func _bind_record_identity(screen: CreatureLibraryScreen, title: String, source: String, hit_dice: String, texture: Texture2D, missing_tooltip: String, text_scale: float) -> void:
	var record := screen.detail_record()
	record.visible = true
	var icon := record.get_node("Header/CreatureIcon") as TextureRect
	icon.texture = texture
	icon.tooltip_text = missing_tooltip if texture == null else title
	_bind_label(record.get_node("Header/Identity/CreatureName") as Label, title, GOLD, 20, text_scale)
	_bind_label(record.get_node("Header/Identity/CreatureSource") as Label, source, MUTED, 13, text_scale)
	_bind_label(record.get_node("Header/Identity/CreatureHitDice") as Label, hit_dice, TEXT, 13, text_scale)


func _bind_description(screen: CreatureLibraryScreen, value: String, text_scale: float) -> void:
	var description := screen.detail_record().get_node("CreatureDescription") as Label
	description.visible = not value.is_empty()
	_bind_label(description, value, TEXT, 13, text_scale)


func _bind_facts(screen: CreatureLibraryScreen, records: Array, text_scale: float) -> void:
	var facts := screen.facts()
	facts.columns = 2 if _layout_profile == UiLayoutProfile.COMPACT else 4
	for index: int in range(8):
		var key := facts.get_node("Fact%dKey" % (index + 1)) as Label
		var value := facts.get_node("Fact%dValue" % (index + 1)) as Label
		var visible := index < records.size()
		key.visible = visible
		value.visible = visible
		if not visible:
			continue
		_bind_label(key, str(records[index][0]), MUTED, 13, text_scale)
		key.custom_minimum_size.x = 104.0
		_bind_label(value, str(records[index][1]), TEXT, 13, text_scale)


func _bind_states(screen: CreatureLibraryScreen, records: Array, text_scale: float) -> void:
	var cards := screen.state_cards()
	for index: int in range(3):
		var panel := cards.get_node("State%d" % (index + 1)) as PanelContainer
		var values: Array[String] = []
		values.assign(records[index][1])
		_bind_label(panel.get_node("Content/Title") as Label, str(records[index][0]), GOLD, 14, text_scale)
		_bind_label(panel.get_node("Content/Body") as Label, "None" if values.is_empty() else " • ".join(values), TEXT, 12, text_scale)


func _bind_label(label: Label, value: String, color: Color, size: int, text_scale: float) -> void:
	label.text = value
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * text_scale)))


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
