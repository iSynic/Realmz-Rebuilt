class_name LevelUpInteraction
extends InteractionComponent

const SpellSelectionChrome := preload("res://src/presentation/controllers/classic_spell_selection_chrome.gd")
const ClassicSpellLevelScript := preload("res://src/presentation/classic_spell_level.gd")
const GOLD := Color("e5c45c")
const CYAN := Color("8fcfd1")
const MUTED := Color("aeb6ba")

var _game_view: GameView
var _media: ClassicMediaCatalog
var _spell_buttons: Dictionary = {}
var _selected_spell_ids: Array[String] = []
var _selection_summary: Label
var _selection_warning: Label
var _confirm_button: Button
var _spell_record_title: Label
var _spell_record_cost: Label
var _spell_record_state: Label
var _spell_record_description: Label
var _spell_list: VBoxContainer
var _spell_list_heading: Label
var _selected_level: int = 1


func configure(game_view: GameView, media: ClassicMediaCatalog) -> void:
	_game_view = game_view
	_media = media


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.LevelUpRequestBody
	if body == null:
		add_hint("The level-up request is malformed.")
		return
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 320.0)
	add_theme_constant_override("separation", 6)
	if body.mode == &"result":
		_build_result(body)
	elif body.mode == &"spell-selection":
		_build_spell_selection(body)
	else:
		add_hint("The level-up request is malformed.")


func _build_result(body: InteractionRequest.LevelUpRequestBody) -> void:
	if body.character_id.is_empty() or body.gains == null:
		add_hint("The level result is unavailable.")
		return
	_build_header("Level Gained", "%s reached level %d" % [body.character_name, body.level])
	var columns := HBoxContainer.new()
	columns.name = "LevelResultColumns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 8)
	add_child(columns)
	_build_level_identity(columns, body)
	_build_gain_record(columns, body)
	_build_result_action(columns, body)


func _build_level_identity(parent: HBoxContainer, body: InteractionRequest.LevelUpRequestBody) -> void:
	var content := _pane(parent, "LevelIdentity", "Adventurer", 0.8)
	var portrait := TextureRect.new()
	portrait.name = "LevelPortrait"
	portrait.texture = _portrait(body.character_id)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(160.0, 220.0)
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(portrait)
	content.add_child(_label(body.character_name, GOLD, 18))
	content.add_child(_label("Level %d" % body.level, CYAN, 16))
	if portrait.texture == null:
		portrait.custom_minimum_size.y = 80.0
		content.add_child(_label("No exact portrait is available.", MUTED, 13))


func _build_gain_record(parent: HBoxContainer, body: InteractionRequest.LevelUpRequestBody) -> void:
	var content := _pane(parent, "LevelGains", "Committed Gains", 1.25)
	var grid := GridContainer.new()
	grid.name = "LevelGainGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	content.add_child(grid)
	for record: Dictionary in [
		{"label": "Stamina", "value": body.gains.stamina},
		{"label": "Spell Points", "value": body.gains.spell_points},
		{"label": "To Hit", "value": body.gains.to_hit},
		{"label": "Magic Resistance", "value": body.gains.magic_resistance},
	]:
		var card := PanelContainer.new()
		card.theme_type_variation = &"ClassicInset"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
		var facts := VBoxContainer.new()
		facts.alignment = BoxContainer.ALIGNMENT_CENTER
		facts.add_child(_label(String(record.label), MUTED, 14))
		facts.add_child(_label("%+d" % int(record.value), GOLD, 24))
		card.add_child(facts)


func _build_result_action(parent: HBoxContainer, body: InteractionRequest.LevelUpRequestBody) -> void:
	var content := _pane(parent, "LevelContinuation", "Adventure", 0.85)
	content.add_child(_label("These gains are already committed to the adventure.", MUTED, 14))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	var button := add_response_to(content, "Continue", InteractionResponse.LevelUpBody.new(&"continue", body.character_id))
	button.name = "LevelContinue"
	button.custom_minimum_size.y = 44.0


func _build_spell_selection(body: InteractionRequest.LevelUpRequestBody) -> void:
	if body.character_id.is_empty():
		add_hint("The spell-selection request is unavailable.")
		return
	_build_header("Learn Spells", body.character_name)
	_selected_spell_ids.clear()
	for spell: InteractionRequestValue.SpellChoice in body.spells:
		if spell.selected:
			_selected_spell_ids.append(spell.id)
	var available_levels := _available_spell_levels(body)
	_selected_level = available_levels[0] if not available_levels.is_empty() else 1
	var columns := HBoxContainer.new()
	columns.name = "LevelSpellColumns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 8)
	add_child(columns)
	_build_spell_level_rail(columns, body, available_levels)
	var list_content := _pane(columns, "LevelSpellCandidates", "", 1.45)
	_spell_list_heading = _label("", GOLD, 17)
	_spell_list_heading.theme_type_variation = &"ClassicHeading"
	list_content.add_child(_spell_list_heading)
	var scroll := ScrollContainer.new()
	scroll.name = "LevelSpellScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_content.add_child(scroll)
	_spell_list = VBoxContainer.new()
	_spell_list.name = "LevelSpellList"
	_spell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spell_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_spell_list)
	_rebuild_spell_list(body)
	var action_content := _pane(columns, "LevelSpellAllowance", "Spell Record", 0.9)
	_selection_summary = _label("", CYAN, 16)
	action_content.add_child(_selection_summary)
	_selection_warning = _label("", MUTED, 13)
	_selection_warning.name = "LevelSpellBudgetNotice"
	action_content.add_child(_selection_warning)
	var record := PanelContainer.new()
	record.name = "LevelSelectedSpellRecord"
	record.theme_type_variation = &"ClassicInset"
	record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_content.add_child(record)
	var record_content := VBoxContainer.new()
	record_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	record_content.add_theme_constant_override("separation", 4)
	record.add_child(record_content)
	_spell_record_title = _label("", GOLD, 18)
	_spell_record_title.theme_type_variation = &"ClassicHeading"
	record_content.add_child(_spell_record_title)
	_spell_record_cost = _label("", CYAN, 15)
	record_content.add_child(_spell_record_cost)
	_spell_record_state = _label("", MUTED, 14)
	record_content.add_child(_spell_record_state)
	_spell_record_description = _label("", Color("eee9db"), 14)
	_spell_record_description.name = "LevelSpellDescription"
	_spell_record_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	record_content.add_child(_spell_record_description)
	_confirm_button = Button.new()
	_confirm_button.name = "LevelSpellConfirm"
	_confirm_button.text = "Confirm spell selection"
	_confirm_button.theme_type_variation = &"ClassicTheldrowButton"
	_confirm_button.custom_minimum_size.y = 44.0
	_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_button.pressed.connect(_submit_spells.bind(body))
	action_content.add_child(_confirm_button)
	if not body.spells.is_empty():
		var initial_spell := _first_spell_at_level(body, _selected_level)
		_refresh_spell_record(initial_spell)
	_refresh_spell_selection(body)


func _build_spell_level_rail(parent: HBoxContainer, body: InteractionRequest.LevelUpRequestBody, available_levels: Array[int]) -> void:
	var panel := PanelContainer.new()
	panel.name = "LevelSpellLevelRail"
	panel.theme_type_variation = &"ClassicTextWell"
	panel.custom_minimum_size.x = 112.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.45
	parent.add_child(panel)
	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 4)
	panel.add_child(rail)
	rail.add_child(SpellSelectionChrome.level_heading())
	var group := ButtonGroup.new()
	for level: int in range(1, 8):
		var button := SpellSelectionChrome.level_button(level, level == _selected_level, available_levels.has(level), _select_spell_level.bind(body, level), "No learnable level %d spells" % level)
		button.name = "LevelSpellLevel%d" % level
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rail.add_child(button)


func _rebuild_spell_list(body: InteractionRequest.LevelUpRequestBody) -> void:
	if _spell_list == null:
		return
	for child: Node in _spell_list.get_children():
		_spell_list.remove_child(child)
		child.queue_free()
	_spell_buttons.clear()
	var spells := _spells_at_level(body, _selected_level)
	_spell_list_heading.text = "Level %d — Available Spells" % _selected_level
	var spent := _selected_spell_points(body)
	var remaining := maxi(body.point_total - spent, 0)
	for spell: InteractionRequestValue.SpellChoice in spells:
		var selected := _selected_spell_ids.has(spell.id)
		var affordable := selected or spell.cost <= remaining
		var tooltip := spell.name if affordable else "%s costs %d points; only %d remain." % [spell.name, spell.cost, remaining]
		var button := SpellSelectionChrome.spell_button("LevelSpell_%s" % spell.id, "%s  •  %d point%s" % [spell.name, spell.cost, "" if spell.cost == 1 else "s"], selected, affordable, tooltip, _toggle_spell.bind(body, spell.id), _spell_icon(body.character_id, spell.id))
		button.theme_type_variation = &"ClassicTheldrowButton"
		button.set_meta(&"spell_id", spell.id)
		_spell_buttons[spell.id] = button
		_spell_list.add_child(button)


func _select_spell_level(body: InteractionRequest.LevelUpRequestBody, level: int) -> void:
	_selected_level = level
	_rebuild_spell_list(body)
	var spell := _first_spell_at_level(body, level)
	if spell != null:
		_refresh_spell_record(spell)


func _available_spell_levels(body: InteractionRequest.LevelUpRequestBody) -> Array[int]:
	var levels: Array[int] = []
	for spell: InteractionRequestValue.SpellChoice in body.spells:
		var level := ClassicSpellLevelScript.from_classic_id(spell.classic_id)
		if not levels.has(level):
			levels.append(level)
	levels.sort()
	return levels


func _spells_at_level(body: InteractionRequest.LevelUpRequestBody, level: int) -> Array[InteractionRequestValue.SpellChoice]:
	var spells: Array[InteractionRequestValue.SpellChoice] = []
	for spell: InteractionRequestValue.SpellChoice in body.spells:
		if ClassicSpellLevelScript.from_classic_id(spell.classic_id) == level:
			spells.append(spell)
	return spells


func _first_spell_at_level(body: InteractionRequest.LevelUpRequestBody, level: int) -> InteractionRequestValue.SpellChoice:
	var spells := _spells_at_level(body, level)
	return spells[0] if not spells.is_empty() else null


func _toggle_spell(body: InteractionRequest.LevelUpRequestBody, spell_id: String) -> void:
	var button := _spell_buttons.get(spell_id) as Button
	if button == null:
		return
	if button.button_pressed and not _selected_spell_ids.has(spell_id):
		var spell := _spell_choice(body, spell_id)
		if spell == null or _selected_spell_points(body) + spell.cost > body.point_total:
			button.button_pressed = false
			_refresh_spell_selection(body)
			return
		_selected_spell_ids.append(spell_id)
	elif not button.button_pressed:
		_selected_spell_ids.erase(spell_id)
	for spell: InteractionRequestValue.SpellChoice in body.spells:
		if spell.id == spell_id:
			_refresh_spell_record(spell)
			break
	_refresh_spell_selection(body)


func _refresh_spell_selection(body: InteractionRequest.LevelUpRequestBody) -> void:
	if _selection_summary == null:
		return
	var points := _selected_spell_points(body)
	var remaining := body.point_total - points
	_selection_summary.text = "Selected %d / %d points" % [points, body.point_total]
	if _selection_warning != null:
		_selection_warning.text = "Selection exceeds the allowance by %d points. Remove a selected spell to continue." % -remaining if remaining < 0 else "%d point%s may be banked for later." % [remaining, "" if remaining == 1 else "s"]
		_selection_warning.add_theme_color_override("font_color", Color("e58b72") if remaining < 0 else MUTED)
	if _confirm_button != null:
		_confirm_button.disabled = remaining < 0
		_confirm_button.tooltip_text = "Remove selected spells until the total is within the allowance." if remaining < 0 else "Confirm this selection; unspent points will be banked."
	for spell: InteractionRequestValue.SpellChoice in body.spells:
		var button := _spell_buttons.get(spell.id) as Button
		if button == null:
			continue
		var selected := _selected_spell_ids.has(spell.id)
		button.button_pressed = selected
		button.disabled = not selected and spell.cost > maxi(remaining, 0)
		button.tooltip_text = spell.name if not button.disabled else "%s costs %d points; only %d remain." % [spell.name, spell.cost, maxi(remaining, 0)]


func _selected_spell_points(body: InteractionRequest.LevelUpRequestBody) -> int:
	var points := 0
	for spell: InteractionRequestValue.SpellChoice in body.spells:
		if _selected_spell_ids.has(spell.id):
			points += spell.cost
	return points


func _spell_choice(body: InteractionRequest.LevelUpRequestBody, spell_id: String) -> InteractionRequestValue.SpellChoice:
	for spell: InteractionRequestValue.SpellChoice in body.spells:
		if spell.id == spell_id:
			return spell
	return null


func _refresh_spell_record(spell: InteractionRequestValue.SpellChoice) -> void:
	if _spell_record_title == null:
		return
	_spell_record_title.text = spell.name
	_spell_record_cost.text = "%d selection point%s" % [spell.cost, "" if spell.cost == 1 else "s"]
	_spell_record_state.text = "Selected" if _selected_spell_ids.has(spell.id) else "Available"
	_spell_record_description.text = spell.description.strip_edges()
	_spell_record_description.visible = not _spell_record_description.text.is_empty()


func _submit_spells(body: InteractionRequest.LevelUpRequestBody) -> void:
	if _selected_spell_points(body) > body.point_total:
		_refresh_spell_selection(body)
		return
	var selected_ids: Array[String] = []
	for spell: InteractionRequestValue.SpellChoice in body.spells:
		if _selected_spell_ids.has(spell.id):
			selected_ids.append(spell.id)
	response_body_submitted.emit(InteractionResponse.LevelUpBody.new(&"confirm-spells", body.character_id, selected_ids))


func _build_header(title: String, subtitle: String) -> void:
	var row := HBoxContainer.new()
	row.name = "LevelHeader"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)
	var heading := _label(title, GOLD, 20)
	heading.theme_type_variation = &"ClassicHeading"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	var context := _label(subtitle, CYAN, 15)
	context.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(context)


func _pane(parent: HBoxContainer, pane_name: String, title: String, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = pane_name
	panel.theme_type_variation = &"ClassicTextWell"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	var heading := _label(title, GOLD, 16)
	heading.theme_type_variation = &"ClassicHeading"
	content.add_child(heading)
	return content


func _label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	return label


func _character(character_id: String) -> CharacterView:
	if _game_view == null:
		return null
	for character: CharacterView in _game_view.party_members:
		if character.id == character_id:
			return character
	return null


func _portrait(character_id: String) -> Texture2D:
	var character := _character(character_id)
	return _media.image_texture(_media.asset_by_id(character.portrait_id)) if character != null and _media != null and not character.portrait_id.is_empty() else null


func _spell_icon(character_id: String, spell_id: String) -> Texture2D:
	var character := _character(character_id)
	if character == null or _media == null:
		return null
	for spell: SpellView in character.spells:
		if spell.id == spell_id and spell.icon_id > 0:
			return _media.image_texture(_media.asset_by_resource(spell.icon_resource_type, spell.icon_id))
	return null
