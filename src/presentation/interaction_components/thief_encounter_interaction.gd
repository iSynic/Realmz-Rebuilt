class_name ThiefEncounterInteraction
extends InteractionComponent

var _media: ClassicMediaCatalog
var _body: InteractionRequest.ThiefEncounterRequestBody
var _character_buttons: Array[Button] = []
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
	var workspace := HBoxContainer.new()
	workspace.name = "ThiefEncounterWorkspace"
	workspace.add_theme_constant_override("separation", 10)
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_build_character_pane())
	var action_pane := PanelContainer.new()
	action_pane.name = "ThiefActionPane"
	action_pane.theme_type_variation = &"ClassicInset"
	action_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_pane.size_flags_stretch_ratio = 1.6
	var action_column := VBoxContainer.new()
	action_column.add_theme_constant_override("separation", 7)
	action_pane.add_child(action_column)
	_character_name = Label.new()
	_character_name.theme_type_variation = &"ClassicHeading"
	action_column.add_child(_character_name)
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
	for index: int in _character_buttons.size():
		_character_buttons[index].button_pressed = index == _selected_character_index
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


func _build_character_pane() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "ThiefCharacterPane"
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = 220.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "Choose a party member"
	heading.theme_type_variation = &"ClassicHeading"
	column.add_child(heading)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(88.0, 88.0)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	column.add_child(_portrait)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	for index: int in _body.characters.size():
		var character := _body.characters[index]
		var button := Button.new()
		button.text = character.name
		button.icon = _portrait_texture(character.portrait_id)
		button.expand_icon = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.custom_minimum_size.y = 42.0
		button.pressed.connect(_select_character.bind(index))
		list.add_child(button)
		_character_buttons.append(button)
	scroll.add_child(list)
	column.add_child(scroll)
	return panel


func _select_character(index: int) -> void:
	_selected_character_index = index
	_render_character()


func _portrait_texture(asset_id: String) -> Texture2D:
	if _media == null:
		return null
	return _media.image_texture(_media.asset_by_id(asset_id))


func _request_opening_sound() -> void:
	if is_inside_tree() and _body != null:
		presentation_sound_requested.emit(_body.sound_id)
