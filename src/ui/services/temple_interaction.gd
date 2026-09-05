## Binds a temple request to the scene-authored service workspace.

class_name TempleInteraction
extends InteractionComponent

const TEMPLE_CHARACTER_ROW_SCENE_PATH := "res://src/ui/services/temple_character_row.tscn"
const TEMPLE_SERVICE_ROW_SCENE_PATH := "res://src/ui/services/temple_service_row.tscn"

var _media: ClassicMediaCatalog
var _compact := false
var _body: TempleRequestBody
var _characters: Array[InteractionRequestValue.ServiceCharacter] = []
var _services: Array[InteractionRequestValue.TempleService] = []
var _selected_character_id: String
var _selected_service_id: String
var _character_picker: OptionButton
var _purchase_button: Button
var _character_group := ButtonGroup.new()
var _service_group := ButtonGroup.new()


func configure(media: ClassicMediaCatalog, compact: bool) -> void:
	_media = media
	_compact = compact


func build(request: InteractionRequest) -> void:
	_body = request.body as TempleRequestBody
	if _body == null:
		add_hint("The temple request is malformed.")
		return
	_characters = _body.characters.duplicate()
	_services = _body.services.duplicate()
	_selected_character_id = _body.selected_character_id
	if _selected_character_id.is_empty() and not _characters.is_empty():
		_selected_character_id = _characters[0].id
	if not _services.is_empty():
		_selected_service_id = _services[0].id
	(%Facts as Label).text = "Rate %d%%  •  Pool %d gold" % [_body.cost_percent, _body.pooled_wealth.gold]
	_bind_character_picker()
	_populate_character_rows()
	_populate_service_rows()
	_bind_actions()
	_refresh_inspector()


func _bind_character_picker() -> void:
	_character_picker = %TempleCharacterPicker
	_character_picker.visible = _compact
	(%TempleCharacters as PanelContainer).visible = not _compact
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		_character_picker.add_item(character.name)
		_character_picker.set_item_metadata(_character_picker.item_count - 1, character.id)
		if character.id == _selected_character_id:
			_character_picker.select(_character_picker.item_count - 1)
	_character_picker.item_selected.connect(func(_index: int) -> void:
		_selected_character_id = String(_character_picker.get_selected_metadata())
		_refresh_inspector()
	)


func _populate_character_rows() -> void:
	var rows := %TempleCharacterRows as VBoxContainer
	(%CharacterEmpty as Label).visible = _characters.is_empty()
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		var button := (load(TEMPLE_CHARACTER_ROW_SCENE_PATH) as PackedScene).instantiate() as Button
		button.name = "TempleCharacter_%s" % character.id.replace(".", "_")
		button.text = "%s\nHP %d/%d  •  %d gold" % [
			character.name,
			character.current_health,
			character.maximum_health,
			character.available_gold,
		]
		button.button_group = _character_group
		button.icon = _portrait(character.portrait_id)
		button.pressed.connect(_select_character.bind(character.id))
		rows.add_child(button)
		button.set_pressed_no_signal(character.id == _selected_character_id)


func _populate_service_rows() -> void:
	var rows := %TempleServiceRows as VBoxContainer
	(%ServiceEmpty as Label).visible = _services.is_empty()
	for service: InteractionRequestValue.TempleService in _services:
		var button := (load(TEMPLE_SERVICE_ROW_SCENE_PATH) as PackedScene).instantiate() as Button
		button.name = "TempleService_%s" % service.id.replace("-", "_")
		button.text = "%s\n%d gold" % [service.label, service.cost]
		button.button_group = _service_group
		button.pressed.connect(_select_service.bind(service.id))
		rows.add_child(button)
		button.set_pressed_no_signal(service.id == _selected_service_id)


func _bind_actions() -> void:
	_purchase_button = %TemplePurchase
	_purchase_button.pressed.connect(_submit_service)
	_bind_footer_action(%TemplePool as Button, &"pool")
	_bind_footer_action(%TempleShare as Button, &"share")
	_bind_footer_action(%TempleLeave as Button, &"leave")


func _bind_footer_action(button: Button, action: StringName) -> void:
	button.pressed.connect(func() -> void:
		response_body_submitted.emit(InteractionResponse.TempleBody.new(action, _selected_character_id))
	)


func _select_character(character_id: String) -> void:
	_selected_character_id = character_id
	_refresh_inspector()


func _select_service(service_id: String) -> void:
	_selected_service_id = service_id
	_refresh_inspector()


func _refresh_inspector() -> void:
	var character := _character_by_id(_selected_character_id)
	var service := _service_by_id(_selected_service_id)
	(%NoCharacter as Label).visible = character == null
	(%NoService as Label).visible = service == null
	var has_selection := character != null and service != null
	for control: Control in [%TempleSelectedCharacter, %ServiceName, %ServiceDescription, %ServiceCost, %Conditions]:
		control.visible = has_selection
	_purchase_button.disabled = not has_selection or service.cost > character.available_gold
	_purchase_button.tooltip_text = (
		"Select an adventurer and a service."
		if not has_selection
		else "%s has %d available gold; %s costs %d gold." % [character.name, character.available_gold, service.label, service.cost]
		if _purchase_button.disabled
		else ""
	)
	(%UnavailableReason as Label).visible = _purchase_button.disabled
	(%UnavailableReason as Label).text = _purchase_button.tooltip_text
	if not has_selection:
		return
	(%TempleSelectedPortrait as TextureRect).texture = _portrait(character.portrait_id)
	(%CharacterName as Label).text = character.name
	(%CharacterHealth as Label).text = "HP %d/%d  •  Load %d/%d" % [
		character.current_health,
		character.maximum_health,
		character.load,
		character.maximum_load,
	]
	(%CharacterWealth as Label).text = "Personal %d  •  Pool %d  •  Available %d gold" % [
		character.personal_gold,
		_body.pooled_wealth.gold,
		character.available_gold,
	]
	(%ServiceName as Label).text = service.label
	(%ServiceDescription as Label).text = service.description
	(%ServiceCost as Label).text = "Cost: %d gold" % service.cost
	(%Conditions as Label).text = _condition_text(character)


func _condition_text(character: InteractionRequestValue.ServiceCharacter) -> String:
	if character.conditions.is_empty():
		return "No active conditions."
	var names: Array[String] = []
	for index: int in mini(5, character.conditions.size()):
		var condition := character.conditions[index]
		names.append("%s %d" % [condition.name, condition.value])
	return "Conditions: %s" % ", ".join(names)


func _submit_service() -> void:
	var character := _character_by_id(_selected_character_id)
	var service := _service_by_id(_selected_service_id)
	if character == null or service == null or service.cost > character.available_gold:
		return
	response_body_submitted.emit(InteractionResponse.TempleBody.new(&"service", character.id, service.id))


func _character_by_id(character_id: String) -> InteractionRequestValue.ServiceCharacter:
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		if character.id == character_id:
			return character
	return null


func _service_by_id(service_id: String) -> InteractionRequestValue.TempleService:
	for service: InteractionRequestValue.TempleService in _services:
		if service.id == service_id:
			return service
	return null


func _portrait(asset_id: String) -> Texture2D:
	return _media.image_texture(_media.asset_by_id(asset_id)) if _media != null and not asset_id.is_empty() else null
