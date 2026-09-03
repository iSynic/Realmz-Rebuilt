class_name ThiefEncounterInteraction
extends InteractionComponent

var _media: ClassicMediaCatalog
var _body: InteractionRequest.ThiefEncounterRequestBody
var _selected_character_index: int = 0
var _portrait: TextureRect
var _character_name: Label
var _action_grid: GridContainer


func configure(media: ClassicMediaCatalog) -> void:
	_media = media


func build(request: InteractionRequest) -> void:
	_body = request.body as InteractionRequest.ThiefEncounterRequestBody
	if _body == null:
		return
	var workspace := VBoxContainer.new()
	workspace.name = "ThiefEncounterWorkspace"
	workspace.add_theme_constant_override("separation", 7)
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_build_character_navigator())
	var action_pane := PanelContainer.new()
	action_pane.name = "ThiefActionPane"
	action_pane.theme_type_variation = &"ClassicInset"
	action_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var action_column := VBoxContainer.new()
	action_column.add_theme_constant_override("separation", 7)
	action_pane.add_child(action_column)
	_action_grid = GridContainer.new()
	_action_grid.name = "ThiefActionGrid"
	_action_grid.columns = 2
	_action_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_action_grid.add_theme_constant_override("h_separation", 6)
	_action_grid.add_theme_constant_override("v_separation", 6)
	action_column.add_child(_action_grid)
	var back := add_response_to(action_column, "Back to encounter", InteractionResponse.ThiefEncounterBody.new(&"back"))
	back.custom_minimum_size.y = 38.0
	workspace.add_child(action_pane)
	add_child(workspace)
	_render_character()
	if _body.sound_id != 0:
		call_deferred("_request_opening_sound")


func _render_character() -> void:
	if _body == null or _body.characters.is_empty():
		return
	_selected_character_index = clampi(_selected_character_index, 0, _body.characters.size() - 1)
	var character := _body.characters[_selected_character_index]
	_portrait.texture = _portrait_texture(character.portrait_id)
	_character_name.text = "%s · Thief actions" % character.name
	for child: Node in _action_grid.get_children():
		_action_grid.remove_child(child)
		child.queue_free()
	for action: InteractionRequestValue.ThiefAction in character.actions:
		var button := Button.new()
		button.text = "%s  %d" % [action.label, action.value]
		button.custom_minimum_size.y = 42.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not action.enabled
		button.tooltip_text = action.reason if not action.enabled else "%s ability %d" % [action.label, action.value]
		button.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.ThiefEncounterBody.new(&"attempt", character.id, action.index)))
		_action_grid.add_child(button)


func _build_character_navigator() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "ThiefCharacterNavigator"
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)
	var row := HBoxContainer.new()
	row.name = "ThiefCharacterSelectorRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	var previous := Button.new()
	previous.name = "ThiefPreviousCharacter"
	previous.text = "‹"
	previous.custom_minimum_size = Vector2(42.0, 42.0)
	previous.disabled = _body.characters.size() < 2
	previous.pressed.connect(_shift_character.bind(-1))
	row.add_child(previous)
	_portrait = TextureRect.new()
	_portrait.name = "ThiefCharacterPortrait"
	_portrait.custom_minimum_size = Vector2(54.0, 54.0)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(_portrait)
	var next := Button.new()
	next.name = "ThiefNextCharacter"
	next.text = "›"
	next.custom_minimum_size = Vector2(42.0, 42.0)
	next.disabled = _body.characters.size() < 2
	next.pressed.connect(_shift_character.bind(1))
	row.add_child(next)
	_character_name = Label.new()
	_character_name.theme_type_variation = &"ClassicHeading"
	_character_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_character_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_character_name)
	return panel


func _shift_character(delta: int) -> void:
	_selected_character_index = posmod(_selected_character_index + delta, _body.characters.size())
	_render_character()


func _portrait_texture(asset_id: String) -> Texture2D:
	if _media == null:
		return null
	return _media.image_texture(_media.asset_by_id(asset_id))


func _request_opening_sound() -> void:
	if is_inside_tree() and _body != null:
		presentation_sound_requested.emit(_body.sound_id)
