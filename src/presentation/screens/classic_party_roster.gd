class_name ClassicPartyRoster
extends PanelContainer

signal character_selected(character_id: String)
signal combat_auto_changed(character_id: String, enabled: bool)
signal character_selection_completed(character_ids: Array[String])
signal combat_spell_cast_requested(option: InteractionRequestValue.CastOption)
signal combat_spellbook_back_requested

const MUTED := Color("9da8aa")

@onready var _party_list: VBoxContainer = %PartyList
@onready var _heading: Label = %Heading
@onready var _spellbook_footer: VBoxContainer = %SpellbookFooter
@onready var _party_scroll: ScrollContainer = %PartyScroll

var _media: ClassicMediaCatalog
var _selected_character_id: String = ""
var _current_view: GameView
var _selection_request_id: String = ""
var _selection_count: int = 0
var _selection_eligible_ids: Array[String] = []
var _selection_order: Array[String] = []
var _selection_cursors: Dictionary = {}
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


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	_media = media


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


func present_combat_spellbook(actor_id: String, options: Array[InteractionRequestValue.CastOption]) -> void:
	_ensure_controls()
	_party_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
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
	for option: InteractionRequestValue.CastOption in _spellbook_options:
		var level := _classic_spell_level(option.spell_id)
		if not available_levels.has(level):
			available_levels.append(level)
	available_levels.sort()
	if available_levels.is_empty():
		_add_empty("No legal combat spell is available.")
		return
	if not available_levels.has(_spellbook_level):
		_spellbook_level = available_levels[0]
	var selector := HBoxContainer.new()
	selector.name = "CombatSpellbookSelector"
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.add_theme_constant_override("separation", 4)
	_party_list.add_child(selector)
	selector.add_child(_build_spell_level_rail(available_levels))
	var spell_list_panel := PanelContainer.new()
	spell_list_panel.name = "CombatSpellListPanel"
	spell_list_panel.theme_type_variation = &"ClassicInset"
	spell_list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spell_list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	selector.add_child(spell_list_panel)
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
	_spellbook_details.custom_minimum_size.y = 136.0
	_spellbook_detail_column = VBoxContainer.new()
	_spellbook_detail_column.add_theme_constant_override("separation", 3)
	_spellbook_details.add_child(_spellbook_detail_column)
	_spellbook_footer.add_child(_spellbook_details)
	_spellbook_power_row = HBoxContainer.new()
	_spellbook_power_row.name = "CombatSpellPowerChoices"
	_spellbook_power_row.add_theme_constant_override("separation", 3)
	_spellbook_footer.add_child(_spellbook_power_row)
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
	rail.custom_minimum_size.x = 72.0
	rail.add_theme_constant_override("separation", 1)
	var title_art := TextureRect.new()
	title_art.texture = ClassicUiAssetCatalog.texture(&"spells.label.level")
	title_art.custom_minimum_size = Vector2(68.0, 18.0)
	title_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rail.add_child(title_art)
	var group := ButtonGroup.new()
	for level: int in range(1, 8):
		var button := Button.new()
		button.text = str(level)
		button.custom_minimum_size = Vector2(68.0, 24.0)
		button.disabled = not levels.has(level)
		button.button_pressed = level == _spellbook_level
		button.toggle_mode = true
		button.button_group = group
		button.tooltip_text = "Spell level %d" % level
		button.pressed.connect(func() -> void:
			_spellbook_level = level
			_refresh_spellbook_list()
		)
		rail.add_child(button)
	return rail


func _refresh_spellbook_list() -> void:
	for child: Node in _spellbook_list.get_children():
		_spellbook_list.remove_child(child)
		child.queue_free()
	_spellbook_spell_buttons.clear()
	var spell_ids: Array[String] = []
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
		var tooltip := spell.description if spell != null and not spell.description.is_empty() else representative.spell_name
		var button := ClassicSpellSelectionChrome.spell_button(
			"CombatSpell%s" % spell_id.replace(".", "_"),
			representative.spell_name,
			spell_id == _spellbook_spell_id,
			true,
			tooltip,
			_select_spellbook_spell.bind(spell_id)
		)
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
	power_art.custom_minimum_size = Vector2(80.0, 24.0)
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
		button.text = str(option.power)
		button.tooltip_text = "Power %d • %d SP" % [option.power, option.cost]
		button.toggle_mode = true
		button.set_meta("cast_option", option)
		button.pressed.connect(func() -> void: _select_spellbook_power(option))
		_spellbook_power_row.add_child(button)
	if representatives.is_empty():
		_present_spellbook_unavailable("No legal power is available.")
		_spellbook_cast.disabled = true
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
	var title := Label.new()
	title.theme_type_variation = &"ClassicHeading"
	title.text = option.spell_name
	_spellbook_detail_column.add_child(title)
	var actor := _spellbook_actor_view()
	var resource_line := "Level %d  •  Power %d" % [_classic_spell_level(option.spell_id), option.power]
	if spell != null and absi(spell.cost) != option.cost:
		resource_line += "  •  Base %d SP" % absi(spell.cost)
	resource_line += "  •  Cost %d SP" % option.cost
	if actor != null:
		resource_line += "  •  SP %d/%d" % [actor.spell_points, actor.maximum_spell_points]
	var resource_label := _spellbook_label(resource_line, MUTED, 13)
	resource_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resource_label.max_lines_visible = 2
	_spellbook_detail_column.add_child(resource_label)
	var target_line := _spellbook_label("Target  •  %s" % target_text, Color("63d8e7"), 13)
	target_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	target_line.tooltip_text = target_text
	_spellbook_detail_column.add_child(target_line)
	if spell != null:
		var target_and_facts := HBoxContainer.new()
		target_and_facts.add_theme_constant_override("separation", 6)
		var target_art_id := _spellbook_target_art_id(spell)
		if not target_art_id.is_empty() and size.x >= 280.0:
			var target_art := TextureRect.new()
			target_art.texture = ClassicUiAssetCatalog.texture(target_art_id)
			target_art.custom_minimum_size = Vector2(52.0, 52.0)
			target_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			target_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			target_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			target_and_facts.add_child(target_art)
		var facts := GridContainer.new()
		facts.columns = 2
		facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		facts.add_theme_constant_override("h_separation", 8)
		facts.add_theme_constant_override("v_separation", 1)
		_add_spellbook_fact(facts, "Targets", str(option.power if spell.target_type < 1 else 1))
		_add_spellbook_fact(facts, "Range", str(absi(spell.range_min + spell.range_max * option.power)))
		_add_spellbook_fact(facts, "Damage", _spellbook_scaled_pair(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, option.power))
		_add_spellbook_fact(facts, "Duration", _spellbook_scaled_pair(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, option.power, true))
		_add_spellbook_fact(facts, "Magic resist", _spellbook_magic_resistance(spell, option.power))
		_add_spellbook_fact(facts, "Saving throw", _spellbook_saving_throw(spell, option.power))
		target_and_facts.add_child(facts)
		_spellbook_detail_column.add_child(target_and_facts)
	var description := spell.description.strip_edges() if spell != null else ""
	if not description.is_empty():
		var description_well := PanelContainer.new()
		description_well.theme_type_variation = &"ClassicTextWell"
		var description_label := _spellbook_label(description, Color("eee9db"), 15)
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.max_lines_visible = 3
		description_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		description_well.add_child(description_label)
		_spellbook_detail_column.add_child(description_well)


func _present_spellbook_unavailable(message: String) -> void:
	_clear_container(_spellbook_detail_column)
	_spellbook_detail_column.add_child(_spellbook_label(message, MUTED, 15))


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


static func _spellbook_target_art_id(spell: SpellView) -> StringName:
	if spell.target_type == 5 and spell.target_size == 0:
		return &"spells.target.self"
	return {
		7: &"spells.target.party",
		9: &"spells.target.all_friendly",
		10: &"spells.target.all_enemy",
		12: &"spells.target.everyone",
	}.get(spell.target_type, &"")


static func _add_spellbook_fact(parent: GridContainer, name: String, value: String) -> void:
	var name_label := _spellbook_label(name, Color("e7d078"), 13)
	name_label.custom_minimum_size.x = 82.0
	parent.add_child(name_label)
	var value_label := _spellbook_label(value, Color("d8d9d2"), 13)
	value_label.custom_minimum_size.x = 44.0
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	if classic_id < 1101:
		return 1
	return clampi(int(classic_id % 1000 / 100), 1, 7)


func _add_character(character: CharacterView, combat_active: bool, auto_character_ids: Array[String]) -> void:
	var row_container := HBoxContainer.new()
	row_container.custom_minimum_size.y = 54.0
	row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_container.add_theme_constant_override("separation", 3)
	var row := Button.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_meta("character_id", character.id)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_theme_constant_override("icon_max_width", 42)
	row.toggle_mode = not character_selection_active()
	row.button_pressed = not character_selection_active() and character.id == _selected_character_id
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
	var portrait := _portrait_texture(character.portrait_id)
	if portrait != null:
		row.icon = portrait
	row.pressed.connect(func() -> void:
		if character_selection_active():
			_toggle_character_selection(character.id)
			return
		_selected_character_id = character.id
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
	if not _selection_cursors.has(remaining):
		_selection_cursors[remaining] = _number_cursor(remaining)
	Input.set_custom_mouse_cursor(_selection_cursors[remaining], Input.CURSOR_ARROW, Vector2(8.0, 10.0))


func _restore_pointer() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


static func _number_cursor(number: int) -> ImageTexture:
	var patterns := {
		1: ["010", "110", "010", "010", "111"], 2: ["110", "001", "010", "100", "111"],
		3: ["110", "001", "010", "001", "110"], 4: ["101", "101", "111", "001", "001"],
		5: ["111", "100", "110", "001", "110"], 6: ["011", "100", "111", "101", "111"],
	}
	var image := Image.create(18, 22, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var pattern: Array = patterns.get(number, patterns[1])
	for y: int in pattern.size():
		for x: int in 3:
			if String(pattern[y]).substr(x, 1) != "1":
				continue
			for pixel_y: int in 3:
				for pixel_x: int in 3:
					image.set_pixel(4 + x * 3 + pixel_x, 3 + y * 3 + pixel_y, Color("e0bc53"))
	return ImageTexture.create_from_image(image)


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
