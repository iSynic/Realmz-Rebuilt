## Presents the dynamic level up interaction without owning gameplay state.

class_name LevelUpInteraction
extends InteractionComponent

const SpellSelectionChrome := preload("res://src/ui/magic/classic_spell_selection_chrome.gd")
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
	var body := request.body as LevelUpRequestBody
	if body == null:
		add_hint("The level-up request is malformed.")
		return
	%LevelResultColumns.visible = false
	%LevelSpellColumns.visible = false
	if body.mode == &"result":
		_build_result(body)
	elif body.mode == &"spell-selection":
		_build_spell_selection(body)
	else:
		add_hint("The level-up request is malformed.")


func _build_result(body: LevelUpRequestBody) -> void:
	if body.character_id.is_empty() or body.gains == null:
		add_hint("The level result is unavailable.")
		return
	_build_header("Level Gained", "%s reached level %d" % [body.character_name, body.level])
	%LevelResultColumns.visible = true
	var portrait := %LevelPortrait as TextureRect
	portrait.texture = _portrait(body.character_id)
	portrait.custom_minimum_size.y = 80.0 if portrait.texture == null else 220.0
	%PortraitUnavailable.visible = portrait.texture == null
	%CharacterName.text = body.character_name
	%CharacterLevel.text = "Level %d" % body.level
	%StaminaValue.text = "%+d" % body.gains.stamina
	%SpellPointsValue.text = "%+d" % body.gains.spell_points
	%ToHitValue.text = "%+d" % body.gains.to_hit
	%MagicResistanceValue.text = "%+d" % body.gains.magic_resistance
	var continue_button := %LevelContinue as Button
	continue_button.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.LevelUpBody.new(&"continue", body.character_id)), CONNECT_ONE_SHOT)


func _build_spell_selection(body: LevelUpRequestBody) -> void:
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
	%LevelSpellColumns.visible = true
	_build_spell_level_rail(body, available_levels)
	_spell_list_heading = %LevelSpellListHeading as Label
	_spell_list = %LevelSpellList as VBoxContainer
	_rebuild_spell_list(body)
	_selection_summary = %SelectionSummary as Label
	_selection_warning = %LevelSpellBudgetNotice as Label
	_spell_record_title = %Title as Label
	_spell_record_cost = %Cost as Label
	_spell_record_state = %State as Label
	_spell_record_description = %LevelSpellDescription as Label
	_confirm_button = %LevelSpellConfirm as Button
	_confirm_button.pressed.connect(_submit_spells.bind(body))
	if not body.spells.is_empty():
		var initial_spell := _first_spell_at_level(body, _selected_level)
		_refresh_spell_record(initial_spell)
	_refresh_spell_selection(body)


func _build_spell_level_rail(body: LevelUpRequestBody, available_levels: Array[int]) -> void:
	var rail := %Rail as VBoxContainer
	for child: Node in rail.get_children():
		rail.remove_child(child)
		child.queue_free()
	rail.add_child(SpellSelectionChrome.level_heading())
	var group := ButtonGroup.new()
	for level: int in range(1, 8):
		var button := SpellSelectionChrome.level_button(level, level == _selected_level, available_levels.has(level), _select_spell_level.bind(body, level), "No learnable level %d spells" % level)
		button.name = "LevelSpellLevel%d" % level
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rail.add_child(button)


func _rebuild_spell_list(body: LevelUpRequestBody) -> void:
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


func _select_spell_level(body: LevelUpRequestBody, level: int) -> void:
	_selected_level = level
	_rebuild_spell_list(body)
	var spell := _first_spell_at_level(body, level)
	if spell != null:
		_refresh_spell_record(spell)


func _available_spell_levels(body: LevelUpRequestBody) -> Array[int]:
	var levels: Array[int] = []
	for spell: InteractionRequestValue.SpellChoice in body.spells:
		var level := ClassicSpellLevel.from_classic_id(spell.classic_id)
		if not levels.has(level):
			levels.append(level)
	levels.sort()
	return levels


func _spells_at_level(body: LevelUpRequestBody, level: int) -> Array[InteractionRequestValue.SpellChoice]:
	var spells: Array[InteractionRequestValue.SpellChoice] = []
	for spell: InteractionRequestValue.SpellChoice in body.spells:
		if ClassicSpellLevel.from_classic_id(spell.classic_id) == level:
			spells.append(spell)
	return spells


func _first_spell_at_level(body: LevelUpRequestBody, level: int) -> InteractionRequestValue.SpellChoice:
	var spells := _spells_at_level(body, level)
	return spells[0] if not spells.is_empty() else null


func _toggle_spell(body: LevelUpRequestBody, spell_id: String) -> void:
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


func _refresh_spell_selection(body: LevelUpRequestBody) -> void:
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


func _selected_spell_points(body: LevelUpRequestBody) -> int:
	var points := 0
	for spell: InteractionRequestValue.SpellChoice in body.spells:
		if _selected_spell_ids.has(spell.id):
			points += spell.cost
	return points


func _spell_choice(body: LevelUpRequestBody, spell_id: String) -> InteractionRequestValue.SpellChoice:
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


func _submit_spells(body: LevelUpRequestBody) -> void:
	if _selected_spell_points(body) > body.point_total:
		_refresh_spell_selection(body)
		return
	var selected_ids: Array[String] = []
	for spell: InteractionRequestValue.SpellChoice in body.spells:
		if _selected_spell_ids.has(spell.id):
			selected_ids.append(spell.id)
	response_body_submitted.emit(InteractionResponse.LevelUpBody.new(&"confirm-spells", body.character_id, selected_ids))


func _build_header(title: String, subtitle: String) -> void:
	%Heading.text = title
	%Context.text = subtitle


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
