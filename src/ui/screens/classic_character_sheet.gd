## Owns Classic character sheet presentation behavior for its scene-authored screen.

class_name ClassicCharacterSheet
extends VBoxContainer


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

@export var selector_button_scene: PackedScene
@export var metric_row_scene: PackedScene
@export var record_card_scene: PackedScene
@export var item_card_scene: PackedScene
@export var spell_card_scene: PackedScene

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
	var empty_state := get_node("CharacterEmptyState") as Label
	var picker := get_node("CharacterPicker") as HFlowContainer
	var identity := get_node("CharacterIdentity") as PanelContainer
	var tabs := get_node("CharacterSheetTabs") as HFlowContainer
	var workspace := get_node("CharacterSheetWorkspace") as PanelContainer
	_content = get_node("CharacterSheetWorkspace/CharacterSheetContent/DynamicTabContent") as VBoxContainer
	_clear(picker)
	_clear(tabs)
	_clear(_content)
	_hide_authored_tabs()
	empty_state.visible = _characters.is_empty()
	picker.visible = not _characters.is_empty() and _show_character_picker
	identity.visible = not _characters.is_empty()
	tabs.visible = not _characters.is_empty()
	workspace.visible = not _characters.is_empty()
	if _characters.is_empty():
		empty_state.add_theme_font_size_override("font_size", int(round(15.0 * _text_scale)))
		return
	if _show_character_picker:
		_build_character_picker()
	var character := _selected_character()
	_build_identity(character)
	_build_tabs()
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


func _hide_authored_tabs() -> void:
	for tab_name: String in ["OverviewTab", "ConditionsTab", "AbilitiesTab", "RecordTab"]:
		(get_node("CharacterSheetWorkspace/CharacterSheetContent/CharacterSheetStatTabs/%s" % tab_name) as Control).visible = false
	for tab_name: String in ["EquipmentTab", "SpellsTab"]:
		(get_node("CharacterSheetWorkspace/CharacterSheetContent/CharacterSheetInventoryMagicTabs/%s" % tab_name) as Control).visible = false
	for tab_name: String in ["AppearanceTab", "BackgroundTab"]:
		(get_node("CharacterSheetWorkspace/CharacterSheetContent/CharacterSheetIdentityTabs/%s" % tab_name) as Control).visible = false


func _build_character_picker() -> void:
	var picker := get_node("CharacterPicker") as HFlowContainer
	for character: CharacterView in _characters:
		var button := selector_button_scene.instantiate() as Button
		if button == null:
			push_error("Character sheet selector scene must instantiate a Button.")
			return
		button.text = character.name
		button.icon = _textures.get(character.portrait_id) as Texture2D
		button.expand_icon = true
		button.custom_minimum_size = Vector2(88.0 if _layout_profile == UiLayoutProfile.COMPACT else 120.0, 44.0 if _layout_profile == UiLayoutProfile.COMPACT else 48.0)
		button.toggle_mode = true
		button.button_pressed = character.id == _selected_character_id
		button.tooltip_text = "View %s without changing session state." % character.name
		button.pressed.connect(_select_character.bind(character.id))
		picker.add_child(button)


func _build_identity(character: CharacterView) -> void:
	var compact_size := Vector2(64.0, 64.0) if _layout_profile == UiLayoutProfile.COMPACT else Vector2(80.0, 80.0)
	_bind_identity_media("CharacterIdentity/IdentityRow/PortraitMedia", character.portrait_id, character.name.left(1), "Portrait", compact_size)
	_bind_identity_media("CharacterIdentity/IdentityRow/CombatIconMedia", character.combat_icon_id, "⚔", "Combat icon", compact_size)
	_bind_existing_label("CharacterIdentity/IdentityRow/IdentityText/CharacterName", character.name, GOLD, 22)
	_bind_existing_label("CharacterIdentity/IdentityRow/IdentityText/CharacterRole", "Level %d %s %s • %s • Age %d (%s)" % [character.level, character.race_name, character.caste_name, character.gender_name, character.age_years, character.age_group_name], Color("e0e2e5"), 15)
	_bind_existing_label("CharacterIdentity/IdentityRow/IdentityText/CharacterSummary", "ST %d/%d • SP %d/%d • AR %d • Attacks %s • Load %d/%d" % [character.current_health, character.maximum_health, character.spell_points, character.maximum_spell_points, character.armor, character.attacks_per_round, character.carried_load, character.maximum_load], BAD if character.current_health <= 0 else Color("e0e2e5"), 15)


func _build_tabs() -> void:
	var tabs := get_node("CharacterSheetTabs") as HFlowContainer
	for tab: Dictionary in TABS:
		var button := selector_button_scene.instantiate() as Button
		if button == null:
			push_error("Character sheet selector scene must instantiate a Button.")
			return
		button.custom_minimum_size = Vector2.ZERO
		button.text = String(tab["label"])
		button.toggle_mode = true
		button.button_pressed = StringName(tab["id"]) == _active_tab
		button.pressed.connect(_select_tab.bind(StringName(tab["id"])))
		tabs.add_child(button)


func _bind_identity_media(path: NodePath, asset_id: String, fallback_text: String, role: String, minimum_size: Vector2) -> void:
	var frame := get_node(path) as PanelContainer
	var image := frame.get_child(0) as TextureRect
	var fallback := frame.get_child(1) as Label
	var texture := _textures.get(asset_id) as Texture2D
	frame.custom_minimum_size = minimum_size
	image.texture = texture
	image.visible = texture != null
	fallback.visible = texture == null
	fallback.text = fallback_text if not fallback_text.is_empty() else "?"
	fallback.tooltip_text = "%s media unavailable." % role if texture == null else role
	fallback.add_theme_font_size_override("font_size", int(round(18.0 * _text_scale)))


func _bind_existing_label(path: NodePath, value: String, color: Color, font_size: int) -> void:
	var label := get_node(path) as Label
	label.text = value
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(font_size) * _text_scale)))


func _build_overview(character: CharacterView) -> void:
	var tab := get_node("CharacterSheetWorkspace/CharacterSheetContent/CharacterSheetStatTabs/OverviewTab") as VBoxContainer
	tab.visible = true
	var regions := tab.get_node("OverviewRegions") as BoxContainer
	regions.vertical = _layout_profile == UiLayoutProfile.COMPACT
	_bind_metric_region(regions.get_node("OverviewAttributes") as PanelContainer, [
		_metric("Brawn", character.brawn), _metric("Knowledge", character.knowledge), _metric("Judgment", character.judgment),
		_metric("Agility", character.agility), _metric("Vitality", character.vitality), _metric("Luck", character.luck),
	])
	_bind_metric_region(regions.get_node("OverviewCombat") as PanelContainer, [
		_metric("Attack Bonus", character.attack_bonus), _metric("Defense Bonus", character.defense_bonus), _metric("Base To Hit", character.to_hit), _metric("Armor", character.armor),
		_metric("Dodge", character.dodge), _metric("Missile", character.missile),
		_metric("Two-Hand", character.two_hand), _metric("Hand-to-Hand", character.hand_to_hand), _metric("Damage Bonus", character.damage_bonus),
		_metric("Magic Resistance", character.magic_resistance),
	])
	var status := regions.get_node("OverviewStatus") as PanelContainer
	_bind_metric_region(status, [
		_metric("Stamina", character.current_health, "%d / %d" % [character.current_health, character.maximum_health]), _metric("Spell Points", character.spell_points, "%d / %d" % [character.spell_points, character.maximum_spell_points]),
		_metric("Load", character.carried_load, "%d / %d" % [character.carried_load, character.maximum_load]), _metric("Movement", character.movement, "%d / %d" % [character.movement, character.maximum_movement]),
		_metric("Attacks / Round", 0, character.attacks_per_round), _metric("Experience", character.experience),
		_metric("Gold", character.gold), _metric("Gems", character.gems), _metric("Jewelry", character.jewelry),
	])
	var condition_rows := status.get_node("Content/ConditionRows") as VBoxContainer
	_clear(condition_rows)
	_bind_metric_rows(condition_rows, character.conditions, "No active conditions.")


func _build_conditions(character: CharacterView) -> void:
	var tab := get_node("CharacterSheetWorkspace/CharacterSheetContent/CharacterSheetStatTabs/ConditionsTab") as VBoxContainer
	tab.visible = true
	var regions := tab.get_node("ConditionSaveRegions") as BoxContainer
	regions.vertical = _layout_profile == UiLayoutProfile.COMPACT
	_bind_metric_region(regions.get_node("ConditionsRegion") as PanelContainer, character.conditions, "No active conditions.")
	_bind_metric_region(regions.get_node("SavingThrowsRegion") as PanelContainer, character.saving_throws)


func _build_equipment(character: CharacterView) -> void:
	var tab := get_node("CharacterSheetWorkspace/CharacterSheetContent/CharacterSheetInventoryMagicTabs/EquipmentTab") as VBoxContainer
	tab.visible = true
	_bind_label(tab.get_node("Header/Detail") as Label, "%d of 30 inventory slots • Load %d/%d" % [character.items.size(), character.carried_load, character.maximum_load], MUTED, 13)
	var empty := tab.get_node("EquipmentEmpty") as Label
	empty.visible = character.items.is_empty()
	_bind_label(empty, "This character carries no items.", MUTED, 15)
	var regions := tab.get_node("EquipmentRegions") as BoxContainer
	regions.visible = not character.items.is_empty()
	regions.vertical = _layout_profile == UiLayoutProfile.COMPACT
	var equipped: Array[ItemView] = []
	var carried: Array[ItemView] = []
	for item: ItemView in character.items:
		(equipped if item.equipped else carried).append(item)
	_bind_item_region(regions.get_node("EquippedItems") as PanelContainer, equipped, "No items are equipped.")
	_bind_item_region(regions.get_node("CarriedItems") as PanelContainer, carried, "No unequipped items are carried.")


func _bind_item_region(frame: PanelContainer, items: Array[ItemView], empty_text: String) -> void:
	var content := frame.get_node("Content") as VBoxContainer
	_bind_label(content.get_node("Header/Count") as Label, "%d item%s" % [items.size(), "" if items.size() == 1 else "s"], MUTED, 13)
	var rows := content.get_node("Items") as VBoxContainer
	_clear(rows)
	if items.is_empty():
		var empty_card := record_card_scene.instantiate() as PanelContainer
		_bind_label(empty_card.get_node("Content/Title") as Label, empty_text, MUTED, 13)
		empty_card.get_node("Content/Subtitle").visible = false
		empty_card.get_node("Content/Detail").visible = false
		rows.add_child(empty_card)
		return
	for item: ItemView in items:
		rows.add_child(_equipment_item_card(item))


func _equipment_item_card(item: ItemView) -> PanelContainer:
	var panel := item_card_scene.instantiate() as PanelContainer
	panel.tooltip_text = "Item instance %s" % item.instance_id
	_bind_media_frame(panel.get_node("Content/Media") as PanelContainer, item.icon_resource_type, item.icon_id, "◈")
	var facts: Array[String] = ["Identified" if item.identified else "Unidentified"]
	if item.charges != 0:
		facts.append("%d charges" % item.charges)
	_bind_label(panel.get_node("Content/Text/Name") as Label, item.name, GOLD, 15)
	_bind_label(panel.get_node("Content/Text/Facts") as Label, " • ".join(facts), Color("e0e2e5"), 13)
	_bind_label(panel.get_node("Content/Text/Meta") as Label, "%d weight • value %d" % [item.weight, item.value], MUTED, 12)
	return panel


func _build_abilities(character: CharacterView) -> void:
	var tab := get_node("CharacterSheetWorkspace/CharacterSheetContent/CharacterSheetStatTabs/AbilitiesTab") as VBoxContainer
	tab.visible = true
	var regions := tab.get_node("AbilityRegions") as BoxContainer
	regions.vertical = _layout_profile == UiLayoutProfile.COMPACT
	_bind_metric_region(regions.get_node("SpecialModifiersRegion") as PanelContainer, character.special_modifiers, "No active special modifiers.")
	_bind_metric_region(regions.get_node("SpecialAbilitiesRegion") as PanelContainer, character.abilities, "No active special abilities.")


func _build_spells(character: CharacterView) -> void:
	var tab := get_node("CharacterSheetWorkspace/CharacterSheetContent/CharacterSheetInventoryMagicTabs/SpellsTab") as VBoxContainer
	tab.visible = true
	var regions := tab.get_node("CharacterSpellRegions") as BoxContainer
	regions.vertical = _layout_profile == UiLayoutProfile.COMPACT
	var known := regions.get_node("KnownSpellRegion/Content") as VBoxContainer
	_bind_label(known.get_node("Header/Detail") as Label, "%d SP available • %d known" % [character.spell_points, character.spells.size()], MUTED, 13)
	var spell_grid := known.get_node("SpellCards") as GridContainer
	_clear(spell_grid)
	if character.spells.is_empty():
		_add_record_card(spell_grid, "This character knows no spells.", "", "")
	else:
		spell_grid.columns = 1 if _layout_profile == UiLayoutProfile.COMPACT else 2
		for spell: SpellView in character.spells:
			spell_grid.add_child(_character_spell_card(spell))
	var scrolls := regions.get_node("ScrollCaseRegion/Content") as VBoxContainer
	_bind_label(scrolls.get_node("Header/Detail") as Label, "%d fixed Classic slots" % character.scrolls.size(), MUTED, 13)
	var scroll_cards := scrolls.get_node("ScrollCards") as VBoxContainer
	_clear(scroll_cards)
	if character.scrolls.is_empty():
		_add_record_card(scroll_cards, "No scroll case slots are available.", "", "")
	for scroll: SpellScrollView in character.scrolls:
		var empty := scroll.spell_id.is_empty()
		_add_record_card(scroll_cards, "Slot %d" % (scroll.slot_index + 1), "Empty" if empty else scroll.spell_name, "" if empty else "Power %d" % scroll.power)


func _character_spell_card(spell: SpellView) -> PanelContainer:
	var panel := spell_card_scene.instantiate() as PanelContainer
	_bind_media_frame(panel.get_node("Content/Media") as PanelContainer, spell.icon_resource_type, spell.icon_id, "✦")
	_bind_label(panel.get_node("Content/Text/Name") as Label, spell.name, GOLD, 15)
	_bind_label(panel.get_node("Content/Text/Facts") as Label, "Level %d • %d SP • Range %d–%d" % [_classic_spell_level(spell), absi(spell.cost), spell.range_min, spell.range_max], Color("e0e2e5"), 12)
	_bind_label(panel.get_node("Content/Text/Description") as Label, spell.description, MUTED, 12)
	return panel


static func _classic_spell_level(spell: SpellView) -> int:
	return ClassicSpellLevel.from_classic_id(spell.classic_id)


func _build_appearance(character: CharacterView) -> void:
	var tab := get_node("CharacterSheetWorkspace/CharacterSheetContent/CharacterSheetIdentityTabs/AppearanceTab") as VBoxContainer
	tab.visible = true
	(tab.get_node("AppearanceRegions") as BoxContainer).vertical = _layout_profile == UiLayoutProfile.COMPACT
	_bind_appearance_region(tab.get_node("AppearanceRegions/PortraitAppearanceRegion") as PanelContainer, character, CharacterAppearanceDefinition.PORTRAIT, _portrait_options, _draft_portrait_id, "Portrait")
	_bind_appearance_region(tab.get_node("AppearanceRegions/CombatIconAppearanceRegion") as PanelContainer, character, CharacterAppearanceDefinition.COMBAT_ICON, _combat_icon_options, _draft_combat_icon_id, "Combat icon")
	var unavailable := tab.get_node("Unavailable") as Label
	unavailable.visible = not _appearance_availability.enabled
	_bind_label(unavailable, _appearance_availability.reason, BAD, 13)
	var discard := tab.get_node("DiscardAppearanceChanges") as Button
	discard.disabled = _draft_portrait_id == character.portrait_id and _draft_combat_icon_id == character.combat_icon_id
	discard.tooltip_text = "The preview already matches the session." if discard.disabled else "Restore both previews without changing the session."
	_clear_pressed_connections(discard)
	if not discard.disabled:
		discard.pressed.connect(_discard_appearance_draft)


func _bind_appearance_region(frame: PanelContainer, character: CharacterView, kind: StringName, options: Array[CharacterAppearanceOptionView], selected_id: String, title: String) -> void:
	var column := frame.get_node("Content") as VBoxContainer
	var role_name := "Portrait" if kind == CharacterAppearanceDefinition.PORTRAIT else "CombatIcon"
	_bind_label(column.get_node("Header/Count") as Label, "%d package choices" % options.size(), MUTED, 13)
	_bind_appearance_media(column.get_node("PreviewCenter/PreviewMedia") as PanelContainer, selected_id, character.name.left(1) if kind == CharacterAppearanceDefinition.PORTRAIT else "⚔", "%s preview" % title)
	var picker := column.get_node("%sPicker" % role_name) as OptionButton
	_clear_option_button(picker)
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
	var apply := column.get_node("Apply%s" % role_name) as Button
	var original_id := character.portrait_id if kind == CharacterAppearanceDefinition.PORTRAIT else character.combat_icon_id
	apply.disabled = not _appearance_availability.enabled or selected_id == original_id
	apply.tooltip_text = _appearance_availability.reason if not _appearance_availability.enabled else "Choose a different %s first." % title.to_lower() if selected_id == original_id else "Commit this %s to the campaign session." % title.to_lower()
	_clear_pressed_connections(apply)
	if not apply.disabled:
		apply.pressed.connect(_apply_appearance.bind(kind, selected_id))


func _bind_appearance_media(frame: PanelContainer, asset_id: String, fallback_text: String, role: String) -> void:
	var image := frame.get_node("Image") as TextureRect
	var fallback := frame.get_node("Fallback") as Label
	var texture := _textures.get(asset_id) as Texture2D
	image.texture = texture
	image.visible = texture != null
	fallback.visible = texture == null
	fallback.text = fallback_text if not fallback_text.is_empty() else "?"
	fallback.tooltip_text = "%s media unavailable." % role if texture == null else role
	_bind_label(fallback, fallback.text, MUTED, 18)


func _clear_option_button(picker: OptionButton) -> void:
	for connection: Dictionary in picker.item_selected.get_connections():
		picker.item_selected.disconnect(connection["callable"] as Callable)
	picker.clear()


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
	var tab := get_node("CharacterSheetWorkspace/CharacterSheetContent/CharacterSheetIdentityTabs/BackgroundTab") as VBoxContainer
	tab.visible = true
	var identities := tab.get_node("RaceClassRegions") as BoxContainer
	identities.vertical = _layout_profile == UiLayoutProfile.COMPACT
	_bind_background_region(identities.get_node("RaceRegion") as PanelContainer, "Race", character.race_name, character.race_description, character.race_traits)
	_bind_background_region(identities.get_node("CasteRegion") as PanelContainer, "Caste", character.caste_name, character.caste_description, character.caste_traits)
	var aging := tab.get_node("AgingRegion") as VBoxContainer
	_bind_label(aging.get_node("Header/Detail") as Label, "Age %d • current band highlighted" % character.age_years, MUTED, 13)
	var bands := aging.get_node("AgeBands") as GridContainer
	_clear(bands)
	bands.columns = 1 if _layout_profile == UiLayoutProfile.COMPACT else 5
	for band: CharacterAgeBandView in character.age_bands:
		var changes: Array[String] = []
		for change: CharacterMetricView in band.changes:
			if change.value != 0:
				changes.append("%s %+d" % [change.name, change.value])
		_add_record_card(bands, "%s%s" % ["Current • " if band.active else "", band.name], "Ages %d–%d" % [band.minimum_age, band.maximum_age], "No changes" if changes.is_empty() else " • ".join(changes))


func _bind_background_region(frame: PanelContainer, kind: String, title: String, description: String, metrics: Array[CharacterMetricView]) -> void:
	var column := frame.get_node("Content") as VBoxContainer
	_bind_label(column.get_node("Header/Title") as Label, title, GOLD, 18)
	_bind_label(column.get_node("Header/Kind") as Label, kind, MUTED, 13)
	_bind_label(column.get_node("Description") as Label, description if not description.is_empty() else "No %s description is present in this package." % kind.to_lower(), MUTED, 13)
	var rows := column.get_node("MetricRows") as VBoxContainer
	_clear(rows)
	_bind_metric_rows(rows, metrics)


func _build_record(character: CharacterView) -> void:
	var tab := get_node("CharacterSheetWorkspace/CharacterSheetContent/CharacterSheetStatTabs/RecordTab") as VBoxContainer
	tab.visible = true
	var panel := tab.get_node("LifetimeRecord") as PanelContainer
	_bind_existing_label("CharacterSheetWorkspace/CharacterSheetContent/CharacterSheetStatTabs/RecordTab/LifetimeRecord/Content/Header/Prestige", "Prestige %d" % character.prestige, MUTED, 13)
	var grid := panel.get_node("Content/RecordCards") as GridContainer
	_clear(grid)
	grid.columns = 2 if _layout_profile == UiLayoutProfile.COMPACT else 4
	var record := character.lifetime_record
	for metric: Dictionary in [{"name": "Damage given", "value": record.damage_given}, {"name": "Damage taken", "value": record.damage_taken}, {"name": "Hits given", "value": record.hits_given}, {"name": "Hits taken", "value": record.hits_taken}, {"name": "Enemy misses", "value": record.enemy_misses}, {"name": "Attacks missed", "value": record.attacks_missed}, {"name": "Kills", "value": record.kills}, {"name": "Deaths", "value": record.deaths}, {"name": "Knockouts", "value": record.knockouts}, {"name": "Spells cast", "value": record.spells_cast}, {"name": "Destroyed", "value": record.destroyed}, {"name": "Turned", "value": record.turns}]:
		_add_record_card(grid, metric["name"], str(metric["value"]), "Lifetime Classic counter")
	var penalty := panel.get_node("Content/PrestigePenalty") as Label
	_bind_label(penalty, "Prestige penalty %d" % character.prestige_penalty, BAD if character.prestige_penalty > 0 else MUTED, 13)


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


func _bind_metric_region(panel: PanelContainer, metrics: Array[CharacterMetricView], empty_text: String = "") -> void:
	var rows := panel.get_node("Content/MetricRows") as GridContainer
	_clear(rows)
	_bind_metric_rows(rows, metrics, empty_text)


func _bind_metric_rows(parent: Container, metrics: Array[CharacterMetricView], empty_text: String = "") -> void:
	if metrics.is_empty() and not empty_text.is_empty():
		var empty_row := metric_row_scene.instantiate() as HBoxContainer
		_bind_label(empty_row.get_node("MetricName") as Label, empty_text, MUTED, 13)
		empty_row.get_node("MetricValue").visible = false
		parent.add_child(empty_row)
		return
	for metric: CharacterMetricView in metrics:
		var row := metric_row_scene.instantiate() as HBoxContainer
		var name_label := row.get_node("MetricName") as Label
		var value_label := row.get_node("MetricValue") as Label
		_bind_label(name_label, metric.name, MUTED, 14)
		_bind_label(value_label, _metric_value_text(metric), GOOD if metric.value > 0 else BAD if metric.value < 0 else Color("e0e2e5"), 14)
		if not metric.detail.is_empty():
			name_label.tooltip_text = metric.detail
			value_label.tooltip_text = metric.detail
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if _layout_profile == UiLayoutProfile.COMPACT else HORIZONTAL_ALIGNMENT_RIGHT
		parent.add_child(row)


func _metric_value_text(metric: CharacterMetricView) -> String:
	if metric.value in [0, 1] and metric.detail in ["Yes", "No"]:
		return metric.detail
	if not metric.detail.is_empty() and metric.name in ["Attacks / Round", "Movement", "Stamina", "Spell Points", "Load"]:
		return metric.detail
	if metric.detail == "Permanent":
		return "Permanent"
	return "%+d" % metric.value if metric.value > 0 else str(metric.value)


func _add_record_card(parent: Container, title: String, subtitle: String, detail: String) -> void:
	var card := record_card_scene.instantiate() as PanelContainer
	_bind_label(card.get_node("Content/Title") as Label, title, GOLD, 16)
	_bind_label(card.get_node("Content/Subtitle") as Label, subtitle, Color("e0e2e5"), 14)
	var detail_label := card.get_node("Content/Detail") as Label
	detail_label.visible = not detail.is_empty()
	_bind_label(detail_label, detail, MUTED, 13)
	parent.add_child(card)


func _bind_media_frame(frame: PanelContainer, resource_type: String, resource_id: int, fallback_text: String) -> void:
	var asset: MediaAsset = _media.asset_by_resource(resource_type, resource_id) if _media != null and resource_id != 0 else null
	var texture := _media.image_texture(asset) if asset != null else null
	var image := frame.get_node("Image") as TextureRect
	var fallback := frame.get_node("Fallback") as Label
	image.texture = texture
	image.visible = texture != null
	fallback.visible = texture == null
	_bind_label(fallback, fallback_text, MUTED, 18)


func _metric(metric_name: String, value: int, detail: String = "") -> CharacterMetricView:
	return CharacterMetricView.new(StringName(metric_name.to_lower().replace(" ", "-")), 0, metric_name, value, detail)


func _bind_label(label: Label, text: String, color: Color = Color.WHITE, font_size: int = 15) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(font_size) * _text_scale)))


func _clear_pressed_connections(button: Button) -> void:
	for connection: Dictionary in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"] as Callable)


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
