class_name ClassicCharacterSheet
extends VBoxContainer

const ClassicSpellLevelScript := preload("res://src/presentation/classic_spell_level.gd")

signal character_selected(character_id: String)
signal tab_changed(tab_id: StringName)
signal appearance_change_requested(character_id: String, appearance_kind: StringName, appearance_id: String)

const GOLD := Color("d5b45d")
const MUTED := Color("9aa0a8")
const GOOD := Color("75c889")
const BAD := Color("ef7770")
const TABS: Array[Dictionary] = [
	{"id": &"overview", "label": "Overview"},
	{"id": &"conditions", "label": "Conditions & Saves"},
	{"id": &"equipment", "label": "Equipment"},
	{"id": &"abilities", "label": "Abilities"},
	{"id": &"spells", "label": "Spells"},
	{"id": &"appearance", "label": "Appearance"},
	{"id": &"background", "label": "Race, Caste & Aging"},
	{"id": &"record", "label": "Lifetime Record"},
]

var _characters: Array[CharacterView] = []
var _selected_character_id: String = ""
var _active_tab: StringName = &"overview"
var _textures: Dictionary = {}
var _text_scale: float = 1.0
var _content: VBoxContainer
var _portrait_options: Array[CharacterAppearanceOptionView] = []
var _combat_icon_options: Array[CharacterAppearanceOptionView] = []
var _media: ClassicMediaCatalog
var _appearance_availability: ActionAvailabilityView = ActionAvailabilityView.new(&"change_character_appearance", false, "Appearance changes are unavailable.")
var _draft_portrait_id: String = ""
var _draft_combat_icon_id: String = ""
var _layout_profile: StringName = UiLayoutProfile.WIDE
var _show_character_picker: bool = true


func present(characters: Array[CharacterView], initial_character_id: String = "", textures: Dictionary = {}, text_scale: float = 1.0, initial_tab: StringName = &"overview", portrait_options: Array[CharacterAppearanceOptionView] = [], combat_icon_options: Array[CharacterAppearanceOptionView] = [], appearance_availability: ActionAvailabilityView = null, media: ClassicMediaCatalog = null, layout_profile: StringName = UiLayoutProfile.WIDE, show_character_picker: bool = true) -> void:
	_characters = characters.duplicate()
	_textures = textures
	_text_scale = clampf(text_scale, 1.0, 1.5)
	_portrait_options = portrait_options.duplicate()
	_combat_icon_options = combat_icon_options.duplicate()
	_media = media
	_layout_profile = layout_profile
	_show_character_picker = show_character_picker
	_appearance_availability = appearance_availability if appearance_availability != null else ActionAvailabilityView.new(&"change_character_appearance", false, "Appearance changes are unavailable.")
	_active_tab = initial_tab if _tab_exists(initial_tab) else &"overview"
	_selected_character_id = initial_character_id
	if _selected_character() == null and not _characters.is_empty():
		_selected_character_id = _characters[0].id
	_sync_appearance_draft()
	_rebuild()


func selected_character_id() -> String:
	return _selected_character_id


func active_tab() -> StringName:
	return _active_tab


func _rebuild() -> void:
	_clear(self)
	add_theme_constant_override("separation", 8)
	if _characters.is_empty():
		_add_label(self, "No characters are available for inspection.", MUTED)
		return
	if _show_character_picker:
		_build_character_picker()
	var character := _selected_character()
	_build_identity(character)
	_build_tabs()
	var content_frame := PanelContainer.new()
	content_frame.name = "CharacterSheetWorkspace"
	content_frame.theme_type_variation = &"ClassicInset"
	content_frame.custom_minimum_size.y = 300.0
	content_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content = VBoxContainer.new()
	_content.name = "CharacterSheetContent"
	_content.add_theme_constant_override("separation", 8)
	content_frame.add_child(_content)
	add_child(content_frame)
	match _active_tab:
		&"conditions":
			_build_conditions(character)
		&"equipment":
			_build_equipment(character)
		&"abilities":
			_build_abilities(character)
		&"spells":
			_build_spells(character)
		&"appearance":
			_build_appearance(character)
		&"background":
			_build_background(character)
		&"record":
			_build_record(character)
		_:
			_build_overview(character)


func _build_character_picker() -> void:
	var picker := HFlowContainer.new()
	picker.name = "CharacterPicker"
	picker.add_theme_constant_override("h_separation", 6)
	picker.add_theme_constant_override("v_separation", 6)
	for character: CharacterView in _characters:
		var button := Button.new()
		button.text = character.name
		button.icon = _textures.get(character.portrait_id) as Texture2D
		button.expand_icon = true
		button.custom_minimum_size = Vector2(88.0 if _layout_profile == UiLayoutProfile.COMPACT else 120.0, 44.0 if _layout_profile == UiLayoutProfile.COMPACT else 48.0)
		button.toggle_mode = true
		button.button_pressed = character.id == _selected_character_id
		button.tooltip_text = "View %s without changing session state." % character.name
		button.pressed.connect(_select_character.bind(character.id))
		picker.add_child(button)
	add_child(picker)


func _build_identity(character: CharacterView) -> void:
	var frame := PanelContainer.new()
	frame.name = "CharacterIdentity"
	frame.theme_type_variation = &"ClassicInset"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	frame.add_child(row)
	var portrait := _appearance(character.portrait_id, character.name.left(1), "Portrait")
	portrait.custom_minimum_size = Vector2(64.0, 64.0) if _layout_profile == UiLayoutProfile.COMPACT else Vector2(80.0, 80.0)
	row.add_child(portrait)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 2)
	row.add_child(identity)
	_add_label(identity, character.name, GOLD, 22)
	_add_label(identity, "Level %d %s %s • %s • Age %d (%s)" % [character.level, character.race_name, character.caste_name, character.gender_name, character.age_years, character.age_group_name])
	_add_label(identity, "ST %d/%d • SP %d/%d • AR %d • Attacks %s • Load %d/%d" % [character.current_health, character.maximum_health, character.spell_points, character.maximum_spell_points, character.armor, character.attacks_per_round, character.carried_load, character.maximum_load], BAD if character.current_health <= 0 else Color("e0e2e5"))
	var combat_icon := _appearance(character.combat_icon_id, "⚔", "Combat icon")
	combat_icon.custom_minimum_size = Vector2(64.0, 64.0) if _layout_profile == UiLayoutProfile.COMPACT else Vector2(80.0, 80.0)
	row.add_child(combat_icon)
	add_child(frame)


func _build_tabs() -> void:
	var tabs := HFlowContainer.new()
	tabs.name = "CharacterSheetTabs"
	tabs.add_theme_constant_override("h_separation", 4)
	tabs.add_theme_constant_override("v_separation", 4)
	for tab: Dictionary in TABS:
		var button := Button.new()
		button.text = String(tab["label"])
		button.toggle_mode = true
		button.button_pressed = StringName(tab["id"]) == _active_tab
		button.pressed.connect(_select_tab.bind(StringName(tab["id"])))
		tabs.add_child(button)
	add_child(tabs)


func _build_overview(character: CharacterView) -> void:
	var regions: Container = VBoxContainer.new() if _layout_profile == UiLayoutProfile.COMPACT else HBoxContainer.new()
	regions.name = "OverviewRegions"
	regions.add_theme_constant_override("separation", 10)
	regions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(regions)
	_add_metric_region(regions, "Attributes", "OverviewAttributes", [
		_metric("Brawn", character.brawn), _metric("Knowledge", character.knowledge), _metric("Judgment", character.judgment),
		_metric("Agility", character.agility), _metric("Vitality", character.vitality), _metric("Luck", character.luck),
	])
	_add_metric_region(regions, "Combat profile", "OverviewCombat", [
		_metric("Attack Bonus", character.attack_bonus), _metric("Defense Bonus", character.defense_bonus), _metric("Base To Hit", character.to_hit), _metric("Armor", character.armor),
		_metric("Dodge", character.dodge), _metric("Missile", character.missile),
		_metric("Two-Hand", character.two_hand), _metric("Hand-to-Hand", character.hand_to_hand), _metric("Damage Bonus", character.damage_bonus),
		_metric("Magic Resistance", character.magic_resistance),
	])
	var status := _add_metric_region(regions, "Resources and wealth", "OverviewStatus", [
		_metric("Stamina", character.current_health, "%d / %d" % [character.current_health, character.maximum_health]), _metric("Spell Points", character.spell_points, "%d / %d" % [character.spell_points, character.maximum_spell_points]),
		_metric("Load", character.carried_load, "%d / %d" % [character.carried_load, character.maximum_load]), _metric("Movement", character.movement, "%d / %d" % [character.movement, character.maximum_movement]),
		_metric("Attacks / Round", 0, character.attacks_per_round), _metric("Experience", character.experience),
		_metric("Gold", character.gold), _metric("Gems", character.gems), _metric("Jewelry", character.jewelry),
	])
	_add_heading(status, "Current conditions")
	if character.conditions.is_empty():
		_add_label(status, "No active conditions.", MUTED, 13)
	else:
		_add_metric_views(status, character.conditions)


func _add_metric_region(parent: Container, title: String, node_name: String, metrics: Array[CharacterMetricView]) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.name = node_name
	frame.theme_type_variation = &"ClassicInset"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	frame.add_child(column)
	_add_heading(column, title)
	_add_metric_views(column, metrics)
	parent.add_child(frame)
	return column


func _build_conditions(character: CharacterView) -> void:
	var regions: Container = VBoxContainer.new() if _layout_profile == UiLayoutProfile.COMPACT else HBoxContainer.new()
	regions.name = "ConditionSaveRegions"
	regions.add_theme_constant_override("separation", 10)
	regions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(regions)
	var conditions := _add_metric_region(regions, "Conditions", "ConditionsRegion", character.conditions)
	if character.conditions.is_empty():
		_add_label(conditions, "No active conditions.", MUTED, 13)
	_add_metric_region(regions, "Saving throws", "SavingThrowsRegion", character.saving_throws)


func _build_equipment(character: CharacterView) -> void:
	_add_heading(_content, "Equipment", "%d of 30 inventory slots • Load %d/%d" % [character.items.size(), character.carried_load, character.maximum_load])
	if character.items.is_empty():
		_add_label(_content, "This character carries no items.", MUTED)
		return
	var equipped: Array[ItemView] = []
	var carried: Array[ItemView] = []
	for item: ItemView in character.items:
		(equipped if item.equipped else carried).append(item)
	var regions: Container = VBoxContainer.new() if _layout_profile == UiLayoutProfile.COMPACT else HBoxContainer.new()
	regions.name = "EquipmentRegions"
	regions.add_theme_constant_override("separation", 10)
	regions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(regions)
	_build_item_region(regions, "Equipped", equipped, "No items are equipped.")
	_build_item_region(regions, "Carried", carried, "No unequipped items are carried.")


func _build_item_region(parent: Container, title: String, items: Array[ItemView], empty_text: String) -> void:
	var frame := PanelContainer.new()
	frame.name = "%sItems" % title
	frame.theme_type_variation = &"ClassicInset"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	frame.add_child(column)
	_add_heading(column, title, "%d item%s" % [items.size(), "" if items.size() == 1 else "s"])
	if items.is_empty():
		_add_label(column, empty_text, MUTED, 13)
	else:
		for item: ItemView in items:
			column.add_child(_equipment_item_card(item))
	parent.add_child(frame)


func _equipment_item_card(item: ItemView) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.tooltip_text = "Item instance %s" % item.instance_id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	row.add_child(_item_icon(item))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var facts: Array[String] = ["Identified" if item.identified else "Unidentified"]
	if item.charges != 0:
		facts.append("%d charges" % item.charges)
	_add_label(text, item.name, GOLD, 15)
	_add_label(text, " • ".join(facts), Color("e0e2e5"), 13)
	_add_label(text, "%d weight • value %d" % [item.weight, item.value], MUTED, 12)
	row.add_child(text)
	return panel


func _build_abilities(character: CharacterView) -> void:
	var regions: Container = VBoxContainer.new() if _layout_profile == UiLayoutProfile.COMPACT else HBoxContainer.new()
	regions.name = "AbilityRegions"
	regions.add_theme_constant_override("separation", 10)
	regions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(regions)
	var modifiers := _add_metric_region(regions, "Special modifiers", "SpecialModifiersRegion", character.special_modifiers)
	if character.special_modifiers.is_empty():
		_add_label(modifiers, "No active special modifiers.", MUTED, 13)
	var abilities := _add_metric_region(regions, "Special abilities", "SpecialAbilitiesRegion", character.abilities)
	if character.abilities.is_empty():
		_add_label(abilities, "No active special abilities.", MUTED, 13)


func _build_spells(character: CharacterView) -> void:
	var regions: Container = VBoxContainer.new() if _layout_profile == UiLayoutProfile.COMPACT else HBoxContainer.new()
	regions.name = "CharacterSpellRegions"
	regions.add_theme_constant_override("separation", 10)
	regions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(regions)
	var known := _spell_region(regions, "Known spells", "KnownSpellRegion", "%d SP available • %d known" % [character.spell_points, character.spells.size()], 1.6)
	if character.spells.is_empty():
		_add_label(known, "This character knows no spells.", MUTED, 13)
	else:
		var spell_grid := GridContainer.new()
		spell_grid.columns = 1 if _layout_profile == UiLayoutProfile.COMPACT else 2
		spell_grid.add_theme_constant_override("h_separation", 6)
		spell_grid.add_theme_constant_override("v_separation", 6)
		for spell: SpellView in character.spells:
			spell_grid.add_child(_character_spell_card(spell))
		known.add_child(spell_grid)
	var scrolls := _spell_region(regions, "Scroll case", "ScrollCaseRegion", "%d fixed Classic slots" % character.scrolls.size(), 0.8)
	if character.scrolls.is_empty():
		_add_label(scrolls, "No scroll case slots are available.", MUTED, 13)
	for scroll: SpellScrollView in character.scrolls:
		var empty := scroll.spell_id.is_empty()
		_add_card(scrolls, "Slot %d" % (scroll.slot_index + 1), "Empty" if empty else scroll.spell_name, "" if empty else "Power %d" % scroll.power)


func _spell_region(parent: Container, title: String, node_name: String, detail: String, stretch: float) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.name = node_name
	frame.theme_type_variation = &"ClassicInset"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = stretch
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	frame.add_child(column)
	_add_heading(column, title, detail)
	parent.add_child(frame)
	return column


func _character_spell_card(spell: SpellView) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	panel.add_child(row)
	row.add_child(_media_icon(spell.icon_resource_type, spell.icon_id, Vector2(44.0, 44.0), "✦"))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_label(text, spell.name, GOLD, 15)
	_add_label(text, "Level %d • %d SP • Range %d–%d" % [_classic_spell_level(spell), absi(spell.cost), spell.range_min, spell.range_max], Color("e0e2e5"), 12)
	var description := _add_label(text, spell.description, MUTED, 12)
	description.max_lines_visible = 2
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(text)
	return panel


static func _classic_spell_level(spell: SpellView) -> int:
	return ClassicSpellLevelScript.from_classic_id(spell.classic_id)


func _build_appearance(character: CharacterView) -> void:
	_add_heading(_content, "Appearance", "Portrait and tactical icon change independently")
	var columns: Container = VBoxContainer.new() if _layout_profile == UiLayoutProfile.COMPACT else HBoxContainer.new()
	columns.name = "AppearanceRegions"
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(_appearance_picker(character, CharacterAppearanceDefinition.PORTRAIT, _portrait_options, _draft_portrait_id, "Portrait"))
	columns.add_child(_appearance_picker(character, CharacterAppearanceDefinition.COMBAT_ICON, _combat_icon_options, _draft_combat_icon_id, "Combat icon"))
	_content.add_child(columns)
	if not _appearance_availability.enabled:
		_add_label(_content, _appearance_availability.reason, BAD, 13)
	var discard := Button.new()
	discard.text = "Discard Appearance Changes"
	discard.name = "DiscardAppearanceChanges"
	discard.disabled = _draft_portrait_id == character.portrait_id and _draft_combat_icon_id == character.combat_icon_id
	discard.tooltip_text = "The preview already matches the session." if discard.disabled else "Restore both previews without changing the session."
	if not discard.disabled:
		discard.pressed.connect(_discard_appearance_draft)
	_content.add_child(discard)


func _appearance_picker(character: CharacterView, kind: StringName, options: Array[CharacterAppearanceOptionView], selected_id: String, title: String) -> PanelContainer:
	var frame := PanelContainer.new()
	var role_name := "Portrait" if kind == CharacterAppearanceDefinition.PORTRAIT else "CombatIcon"
	frame.name = "%sAppearanceRegion" % role_name
	frame.theme_type_variation = &"ClassicInset"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1.0
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	frame.add_child(column)
	_add_heading(column, title, "%d package choices" % options.size())
	var preview_center := CenterContainer.new()
	preview_center.add_child(_appearance(selected_id, character.name.left(1) if kind == CharacterAppearanceDefinition.PORTRAIT else "⚔", "%s preview" % title, Vector2(132.0, 132.0)))
	column.add_child(preview_center)
	var picker := OptionButton.new()
	picker.name = "%sPicker" % title.replace(" ", "")
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var ordered := _recommended_first(options, character.race_id)
	var selected_index := -1
	for option: CharacterAppearanceOptionView in ordered:
		var recommended := option.is_recommended_for(character.race_id)
		var item_label := "%s%s" % ["Recommended • " if recommended else "", option.label]
		var texture := _textures.get(option.id) as Texture2D
		if texture != null:
			picker.add_icon_item(texture, item_label)
		else:
			picker.add_item(item_label)
		var index := picker.item_count - 1
		picker.set_item_metadata(index, option.id)
		if option.id == selected_id:
			selected_index = index
	picker.select(selected_index)
	picker.disabled = not _appearance_availability.enabled or options.is_empty()
	picker.tooltip_text = _appearance_availability.reason if not _appearance_availability.enabled else "Browse all %d package-backed %s choices; Castle recommendations appear first." % [options.size(), title.to_lower()]
	if not picker.disabled:
		picker.item_selected.connect(_select_appearance_option.bind(picker, kind))
	column.add_child(picker)
	var apply := Button.new()
	apply.name = "Apply%s" % role_name
	apply.text = "Apply %s" % title
	var original_id := character.portrait_id if kind == CharacterAppearanceDefinition.PORTRAIT else character.combat_icon_id
	apply.disabled = not _appearance_availability.enabled or selected_id == original_id
	apply.tooltip_text = _appearance_availability.reason if not _appearance_availability.enabled else "Choose a different %s first." % title.to_lower() if selected_id == original_id else "Commit this %s to the campaign session." % title.to_lower()
	if not apply.disabled:
		apply.pressed.connect(_apply_appearance.bind(kind, selected_id))
	column.add_child(apply)
	return frame


func _recommended_first(options: Array[CharacterAppearanceOptionView], race_id: String) -> Array[CharacterAppearanceOptionView]:
	var result: Array[CharacterAppearanceOptionView] = []
	for option: CharacterAppearanceOptionView in options:
		if option.is_recommended_for(race_id):
			result.append(option)
	for option: CharacterAppearanceOptionView in options:
		if not option.is_recommended_for(race_id):
			result.append(option)
	return result


func _select_appearance_option(index: int, picker: OptionButton, kind: StringName) -> void:
	if index < 0 or index >= picker.item_count:
		return
	var selected_id := String(picker.get_item_metadata(index))
	if kind == CharacterAppearanceDefinition.PORTRAIT:
		_draft_portrait_id = selected_id
	else:
		_draft_combat_icon_id = selected_id
	_rebuild()


func _apply_appearance(kind: StringName, appearance_id: String) -> void:
	appearance_change_requested.emit(_selected_character_id, kind, appearance_id)


func _discard_appearance_draft() -> void:
	_sync_appearance_draft()
	_rebuild()


func _sync_appearance_draft() -> void:
	var character := _selected_character()
	_draft_portrait_id = "" if character == null else character.portrait_id
	_draft_combat_icon_id = "" if character == null else character.combat_icon_id


func _build_background(character: CharacterView) -> void:
	var identities: Container = VBoxContainer.new() if _layout_profile == UiLayoutProfile.COMPACT else HBoxContainer.new()
	identities.name = "RaceClassRegions"
	identities.add_theme_constant_override("separation", 10)
	identities.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(identities)
	_build_background_region(identities, "Race", "RaceRegion", character.race_name, character.race_description, character.race_traits)
	_build_background_region(identities, "Caste", "CasteRegion", character.caste_name, character.caste_description, character.caste_traits)
	var aging := VBoxContainer.new()
	aging.name = "AgingRegion"
	_add_heading(aging, "Aging", "Age %d • current band highlighted" % character.age_years)
	var bands := GridContainer.new()
	bands.columns = 1 if _layout_profile == UiLayoutProfile.COMPACT else 5
	for band: CharacterAgeBandView in character.age_bands:
		var changes: Array[String] = []
		for change: CharacterMetricView in band.changes:
			if change.value != 0:
				changes.append("%s %+d" % [change.name, change.value])
		_add_card(bands, "%s%s" % ["Current • " if band.active else "", band.name], "Ages %d–%d" % [band.minimum_age, band.maximum_age], "No changes" if changes.is_empty() else " • ".join(changes))
	aging.add_child(bands)
	_content.add_child(aging)


func _build_background_region(parent: Container, kind: String, node_name: String, title: String, description: String, metrics: Array[CharacterMetricView]) -> void:
	var frame := PanelContainer.new()
	frame.name = node_name
	frame.theme_type_variation = &"ClassicInset"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	frame.add_child(column)
	_add_heading(column, title, kind)
	_add_label(column, description if not description.is_empty() else "No %s description is present in this package." % kind.to_lower(), MUTED, 13)
	_add_metric_views(column, metrics)
	parent.add_child(frame)


func _build_record(character: CharacterView) -> void:
	var panel := PanelContainer.new()
	panel.name = "LifetimeRecord"
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.y = 180.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	_add_heading(column, "Lifetime Record", "Prestige %d" % character.prestige)
	var grid := GridContainer.new()
	grid.columns = 2 if _layout_profile == UiLayoutProfile.COMPACT else 4
	var record := character.lifetime_record
	for metric: Dictionary in [{"name": "Damage given", "value": record.damage_given}, {"name": "Damage taken", "value": record.damage_taken}, {"name": "Hits given", "value": record.hits_given}, {"name": "Hits taken", "value": record.hits_taken}, {"name": "Enemy misses", "value": record.enemy_misses}, {"name": "Attacks missed", "value": record.attacks_missed}, {"name": "Kills", "value": record.kills}, {"name": "Deaths", "value": record.deaths}, {"name": "Knockouts", "value": record.knockouts}, {"name": "Spells cast", "value": record.spells_cast}, {"name": "Destroyed", "value": record.destroyed}, {"name": "Turned", "value": record.turns}]:
		_add_card(grid, metric["name"], str(metric["value"]), "Lifetime Classic counter")
	column.add_child(grid)
	_add_label(column, "Prestige penalty %d" % character.prestige_penalty, BAD if character.prestige_penalty > 0 else MUTED, 13)
	_content.add_child(panel)


func _select_character(character_id: String) -> void:
	if character_id == _selected_character_id:
		return
	_selected_character_id = character_id
	_sync_appearance_draft()
	character_selected.emit(character_id)
	_rebuild()


func _select_tab(tab_id: StringName) -> void:
	if tab_id == _active_tab:
		return
	_active_tab = tab_id
	tab_changed.emit(tab_id)
	_rebuild()


func _selected_character() -> CharacterView:
	for character: CharacterView in _characters:
		if character.id == _selected_character_id:
			return character
	return null


func _tab_exists(tab_id: StringName) -> bool:
	for tab: Dictionary in TABS:
		if StringName(tab["id"]) == tab_id:
			return true
	return false


func _appearance(asset_id: String, fallback_text: String, role: String, minimum_size: Vector2 = Vector2(68.0, 68.0)) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = "%sMedia" % role.to_pascal_case()
	frame.custom_minimum_size = minimum_size
	var texture := _textures.get(asset_id) as Texture2D
	if texture != null:
		var image := TextureRect.new()
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.tooltip_text = role
		frame.add_child(image)
	else:
		var fallback := _label(fallback_text if not fallback_text.is_empty() else "?", MUTED, 18)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.tooltip_text = "%s media unavailable." % role
		frame.add_child(fallback)
	return frame


func _add_metrics(parent: Container, metrics: Array[CharacterMetricView]) -> void:
	_add_metric_views(parent, metrics)


func _add_metric_views(parent: Container, metrics: Array[CharacterMetricView]) -> void:
	var grid := GridContainer.new()
	grid.columns = 2 if _layout_profile == UiLayoutProfile.COMPACT else 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for metric: CharacterMetricView in metrics:
		var name_label := _label(metric.name, MUTED, 14)
		if _layout_profile != UiLayoutProfile.COMPACT:
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not metric.detail.is_empty():
			name_label.tooltip_text = metric.detail
		grid.add_child(name_label)
		var value_text := metric.detail if metric.value in [0, 1] and metric.detail in ["Yes", "No"] else "%+d" % metric.value if metric.value > 0 else str(metric.value)
		if not metric.detail.is_empty() and metric.name in ["Attacks / Round", "Movement", "Stamina", "Spell Points", "Load"]:
			value_text = metric.detail
		elif metric.detail == "Permanent":
			value_text = "Permanent"
		var value_label := _label(value_text, GOOD if metric.value > 0 else BAD if metric.value < 0 else Color("e0e2e5"), 14)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if _layout_profile == UiLayoutProfile.COMPACT else HORIZONTAL_ALIGNMENT_RIGHT
		if not metric.detail.is_empty():
			value_label.tooltip_text = metric.detail
		grid.add_child(value_label)
	parent.add_child(grid)


func _item_icon(item: ItemView) -> Control:
	return _media_icon(item.icon_resource_type, item.icon_id, Vector2(52.0, 52.0), "◈")


func _media_icon(resource_type: String, resource_id: int, size: Vector2, fallback_text: String) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = size
	var asset: MediaAsset = _media.asset_by_resource(resource_type, resource_id) if _media != null and resource_id != 0 else null
	var texture := _media.image_texture(asset) if asset != null else null
	if texture != null:
		var image := TextureRect.new()
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		frame.add_child(image)
	else:
		var fallback := _label(fallback_text, MUTED, 18)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(fallback)
	return frame


func _metric(metric_name: String, value: int, detail: String = "") -> CharacterMetricView:
	return CharacterMetricView.new(StringName(metric_name.to_lower().replace(" ", "-")), 0, metric_name, value, detail)


func _add_heading(parent: Container, title: String, detail: String = "") -> void:
	var row := HBoxContainer.new()
	var heading := _label(title, GOLD, 18)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	if not detail.is_empty():
		var note := _label(detail, MUTED, 13)
		note.name = "HeadingDetail"
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.size_flags_stretch_ratio = 0.75
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(note)
	parent.add_child(row)


func _add_card(parent: Container, title: String, subtitle: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	_add_label(box, title, GOLD, 16)
	_add_label(box, subtitle, Color("e0e2e5"), 14)
	if not detail.is_empty():
		_add_label(box, detail, MUTED, 13)
	parent.add_child(panel)


func _label(text: String, color: Color = Color.WHITE, font_size: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(font_size) * _text_scale)))
	return label


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, font_size: int = 15) -> Label:
	var label := _label(text, color, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
