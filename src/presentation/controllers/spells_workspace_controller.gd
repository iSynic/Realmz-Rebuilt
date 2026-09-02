class_name SpellsWorkspaceController
extends RefCounted

const SpellSelectionChrome := preload("res://src/presentation/controllers/classic_spell_selection_chrome.gd")
const ClassicSpellLevelScript := preload("res://src/presentation/classic_spell_level.gd")
const SpellTargetBadge := preload("res://src/presentation/classic_spell_target_badge.gd")

signal intent_submitted(intent: PlayerIntent)
signal route_requested(route_id: StringName)
signal refresh_requested
signal sound_requested(sound_id: int, wait_for_completion: bool, stop_existing: bool)
signal encounter_spell_selected(character_id: String, classic_spell_id: int)

const GOLD := Color("d5b45d")
const TEXT := Color("e0e2e5")
const MUTED := Color("9aa0a8")
const SECTIONS: Array[StringName] = [&"known", &"fast", &"scrolls"]

var _view: GameView
var _text_scale: float = 1.0
var _selected_character_id: String = ""
var _selected_spell_id: String = ""
var _section_id: StringName = &"known"
var _selected_level: int = 1
var _selected_power: int = 1
var _compact: bool = false
var _encounter_mode: bool = false
var _encounter_spell_ids: Dictionary = {}


func set_layout_profile(profile_id: StringName) -> void:
	_compact = profile_id == UiLayoutProfile.COMPACT


func reset() -> void:
	_selected_character_id = ""
	_selected_spell_id = ""
	_section_id = &"known"
	_selected_level = 1
	_selected_power = 1


func present(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float, fixed_actions: Container = null) -> void:
	if parent == null or view == null:
		return
	_view = view
	_encounter_mode = false
	_encounter_spell_ids.clear()
	_text_scale = maxf(0.1, text_scale)
	if view.party_members.is_empty():
		_add_empty_state(parent, "No spellbooks", "The party has no characters.")
		return
	var character := _selected_character()
	if character == null:
		_add_empty_state(parent, "No spellbooks", "No party member can be selected.")
		return
	_add_character_selector(parent, character)
	_add_section_tabs(parent)
	if view.character_spellcasting_blocked:
		_add_spellcasting_blocked_notice(parent)
	match _section_id:
		&"fast":
			_add_fast_spells(parent, character)
		&"scrolls":
			_add_scrolls(parent, character)
		_:
			_add_known_spells(parent, character, fixed_actions)


func present_encounter(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float, entries: Array[InteractionRequestValue.EncounterCatalogEntry]) -> void:
	if parent == null or view == null:
		return
	_view = view
	_text_scale = maxf(0.1, text_scale)
	_encounter_mode = true
	_encounter_spell_ids.clear()
	for entry: InteractionRequestValue.EncounterCatalogEntry in entries:
		var ids: Array[int] = []
		ids.assign(_encounter_spell_ids.get(entry.character_id, []))
		if not ids.has(entry.classic_id): ids.append(entry.classic_id)
		_encounter_spell_ids[entry.character_id] = ids
	var character := _selected_character()
	if character == null:
		_add_empty_state(parent, "No encounter spells", "No living party member knows an eligible spell.")
		return
	_add_character_selector(parent, character)
	_add_known_spells(parent, character, null)


func _selected_character() -> CharacterView:
	for character: CharacterView in _view.party_members:
		if character.id == _selected_character_id and not _eligible_spells(character).is_empty():
			return character
	for character: CharacterView in _view.party_members:
		if not _eligible_spells(character).is_empty():
			_selected_character_id = character.id
			return character
	if _encounter_mode:
		return null
	var fallback: CharacterView = _view.party_members[0]
	_selected_character_id = fallback.id
	return fallback


func _add_character_selector(parent: VBoxContainer, character: CharacterView) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var label := _label("Caster", GOLD, 14)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var picker := OptionButton.new()
	picker.name = "SpellCharacterSelector"
	picker.theme_type_variation = &"ClassicTheldrowOptionButton"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for candidate: CharacterView in _view.party_members:
		if _encounter_mode and _eligible_spells(candidate).is_empty():
			continue
		picker.add_item("%s  •  SP %d/%d" % [candidate.name, candidate.spell_points, candidate.maximum_spell_points])
		picker.set_item_metadata(picker.item_count - 1, candidate.id)
		if candidate.id == character.id:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int) -> void: _select_character(String(picker.get_item_metadata(index))))
	row.add_child(picker)
	parent.add_child(panel)


func _add_section_tabs(parent: VBoxContainer) -> void:
	if _compact:
		var picker := OptionButton.new()
		picker.name = "SpellSectionSelector"
		picker.theme_type_variation = &"ClassicTheldrowOptionButton"
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for section_id: StringName in SECTIONS:
			picker.add_item({&"known": "Known Spells", &"fast": "Fast Spells (1–0)", &"scrolls": "Scroll Case"}[section_id])
			picker.set_item_metadata(picker.item_count - 1, section_id)
			if section_id == _section_id:
				picker.select(picker.item_count - 1)
		picker.item_selected.connect(func(index: int) -> void: _select_section(picker.get_item_metadata(index) as StringName))
		parent.add_child(picker)
		return
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 5)
	for section_id: StringName in SECTIONS:
		var button := Button.new()
		button.text = {&"known": "Known Spells", &"fast": "Fast Spells (1–0)", &"scrolls": "Scroll Case"}[section_id]
		button.tooltip_text = {&"known": "Browse every spell this character knows.", &"fast": "Assign the ten Classic number-key quick-cast bindings.", &"scrolls": "Use one of the five Classic scroll slots."}[section_id]
		button.toggle_mode = true
		button.button_pressed = section_id == _section_id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 34.0
		button.pressed.connect(_select_section.bind(section_id))
		row.add_child(button)
	parent.add_child(row)


func _add_spellcasting_blocked_notice(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "SpellcastingBlockedNotice"
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := _label("Spellcasting is disabled in this area.", Color("efc85c"), 14)
	label.name = "SpellcastingBlockedNoticeText"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.tooltip_text = "You may inspect spellbooks, Fast Spells, and scrolls, but characters cannot cast while this effect is active."
	panel.add_child(label)
	parent.add_child(panel)


func _add_known_spells(parent: VBoxContainer, character: CharacterView, fixed_actions: Container) -> void:
	if _eligible_spells(character).is_empty():
		_add_empty_state(parent, "No known spells", "%s does not currently know a spell." % character.name)
		return
	var spell := _selected_spell(character)
	var available_levels := _available_levels(character)
	if not available_levels.has(_selected_level):
		_selected_level = _spell_level(spell)
	if _spell_level(spell) != _selected_level:
		spell = _first_spell_at_level(character, _selected_level)
		_selected_spell_id = spell.id
	var workspace := PanelContainer.new()
	workspace.name = "ClassicSpellbookWorkspace"
	workspace.theme_type_variation = &"ClassicInset"
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	workspace.add_child(column)
	var browser := HBoxContainer.new()
	browser.name = "LevelStructuredSpellbook"
	browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser.add_theme_constant_override("separation", 4)
	column.add_child(browser)
	browser.add_child(_build_level_rail(available_levels, spell))
	var records := VBoxContainer.new()
	records.name = "LevelSpellRecords"
	records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	records.size_flags_vertical = Control.SIZE_EXPAND_FILL
	records.add_theme_constant_override("separation", 4)
	records.add_child(_build_spell_list(character, spell))
	records.add_child(_spell_detail(character, spell))
	browser.add_child(records)
	var action_dock := _build_spell_action_dock(character, spell)
	if fixed_actions != null:
		fixed_actions.add_child(action_dock)
	else:
		column.add_child(action_dock)
	parent.add_child(workspace)


func _build_level_rail(available_levels: Array[int], spell: SpellView) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "SpellLevelRail"
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = 78.0 if _compact else 92.0
	panel.size_flags_horizontal = Control.SIZE_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 2 if _compact else 3)
	panel.add_child(rail)
	rail.add_child(SpellSelectionChrome.level_heading())
	for level: int in range(1, 8):
		var button := SpellSelectionChrome.level_button(
			level,
			level == _selected_level,
			available_levels.has(level),
			_select_level.bind(level),
			"No known level %d spells" % level
		)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(74.0 if _compact else 88.0, 24.0)
		rail.add_child(button)
	if not _encounter_mode:
		var divider := HSeparator.new()
		divider.custom_minimum_size.y = 4.0
		rail.add_child(divider)
		rail.add_child(_build_power_rail(spell))
	return panel


func _build_spell_list(character: CharacterView, selected: SpellView) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "KnownSpellList"
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.y = 210.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 2.5
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	_add_section_heading(column, "Level %d spells" % _selected_level, "%d known" % _spells_at_level(character, _selected_level).size())
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 1)
	scroll.add_child(list)
	column.add_child(scroll)
	for candidate: SpellView in _spells_at_level(character, _selected_level):
		var button := SpellSelectionChrome.spell_button(
			"KnownSpell_%s" % candidate.id,
			"%s   %d SP" % [candidate.name, absi(candidate.cost)],
			candidate.id == selected.id,
			true,
			candidate.description,
			_select_spell.bind(candidate.id),
			ClassicUiAssetCatalog.texture(&"spells.button.available" if candidate.id == selected.id else &"spells.button.unavailable")
		)
		button.clip_text = true
		button.custom_minimum_size.y = 21.0
		button.add_theme_font_size_override("font_size", int(round(14.0 * _text_scale)))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _view.character_spellcasting_blocked:
			# Keep the record browsable while making the unavailable casting state
			# unmistakable. The action probe remains the authority for Cast.
			button.modulate = Color(0.58, 0.58, 0.58, 1.0)
			button.tooltip_text = "%s — spellcasting is disabled in this area." % candidate.name
		list.add_child(button)
	return panel


func _selected_spell(character: CharacterView) -> SpellView:
	var eligible := _eligible_spells(character)
	for spell: SpellView in eligible:
		if spell.id == _selected_spell_id:
			_selected_power = _valid_power(spell, _selected_power)
			return spell
	var fallback: SpellView = eligible[0]
	_selected_spell_id = fallback.id
	_selected_level = _spell_level(fallback)
	_selected_power = _valid_power(fallback, 1)
	return fallback


func _spell_detail(character: CharacterView, spell: SpellView) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.name = "SelectedSpellRecord"
	panel.custom_minimum_size.x = 0.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 10)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_label(title_box, spell.name, Color("e7d078"), 16)
	_add_label(title_box, "Level %d  •  SP %d/%d" % [_spell_level(spell), character.spell_points, character.maximum_spell_points], MUTED, 12)
	identity.add_child(title_box)
	column.add_child(identity)
	var description := _add_label(column, spell.description, TEXT, 12)
	description.max_lines_visible = 1
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	description.tooltip_text = spell.description
	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 10)
	if not _compact:
		var target_badge := SpellTargetBadge.new()
		if target_badge.present(spell.target_type, spell.target_size, _target_label(spell), Vector2(48.0, 48.0)):
			target_row.add_child(target_badge)
		else:
			target_badge.free()
	var facts := GridContainer.new()
	facts.columns = 4
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_fact(facts, "Target", _target_label(spell))
	_add_fact(facts, "Range", str(absi(spell.range_min + spell.range_max * _selected_power)))
	_add_fact(facts, "Damage", _scaled_pair(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max))
	_add_fact(facts, "Duration", _scaled_pair(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, true))
	_add_fact(facts, "Magic resist", _magic_resistance_label(spell))
	_add_fact(facts, "Saving throw", _saving_throw_label(spell))
	target_row.add_child(facts)
	column.add_child(target_row)
	return panel


func _build_power_rail(spell: SpellView) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "SpellPowerRail"
	column.add_theme_constant_override("separation", 2)
	column.add_child(_ui_art("spells.label.power", Vector2(68.0, 18.0)))
	var cost := _label("Cost %d SP" % absi(spell.cost * _selected_power), GOLD, 12)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(cost)
	var available_powers := _available_powers(spell)
	for power: int in range(1, 8):
		var button := Button.new()
		button.name = "SpellPower%d" % power
		button.text = str(power)
		button.toggle_mode = true
		button.button_pressed = power == _selected_power
		button.disabled = not available_powers.has(power)
		button.custom_minimum_size = Vector2(0.0, 22.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "%d SP" % absi(spell.cost * power) if not button.disabled else "This power is unavailable."
		button.pressed.connect(_select_power.bind(power))
		column.add_child(button)
	return column


func _build_spell_action_dock(character: CharacterView, spell: SpellView) -> BoxContainer:
	var row := HBoxContainer.new()
	row.name = "SpellActionDock"
	row.add_theme_constant_override("separation", 5)
	if _encounter_mode:
		var choose := _bitmap_action("EncounterSpellChoose", &"spells.action.cast", "Use %s in this encounter" % spell.name, ActionAvailabilityView.new(&"encounter_spell", true, ""), func() -> void: encounter_spell_selected.emit(character.id, spell.classic_id))
		choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(choose)
		return row
	var cast := _bitmap_action("SpellCastAction", &"spells.action.cast", "Cast %s at power %d" % [spell.name, _selected_power], spell.field_cast, func() -> void:
		intent_submitted.emit(PlayerIntent.cast_spell(spell.id, character.id, "", _selected_power))
	)
	cast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cast)
	var make_scroll := Button.new()
	make_scroll.text = "Make Scroll"
	make_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	make_scroll.disabled = spell.make_scroll == null or not spell.make_scroll.enabled or not _available_scroll_powers(spell).has(_selected_power)
	make_scroll.tooltip_text = "Unavailable at this power" if make_scroll.disabled and spell.make_scroll != null and spell.make_scroll.enabled else "Unavailable" if spell.make_scroll == null else spell.make_scroll.reason if make_scroll.disabled else "Scribe at power %d for %d SP" % [_selected_power, absi(spell.cost * 2 * _selected_power)]
	if not make_scroll.disabled:
		make_scroll.pressed.connect(func() -> void: intent_submitted.emit(PlayerIntent.make_scroll(spell.id, character.id, _selected_power)))
	row.add_child(make_scroll)
	return row


func _available_levels(character: CharacterView) -> Array[int]:
	var result: Array[int] = []
	for spell: SpellView in _eligible_spells(character):
		var level := _spell_level(spell)
		if not result.has(level):
			result.append(level)
	result.sort()
	return result


func _spells_at_level(character: CharacterView, level: int) -> Array[SpellView]:
	var result: Array[SpellView] = []
	for spell: SpellView in _eligible_spells(character):
		if _spell_level(spell) == level:
			result.append(spell)
	result.sort_custom(func(left: SpellView, right: SpellView) -> bool: return left.name.naturalnocasecmp_to(right.name) < 0)
	return result


func _eligible_spells(character: CharacterView) -> Array[SpellView]:
	if not _encounter_mode:
		return character.spells
	var classic_ids: Array[int] = []
	classic_ids.assign(_encounter_spell_ids.get(character.id, []))
	var result: Array[SpellView] = []
	for spell: SpellView in character.spells:
		if classic_ids.has(spell.classic_id): result.append(spell)
	return result


func _first_spell_at_level(character: CharacterView, level: int) -> SpellView:
	var spells := _spells_at_level(character, level)
	if not spells.is_empty():
		return spells[0]
	var eligible := _eligible_spells(character)
	return eligible[0] if not eligible.is_empty() else null


static func _spell_level(spell: SpellView) -> int:
	return ClassicSpellLevelScript.from_classic_id(spell.classic_id)


static func _available_powers(spell: SpellView) -> Array[int]:
	if not spell.power_levels.is_empty():
		return spell.power_levels
	var result: Array[int] = [1]
	return result


static func _available_scroll_powers(spell: SpellView) -> Array[int]:
	if not spell.scroll_power_levels.is_empty():
		return spell.scroll_power_levels
	var result: Array[int] = [1]
	return result


static func _valid_power(spell: SpellView, preferred: int) -> int:
	var powers := _available_powers(spell)
	return preferred if powers.has(preferred) else powers[0]


func _scaled_pair(base_min: int, base_max: int, per_power_min: int, per_power_max: int, absolute_values: bool = false) -> String:
	var low := base_min + per_power_min * _selected_power
	var high := base_max + per_power_max * _selected_power
	if absolute_values:
		low = absi(low)
		high = absi(high)
	if low == 0 and high == 0:
		return "—"
	return str(low) if low == high else "%d–%d" % [low, high]


func _magic_resistance_label(spell: SpellView) -> String:
	if spell.damage_type < 1:
		return "Versus"
	if spell.cannot == 1 or spell.cannot > 2:
		return "No"
	if spell.resistance_adjust == 0:
		return "Yes"
	return "%+d" % (_selected_power * spell.resistance_adjust)


func _saving_throw_label(spell: SpellView) -> String:
	if spell.cannot > 1:
		return "No"
	if spell.save_adjust == 0 and spell.save_bonus == 0:
		return "Yes"
	return "%+d" % (spell.save_bonus + _selected_power * spell.save_adjust)


static func _target_label(spell: SpellView) -> String:
	return {
		0: "Up to power targets",
		1: "One party member",
		3: "Fixed battlefield area",
		4: "Power-sized battlefield area",
		5: "Caster",
		6: "Classic target type 6",
		7: "Party state",
		9: "All friendly",
		10: "All enemies",
		11: "Classic target type 11",
		12: "Everybody",
	}.get(spell.target_type, "Classic target type %d" % spell.target_type)


func _add_fact(parent: GridContainer, name: String, value: String) -> void:
	var name_label := _label(name, MUTED, 12)
	name_label.custom_minimum_size.x = 46.0 if _compact else 56.0
	parent.add_child(name_label)
	var value_label := _label(value, TEXT, 12)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.max_lines_visible = 1
	value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value_label.tooltip_text = value
	parent.add_child(value_label)


func _ui_art(asset_id: StringName, minimum_size: Vector2) -> TextureRect:
	var texture := TextureRect.new()
	texture.custom_minimum_size = minimum_size
	texture.texture = ClassicUiAssetCatalog.texture(asset_id)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return texture


func _bitmap_action(node_name: String, asset_id: StringName, tooltip: String, availability: ActionAvailabilityView, callback: Callable) -> ClassicBitmapButton:
	var button := ClassicBitmapButton.new()
	button.name = node_name
	button.configure({"id": asset_id, "asset_id": asset_id, "tooltip": tooltip, "accelerator": ""}, 1)
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if button.disabled else tooltip
	if not button.disabled:
		button.pressed.connect(callback)
	return button


func _add_fast_spells(parent: VBoxContainer, character: CharacterView) -> void:
	_add_section_heading(parent, "%s's Fast Spell bindings" % character.name, "Top-row 1–0")
	var explanation := _add_label(parent, "Choosing a spell assigns it immediately. Clear removes it; Back keeps every assigned slot.", MUTED, 13)
	explanation.max_lines_visible = 2
	if character.fast_spells.is_empty():
		_add_empty_state(parent, "No Fast Spell slots", "This character has no Fast Spell bindings.")
	else:
		var panel := PanelContainer.new()
		panel.name = "FastSpellGrid"
		panel.theme_type_variation = &"ClassicInset"
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var grid := GridContainer.new()
		grid.columns = 1
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 5)
		panel.add_child(grid)
		for binding: FastSpellBindingView in character.fast_spells:
			_add_fast_spell_row(grid, character, binding)
		parent.add_child(panel)


func _add_fast_spell_row(parent: Container, character: CharacterView, binding: FastSpellBindingView) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row: BoxContainer = VBoxContainer.new() if _compact else HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var label := _add_label(row, "Slot %s" % binding.shortcut_label, GOLD, 13)
	label.custom_minimum_size.x = 0.0 if _compact else 52.0
	var picker := OptionButton.new()
	picker.name = "FastSpellPicker%d" % binding.slot_index
	picker.theme_type_variation = &"ClassicTheldrowOptionButton"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.fit_to_longest_item = false
	picker.add_item("Choose a spell")
	picker.set_item_metadata(0, {})
	for known_spell: SpellView in character.spells:
		var powers: Array[int] = []
		powers.assign([1] if known_spell.cost < 0 else [1, 2, 3, 4, 5, 6, 7])
		for power: int in powers:
			picker.add_item("%s • P%d" % [known_spell.name, power])
			picker.set_item_metadata(picker.item_count - 1, {"spellId": known_spell.id, "power": power})
			if known_spell.id == binding.spell_id and power == binding.power:
				picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int) -> void: _assign_fast_spell(character.id, binding.slot_index, picker.get_item_metadata(index)))
	row.add_child(picker)
	var availability := _view.availability(&"set_fast_spell")
	var clear_availability := availability if not binding.spell_id.is_empty() else ActionAvailabilityView.new(&"set_fast_spell", false, "This slot is already empty.")
	var clear := _add_button(row, "Clear", clear_availability, _clear_fast_spell.bind(character.id, binding.slot_index))
	clear.custom_minimum_size.x = 56.0
	parent.add_child(panel)


func _add_scrolls(parent: VBoxContainer, character: CharacterView) -> void:
	_add_section_heading(parent, "%s's Scroll Case" % character.name, "Five fixed Classic slots")
	var case_panel := PanelContainer.new()
	case_panel.name = "SpellScrollCase"
	case_panel.theme_type_variation = &"ClassicInset"
	case_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var case_column := VBoxContainer.new()
	case_column.add_theme_constant_override("separation", 5)
	case_panel.add_child(case_column)
	for scroll: SpellScrollView in character.scrolls:
		var panel := PanelContainer.new()
		panel.theme_type_variation = &"ClassicInset"
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row: BoxContainer = VBoxContainer.new() if _compact else HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		panel.add_child(row)
		var text := "Slot %d  •  %s%s" % [scroll.slot_index + 1, scroll.spell_name, "" if scroll.power == 0 else "  •  Power %d" % scroll.power]
		var label := _add_label(row, text, MUTED if scroll.power == 0 else Color("e0e2e5"), 14)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var use := _add_intent_action(row, "Use", scroll.use, PlayerIntent.use_scroll(character.id, scroll.slot_index))
		use.name = "UseScroll%d" % scroll.slot_index
		var discard := _add_intent_action(row, "Discard", scroll.discard, PlayerIntent.use_scroll(character.id, scroll.slot_index))
		discard.name = "DiscardScroll%d" % scroll.slot_index
		case_column.add_child(panel)
	if character.scrolls.is_empty():
		_add_label(case_column, "This character has no Classic scroll slots.", MUTED)
	parent.add_child(case_panel)


func _select_character(character_id: String) -> void:
	_selected_character_id = character_id
	_selected_spell_id = ""
	_selected_level = 1
	_selected_power = 1
	refresh_requested.emit()


func _select_section(section_id: StringName) -> void:
	_section_id = section_id
	refresh_requested.emit()


func _select_spell(spell_id: String) -> void:
	_selected_spell_id = spell_id
	var character := _selected_character()
	if character != null:
		var spell := _selected_spell(character)
		_selected_level = _spell_level(spell)
		_selected_power = _valid_power(spell, 1)
	refresh_requested.emit()


func _select_level(level: int) -> void:
	_selected_level = level
	var character := _selected_character()
	if character != null:
		var spell := _first_spell_at_level(character, level)
		_selected_spell_id = spell.id
		_selected_power = _valid_power(spell, 1)
	refresh_requested.emit()


func _select_power(power: int) -> void:
	_selected_power = power
	refresh_requested.emit()


func _assign_fast_spell(character_id: String, slot_index: int, selected: Variant) -> void:
	if not selected is Dictionary or selected.is_empty():
		return
	sound_requested.emit(144, false, false)
	intent_submitted.emit(PlayerIntent.set_fast_spell(character_id, slot_index, String(selected.get("spellId", "")), int(selected.get("power", 0))))


func _clear_fast_spell(character_id: String, slot_index: int) -> void:
	sound_requested.emit(144, false, false)
	intent_submitted.emit(PlayerIntent.set_fast_spell(character_id, slot_index))


func _add_intent_action(parent: Container, label: String, availability: ActionAvailabilityView, intent: PlayerIntent) -> Button:
	return _add_button(parent, label, availability, func() -> void: intent_submitted.emit(intent))


func _add_button(parent: Container, label: String, availability: ActionAvailabilityView, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(74.0, 34.0)
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if not availability.enabled else label
	if not button.disabled:
		button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _add_section_heading(parent: Container, title: String, detail: String = "") -> void:
	var row := HBoxContainer.new()
	var heading := _label(title, GOLD, 18)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	if not detail.is_empty() and not _compact:
		var note := _label(detail, MUTED, 13)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(note)
	parent.add_child(row)


func _add_empty_state(parent: Container, title: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	var column := VBoxContainer.new()
	panel.add_child(column)
	column.add_child(_label(title, GOLD, 16))
	var body := _label(detail, MUTED, 13)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)
	parent.add_child(panel)


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var result := _label(text, color, size)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(result)
	return result


func _label(text: String, color: Color, size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_color_override("font_color", color)
	result.add_theme_font_size_override("font_size", int(round(float(size) * _text_scale)))
	return result
