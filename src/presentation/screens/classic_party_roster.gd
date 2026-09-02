class_name ClassicPartyRoster
extends PanelContainer

const ClassicSpellLevelScript := preload("res://src/presentation/classic_spell_level.gd")
const SpellTargetBadge := preload("res://src/presentation/classic_spell_target_badge.gd")

signal character_selected(character_id: String)
signal character_activated(character_id: String)
signal combat_auto_changed(character_id: String, enabled: bool)
signal character_selection_completed(character_ids: Array[String])
signal combat_spell_cast_requested(option: InteractionRequestValue.CastOption)
signal combat_spellbook_back_requested

const MUTED := Color("9da8aa")
const CLASSIC_PORTRAIT_STAGE_SIZE := Vector2i(50, 50)
const CLASSIC_DEATH_HEALTH := -10
const CLASSIC_PORTRAIT_SHADE_CICN := 2019
const CLASSIC_DEATH_MARKER_CICN := 2015
const SPELLBOOK_POWER_HEIGHT := 22.0
const SPELLBOOK_POWER_LABEL_WIDTH := 60.0
const SPELLBOOK_POWER_BUTTON_WIDTH := 20.0

@onready var _party_list: VBoxContainer = %PartyList
@onready var _heading: Label = %Heading
@onready var _spellbook_footer: VBoxContainer = %SpellbookFooter
@onready var _party_scroll: ScrollContainer = %PartyScroll

var _media: ClassicMediaCatalog
var _portrait_composites: Dictionary = {}
var _selected_character_id: String = ""
var _current_view: GameView
var _selection_request_id: String = ""
var _selection_count: int = 0
var _selection_eligible_ids: Array[String] = []
var _selection_order: Array[String] = []
var _selection_cursor_layer: CanvasLayer
var _selection_cursor_label: Label
var _combat_spellbook_active: bool = false
var _spellbook_options: Array[InteractionRequestValue.CastOption] = []
var _spellbook_actor_id: String = ""
var _spellbook_level: int = 1
var _spellbook_spell_id: String = ""
var _spellbook_list: VBoxContainer
var _spellbook_spell_buttons: Dictionary = {}
var _spellbook_power_row: HBoxContainer
var _spellbook_details: PanelContainer
var _spellbook_detail_column: VBoxContainer
var _spellbook_cast: Button


func _exit_tree() -> void:
	_restore_pointer()


func _process(_delta: float) -> void:
	if not character_selection_active() or not is_instance_valid(_selection_cursor_label):
		set_process(false)
		return
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	var viewport := get_viewport()
	if viewport != null:
		_selection_cursor_label.position = viewport.get_mouse_position() + Vector2(14.0, 10.0)


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	_media = media
	_portrait_composites.clear()


func present(view: GameView, selected_character_id: String = "") -> void:
	_ensure_controls()
	_party_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_combat_spellbook_active = false
	_current_view = view
	_selected_character_id = selected_character_id
	_clear()
	if view == null or not view.session_started:
		_heading.text = "Party"
		_add_empty("No active party")
		return
	_heading.text = "Party • Pick %d" % (_selection_count - _selection_order.size()) if character_selection_active() else "Party"
	var combat_active := view.combat_view != null and view.combat_view.outcome == &"active"
	var auto_character_ids: Array[String] = []
	if combat_active:
		auto_character_ids.assign(view.combat_view.auto_character_ids)
	for character: CharacterView in view.party_members:
		_add_character(character, combat_active, auto_character_ids)
	for index: int in maxi(0, 6 - view.party_members.size()):
		_add_empty("Empty position %d" % (view.party_members.size() + index + 1))


func present_ordinary_exploration(view: GameView, selected_character_id: String = "", affected_character_ids: Array[String] = []) -> void:
	_ensure_controls()
	if view == null or not view.session_started or character_selection_active() or _combat_spellbook_active or view.combat_view != null:
		present(view, selected_character_id)
		return
	for character: CharacterView in view.party_members:
		if _character_row(character.id) == null:
			present(view, selected_character_id)
			return
	_current_view = view
	var selection_changed := _selected_character_id != selected_character_id
	_selected_character_id = selected_character_id
	for character: CharacterView in view.party_members:
		if not affected_character_ids.is_empty() and not affected_character_ids.has(character.id):
			continue
		_update_exploration_character_row(_character_row(character.id), character)
	if selection_changed:
		_update_current_character_markers()


func present_combat_spellbook(actor_id: String, options: Array[InteractionRequestValue.CastOption]) -> void:
	_ensure_controls()
	_party_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_combat_spellbook_active = true
	_spellbook_options.assign(options)
	_spellbook_actor_id = actor_id
	_spellbook_spell_id = ""
	_clear()
	var actor_name := actor_id
	if _current_view != null:
		for character: CharacterView in _current_view.party_members:
			if character.id == actor_id:
				actor_name = character.name
				break
	_heading.text = "Spellcasting • %s" % actor_name
	_build_spellbook()


func close_combat_spellbook() -> void:
	if not _combat_spellbook_active:
		return
	_combat_spellbook_active = false
	if _current_view != null:
		present(_current_view, _selected_character_id)


func combat_spellbook_active() -> bool:
	return _combat_spellbook_active


func _build_spellbook() -> void:
	var available_levels: Array[int] = []
	for spell: SpellView in _spellbook_known_combat_spells():
		var level := ClassicSpellLevelScript.from_classic_id(spell.classic_id)
		if not available_levels.has(level):
			available_levels.append(level)
	for option: InteractionRequestValue.CastOption in _spellbook_options:
		var level := _classic_spell_level(option.spell_id)
		if not available_levels.has(level):
			available_levels.append(level)
	available_levels.sort()
	if available_levels.is_empty():
		_add_empty("No combat spell is known.")
		return
	if not available_levels.has(_spellbook_level):
		_spellbook_level = available_levels[0]
	var selector := HBoxContainer.new()
	selector.name = "CombatSpellbookSelector"
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	selector.add_theme_constant_override("separation", 4)
	_party_list.add_child(selector)
	selector.add_child(_build_spell_level_rail(available_levels))
	var spell_list_panel := PanelContainer.new()
	spell_list_panel.name = "CombatSpellListPanel"
	spell_list_panel.theme_type_variation = &"ClassicInset"
	spell_list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spell_list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var records := VBoxContainer.new()
	records.name = "CombatSpellRecords"
	records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	records.size_flags_vertical = Control.SIZE_EXPAND_FILL
	records.add_theme_constant_override("separation", 3)
	selector.add_child(records)
	records.add_child(spell_list_panel)
	var spell_scroll := ScrollContainer.new()
	spell_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	spell_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spell_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spell_list_panel.add_child(spell_scroll)
	_spellbook_list = VBoxContainer.new()
	_spellbook_list.name = "CombatSpellList"
	_spellbook_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spellbook_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spellbook_list.add_theme_constant_override("separation", 3)
	spell_scroll.add_child(_spellbook_list)
	_spellbook_details = PanelContainer.new()
	_spellbook_details.name = "CombatSpellDetails"
	_spellbook_details.theme_type_variation = &"ClassicInset"
	_spellbook_details.custom_minimum_size.y = 112.0
	_spellbook_detail_column = VBoxContainer.new()
	_spellbook_detail_column.add_theme_constant_override("separation", 3)
	_spellbook_details.add_child(_spellbook_detail_column)
	records.add_child(_spellbook_details)
	_spellbook_power_row = HBoxContainer.new()
	_spellbook_power_row.name = "CombatSpellPowerChoices"
	_spellbook_power_row.add_theme_constant_override("separation", 3)
	records.add_child(_spellbook_power_row)
	var actions := HBoxContainer.new()
	actions.name = "CombatSpellbookActions"
	actions.custom_minimum_size.y = 30.0
	actions.add_theme_constant_override("separation", 4)
	_spellbook_cast = Button.new()
	_spellbook_cast.name = "CombatSpellAim"
	_spellbook_cast.theme_type_variation = &"BattleCommandButton"
	_spellbook_cast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spellbook_cast.icon = ClassicUiAssetCatalog.texture(&"spells.action.cast")
	_spellbook_cast.expand_icon = false
	_spellbook_cast.add_theme_constant_override("icon_max_width", 128)
	_spellbook_cast.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_spellbook_cast.pressed.connect(_on_spellbook_cast_pressed)
	actions.add_child(_spellbook_cast)
	var back := Button.new()
	back.name = "CombatSpellbookBack"
	back.icon = ClassicUiAssetCatalog.texture(&"spells.action.abort")
	back.expand_icon = false
	back.add_theme_constant_override("icon_max_width", 92)
	back.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	back.tooltip_text = "Return to the battle commands."
	back.theme_type_variation = &"BattleCommandButton"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void: combat_spellbook_back_requested.emit())
	actions.add_child(back)
	_spellbook_footer.add_child(actions)
	_spellbook_footer.visible = true
	_refresh_spellbook_list()


func _build_spell_level_rail(levels: Array[int]) -> VBoxContainer:
	var rail := VBoxContainer.new()
	rail.name = "CombatSpellLevels"
	rail.custom_minimum_size.x = 82.0
	rail.add_theme_constant_override("separation", 1)
	rail.add_child(ClassicSpellSelectionChrome.level_heading())
	var group := ButtonGroup.new()
	for level: int in range(1, 8):
		var button := ClassicSpellSelectionChrome.level_button(level, level == _spellbook_level, levels.has(level), _select_spellbook_level.bind(level), "No available level %d spells" % level)
		button.custom_minimum_size = Vector2(80.0, 24.0)
		button.button_group = group
		rail.add_child(button)
	return rail


func _select_spellbook_level(level: int) -> void:
	_spellbook_level = level
	_refresh_spellbook_list()


func _refresh_spellbook_list() -> void:
	for child: Node in _spellbook_list.get_children():
		_spellbook_list.remove_child(child)
		child.queue_free()
	_spellbook_spell_buttons.clear()
	var spell_ids: Array[String] = []
	for spell: SpellView in _spellbook_known_combat_spells():
		if ClassicSpellLevelScript.from_classic_id(spell.classic_id) == _spellbook_level:
			spell_ids.append(spell.id)
	for option: InteractionRequestValue.CastOption in _spellbook_options:
		if _classic_spell_level(option.spell_id) != _spellbook_level or spell_ids.has(option.spell_id):
			continue
		spell_ids.append(option.spell_id)
	if spell_ids.is_empty():
		_spellbook_spell_id = ""
		_refresh_spellbook_power_choices()
		return
	if not spell_ids.has(_spellbook_spell_id):
		_spellbook_spell_id = spell_ids[0]
	for spell_id: String in spell_ids:
		var representative := _first_spellbook_option(spell_id)
		var spell := _spellbook_spell_view(spell_id)
		var legal := representative != null
		var spell_name := spell.name if spell != null else representative.spell_name
		var tooltip := spell.description if spell != null and not spell.description.is_empty() else spell_name
		if not legal:
			tooltip = "%s\n%s" % [tooltip, _spellbook_unavailable_reason(spell)]
		var button := ClassicSpellSelectionChrome.spell_button(
			"CombatSpell%s" % spell_id.replace(".", "_"),
			"%s%s" % [spell_name, "  •  Unavailable" if not legal else ""],
			spell_id == _spellbook_spell_id,
			true,
			tooltip,
			_select_spellbook_spell.bind(spell_id)
		)
		button.custom_minimum_size.y = 21.0
		button.add_theme_font_size_override("font_size", 14)
		_spellbook_spell_buttons[spell_id] = button
		_spellbook_list.add_child(button)
	_refresh_spellbook_power_choices()


func _select_spellbook_spell(spell_id: String) -> void:
	_spellbook_spell_id = spell_id
	for candidate_id: String in _spellbook_spell_buttons:
		(_spellbook_spell_buttons[candidate_id] as Button).button_pressed = candidate_id == spell_id
	_refresh_spellbook_power_choices()


func _refresh_spellbook_power_choices() -> void:
	for child: Node in _spellbook_power_row.get_children():
		_spellbook_power_row.remove_child(child)
		child.queue_free()
	var power_art := TextureRect.new()
	power_art.texture = ClassicUiAssetCatalog.texture(&"spells.label.power")
	power_art.custom_minimum_size = Vector2(SPELLBOOK_POWER_LABEL_WIDTH, SPELLBOOK_POWER_HEIGHT)
	power_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	power_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	power_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_spellbook_power_row.add_child(power_art)
	var representatives: Array[InteractionRequestValue.CastOption] = []
	var powers: Array[int] = []
	for option: InteractionRequestValue.CastOption in _spellbook_options:
		if option.spell_id != _spellbook_spell_id or powers.has(option.power):
			continue
		powers.append(option.power)
		representatives.append(option)
	for option: InteractionRequestValue.CastOption in representatives:
		var button := Button.new()
		button.name = "CombatSpellPower%d" % option.power
		button.text = str(option.power)
		button.tooltip_text = "Power %d • %d SP" % [option.power, option.cost]
		button.accessibility_name = "Power %d" % option.power
		button.custom_minimum_size = Vector2(SPELLBOOK_POWER_BUTTON_WIDTH, SPELLBOOK_POWER_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
		button.toggle_mode = true
		button.set_meta("cast_option", option)
		button.pressed.connect(func() -> void: _select_spellbook_power(option))
		_spellbook_power_row.add_child(button)
	if representatives.is_empty():
		var unavailable_spell := _spellbook_spell_view(_spellbook_spell_id)
		var unavailable_reason := _spellbook_unavailable_reason(unavailable_spell)
		_present_spellbook_unavailable(unavailable_spell, unavailable_reason)
		_spellbook_cast.disabled = true
		_spellbook_cast.set_meta("cast_option", null)
		_spellbook_cast.tooltip_text = unavailable_reason
		return
	_select_spellbook_power(representatives[0])


func _select_spellbook_power(option: InteractionRequestValue.CastOption) -> void:
	for child: Node in _spellbook_power_row.get_children():
		if child is Button:
			(child as Button).button_pressed = (child as Button).get_meta("cast_option") == option
	_spellbook_cast.set_meta("cast_option", option)
	_spellbook_cast.disabled = false
	_spellbook_cast.tooltip_text = "Cast the selected spell." if option.target_mode == &"automatic" else "Aim the selected spell on the battlefield."
	var target_text := option.target_name if not option.target_name.is_empty() else String(option.target_mode).replace("_", " ").capitalize()
	if option.target_mode == &"sequence":
		target_text = "Choose up to %d targets" % option.maximum_targets
	_present_spellbook_details(option, target_text)


func _present_spellbook_details(option: InteractionRequestValue.CastOption, target_text: String) -> void:
	_clear_container(_spellbook_detail_column)
	var spell := _spellbook_spell_view(option.spell_id)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 5)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.theme_type_variation = &"ClassicHeading"
	title.text = option.spell_name
	title_box.add_child(title)
	var actor := _spellbook_actor_view()
	var resource_line := "Level %d  •  Power %d" % [_classic_spell_level(option.spell_id), option.power]
	if spell != null and absi(spell.cost) != option.cost:
		resource_line += "  •  Base %d SP" % absi(spell.cost)
	resource_line += "  •  Cost %d SP" % option.cost
	if actor != null:
		resource_line += "  •  SP %d/%d" % [actor.spell_points, actor.maximum_spell_points]
	var resource_label := _spellbook_label(resource_line, MUTED, 12)
	resource_label.max_lines_visible = 1
	resource_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	resource_label.tooltip_text = resource_line
	title_box.add_child(resource_label)
	identity.add_child(title_box)
	if spell != null and size.x >= 280.0:
		var target_badge := SpellTargetBadge.new()
		if target_badge.present(spell.target_type, spell.target_size, target_text, Vector2(48.0, 48.0)):
			identity.add_child(target_badge)
		else:
			target_badge.free()
	_spellbook_detail_column.add_child(identity)
	var target_line := _spellbook_label("Target  •  %s" % target_text, Color("63d8e7"), 13)
	target_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	target_line.tooltip_text = target_text
	_spellbook_detail_column.add_child(target_line)
	if spell != null:
		var facts := GridContainer.new()
		facts.columns = 4
		facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		facts.add_theme_constant_override("h_separation", 4)
		facts.add_theme_constant_override("v_separation", 1)
		_add_spellbook_fact(facts, "Targets", str(option.power if spell.target_type < 1 else 1))
		_add_spellbook_fact(facts, "Range", str(absi(spell.range_min + spell.range_max * option.power)))
		_add_spellbook_fact(facts, "Damage", _spellbook_scaled_pair(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, option.power))
		_add_spellbook_fact(facts, "Duration", _spellbook_scaled_pair(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, option.power, true))
		_add_spellbook_fact(facts, "Magic resist", _spellbook_magic_resistance(spell, option.power))
		_add_spellbook_fact(facts, "Saving throw", _spellbook_saving_throw(spell, option.power))
		_spellbook_detail_column.add_child(facts)
	var description := spell.description.strip_edges() if spell != null else ""
	if not description.is_empty():
		var description_well := PanelContainer.new()
		description_well.theme_type_variation = &"ClassicTextWell"
		var description_label := _spellbook_label(description, Color("eee9db"), 13)
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.max_lines_visible = 1
		description_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		description_label.tooltip_text = description
		description_well.add_child(description_label)
		_spellbook_detail_column.add_child(description_well)


func _present_spellbook_unavailable(spell: SpellView, message: String) -> void:
	_clear_container(_spellbook_detail_column)
	if spell != null:
		var title := _spellbook_label(spell.name, Color("e7d078"), 18)
		title.theme_type_variation = &"ClassicHeading"
		_spellbook_detail_column.add_child(title)
		if not spell.description.strip_edges().is_empty():
			var description := _spellbook_label(spell.description.strip_edges(), Color("eee9db"), 14)
			description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_spellbook_detail_column.add_child(description)
	_spellbook_detail_column.add_child(_spellbook_label(message, MUTED, 15))


func _spellbook_unavailable_reason(spell: SpellView) -> String:
	if spell != null and not spell.combat_cast.reason.is_empty():
		return spell.combat_cast.reason
	return "No rules-legal power or tactical target is available this activation."


func _spellbook_actor_view() -> CharacterView:
	if _current_view == null:
		return null
	for character: CharacterView in _current_view.party_members:
		if character.id == _spellbook_actor_id:
			return character
	return null


func _spellbook_spell_view(spell_id: String) -> SpellView:
	var actor := _spellbook_actor_view()
	if actor == null:
		return null
	for spell: SpellView in actor.spells:
		if spell.id == spell_id:
			return spell
	return null


func _spellbook_known_combat_spells() -> Array[SpellView]:
	var result: Array[SpellView] = []
	var actor := _spellbook_actor_view()
	if actor == null:
		return result
	for spell: SpellView in actor.spells:
		if spell.castable_in_combat:
			result.append(spell)
	return result


func _first_spellbook_option(spell_id: String) -> InteractionRequestValue.CastOption:
	for option: InteractionRequestValue.CastOption in _spellbook_options:
		if option.spell_id == spell_id:
			return option
	return null


static func _spellbook_scaled_pair(base_min: int, base_max: int, per_power_min: int, per_power_max: int, power: int, absolute_values: bool = false) -> String:
	var low := base_min + per_power_min * power
	var high := base_max + per_power_max * power
	if absolute_values:
		low = absi(low)
		high = absi(high)
	if low == 0 and high == 0:
		return "—"
	return str(low) if low == high else "%d–%d" % [low, high]


static func _spellbook_magic_resistance(spell: SpellView, power: int) -> String:
	if spell.damage_type < 1:
		return "Versus"
	if spell.cannot == 1 or spell.cannot > 2:
		return "No"
	if spell.resistance_adjust == 0:
		return "Yes"
	return "%+d" % (power * spell.resistance_adjust)


static func _spellbook_saving_throw(spell: SpellView, power: int) -> String:
	if spell.damage_type < 1:
		return "—"
	if spell.cannot > 1:
		return "No"
	if spell.save_adjust == 0 and spell.save_bonus == 0:
		return "Yes"
	return "%+d" % (spell.save_bonus + power * spell.save_adjust)


static func _add_spellbook_fact(parent: GridContainer, name: String, value: String) -> void:
	var name_label := _spellbook_label(name, Color("e7d078"), 12)
	name_label.custom_minimum_size.x = 48.0
	parent.add_child(name_label)
	var value_label := _spellbook_label(value, Color("d8d9d2"), 12)
	value_label.custom_minimum_size.x = 28.0
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value_label.tooltip_text = value
	parent.add_child(value_label)


static func _spellbook_label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	return label


static func _clear_container(container: Container) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _on_spellbook_cast_pressed() -> void:
	var option := _spellbook_cast.get_meta("cast_option") as InteractionRequestValue.CastOption
	if option != null:
		combat_spell_cast_requested.emit(option)


static func _classic_spell_level(spell_id: String) -> int:
	var parts := spell_id.split(".")
	var classic_id := String(parts[parts.size() - 1]).to_int() if not parts.is_empty() else 0
	return ClassicSpellLevelScript.from_classic_id(classic_id)


func _add_character(character: CharacterView, combat_active: bool, auto_character_ids: Array[String]) -> void:
	var row_container := HBoxContainer.new()
	row_container.custom_minimum_size.y = 54.0
	row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_container.add_theme_constant_override("separation", 3)
	if not character_selection_active():
		var marker := ColorRect.new()
		marker.name = "CurrentCharacterMarker"
		marker.custom_minimum_size.x = 6.0
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.color = Color("e0bc53") if character.id == _selected_character_id else Color.TRANSPARENT
		marker.set_meta("character_id", character.id)
		row_container.add_child(marker)
	var row := Button.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_meta("character_id", character.id)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_theme_constant_override("icon_max_width", CLASSIC_PORTRAIT_STAGE_SIZE.x)
	row.toggle_mode = false
	row.tooltip_text = "Level %d • %s / %s • Movement %d/%d" % [character.level, character.race_name, character.caste_name, character.movement, character.maximum_movement]
	var selection_eligible := _selection_eligible_ids.has(character.id)
	if character_selection_active() and not selection_eligible:
		row.disabled = true
		row.tooltip_text = "This character is not eligible for the current selection."
	var condition_text := _condition_summary(character.condition_values)
	var action_fact := "SP %d/%d" % [character.spell_points, character.maximum_spell_points] if character.maximum_spell_points > 0 else "Attacks %d" % character.normal_attacks
	row.text = "%s\nHP %d/%d  •  %s  •  AR %d\n%s / %s" % [
		character.name,
		character.current_health,
		character.maximum_health,
		action_fact,
		character.armor,
		character.race_name,
		character.caste_name,
	]
	if not condition_text.is_empty():
		row.tooltip_text += " • %s" % condition_text
	row.set_meta("base_tooltip", row.tooltip_text)
	row.set_meta("condition_values", character.condition_values.duplicate())
	if not character_selection_active():
		row.tooltip_text += " • Current character; click to open its record." if character.id == _selected_character_id else " • Click to make this the current character."
	var portrait := _roster_portrait_texture(character)
	if portrait != null:
		row.icon = portrait
	row.pressed.connect(func() -> void:
		if character_selection_active():
			_toggle_character_selection(character.id)
			return
		var already_selected := character.id == _selected_character_id
		_selected_character_id = character.id
		_update_current_character_markers()
		if already_selected:
			character_activated.emit(character.id)
		else:
			character_selected.emit(character.id)
	)
	row_container.add_child(row)
	if character_selection_active():
		var marker := Label.new()
		marker.name = "SelectionNumber"
		marker.custom_minimum_size = Vector2(30.0, 30.0)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		marker.add_theme_font_size_override("font_size", 20)
		marker.add_theme_color_override("font_color", Color("e0bc53"))
		var selected_index := _selection_order.find(character.id)
		marker.text = str(_selection_count - selected_index) if selected_index >= 0 else ""
		row_container.add_child(marker)
	elif combat_active:
		var auto_toggle := Button.new()
		auto_toggle.name = "CombatAuto"
		auto_toggle.text = "A"
		auto_toggle.custom_minimum_size.x = 28.0
		auto_toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
		auto_toggle.toggle_mode = true
		auto_toggle.add_theme_font_size_override("font_size", 16)
		var auto_available := character.current_health > 0 and not character.traitor
		auto_toggle.disabled = not auto_available
		auto_toggle.accessibility_name = "Persistent Auto for %s" % character.name
		auto_toggle.button_pressed = auto_character_ids.has(character.id)
		auto_toggle.tooltip_text = _combat_auto_tooltip(auto_toggle.button_pressed, auto_available)
		auto_toggle.toggled.connect(func(enabled: bool) -> void:
			auto_toggle.tooltip_text = _combat_auto_tooltip(enabled, auto_available)
			combat_auto_changed.emit(character.id, enabled)
		)
		row_container.add_child(auto_toggle)
	_party_list.add_child(row_container)


func _update_exploration_character_row(row: Button, character: CharacterView) -> void:
	if row == null:
		return
	var condition_text := _condition_summary(character.condition_values)
	var action_fact := "SP %d/%d" % [character.spell_points, character.maximum_spell_points] if character.maximum_spell_points > 0 else "Attacks %d" % character.normal_attacks
	row.text = "%s\nHP %d/%d  •  %s  •  AR %d\n%s / %s" % [
		character.name,
		character.current_health,
		character.maximum_health,
		action_fact,
		character.armor,
		character.race_name,
		character.caste_name,
	]
	var previous_condition_values: Array = row.get_meta("condition_values", []) as Array
	if previous_condition_values != character.condition_values:
		var base_tooltip := "Level %d • %s / %s • Movement %d/%d" % [character.level, character.race_name, character.caste_name, character.movement, character.maximum_movement]
		if not condition_text.is_empty():
			base_tooltip += " • %s" % condition_text
		row.set_meta("base_tooltip", base_tooltip)
		row.set_meta("condition_values", character.condition_values.duplicate())
		row.tooltip_text = base_tooltip + (" • Current character; click to open its record." if character.id == _selected_character_id else " • Click to make this the current character.")


func _update_current_character_markers() -> void:
	for marker: Node in _party_list.find_children("CurrentCharacterMarker", "ColorRect", true, false):
		(marker as ColorRect).color = Color("e0bc53") if String(marker.get_meta("character_id")) == _selected_character_id else Color.TRANSPARENT
	for row: Node in _party_list.find_children("*", "Button", true, false):
		if row.has_meta("character_id"):
			(row as Button).tooltip_text = String(row.get_meta("base_tooltip")) + (" • Current character; click to open its record." if String(row.get_meta("character_id")) == _selected_character_id else " • Click to make this the current character.")


static func _combat_auto_tooltip(enabled: bool, available: bool) -> String:
	if not available:
		return "Persistent Auto requires a living loyal party character."
	return "Persistent Auto is on. Click to control this character manually." if enabled else "Persistent Auto is off. Click to automate this character's next combat activation."


func present_character_selection(request: InteractionRequest) -> void:
	if request == null or request.kind != InteractionRequest.CHARACTER_SELECTION:
		clear_character_selection()
		return
	var body := request.body as InteractionRequest.CharacterSelectionRequestBody
	if body == null:
		clear_character_selection()
		return
	if request.request_id != _selection_request_id:
		_selection_request_id = request.request_id
		_selection_count = body.count
		_selection_eligible_ids.clear()
		for candidate: InteractionRequestValue.SelectionCandidate in body.eligible:
			_selection_eligible_ids.append(candidate.id)
		_selection_order.clear()
		call_deferred("_focus_first_eligible")
	_update_selection_cursor()
	_represent()
	_update_selection_cursor()


func clear_character_selection() -> void:
	if not character_selection_active():
		return
	_selection_request_id = ""
	_selection_count = 0
	_selection_eligible_ids.clear()
	_selection_order.clear()
	_restore_pointer()
	_represent()


func character_selection_active() -> bool:
	return not _selection_request_id.is_empty()


func _toggle_character_selection(character_id: String) -> void:
	if not _selection_eligible_ids.has(character_id):
		return
	var existing := _selection_order.find(character_id)
	if existing >= 0:
		_selection_order.remove_at(existing)
	else:
		_selection_order.append(character_id)
	_update_selection_cursor()
	_represent()
	if _selection_order.size() == _selection_count:
		var selected: Array[String] = []
		for character: CharacterView in _current_view.party_members:
			if _selection_order.has(character.id):
				selected.append(character.id)
		_restore_pointer()
		character_selection_completed.emit(selected)


func _represent() -> void:
	if _current_view != null:
		present(_current_view, _selected_character_id)


func _focus_first_eligible() -> void:
	for row: Node in _party_list.find_children("*", "Button", true, false):
		if row is Button and not (row as Button).disabled:
			(row as Button).grab_focus()
			return


func _update_selection_cursor() -> void:
	var remaining := _selection_count - _selection_order.size()
	if remaining < 1:
		_restore_pointer()
		return
	_ensure_selection_cursor_label()
	_selection_cursor_label.text = str(remaining)
	_selection_cursor_label.visible = true
	set_process(true)
	_process(0.0)


func _restore_pointer() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	set_process(false)
	if is_instance_valid(_selection_cursor_label):
		_selection_cursor_label.visible = false
		_selection_cursor_label.text = ""


func _ensure_selection_cursor_label() -> void:
	if is_instance_valid(_selection_cursor_label):
		return
	_selection_cursor_layer = CanvasLayer.new()
	_selection_cursor_layer.name = "CharacterSelectionCursorLayer"
	_selection_cursor_layer.layer = 600
	add_child(_selection_cursor_layer)
	_selection_cursor_label = Label.new()
	_selection_cursor_label.name = "CharacterSelectionCursorCount"
	_selection_cursor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_cursor_label.add_theme_font_override("font", load("res://src/presentation/assets/fonts/AlegreyaSans-Bold.ttf") as Font)
	_selection_cursor_label.add_theme_font_size_override("font_size", 22)
	_selection_cursor_label.add_theme_color_override("font_color", Color("e0bc53"))
	_selection_cursor_label.add_theme_color_override("font_outline_color", Color("16191d"))
	_selection_cursor_label.add_theme_constant_override("outline_size", 3)
	_selection_cursor_layer.add_child(_selection_cursor_label)


func play_character_effect(character_id: String, first_resource_id: int, frame_count: int) -> void:
	if character_id.is_empty() or first_resource_id <= 0 or frame_count <= 0:
		return
	var row := _character_row(character_id)
	if row == null:
		return
	var base_icon := row.icon
	var tween := create_tween()
	for frame_index: int in frame_count:
		tween.tween_callback(_set_character_effect_frame.bind(row, base_icon, first_resource_id + frame_index))
		tween.tween_interval(0.055)
	tween.tween_callback(_restore_character_effect.bind(row, base_icon))


func _character_row(character_id: String) -> Button:
	for node: Node in _party_list.find_children("*", "Button", true, false):
		if node.has_meta("character_id") and String(node.get_meta("character_id")) == character_id:
			return node as Button
	return null


func _set_character_effect_frame(row: Button, base_icon: Texture2D, resource_id: int) -> void:
	if not is_instance_valid(row):
		return
	var image := Image.create(CLASSIC_PORTRAIT_STAGE_SIZE.x, CLASSIC_PORTRAIT_STAGE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_blend_centered(image, base_icon)
	_blend_centered(image, _resource_texture(resource_id))
	row.icon = ImageTexture.create_from_image(image)


static func _restore_character_effect(row: Button, base_icon: Texture2D) -> void:
	if is_instance_valid(row):
		row.icon = base_icon


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


func _roster_portrait_texture(character: CharacterView) -> Texture2D:
	var state := 2 if character.current_health <= CLASSIC_DEATH_HEALTH else 1 if character.current_health < 1 else 0
	var cache_key := "%s|%d" % [character.portrait_id, state]
	if _portrait_composites.has(cache_key):
		return _portrait_composites[cache_key] as Texture2D
	var portrait := _portrait_texture(character.portrait_id)
	if portrait == null and state == 0:
		return null
	var image := Image.create(CLASSIC_PORTRAIT_STAGE_SIZE.x, CLASSIC_PORTRAIT_STAGE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_blend_centered(image, portrait)
	if state > 0:
		_blend_centered(image, _resource_texture(CLASSIC_PORTRAIT_SHADE_CICN))
	if state == 2:
		_blend_centered(image, _resource_texture(CLASSIC_DEATH_MARKER_CICN))
	var composite := ImageTexture.create_from_image(image)
	_portrait_composites[cache_key] = composite
	return composite


func _resource_texture(resource_id: int) -> Texture2D:
	if _media == null:
		return null
	var asset := _media.asset_by_resource("cicn", resource_id)
	return _media.image_texture(asset) if asset != null and asset.is_picture() else null


static func _blend_centered(destination: Image, texture: Texture2D) -> void:
	if texture == null:
		return
	var source := texture.get_image()
	if source == null or source.is_empty():
		return
	var width := mini(source.get_width(), destination.get_width())
	var height := mini(source.get_height(), destination.get_height())
	var source_position := Vector2i((source.get_width() - width) / 2, (source.get_height() - height) / 2)
	var destination_position := Vector2i((destination.get_width() - width) / 2, (destination.get_height() - height) / 2)
	destination.blend_rect(source, Rect2i(source_position, Vector2i(width, height)), destination_position)


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
	for child: Node in _spellbook_footer.get_children():
		_spellbook_footer.remove_child(child)
		child.queue_free()
	_spellbook_footer.visible = false


func _ensure_controls() -> void:
	if _party_list == null:
		_party_list = get_node("RosterColumn/PartyScroll/PartyList") as VBoxContainer
	if _heading == null:
		_heading = get_node("RosterColumn/Heading") as Label
	if _spellbook_footer == null:
		_spellbook_footer = get_node("RosterColumn/SpellbookFooter") as VBoxContainer
	if _party_scroll == null:
		_party_scroll = get_node("RosterColumn/PartyScroll") as ScrollContainer
