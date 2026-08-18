class_name LevelUpInteraction
extends InteractionComponent

const GOLD := Color("e5c45c")
const CYAN := Color("8fcfd1")
const MUTED := Color("aeb6ba")

var _game_view: GameView
var _media: ClassicMediaCatalog
var _spell_list: ItemList
var _selection_summary: Label


func configure(game_view: GameView, media: ClassicMediaCatalog) -> void:
	_game_view = game_view
	_media = media


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.LevelUpRequestBody
	if body == null:
		add_hint("The level-up request is malformed.")
		return
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 500.0)
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
	var columns := HBoxContainer.new()
	columns.name = "LevelSpellColumns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 8)
	add_child(columns)
	var list_content := _pane(columns, "LevelSpellCandidates", "Available Spells", 1.6)
	_spell_list = ItemList.new()
	_spell_list.name = "LevelSpellList"
	_spell_list.select_mode = ItemList.SELECT_MULTI
	_spell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spell_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spell_list.fixed_icon_size = Vector2i(32, 32)
	for spell: InteractionRequestValue.SpellChoice in body.spells:
		_spell_list.add_item("%s  •  %d point%s" % [spell.name, spell.cost, "" if spell.cost == 1 else "s"], _spell_icon(body.character_id, spell.id))
		_spell_list.set_item_metadata(_spell_list.item_count - 1, spell.id)
		_spell_list.set_item_tooltip_enabled(_spell_list.item_count - 1, false)
		if spell.selected:
			_spell_list.select(_spell_list.item_count - 1, false)
	_spell_list.multi_selected.connect(func(_index: int, _selected: bool) -> void: _refresh_spell_selection(body))
	list_content.add_child(_spell_list)
	var action_content := _pane(columns, "LevelSpellAllowance", "Spell Allowance", 0.9)
	_selection_summary = _label("", CYAN, 16)
	action_content.add_child(_selection_summary)
	action_content.add_child(_label("Choose from the complete source-authorized list. The session validates the final set.", MUTED, 14))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_content.add_child(spacer)
	var confirm := Button.new()
	confirm.name = "LevelSpellConfirm"
	confirm.text = "Confirm spell selection"
	confirm.custom_minimum_size.y = 44.0
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(_submit_spells.bind(body))
	action_content.add_child(confirm)
	_refresh_spell_selection(body)


func _refresh_spell_selection(body: InteractionRequest.LevelUpRequestBody) -> void:
	if _selection_summary == null or _spell_list == null:
		return
	var points := 0
	for index: int in _spell_list.get_selected_items():
		var id := String(_spell_list.get_item_metadata(index))
		for spell: InteractionRequestValue.SpellChoice in body.spells:
			if spell.id == id:
				points += spell.cost
				break
	_selection_summary.text = "Selected %d / %d points" % [points, body.point_total]


func _submit_spells(body: InteractionRequest.LevelUpRequestBody) -> void:
	var selected_ids: Array[String] = []
	for index: int in _spell_list.get_selected_items():
		selected_ids.append(String(_spell_list.get_item_metadata(index)))
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
