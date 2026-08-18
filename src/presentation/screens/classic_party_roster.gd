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
var _spellbook_level: int = 1
var _spellbook_spell_id: String = ""
var _spellbook_list: ItemList
var _spellbook_power_row: HBoxContainer
var _spellbook_details: Label
var _spellbook_cast: Button


func _exit_tree() -> void:
	_restore_pointer()


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	_media = media


func present(view: GameView, selected_character_id: String = "") -> void:
	_ensure_controls()
	_combat_spellbook_active = false
	_current_view = view
	_selected_character_id = selected_character_id
	_clear()
	if view == null or not view.session_started:
		_heading.text = "Party"
		_add_empty("No active party")
		return
	_heading.text = "Party • Pick %d" % (_selection_count - _selection_order.size()) if character_selection_active() else "Party • %d / 6" % view.party_members.size()
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
	_combat_spellbook_active = true
	_spellbook_options.assign(options)
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
	selector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	selector.add_theme_constant_override("separation", 4)
	_party_list.add_child(selector)
	selector.add_child(_build_spell_level_rail(available_levels))
	_spellbook_list = ItemList.new()
	_spellbook_list.name = "CombatSpellList"
	_spellbook_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spellbook_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spellbook_list.select_mode = ItemList.SELECT_SINGLE
	_spellbook_list.item_selected.connect(_on_spellbook_spell_selected)
	selector.add_child(_spellbook_list)
	_spellbook_details = Label.new()
	_spellbook_details.name = "CombatSpellDetails"
	_spellbook_details.custom_minimum_size.y = 104.0
	_spellbook_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spellbook_details.add_theme_color_override("font_color", Color("d8d9d2"))
	_party_list.add_child(_spellbook_details)
	var power_heading := Label.new()
	power_heading.text = "Power"
	power_heading.add_theme_color_override("font_color", Color("63d8e7"))
	_party_list.add_child(power_heading)
	_spellbook_power_row = HBoxContainer.new()
	_spellbook_power_row.name = "CombatSpellPowerChoices"
	_spellbook_power_row.add_theme_constant_override("separation", 3)
	_party_list.add_child(_spellbook_power_row)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	_spellbook_cast = Button.new()
	_spellbook_cast.name = "CombatSpellAim"
	_spellbook_cast.theme_type_variation = &"BattleCommandButton"
	_spellbook_cast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spellbook_cast.pressed.connect(_on_spellbook_cast_pressed)
	actions.add_child(_spellbook_cast)
	var back := Button.new()
	back.name = "CombatSpellbookBack"
	back.text = "Back"
	back.theme_type_variation = &"BattleCommandButton"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void: combat_spellbook_back_requested.emit())
	actions.add_child(back)
	_party_list.add_child(actions)
	_refresh_spellbook_list()


func _build_spell_level_rail(levels: Array[int]) -> VBoxContainer:
	var rail := VBoxContainer.new()
	rail.name = "CombatSpellLevels"
	rail.custom_minimum_size.x = 34.0
	rail.add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	for level: int in range(1, 8):
		var button := Button.new()
		button.text = str(level)
		button.custom_minimum_size = Vector2(32.0, 28.0)
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
	_spellbook_list.clear()
	var spell_ids: Array[String] = []
	for option: InteractionRequestValue.CastOption in _spellbook_options:
		if _classic_spell_level(option.spell_id) != _spellbook_level or spell_ids.has(option.spell_id):
			continue
		spell_ids.append(option.spell_id)
		_spellbook_list.add_item(option.spell_name)
		_spellbook_list.set_item_metadata(_spellbook_list.item_count - 1, option.spell_id)
	if _spellbook_list.item_count == 0:
		_spellbook_spell_id = ""
		_refresh_spellbook_power_choices()
		return
	var selected_index := spell_ids.find(_spellbook_spell_id)
	if selected_index < 0:
		selected_index = 0
	_spellbook_list.select(selected_index)
	_on_spellbook_spell_selected(selected_index)


func _on_spellbook_spell_selected(index: int) -> void:
	_spellbook_spell_id = String(_spellbook_list.get_item_metadata(index))
	_refresh_spellbook_power_choices()


func _refresh_spellbook_power_choices() -> void:
	for child: Node in _spellbook_power_row.get_children():
		_spellbook_power_row.remove_child(child)
		child.queue_free()
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
		_spellbook_details.text = "No legal power is available."
		_spellbook_cast.disabled = true
		return
	_select_spellbook_power(representatives[0])


func _select_spellbook_power(option: InteractionRequestValue.CastOption) -> void:
	for child: Node in _spellbook_power_row.get_children():
		if child is Button:
			(child as Button).button_pressed = (child as Button).get_meta("cast_option") == option
	_spellbook_cast.set_meta("cast_option", option)
	_spellbook_cast.disabled = false
	_spellbook_cast.text = "Cast" if option.target_mode == &"automatic" else "Aim on battlefield"
	var target_text := option.target_name if not option.target_name.is_empty() else String(option.target_mode).replace("_", " ").capitalize()
	if option.target_mode == &"sequence":
		target_text = "Choose up to %d targets" % option.maximum_targets
	_spellbook_details.text = "%s\nPower %d • Cost %d SP\nTarget • %s" % [option.spell_name, option.power, option.cost, target_text]


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
	row_container.custom_minimum_size.y = 58.0
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
	row.tooltip_text = "Level %d • Movement %d/%d" % [character.level, character.movement, character.maximum_movement]
	var selection_eligible := _selection_eligible_ids.has(character.id)
	if character_selection_active() and not selection_eligible:
		row.disabled = true
		row.tooltip_text = "This character is not eligible for the current selection."
	var condition_text := _condition_summary(character.condition_values)
	var action_fact := "SP %d/%d" % [character.spell_points, character.maximum_spell_points] if character.maximum_spell_points > 0 else "Attacks %d" % character.normal_attacks
	row.text = "%s\n%s / %s  •  Stamina %d/%d\n%s  •  AR %d%s" % [
		character.name,
		character.race_name,
		character.caste_name,
		character.current_health,
		character.maximum_health,
		action_fact,
		character.armor,
		"  •  %s" % condition_text if not condition_text.is_empty() else "",
	]
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
		var auto_toggle := CheckButton.new()
		auto_toggle.name = "CombatAuto"
		auto_toggle.text = "Auto"
		auto_toggle.custom_minimum_size.x = 52.0
		var auto_available := character.current_health > 0 and not character.traitor
		auto_toggle.disabled = not auto_available
		auto_toggle.tooltip_text = "Persistent Auto for this character's next combat activation." if auto_available else "Persistent Auto requires a living loyal party character."
		auto_toggle.button_pressed = auto_character_ids.has(character.id)
		auto_toggle.toggled.connect(func(enabled: bool) -> void: combat_auto_changed.emit(character.id, enabled))
		row_container.add_child(auto_toggle)
	_party_list.add_child(row_container)


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


func _ensure_controls() -> void:
	if _party_list == null:
		_party_list = get_node("RosterColumn/PartyScroll/PartyList") as VBoxContainer
	if _heading == null:
		_heading = get_node("RosterColumn/Heading") as Label
