class_name SpellsWorkspaceController
extends RefCounted

const SpellSelectionChrome := preload("res://src/presentation/controllers/classic_spell_selection_chrome.gd")

signal intent_submitted(intent: PlayerIntent)
signal route_requested(route_id: StringName)
signal refresh_requested
signal sound_requested(sound_id: int, wait_for_completion: bool, stop_existing: bool)

const GOLD := Color("d5b45d")
const TEXT := Color("e0e2e5")
const MUTED := Color("9aa0a8")
const SECTIONS: Array[StringName] = [&"known", &"fast", &"scrolls"]

var _view: GameView
var _media: ClassicMediaCatalog
var _text_scale: float = 1.0
var _selected_character_id: String = ""
var _selected_spell_id: String = ""
var _section_id: StringName = &"known"
var _selected_level: int = 1
var _selected_power: int = 1
var _compact: bool = false


func set_layout_profile(profile_id: StringName) -> void:
	_compact = profile_id == UiLayoutProfile.COMPACT


func reset() -> void:
	_selected_character_id = ""
	_selected_spell_id = ""
	_section_id = &"known"
	_selected_level = 1
	_selected_power = 1


func present(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	if parent == null or view == null:
		return
	_view = view
	_media = media
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
	match _section_id:
		&"fast":
			_add_fast_spells(parent, character)
		&"scrolls":
			_add_scrolls(parent, character)
		_:
			_add_known_spells(parent, character)


func _selected_character() -> CharacterView:
	for character: CharacterView in _view.party_members:
		if character.id == _selected_character_id:
			return character
	for character: CharacterView in _view.party_members:
		if not character.spells.is_empty():
			_selected_character_id = character.id
			return character
	var fallback: CharacterView = _view.party_members[0]
	_selected_character_id = fallback.id
	return fallback


func _add_character_selector(parent: VBoxContainer, character: CharacterView) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row: BoxContainer = VBoxContainer.new() if _compact else HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var label := _label("Caster", GOLD, 14)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var picker := OptionButton.new()
	picker.name = "SpellCharacterSelector"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for candidate: CharacterView in _view.party_members:
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
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for section_id: StringName in SECTIONS:
			picker.add_item({&"known": "Known spells", &"fast": "Fast spells", &"scrolls": "Scroll case"}[section_id])
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
		button.text = {&"known": "Known", &"fast": "Fast", &"scrolls": "Scrolls"}[section_id]
		button.toggle_mode = true
		button.button_pressed = section_id == _section_id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 34.0
		button.pressed.connect(_select_section.bind(section_id))
		row.add_child(button)
	parent.add_child(row)


func _add_known_spells(parent: VBoxContainer, character: CharacterView) -> void:
	if character.spells.is_empty():
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
	workspace.custom_minimum_size.y = 380.0
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	workspace.add_child(column)
	column.add_child(_build_level_rail(available_levels))
	column.add_child(_build_spell_list(character, spell))
	column.add_child(_spell_detail(character, spell))
	parent.add_child(workspace)


func _build_level_rail(available_levels: Array[int]) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "SpellLevelRail"
	panel.theme_type_variation = &"ClassicInset"
	if _compact:
		var picker := OptionButton.new()
		picker.name = "SpellLevelSelector"
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for level: int in range(1, 8):
			picker.add_item("Spell Level %d" % level)
			picker.set_item_metadata(picker.item_count - 1, level)
			picker.set_item_disabled(picker.item_count - 1, not available_levels.has(level))
			if level == _selected_level:
				picker.select(picker.item_count - 1)
		picker.item_selected.connect(func(index: int) -> void: _select_level(int(picker.get_item_metadata(index))))
		panel.add_child(picker)
		return panel
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	panel.add_child(grid)
	grid.add_child(_ui_art("spells.label.level", Vector2(54.0, 18.0)))
	for level: int in range(1, 8):
		var button := SpellSelectionChrome.level_button(
			level,
			level == _selected_level,
			available_levels.has(level),
			_select_level.bind(level),
			"No known level %d spells" % level
		)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(button)
	return panel


func _build_spell_list(character: CharacterView, selected: SpellView) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "KnownSpellList"
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.y = 132.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.8
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	_add_section_heading(column, "Level %d spells" % _selected_level, "%d known" % _spells_at_level(character, _selected_level).size())
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
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
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(button)
	return panel


func _selected_spell(character: CharacterView) -> SpellView:
	for spell: SpellView in character.spells:
		if spell.id == _selected_spell_id:
			_selected_power = _valid_power(spell, _selected_power)
			return spell
	var fallback: SpellView = character.spells[0]
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
	panel.size_flags_stretch_ratio = 1.2
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	var identity: BoxContainer = VBoxContainer.new() if _compact else HBoxContainer.new()
	identity.add_theme_constant_override("separation", 10)
	if not _compact:
		identity.add_child(_content_icon(spell.icon_resource_type, spell.icon_id))
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_label(title_box, spell.name, Color("e7d078"), 18)
	_add_label(title_box, "Level %d  •  SP %d/%d" % [_spell_level(spell), character.spell_points, character.maximum_spell_points], MUTED, 13)
	identity.add_child(title_box)
	column.add_child(identity)
	var description := _add_label(column, spell.description, TEXT, 14)
	description.max_lines_visible = 4
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var target_row: BoxContainer = VBoxContainer.new() if _compact else HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 10)
	var target_art := _target_art_id(spell)
	if not _compact:
		target_row.add_child(_ui_art(target_art, Vector2(48.0, 48.0)) if not target_art.is_empty() else _target_fallback(spell))
	var facts := GridContainer.new()
	facts.columns = 2
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_fact(facts, "Target", _target_label(spell))
	_add_fact(facts, "Range", str(absi(spell.range_min + spell.range_max * _selected_power)))
	_add_fact(facts, "Damage", _scaled_pair(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max))
	_add_fact(facts, "Duration", _scaled_pair(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, true))
	_add_fact(facts, "Magic resist", _magic_resistance_label(spell))
	_add_fact(facts, "Saving throw", _saving_throw_label(spell))
	target_row.add_child(facts)
	column.add_child(target_row)
	column.add_child(_build_power_rail(spell))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	column.add_child(_build_spell_action_dock(character, spell))
	return panel


func _build_power_rail(spell: SpellView) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "SpellPowerRail"
	panel.theme_type_variation = &"ClassicInset"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	heading.add_child(_ui_art("spells.label.power", Vector2(68.0, 20.0)))
	var cost := _label("Cost %d SP" % absi(spell.cost * _selected_power), GOLD, 14)
	cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(cost)
	column.add_child(heading)
	var powers := GridContainer.new()
	powers.columns = 4
	powers.add_theme_constant_override("h_separation", 3)
	powers.add_theme_constant_override("v_separation", 3)
	column.add_child(powers)
	var available_powers := _available_powers(spell)
	for power: int in range(1, 8):
		var button := Button.new()
		button.name = "SpellPower%d" % power
		button.text = str(power)
		button.toggle_mode = true
		button.button_pressed = power == _selected_power
		button.disabled = not available_powers.has(power)
		button.custom_minimum_size = Vector2(32.0, 32.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "%d SP" % absi(spell.cost * power) if not button.disabled else "This power is unavailable."
		button.pressed.connect(_select_power.bind(power))
		powers.add_child(button)
	return panel


func _build_spell_action_dock(character: CharacterView, spell: SpellView) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.name = "SpellActionDock"
	row.add_theme_constant_override("separation", 5)
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
	var back := _bitmap_action("SpellBackAction", &"spells.action.abort", "Back to adventure", ActionAvailabilityView.new(&"route", true), func() -> void: route_requested.emit(&"exploration"))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(back)
	return row


func _available_levels(character: CharacterView) -> Array[int]:
	var result: Array[int] = []
	for spell: SpellView in character.spells:
		var level := _spell_level(spell)
		if not result.has(level):
			result.append(level)
	result.sort()
	return result


func _spells_at_level(character: CharacterView, level: int) -> Array[SpellView]:
	var result: Array[SpellView] = []
	for spell: SpellView in character.spells:
		if _spell_level(spell) == level:
			result.append(spell)
	result.sort_custom(func(left: SpellView, right: SpellView) -> bool: return left.name.naturalnocasecmp_to(right.name) < 0)
	return result


func _first_spell_at_level(character: CharacterView, level: int) -> SpellView:
	var spells := _spells_at_level(character, level)
	return spells[0] if not spells.is_empty() else character.spells[0]


static func _spell_level(spell: SpellView) -> int:
	if spell.classic_id < 1101:
		return 1
	return clampi(int(spell.classic_id % 1000 / 100), 1, 7)


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


static func _target_art_id(spell: SpellView) -> StringName:
	if spell.target_type == 5 and spell.target_size == 0:
		return &"spells.target.self"
	return {
		9: &"spells.target.all_friendly",
		10: &"spells.target.all_enemy",
		12: &"spells.target.everyone",
	}.get(spell.target_type, &"")


func _target_fallback(spell: SpellView) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size = Vector2(72.0, 72.0)
	var label := _label("TARGET\n%d" % spell.target_type, MUTED, 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


func _add_fact(parent: GridContainer, name: String, value: String) -> void:
	var name_label := _label(name, MUTED, 12)
	name_label.custom_minimum_size.x = 66.0
	parent.add_child(name_label)
	var value_label := _label(value, TEXT, 12)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	_add_section_heading(parent, "%s's Fast Spells" % character.name, "Top-row 1–0")
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
	_add_workspace_back(parent)


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
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("Undefined Spell")
	picker.set_item_metadata(0, {"spellId": "", "power": 0})
	for known_spell: SpellView in character.spells:
		var powers: Array[int] = []
		powers.assign([1] if known_spell.cost < 0 else [1, 2, 3, 4, 5, 6, 7])
		for power: int in powers:
			picker.add_item("%s • P%d" % [known_spell.name, power])
			picker.set_item_metadata(picker.item_count - 1, {"spellId": known_spell.id, "power": power})
			if known_spell.id == binding.spell_id and power == binding.power:
				picker.select(picker.item_count - 1)
	row.add_child(picker)
	var availability := _view.availability(&"set_fast_spell")
	_add_button(row, "Set", availability, _set_fast_spell.bind(character.id, binding.slot_index, picker))
	var clear_availability := availability if not binding.spell_id.is_empty() else ActionAvailabilityView.new(&"set_fast_spell", false, "This slot is already empty.")
	_add_button(row, "Clear", clear_availability, _clear_fast_spell.bind(character.id, binding.slot_index))
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
		_add_intent_action(row, "Use", scroll.use, PlayerIntent.use_scroll(character.id, scroll.slot_index))
		case_column.add_child(panel)
	if character.scrolls.is_empty():
		_add_label(case_column, "This character has no Classic scroll slots.", MUTED)
	parent.add_child(case_panel)
	_add_workspace_back(parent)


func _add_workspace_back(parent: Container) -> void:
	var back := _bitmap_action("SpellWorkspaceBack", &"spells.action.abort", "Back to adventure", ActionAvailabilityView.new(&"route", true), func() -> void: route_requested.emit(&"exploration"))
	parent.add_child(back)


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


func _set_fast_spell(character_id: String, slot_index: int, picker: OptionButton) -> void:
	var selected: Variant = picker.get_selected_metadata()
	if not selected is Dictionary:
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


func _content_icon(resource_type: String, resource_id: int) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(52.0, 52.0)
	var asset: MediaAsset = _media.asset_by_resource(resource_type, resource_id) if _media != null and resource_id != 0 else null
	if asset != null:
		var image := Image.new()
		var bytes := _media.read_bytes(asset)
		var error := ERR_UNAVAILABLE
		match asset.path.get_extension().to_lower():
			"png": error = image.load_png_from_buffer(bytes)
			"jpg", "jpeg": error = image.load_jpg_from_buffer(bytes)
			"webp": error = image.load_webp_from_buffer(bytes)
		if error == OK:
			var texture := TextureRect.new()
			texture.texture = ImageTexture.create_from_image(image)
			texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			texture.tooltip_text = asset.label
			frame.add_child(texture)
			return frame
	var fallback := Label.new()
	fallback.text = "◈\n%d" % resource_id if resource_id != 0 else "◈"
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_theme_color_override("font_color", MUTED)
	frame.add_child(fallback)
	return frame


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
