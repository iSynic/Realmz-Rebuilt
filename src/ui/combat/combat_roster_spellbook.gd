## Binds the scene-authored combat spellbook shown in the persistent party rail.
class_name CombatRosterSpellbook
extends VBoxContainer

signal cast_requested(option: InteractionRequestValue.CastOption)
signal back_requested

const MUTED := Color("9da8aa")

@export var spell_button_scene: PackedScene
@export var power_button_scene: PackedScene

var _view: GameView
var _actor_id: String = ""
var _options: Array[InteractionRequestValue.CastOption] = []
var _level: int = 1
var _spell_id: String = ""
var _spell_buttons: Dictionary = {}
var _available_width: float = 0.0
var _controls_ready: bool = false
var _level_spells: Dictionary = {}
var _spell_powers: Dictionary = {}


func present(actor_id: String, options: Array[InteractionRequestValue.CastOption], view: GameView, available_width: float) -> void:
	_ensure_controls()
	var opened := not visible or _actor_id != actor_id
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_name: StringName = focused.name if not opened and focused != null and is_ancestor_of(focused) else &""
	if opened:
		_level_spells.clear()
		_spell_powers.clear()
		_spell_id = ""
	visible = true
	_view = view
	_actor_id = actor_id
	_options.assign(options)
	_available_width = available_width
	var levels := _available_levels()
	if levels.is_empty():
		$CombatSpellbookSelector.visible = false
		$SpellbookEmpty.visible = true
		$SpellbookFooter/CombatSpellbookActions/CombatSpellAim.visible = false
		focus_selected_spell.call_deferred()
		return
	$CombatSpellbookSelector.visible = true
	$SpellbookEmpty.visible = false
	$SpellbookFooter/CombatSpellbookActions/CombatSpellAim.visible = true
	if not levels.has(_level):
		_level = levels[0]
	_bind_level_rail(levels)
	_refresh_spell_list()
	_restore_focus.call_deferred(focus_name)


func _restore_focus(control_name: StringName) -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		return
	var control := find_child(String(control_name), true, false) as Control if not control_name.is_empty() else null
	if control != null and control.is_visible_in_tree() and not (control is BaseButton and (control as BaseButton).disabled):
		control.grab_focus()
		SpellsWorkspace.reveal_controller_focus(control)
	else:
		focus_selected_spell()


func close() -> void:
	visible = false
	_level_spells.clear()
	_spell_powers.clear()


func controller_cycle_section(delta: int) -> bool:
	var levels := _available_levels()
	if not levels.is_empty():
		_select_level(levels[wrapi(levels.find(_level) + delta, 0, levels.size())])
		focus_selected_spell.call_deferred()
	return true


func focus_selected_spell() -> bool:
	if not is_inside_tree() or not is_visible_in_tree():
		return false
	SpellsWorkspace.link_controller_focus(self)
	var button := _spell_buttons.get(_spell_id) as Control
	if button == null or not button.is_visible_in_tree():
		button = $SpellbookFooter/CombatSpellbookActions/CombatSpellbookBack
	button.grab_focus()
	SpellsWorkspace.reveal_controller_focus(button)
	return true


func focus_cast_action() -> void:
	if is_inside_tree() and is_visible_in_tree():
		var button := $SpellbookFooter/CombatSpellbookActions/CombatSpellAim as Button
		if not button.disabled:
			button.grab_focus()


func _available_levels() -> Array[int]:
	var levels: Array[int] = []
	for spell: SpellView in _known_combat_spells():
		var level := ClassicSpellLevel.from_classic_id(spell.classic_id)
		if not levels.has(level):
			levels.append(level)
	for option: InteractionRequestValue.CastOption in _options:
		var level := _classic_spell_level(option.spell_id)
		if not levels.has(level):
			levels.append(level)
	levels.sort()
	return levels


func _bind_level_rail(levels: Array[int]) -> void:
	var group := ButtonGroup.new()
	for level: int in range(1, 8):
		var button := get_node("CombatSpellbookSelector/CombatSpellLevels/SpellLevel%d" % level) as Button
		button.button_group = group
		ClassicSpellSelectionChrome.bind_level_button(
			button,
			level,
			level == _level,
			levels.has(level),
			_select_level.bind(level),
			"No available level %d spells" % level
		)


func _select_level(level: int) -> void:
	_level_spells[_level] = _spell_id
	_level = level
	_spell_id = _level_spells.get(level, "")
	_bind_level_rail(_available_levels())
	_refresh_spell_list()


func _refresh_spell_list() -> void:
	var list := $CombatSpellbookSelector/CombatSpellRecords/CombatSpellListPanel/CombatSpellScroll/CombatSpellList as VBoxContainer
	_clear(list)
	_spell_buttons.clear()
	var spell_ids: Array[String] = []
	for spell: SpellView in _known_combat_spells():
		if ClassicSpellLevel.from_classic_id(spell.classic_id) == _level:
			spell_ids.append(spell.id)
	for option: InteractionRequestValue.CastOption in _options:
		if _classic_spell_level(option.spell_id) == _level and not spell_ids.has(option.spell_id):
			spell_ids.append(option.spell_id)
	if spell_ids.is_empty():
		_spell_id = ""
		_refresh_power_choices()
		return
	if not spell_ids.has(_spell_id):
		_spell_id = spell_ids[0]
	for spell_id: String in spell_ids:
		var representative := _first_option(spell_id)
		var spell := _spell_view(spell_id)
		var legal := representative != null
		var spell_name := spell.name if spell != null else representative.spell_name
		var tooltip := spell.description if spell != null and not spell.description.is_empty() else spell_name
		if not legal:
			tooltip = "%s\n%s" % [tooltip, _unavailable_reason(spell)]
		var button := spell_button_scene.instantiate() as Button
		ClassicSpellSelectionChrome.bind_spell_button(
			button,
			"CombatSpell%s" % spell_id.replace(".", "_"),
			"%s%s" % [spell_name, "  •  Unavailable" if not legal else ""],
			spell_id == _spell_id,
			true,
			tooltip,
			_select_spell.bind(spell_id)
		)
		button.custom_minimum_size.y = 21.0
		UiSizing.font_size(button, &"font_size", 14)
		_spell_buttons[spell_id] = button
		list.add_child(button)
	_refresh_power_choices()
	SpellsWorkspace.link_controller_focus(self)


func _select_spell(spell_id: String) -> void:
	_spell_id = spell_id
	_level_spells[_level] = spell_id
	for candidate_id: String in _spell_buttons:
		(_spell_buttons[candidate_id] as Button).button_pressed = candidate_id == spell_id
	_refresh_power_choices()


func _refresh_power_choices() -> void:
	cast_requested.emit(null)
	var host := $CombatSpellbookSelector/CombatSpellRecords/CombatSpellPowerChoices/PowerButtons as HBoxContainer
	_clear(host)
	var representatives: Array[InteractionRequestValue.CastOption] = []
	var powers: Array[int] = []
	for option: InteractionRequestValue.CastOption in _options:
		if option.spell_id == _spell_id and not powers.has(option.power):
			powers.append(option.power)
			representatives.append(option)
	for option: InteractionRequestValue.CastOption in representatives:
		var button := power_button_scene.instantiate() as Button
		button.name = "CombatSpellPower%d" % option.power
		button.text = str(option.power)
		button.tooltip_text = "Power %d • %d SP" % [option.power, option.cost]
		button.accessibility_name = "Power %d" % option.power
		button.set_meta("cast_option", option)
		button.pressed.connect(func() -> void: _select_power(option))
		host.add_child(button)
	var cast := $SpellbookFooter/CombatSpellbookActions/CombatSpellAim as Button
	if representatives.is_empty():
		var unavailable_spell := _spell_view(_spell_id)
		var reason := _unavailable_reason(unavailable_spell)
		_present_unavailable(unavailable_spell, reason)
		cast.disabled = true
		cast.set_meta("cast_option", null)
		cast.tooltip_text = reason
		return
	var selected := representatives[0]
	for option: InteractionRequestValue.CastOption in representatives:
		if option.power == int(_spell_powers.get(_spell_id, -1)):
			selected = option
	_select_power(selected)
	SpellsWorkspace.link_controller_focus(self)


func _select_power(option: InteractionRequestValue.CastOption) -> void:
	_spell_powers[_spell_id] = option.power
	cast_requested.emit(null)
	var host := $CombatSpellbookSelector/CombatSpellRecords/CombatSpellPowerChoices/PowerButtons as HBoxContainer
	for child: Node in host.get_children():
		(child as Button).button_pressed = (child as Button).get_meta("cast_option") == option
	var cast := $SpellbookFooter/CombatSpellbookActions/CombatSpellAim as Button
	cast.set_meta("cast_option", option)
	cast.disabled = false
	cast.text = "Cast Spell" if option.target_mode == &"automatic" else "Choose Targets"
	cast.tooltip_text = "Cast the selected spell." if option.target_mode == &"automatic" else "Aim the selected spell on the battlefield."
	var target_text := option.target_name if not option.target_name.is_empty() else String(option.target_mode).replace("_", " ").capitalize()
	if option.target_mode == &"sequence":
		target_text = "Choose up to %d targets" % option.maximum_targets
	_present_details(option, target_text)


func _present_details(option: InteractionRequestValue.CastOption, target_text: String) -> void:
	var spell := _spell_view(option.spell_id)
	var content := $CombatSpellbookSelector/CombatSpellRecords/CombatSpellDetails/Content
	(content.get_node("Identity/TitleBox/Title") as Label).text = option.spell_name
	var actor := _actor_view()
	var resource_line := "Level %d  •  Power %d" % [_classic_spell_level(option.spell_id), option.power]
	if spell != null and absi(spell.cost) != option.cost:
		resource_line += "  •  Base %d SP" % absi(spell.cost)
	resource_line += "  •  Cost %d SP" % option.cost
	if actor != null:
		resource_line += "  •  SP %d/%d" % [actor.spell_points, actor.maximum_spell_points]
	var resource := content.get_node("Identity/TitleBox/Resource") as Label
	resource.visible = true
	resource.text = resource_line
	resource.tooltip_text = resource_line
	var badge := content.get_node("Identity/TargetBadge") as ClassicSpellTargetBadge
	badge.visible = spell != null and _available_width >= 280.0 and badge.present(spell.target_type, spell.target_size, target_text, Vector2(48.0, 48.0))
	var target := content.get_node("Target") as Label
	target.visible = true
	target.text = "Target  •  %s" % target_text
	target.tooltip_text = target_text
	var facts := content.get_node("Facts") as GridContainer
	facts.visible = spell != null
	if spell != null:
		_bind_fact(facts, "Targets", str(option.power if spell.target_type < 1 else 1))
		_bind_fact(facts, "Range", str(absi(spell.range_min + spell.range_max * option.power)))
		_bind_fact(facts, "Damage", _scaled_pair(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, option.power))
		_bind_fact(facts, "Duration", _scaled_pair(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, option.power, true))
		_bind_fact(facts, "MagicResist", _magic_resistance(spell, option.power))
		_bind_fact(facts, "SavingThrow", _saving_throw(spell, option.power))
	var description := spell.description.strip_edges() if spell != null else ""
	var description_well := content.get_node("DescriptionWell") as PanelContainer
	description_well.visible = not description.is_empty()
	var description_label := description_well.get_node("Description") as Label
	description_label.text = description
	description_label.tooltip_text = description
	(content.get_node("Unavailable") as Label).visible = false


func _present_unavailable(spell: SpellView, message: String) -> void:
	var content := $CombatSpellbookSelector/CombatSpellRecords/CombatSpellDetails/Content
	(content.get_node("Identity/TitleBox/Title") as Label).text = spell.name if spell != null else "Spell unavailable"
	(content.get_node("Identity/TitleBox/Resource") as Label).visible = false
	(content.get_node("Identity/TargetBadge") as Control).visible = false
	(content.get_node("Target") as Label).visible = false
	(content.get_node("Facts") as GridContainer).visible = false
	var description_well := content.get_node("DescriptionWell") as PanelContainer
	var description := spell.description.strip_edges() if spell != null else ""
	description_well.visible = not description.is_empty()
	(description_well.get_node("Description") as Label).text = description
	var unavailable := content.get_node("Unavailable") as Label
	unavailable.visible = true
	unavailable.text = message


func _bind_fact(facts: GridContainer, node_name: String, value: String) -> void:
	var label := facts.get_node(node_name) as Label
	label.text = value
	label.tooltip_text = value


func _unavailable_reason(spell: SpellView) -> String:
	if spell != null and not spell.combat_cast.reason.is_empty():
		return spell.combat_cast.reason
	return "No rules-legal power or tactical target is available this activation."


func _actor_view() -> CharacterView:
	if _view != null:
		for character: CharacterView in _view.party_members:
			if character.id == _actor_id:
				return character
	return null


func _spell_view(spell_id: String) -> SpellView:
	var actor := _actor_view()
	if actor != null:
		for spell: SpellView in actor.spells:
			if spell.id == spell_id:
				return spell
	return null


func _known_combat_spells() -> Array[SpellView]:
	var result: Array[SpellView] = []
	var actor := _actor_view()
	if actor != null:
		for spell: SpellView in actor.spells:
			if spell.castable_in_combat:
				result.append(spell)
	return result


func _first_option(spell_id: String) -> InteractionRequestValue.CastOption:
	for option: InteractionRequestValue.CastOption in _options:
		if option.spell_id == spell_id:
			return option
	return null


static func _scaled_pair(base_min: int, base_max: int, per_power_min: int, per_power_max: int, power: int, absolute_values: bool = false) -> String:
	var low := base_min + per_power_min * power
	var high := base_max + per_power_max * power
	if absolute_values:
		low = absi(low)
		high = absi(high)
	if low == 0 and high == 0:
		return "—"
	return str(low) if low == high else "%d–%d" % [low, high]


static func _magic_resistance(spell: SpellView, power: int) -> String:
	if spell.damage_type < 1:
		return "Versus"
	if spell.cannot == 1 or spell.cannot > 2:
		return "No"
	return "Yes" if spell.resistance_adjust == 0 else "%+d" % (power * spell.resistance_adjust)


static func _saving_throw(spell: SpellView, power: int) -> String:
	if spell.damage_type < 1:
		return "—"
	if spell.cannot > 1:
		return "No"
	return "Yes" if spell.save_adjust == 0 and spell.save_bonus == 0 else "%+d" % (spell.save_bonus + power * spell.save_adjust)


static func _classic_spell_level(spell_id: String) -> int:
	var parts := spell_id.split(".")
	var classic_id := String(parts[parts.size() - 1]).to_int() if not parts.is_empty() else 0
	return ClassicSpellLevel.from_classic_id(classic_id)


func _ensure_controls() -> void:
	if _controls_ready:
		return
	_controls_ready = true
	($CombatSpellbookSelector/CombatSpellLevels/LevelHeading as TextureRect).texture = ClassicUiAssetCatalog.texture(&"spells.label.level")
	($CombatSpellbookSelector/CombatSpellRecords/CombatSpellPowerChoices/PowerLabel as TextureRect).texture = ClassicUiAssetCatalog.texture(&"spells.label.power")
	var cast := $SpellbookFooter/CombatSpellbookActions/CombatSpellAim as Button
	cast.text = "Choose Targets"
	cast.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cast.pressed.connect(_emit_cast)
	var back := $SpellbookFooter/CombatSpellbookActions/CombatSpellbookBack as Button
	back.icon = ClassicUiAssetCatalog.texture(&"spells.action.abort")
	back.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	back.pressed.connect(func() -> void: back_requested.emit())


func _emit_cast() -> void:
	var option := ($SpellbookFooter/CombatSpellbookActions/CombatSpellAim as Button).get_meta("cast_option") as InteractionRequestValue.CastOption
	if option != null:
		cast_requested.emit(option)


static func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
