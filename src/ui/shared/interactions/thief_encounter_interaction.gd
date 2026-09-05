## Binds thief-action requests to the scene-authored character navigator.

class_name ThiefEncounterInteraction
extends InteractionComponent

const THIEF_ACTION_BUTTON_SCENE_PATH := "res://src/ui/shared/interactions/thief_action_button.tscn"

var _media: ClassicMediaCatalog
var _body: ThiefEncounterRequestBody
var _selected_character_index: int = 0
var _portrait: TextureRect
var _character_name: Label
var _action_grid: GridContainer


func configure(media: ClassicMediaCatalog) -> void:
	_media = media


func build(request: InteractionRequest) -> void:
	_body = request.body as ThiefEncounterRequestBody
	if _body == null:
		return
	_portrait = %ThiefCharacterPortrait
	_character_name = %CharacterName
	_action_grid = %ThiefActionGrid
	var can_change_character := _body.characters.size() >= 2
	(%ThiefPreviousCharacter as Button).disabled = not can_change_character
	(%ThiefNextCharacter as Button).disabled = not can_change_character
	(%ThiefPreviousCharacter as Button).pressed.connect(_shift_character.bind(-1))
	(%ThiefNextCharacter as Button).pressed.connect(_shift_character.bind(1))
	(%Back as Button).pressed.connect(func() -> void:
		response_body_submitted.emit(InteractionResponse.ThiefEncounterBody.new(&"back"))
	)
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
		child.queue_free()
	for action: InteractionRequestValue.ThiefAction in character.actions:
		var button := (load(THIEF_ACTION_BUTTON_SCENE_PATH) as PackedScene).instantiate() as Button
		button.text = "%s  %d" % [action.label, action.value]
		button.disabled = not action.enabled
		button.tooltip_text = action.reason if not action.enabled else "%s ability %d" % [action.label, action.value]
		button.pressed.connect(func() -> void:
			response_body_submitted.emit(InteractionResponse.ThiefEncounterBody.new(&"attempt", character.id, action.index))
		)
		_action_grid.add_child(button)


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
