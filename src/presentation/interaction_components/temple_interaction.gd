class_name TempleInteraction
extends InteractionComponent

var _characters: Array[InteractionRequestValue.ServiceCharacter] = []
var _services: Array[InteractionRequestValue.TempleService] = []
var _picker: OptionButton
var _summary: Label
var _service_buttons: Dictionary = {}
var _pooled_gold: int = 0


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.TempleRequestBody
	if body == null: return
	_characters = body.characters.duplicate()
	_services = body.services.duplicate()
	_pooled_gold = body.pooled_wealth.gold
	add_hint("Temple services • %d%% rate • pooled gold %d" % [body.cost_percent, _pooled_gold])
	_picker = character_option(_characters)
	var selected_character_id := body.selected_character_id
	for index: int in _picker.item_count:
		if String(_picker.get_item_metadata(index)) == selected_character_id:
			_picker.select(index)
			break
	_picker.item_selected.connect(func(_index: int) -> void: _refresh_selected_character())
	add_child(_picker)
	_summary = add_hint("")
	for service: InteractionRequestValue.TempleService in _services:
		var service_id := service.id
		var button := Button.new()
		button.text = "%s • %d gold" % [service.label, service.cost]
		button.custom_minimum_size.y = 36.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_submit_service.bind(service_id))
		add_child(button)
		_service_buttons[service_id] = button
	add_hint("Wealth")
	_add_temple_action("Pool party wealth", "pool")
	_add_temple_action("Share pooled wealth", "share")
	_add_temple_action("Leave temple", "leave")
	_refresh_selected_character()


func _submit_service(service_id: String) -> void:
	if _picker == null or _picker.item_count < 1:
		return
	response_body_submitted.emit(InteractionResponse.TempleBody.new(&"service", String(_picker.get_selected_metadata()), service_id))


func _add_temple_action(label: String, action: String) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 36.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_submit_temple_action.bind(action))
	add_child(button)


func _submit_temple_action(action: String) -> void:
	var selected_character_id := String(_picker.get_selected_metadata()) if _picker != null and _picker.item_count > 0 else ""
	response_body_submitted.emit(InteractionResponse.TempleBody.new(StringName(action), selected_character_id))


func _refresh_selected_character() -> void:
	if _picker == null or _picker.item_count < 1:
		_summary.text = "No eligible character was supplied."
		for button: Button in _service_buttons.values():
			button.disabled = true
			button.tooltip_text = "No eligible character was supplied."
		return
	var character_id := String(_picker.get_selected_metadata())
	var character: InteractionRequestValue.ServiceCharacter
	for candidate: InteractionRequestValue.ServiceCharacter in _characters:
		if candidate.id == character_id:
			character = candidate
			break
	if character == null:
		_summary.text = "The selected character is unavailable."
		return
	var condition_names: Array[String] = []
	for condition: InteractionRequestValue.Condition in character.conditions:
		condition_names.append(condition.name)
	var condition_text := "None shown" if condition_names.is_empty() else ", ".join(condition_names)
	_summary.text = "%s • HP %d/%d • personal gold %d • load %d/%d\nConditions: %s" % [
		character.name,
		character.current_health,
		character.maximum_health,
		character.personal_gold,
		character.load,
		character.maximum_load,
		condition_text,
	]
	var available := character.available_gold
	for service: InteractionRequestValue.TempleService in _services:
		var service_id := service.id
		var button: Button = _service_buttons.get(service_id)
		if button == null:
			continue
		var cost := service.cost
		button.disabled = cost > available
		button.tooltip_text = "Requires %d gold from the pool and selected character." % cost if button.disabled else service.description
