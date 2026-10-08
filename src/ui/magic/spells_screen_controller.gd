## Binds spellbooks, scrolls, and casting choices to the Spells screen.
class_name SpellsScreenController
extends RefCounted

const SpellSelectionChrome := preload("res://src/ui/magic/classic_spell_selection_chrome.gd")
const DetailFormatter := preload("res://src/ui/magic/spell_detail_formatter.gd")
const WORKSPACE_SCENE_PATH := "res://src/ui/magic/spells_workspace.tscn"

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
var _controller_focus_root: Control
var _spell_by_level_by_character: Dictionary = {}
var _last_level_by_character: Dictionary = {}
var _power_by_spell: Dictionary = {}
var _controller_level_changed: bool = false
var controller_browses_levels: bool:
	get: return _section_id == &"known"


func set_layout_profile(profile_id: StringName) -> void:
	_compact = profile_id == UiLayoutProfile.COMPACT


func reset() -> void:
	_selected_character_id = ""
	_selected_spell_id = ""
	_section_id = &"known"
	_selected_level = 1
	_selected_power = 1
	_spell_by_level_by_character.clear()
	_last_level_by_character.clear()
	_power_by_spell.clear()
	_controller_focus_root = null
	_controller_level_changed = false


## Returns the active ordinary screen or Encounter container, including its
## authored fixed actions and exit control.
func controller_focus_root() -> Control:
	if _controller_focus_root == null or not is_instance_valid(_controller_focus_root) or not _controller_focus_root.is_visible_in_tree():
		return null
	return _controller_focus_root


## Focuses the currently selected known spell after route entry. Call only
## after the screen has finished presenting its current section.
func focus_selected_spell() -> bool:
	var root := controller_focus_root()
	if root == null or _section_id != &"known":
		return false
	var selected := root.find_child("KnownSpell_%s" % _selected_spell_id.validate_node_name(), true, false) as Control
	if selected == null or not selected.is_visible_in_tree() or selected.focus_mode == Control.FOCUS_NONE:
		selected = root.find_child("EncounterCatalogCancel" if _encounter_mode else "RouteBackAction", true, false) as Control
	if selected == null or not selected.is_visible_in_tree():
		return false
	selected.grab_focus()
	SpellsWorkspace.reveal_controller_focus(selected)
	return true


## Moves among populated spell levels, wrapping in either direction.
func controller_cycle_section(delta: int) -> bool:
	if delta == 0 or _view == null:
		return false
	if _section_id != &"known":
		return navigate_section(&"", delta)
	var character := _selected_character()
	if character == null:
		return false
	var levels := _available_levels(character)
	if levels.is_empty():
		return false
	var current_index := levels.find(_selected_level)
	if current_index < 0:
		current_index = 0 if delta > 0 else levels.size() - 1
	_controller_level_changed = true
	_select_level(int(levels[posmod(current_index + (1 if delta > 0 else -1), levels.size())]))
	return true


func restore_controller_focus(opened: bool) -> void:
	var root := controller_focus_root()
	var owner := root.get_viewport().gui_get_focus_owner() if root != null else null
	if owner != null and owner.is_visible_in_tree() and not root.is_ancestor_of(owner) and (not opened or not _encounter_mode):
		_controller_level_changed = false
		return
	if opened or _controller_level_changed or owner is BaseButton and (owner as BaseButton).disabled:
		focus_selected_spell()
	_controller_level_changed = false


func navigate_section(section_name: StringName, delta: int = 0) -> bool:
	var next := StringName(String(section_name).to_lower()) if not section_name.is_empty() else SECTIONS[posmod(SECTIONS.find(_section_id) + delta, SECTIONS.size())]
	if next not in SECTIONS or _encounter_mode: return false
	_select_section(next)
	return true


func present(target: Control, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	if target == null or view == null:
		return
	var screen := target as SpellsScreen
	var fixed_actions := screen.context_action_control() if screen != null else null
	var workspace: SpellsWorkspace
	if screen != null:
		if _controller_focus_root != screen.controller_focus_root():
			_controller_level_changed = true
		_controller_focus_root = screen.controller_focus_root()
		workspace = screen.workspace()
	else:
		_controller_focus_root = target as Control
		var parent := target as VBoxContainer
		_clear(parent)
		workspace = (load(WORKSPACE_SCENE_PATH) as PackedScene).instantiate() as SpellsWorkspace
		parent.add_child(workspace)
	_view = view
	_encounter_mode = false
	_encounter_spell_ids.clear()
	_text_scale = maxf(0.1, text_scale)
	workspace.prepare(_compact)
	if fixed_actions != null:
		fixed_actions.get_node("SpellActionDock").visible = false
	if view.party_members.is_empty():
		workspace.show_empty("No spellbooks", "The party has no characters.")
		SpellsWorkspace.link_controller_focus(_controller_focus_root)
		return
	var character := _selected_character()
	if character == null:
		workspace.show_empty("No spellbooks", "No party member can be selected.")
		SpellsWorkspace.link_controller_focus(_controller_focus_root)
		return
	_bind_character_selector(workspace, character)
	_bind_section_tabs(workspace)
	if view.character_spellcasting_blocked:
		workspace.blocked_notice().visible = true
	match _section_id:
		&"fast":
			_bind_fast_spells(workspace, character)
		&"scrolls":
			_bind_scrolls(workspace, character)
		_:
			_bind_known_spells(workspace, character, fixed_actions)
	SpellsWorkspace.link_controller_focus(_controller_focus_root)


func present_encounter(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float, entries: Array[InteractionRequestValue.EncounterCatalogEntry]) -> void:
	if parent == null or view == null:
		return
	_view = view
	var encounter_root := parent.get_parent() as Control
	_controller_focus_root = encounter_root if encounter_root != null else parent
	_clear(parent)
	var workspace := (load(WORKSPACE_SCENE_PATH) as PackedScene).instantiate() as SpellsWorkspace
	parent.add_child(workspace)
	_text_scale = maxf(0.1, text_scale)
	_encounter_mode = true
	_encounter_spell_ids.clear()
	for entry: InteractionRequestValue.EncounterCatalogEntry in entries:
		var ids: Array[int] = []
		ids.assign(_encounter_spell_ids.get(entry.character_id, []))
		if not ids.has(entry.classic_id): ids.append(entry.classic_id)
		_encounter_spell_ids[entry.character_id] = ids
	workspace.prepare(_compact, true)
	workspace.get_node("Sections").visible = false
	var character := _selected_character()
	if character == null:
		workspace.show_empty("No encounter spells", "No living party member knows an eligible spell.")
		SpellsWorkspace.link_controller_focus(_controller_focus_root)
		return
	_bind_character_selector(workspace, character)
	_bind_known_spells(workspace, character, null)
	SpellsWorkspace.link_controller_focus(_controller_focus_root)


func _selected_character() -> CharacterView:
	for character: CharacterView in _view.party_members:
		if character.id == _selected_character_id and (not _encounter_mode or not _eligible_spells(character).is_empty()):
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


func _bind_character_selector(workspace: SpellsWorkspace, character: CharacterView) -> void:
	var picker := workspace.caster_picker()
	_clear_option_button(picker)
	for candidate: CharacterView in _view.party_members:
		if _encounter_mode and _eligible_spells(candidate).is_empty():
			continue
		picker.add_item("%s  •  SP %d/%d" % [candidate.name, candidate.spell_points, candidate.maximum_spell_points])
		picker.set_item_metadata(picker.item_count - 1, candidate.id)
		if candidate.id == character.id:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int) -> void: _select_character(String(picker.get_item_metadata(index))))
	picker.tooltip_text = picker.get_item_text(picker.selected)


func _bind_section_tabs(workspace: SpellsWorkspace) -> void:
	var picker := workspace.compact_section_picker()
	_clear_option_button(picker)
	for section_id: StringName in SECTIONS:
		var label: String = {&"known": "Known Spells", &"fast": "Fast Spells (1–0)", &"scrolls": "Scroll Case"}[section_id]
		picker.add_item(label)
		picker.set_item_metadata(picker.item_count - 1, section_id)
		if section_id == _section_id:
			picker.select(picker.item_count - 1)
		var button := workspace.wide_sections().get_node({&"known": "Known", &"fast": "Fast", &"scrolls": "Scrolls"}[section_id]) as Button
		button.button_pressed = section_id == _section_id
		_clear_pressed_connections(button)
		button.pressed.connect(_select_section.bind(section_id))
	picker.item_selected.connect(func(index: int) -> void: _select_section(picker.get_item_metadata(index) as StringName))


func _bind_known_spells(workspace: SpellsWorkspace, character: CharacterView, fixed_actions: Container) -> void:
	workspace.show_section(&"known")
	if _eligible_spells(character).is_empty():
		workspace.show_empty("No known spells", "%s does not currently know a spell." % character.name)
		return
	var spell := _selected_spell(character)
	var available_levels := _available_levels(character)
	if not available_levels.has(_selected_level):
		_selected_level = DetailFormatter.level(spell)
	if DetailFormatter.level(spell) != _selected_level:
		spell = _first_spell_at_level(character, _selected_level)
		_selected_spell_id = spell.id
	_bind_level_rail(workspace, available_levels, spell)
	_bind_spell_list(workspace, character, spell)
	_bind_spell_detail(workspace, character, spell)
	var action_host := fixed_actions if fixed_actions != null else workspace.known_action_host()
	_bind_spell_action_dock(action_host.get_node("SpellActionDock") as HBoxContainer, character, spell)


func _bind_level_rail(workspace: SpellsWorkspace, available_levels: Array[int], spell: SpellView) -> void:
	var panel := workspace.get_node("ClassicSpellbookWorkspace/Content/LevelStructuredSpellbook/SpellLevelRail") as PanelContainer
	UiSizing.minimum_size(panel, Vector2(78.0 if _compact else 92.0, 0.0))
	var rail := workspace.level_rail()
	UiSizing.constant(rail, &"separation", 2 if _compact else 3)
	(rail.get_node("SpellLevelHeading") as TextureRect).texture = ClassicUiAssetCatalog.texture(&"spells.label.level")
	for level: int in range(1, 8):
		var button := rail.get_node("LevelButtons/SpellLevel%d" % level) as Button
		button.set_meta(&"focus_key", "spells:level:%d" % level)
		SpellSelectionChrome.bind_level_button(
			button,
			level,
			level == _selected_level,
			available_levels.has(level),
			_select_level.bind(level),
			"No known level %d spells" % level
		)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiSizing.minimum_size(button, Vector2(31.0 if _compact else 88.0, 24.0))
		if _compact:
			button.text = str(level)
	(rail.get_node("PowerDivider") as HSeparator).visible = not _encounter_mode
	workspace.power_rail().visible = not _encounter_mode
	if not _encounter_mode:
		_bind_power_rail(workspace.power_rail(), spell)


func _bind_spell_list(workspace: SpellsWorkspace, character: CharacterView, selected: SpellView) -> void:
	var panel := workspace.get_node("ClassicSpellbookWorkspace/Content/LevelStructuredSpellbook/LevelSpellRecords/KnownSpellList") as PanelContainer
	_bind_label(panel.get_node("Content/Header/Title") as Label, "Level %d spells" % _selected_level, GOLD, 18)
	_bind_label(panel.get_node("Content/Header/Count") as Label, str(_spells_at_level(character, _selected_level).size()) if _compact else "%d known" % _spells_at_level(character, _selected_level).size(), MUTED, 13)
	var list := workspace.known_spell_list()
	_clear(list)
	for candidate: SpellView in _spells_at_level(character, _selected_level):
		var button := workspace.known_spell_button_scene.instantiate() as Button
		SpellSelectionChrome.bind_spell_button(
			button,
			"KnownSpell_%s" % candidate.id,
			"%s   %d SP" % [candidate.name, absi(candidate.cost)],
			candidate.id == selected.id,
			true,
			candidate.description,
			_select_spell.bind(candidate.id),
			ClassicUiAssetCatalog.texture(&"spells.button.available" if candidate.id == selected.id else &"spells.button.unavailable")
		)
		button.clip_text = true
		button.set_meta(&"focus_key", "spells:known:selected" if candidate.id == selected.id else "spells:known:%s:%s" % [character.id, candidate.id])
		UiSizing.minimum_size(button, Vector2(0.0, 21.0))
		UiSizing.font_size(button, &"font_size", 14)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _view.character_spellcasting_blocked:
			# Keep the record browsable while making the unavailable casting state
			# unmistakable. The action probe remains the authority for Cast.
			button.modulate = Color(0.58, 0.58, 0.58, 1.0)
			button.tooltip_text = "%s — spellcasting is disabled in this area." % candidate.name
		list.add_child(button)


func _selected_spell(character: CharacterView) -> SpellView:
	var eligible := _eligible_spells(character)
	if eligible.is_empty():
		return null
	var character_levels: Dictionary = _spell_by_level_by_character.get(character.id, {})
	var remembered_id := String(character_levels.get(_selected_level, ""))
	for spell: SpellView in eligible:
		if DetailFormatter.level(spell) == _selected_level and (spell.id == remembered_id or spell.id == _selected_spell_id):
			_selected_spell_id = spell.id
			_selected_power = DetailFormatter.valid_power(spell, int(_power_by_spell.get(spell.id, _selected_power)))
			_power_by_spell[spell.id] = _selected_power
			_last_level_by_character[character.id] = _selected_level
			_remember_spell_selection(character.id, _selected_level, spell.id)
			return spell
	var fallback := _first_spell_at_level(character, _selected_level)
	if fallback == null:
		fallback = eligible[0]
	_selected_spell_id = fallback.id
	_selected_level = DetailFormatter.level(fallback)
	_selected_power = DetailFormatter.valid_power(fallback, int(_power_by_spell.get(fallback.id, 1)))
	_power_by_spell[fallback.id] = _selected_power
	_last_level_by_character[character.id] = _selected_level
	_remember_spell_selection(character.id, _selected_level, fallback.id)
	return fallback


func _remember_spell_selection(character_id: String, level: int, spell_id: String) -> void:
	var levels: Dictionary = _spell_by_level_by_character.get(character_id, {})
	levels[level] = spell_id
	_spell_by_level_by_character[character_id] = levels


func _bind_spell_detail(workspace: SpellsWorkspace, character: CharacterView, spell: SpellView) -> void:
	var panel := workspace.selected_spell_record()
	var column := panel.get_node("Content") as VBoxContainer
	_bind_label(column.get_node("Name") as Label, spell.name, Color("e7d078"), 16)
	_bind_label(column.get_node("Resource") as Label, "Level %d  •  SP %d/%d" % [DetailFormatter.level(spell), character.spell_points, character.maximum_spell_points], MUTED, 12)
	var description := column.get_node("Description") as Label
	_bind_label(description, spell.description, TEXT, 12)
	description.tooltip_text = spell.description
	var target_badge := column.get_node("TargetAndFacts/ClassicSpellTargetBadge") as ClassicSpellTargetBadge
	var target_label := DetailFormatter.target_label(spell)
	target_badge.visible = not _compact and target_badge.present(spell.target_type, spell.target_size, target_label, Vector2(48.0, 48.0))
	var values := {
		"TargetValue": target_label,
		"RangeValue": str(absi(spell.range_min + spell.range_max * _selected_power)),
		"DamageValue": DetailFormatter.scaled_pair(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, _selected_power),
		"DurationValue": DetailFormatter.scaled_pair(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, _selected_power, true),
		"MagicResistValue": DetailFormatter.magic_resistance_label(spell, _selected_power),
		"SavingThrowValue": DetailFormatter.saving_throw_label(spell, _selected_power),
	}
	var facts := column.get_node("TargetAndFacts/Facts") as GridContainer
	for node_name: String in values:
		var value_label := facts.get_node(node_name) as Label
		_bind_label(value_label, values[node_name], TEXT, 12)
		value_label.tooltip_text = values[node_name]
	for name_node: String in ["TargetName", "RangeName", "DamageName", "DurationName", "MagicResistName", "SavingThrowName"]:
		_bind_label(facts.get_node(name_node) as Label, (facts.get_node(name_node) as Label).text, MUTED, 12)


func _bind_power_rail(column: VBoxContainer, spell: SpellView) -> void:
	(column.get_node("PowerLabel") as TextureRect).texture = ClassicUiAssetCatalog.texture(&"spells.label.power")
	_bind_label(column.get_node("Cost") as Label, "Cost %d SP" % absi(spell.cost * _selected_power), GOLD, 12)
	var available_powers := DetailFormatter.available_powers(spell)
	for power: int in range(1, 8):
		var button := column.get_node("PowerButtons/SpellPower%d" % power) as Button
		button.set_meta(&"focus_key", "spells:power:%s:%d" % [_selected_spell_id, power])
		button.button_pressed = power == _selected_power
		button.disabled = not available_powers.has(power)
		button.tooltip_text = "%d SP" % absi(spell.cost * power) if not button.disabled else "This power is unavailable."
		_clear_pressed_connections(button)
		button.pressed.connect(_select_power.bind(power))


func _bind_spell_action_dock(row: HBoxContainer, character: CharacterView, spell: SpellView) -> void:
	row.visible = true
	var cast := row.get_node("SpellCastAction") as ClassicBitmapButton
	if _encounter_mode:
		cast.name = "EncounterSpellChoose"
		_bind_bitmap_action(cast, &"spells.action.cast", "Use %s in this encounter" % spell.name, ActionAvailabilityView.new(&"encounter_spell", true, ""), func() -> void: encounter_spell_selected.emit(character.id, spell.classic_id))
		row.get_node("MakeScrollAction").visible = false
		return
	_bind_bitmap_action(cast, &"spells.action.cast", "Cast %s at power %d" % [spell.name, _selected_power], spell.field_cast, func() -> void:
		intent_submitted.emit(MagicIntents.cast(spell.id, character.id, "", _selected_power))
	)
	var make_scroll := row.get_node("MakeScrollAction") as Button
	make_scroll.text = "Scroll" if _compact else "Make Scroll"
	UiSizing.minimum_size(make_scroll, Vector2(60.0 if _compact else 74.0, 0.0))
	make_scroll.disabled = spell.make_scroll == null or not spell.make_scroll.enabled or not DetailFormatter.available_scroll_powers(spell).has(_selected_power)
	make_scroll.tooltip_text = "Unavailable at this power" if make_scroll.disabled and spell.make_scroll != null and spell.make_scroll.enabled else "Unavailable" if spell.make_scroll == null else spell.make_scroll.reason if make_scroll.disabled else "Scribe at power %d for %d SP" % [_selected_power, absi(spell.cost * 2 * _selected_power)]
	_clear_pressed_connections(make_scroll)
	if not make_scroll.disabled:
		make_scroll.pressed.connect(func() -> void: intent_submitted.emit(MagicIntents.make_scroll(spell.id, character.id, _selected_power)))


func _available_levels(character: CharacterView) -> Array[int]:
	var result: Array[int] = []
	for spell: SpellView in _eligible_spells(character):
		var level := DetailFormatter.level(spell)
		if not result.has(level):
			result.append(level)
	result.sort()
	return result


func _spells_at_level(character: CharacterView, level: int) -> Array[SpellView]:
	var result: Array[SpellView] = []
	for spell: SpellView in _eligible_spells(character):
		if DetailFormatter.level(spell) == level:
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


func _bind_fast_spells(workspace: SpellsWorkspace, character: CharacterView) -> void:
	workspace.show_section(&"fast")
	_bind_label(workspace.get_node("FastSection/Header/Title") as Label, "%s's Fast Spell bindings" % character.name, GOLD, 18)
	var detail := workspace.get_node("FastSection/Header/Detail") as Label
	detail.visible = not _compact
	_bind_label(detail, "Top-row 1–0", MUTED, 13)
	_bind_label(workspace.get_node("FastSection/Explanation") as Label, "Choosing a spell assigns it immediately. Clear removes it; Back keeps every assigned slot.", MUTED, 13)
	var grid := workspace.get_node("FastSection/FastSpellGrid") as PanelContainer
	var empty := workspace.get_node("FastSection/Empty") as Label
	grid.visible = not character.fast_spells.is_empty()
	empty.visible = character.fast_spells.is_empty()
	if character.fast_spells.is_empty():
		_bind_label(empty, "This character has no Fast Spell bindings.", MUTED, 15)
		return
	for binding: FastSpellBindingView in character.fast_spells:
		_bind_fast_spell_row(workspace, character, binding)


func _bind_fast_spell_row(workspace: SpellsWorkspace, character: CharacterView, binding: FastSpellBindingView) -> void:
	var panel := workspace.fast_spell_rows().get_node("FastSpellSlot%d" % binding.slot_index) as PanelContainer
	panel.visible = true
	var row := panel.get_node("Content") as BoxContainer
	row.vertical = _compact
	var label := row.get_node("Slot") as Label
	_bind_label(label, "Slot %s" % binding.shortcut_label, GOLD, 13)
	UiSizing.minimum_size(label, Vector2(0.0 if _compact else 52.0, 0.0))
	var picker := row.get_node("FastSpellPicker%d" % binding.slot_index) as OptionButton
	_clear_option_button(picker)
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
	var availability := _view.availability(&"set_fast_spell")
	var clear_availability := availability if not binding.spell_id.is_empty() else ActionAvailabilityView.new(&"set_fast_spell", false, "This slot is already empty.")
	_bind_button(row.get_node("Clear") as Button, "Clear", clear_availability, _clear_fast_spell.bind(character.id, binding.slot_index))


func _bind_scrolls(workspace: SpellsWorkspace, character: CharacterView) -> void:
	workspace.show_section(&"scrolls")
	_bind_label(workspace.get_node("ScrollSection/Header/Title") as Label, "%s's Scroll Case" % character.name, GOLD, 18)
	var detail := workspace.get_node("ScrollSection/Header/Detail") as Label
	detail.visible = not _compact
	_bind_label(detail, "Five fixed Classic slots", MUTED, 13)
	var case_panel := workspace.get_node("ScrollSection/SpellScrollCase") as PanelContainer
	var empty := workspace.get_node("ScrollSection/Empty") as Label
	case_panel.visible = not character.scrolls.is_empty()
	empty.visible = character.scrolls.is_empty()
	if character.scrolls.is_empty():
		_bind_label(empty, "This character has no Classic scroll slots.", MUTED, 15)
		return
	for scroll: SpellScrollView in character.scrolls:
		var panel := workspace.scroll_rows().get_node("ScrollCaseSlot%d" % scroll.slot_index) as PanelContainer
		panel.visible = true
		var row := panel.get_node("Content") as BoxContainer
		row.vertical = _compact
		var text := "Slot %d  •  %s%s" % [scroll.slot_index + 1, scroll.spell_name, "" if scroll.power == 0 else "  •  Power %d" % scroll.power]
		_bind_label(row.get_node("Record") as Label, text, MUTED if scroll.power == 0 else TEXT, 14)
		var use := row.get_node("UseScroll%d" % scroll.slot_index) as Button
		_bind_button(use, "Use", scroll.use, func() -> void: intent_submitted.emit(MagicIntents.use_scroll(character.id, scroll.slot_index)))
		var discard := row.get_node("DiscardScroll%d" % scroll.slot_index) as Button
		_bind_button(discard, "Discard", scroll.discard, func() -> void: intent_submitted.emit(MagicIntents.use_scroll(character.id, scroll.slot_index)))


func _select_character(character_id: String) -> void:
	_selected_character_id = character_id
	var levels: Dictionary = _spell_by_level_by_character.get(character_id, {})
	_selected_level = int(_last_level_by_character.get(character_id, 1))
	_selected_spell_id = String(levels.get(_selected_level, ""))
	_selected_power = int(_power_by_spell.get(_selected_spell_id, 1))
	refresh_requested.emit()


func _select_section(section_id: StringName) -> void:
	_section_id = section_id
	refresh_requested.emit()


func _select_spell(spell_id: String) -> void:
	_selected_spell_id = spell_id
	var character := _selected_character()
	if character != null:
		var focused_spell := _controller_focus_root.find_child("KnownSpell_%s" % spell_id.validate_node_name(), true, false) as Control if _controller_focus_root != null and is_instance_valid(_controller_focus_root) else null
		if focused_spell != null:
			focused_spell.set_meta(&"focus_key", "spells:known:selected")
		for spell: SpellView in _eligible_spells(character):
			if spell.id != spell_id:
				continue
			_selected_level = DetailFormatter.level(spell)
			_selected_power = DetailFormatter.valid_power(spell, int(_power_by_spell.get(spell.id, 1)))
			_power_by_spell[spell.id] = _selected_power
			_last_level_by_character[character.id] = _selected_level
			_remember_spell_selection(character.id, _selected_level, spell.id)
			break
	refresh_requested.emit()


func _select_level(level: int) -> void:
	_selected_level = level
	var character := _selected_character()
	if character != null:
		var spell := _first_spell_at_level(character, level)
		if spell != null:
			var levels: Dictionary = _spell_by_level_by_character.get(character.id, {})
			var remembered_id := String(levels.get(level, ""))
			for candidate: SpellView in _spells_at_level(character, level):
				if candidate.id == remembered_id:
					spell = candidate
					break
			_selected_spell_id = spell.id
			_selected_power = DetailFormatter.valid_power(spell, int(_power_by_spell.get(spell.id, 1)))
			_power_by_spell[spell.id] = _selected_power
			_last_level_by_character[character.id] = level
			_remember_spell_selection(character.id, level, spell.id)
	refresh_requested.emit()


func _select_power(power: int) -> void:
	_selected_power = power
	if not _selected_spell_id.is_empty():
		_power_by_spell[_selected_spell_id] = power
	refresh_requested.emit()


func _assign_fast_spell(character_id: String, slot_index: int, selected: Variant) -> void:
	if not selected is Dictionary or selected.is_empty():
		return
	sound_requested.emit(144, false, false)
	intent_submitted.emit(MagicIntents.set_fast_spell(character_id, slot_index, String(selected.get("spellId", "")), int(selected.get("power", 0))))


func _clear_fast_spell(character_id: String, slot_index: int) -> void:
	sound_requested.emit(144, false, false)
	intent_submitted.emit(MagicIntents.set_fast_spell(character_id, slot_index))


func _bind_button(button: Button, label: String, availability: ActionAvailabilityView, callback: Callable) -> void:
	button.text = label
	UiSizing.minimum_size(button, Vector2(74.0, 34.0))
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if not availability.enabled else label
	_clear_pressed_connections(button)
	if not button.disabled:
		button.pressed.connect(callback)


func _bind_bitmap_action(button: ClassicBitmapButton, asset_id: StringName, tooltip: String, availability: ActionAvailabilityView, callback: Callable) -> void:
	var previous: Callable = button.get_meta(&"spell_action_callback", Callable())
	if not previous.is_null() and button.pressed.is_connected(previous):
		button.pressed.disconnect(previous)
	button.remove_meta(&"spell_action_callback")
	button.configure({"id": asset_id, "asset_id": asset_id, "tooltip": tooltip, "accelerator": ""}, 1)
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if button.disabled else tooltip
	if not button.disabled:
		button.pressed.connect(callback)
		button.set_meta(&"spell_action_callback", callback)


func _bind_label(label: Label, text: String, color: Color = Color.WHITE, size: int = 15) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	UiSizing.font_size(label, &"font_size", size)


static func _clear_pressed_connections(button: BaseButton) -> void:
	for connection: Dictionary in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"] as Callable)


static func _clear_option_button(picker: OptionButton) -> void:
	for connection: Dictionary in picker.item_selected.get_connections():
		picker.item_selected.disconnect(connection["callable"] as Callable)
	picker.clear()


static func _clear(parent: Node) -> void:
	if parent == null:
		return
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
