class_name ThiefEncounterInteraction
extends InteractionComponent

var _media: ClassicMediaCatalog
var _body: InteractionRequest.ThiefEncounterRequestBody
var _character_picker: OptionButton
var _portrait: TextureRect
var _action_grid: GridContainer


func configure(media: ClassicMediaCatalog) -> void:
	_media = media


func build(request: InteractionRequest) -> void:
	_body = request.body as InteractionRequest.ThiefEncounterRequestBody
	if _body == null:
		return
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(72.0, 72.0)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	header.add_child(_portrait)
	var chooser := VBoxContainer.new()
	chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = "Choose a party member"
	chooser.add_child(label)
	_character_picker = OptionButton.new()
	_character_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for character: InteractionRequestValue.ThiefCharacter in _body.characters:
		_character_picker.add_item(character.name)
		_character_picker.set_item_metadata(_character_picker.item_count - 1, character.id)
	_character_picker.item_selected.connect(func(_index: int) -> void: _render_character())
	chooser.add_child(_character_picker)
	header.add_child(chooser)
	add_child(header)
	var divider := HSeparator.new()
	add_child(divider)
	_action_grid = GridContainer.new()
	_action_grid.columns = 2
	_action_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_action_grid)
	add_response("Back to encounter", InteractionResponse.ThiefEncounterBody.new(&"back"))
	_render_character()
	if _body.sound_id != 0:
		call_deferred("_request_opening_sound")


func _render_character() -> void:
	if _body == null or _body.characters.is_empty():
		return
	var selected := clampi(_character_picker.selected, 0, _body.characters.size() - 1)
	var character := _body.characters[selected]
	_portrait.texture = _portrait_texture(character.portrait_id)
	for child: Node in _action_grid.get_children():
		_action_grid.remove_child(child)
		child.queue_free()
	for action: InteractionRequestValue.ThiefAction in character.actions:
		var button := Button.new()
		button.text = "%s  %d" % [action.label, action.value]
		button.custom_minimum_size.y = 42.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not action.enabled
		button.tooltip_text = action.reason
		button.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.ThiefEncounterBody.new(&"attempt", character.id, action.index)))
		_action_grid.add_child(button)


func _portrait_texture(asset_id: String) -> Texture2D:
	if _media == null:
		return null
	return _media.image_texture(_media.asset_by_id(asset_id))


func _request_opening_sound() -> void:
	if is_inside_tree() and _body != null:
		presentation_sound_requested.emit(_body.sound_id)
