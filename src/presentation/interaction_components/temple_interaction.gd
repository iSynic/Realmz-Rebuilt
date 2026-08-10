class_name TempleInteraction
extends InteractionComponent

var _characters: Array[Dictionary] = []
var _services: Array[Dictionary] = []
var _picker: OptionButton
var _summary: Label
var _service_buttons: Dictionary = {}
var _pooled_gold: int = 0


func build(request: InteractionRequest) -> void:
	var characters: Variant = request.payload.get("characters", [])
	if characters is Array:
		for character: Variant in characters:
			if character is Dictionary:
				_characters.append(character.duplicate(true))
	var services: Variant = request.payload.get("services", [])
	if services is Array:
		for service: Variant in services:
			if service is Dictionary:
				_services.append(service.duplicate(true))
	var pooled: Variant = request.payload.get("pooledWealth", {})
	_pooled_gold = int(pooled.get("gold", 0)) if pooled is Dictionary else 0
	add_hint("Temple services • %d%% rate • pooled gold %d" % [int(request.payload.get("costPercent", 100)), _pooled_gold])
	_picker = character_option(_characters)
	var selected_character_id := String(request.payload.get("selectedCharacterId", ""))
	for index: int in _picker.item_count:
		if String(_picker.get_item_metadata(index)) == selected_character_id:
			_picker.select(index)
			break
	_picker.item_selected.connect(func(_index: int) -> void: _refresh_selected_character())
	add_child(_picker)
	_summary = add_hint("")
	for service: Dictionary in _services:
		var service_id := String(service.get("id", ""))
		var button := Button.new()
		button.text = "%s • %d gold" % [service.get("label", "Service"), int(service.get("cost", 0))]
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
	payload_submitted.emit({"action": "service", "serviceId": service_id, "characterId": String(_picker.get_selected_metadata())})


func _add_temple_action(label: String, action: String) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 36.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_submit_temple_action.bind(action))
	add_child(button)


func _submit_temple_action(action: String) -> void:
	var payload := {"action": action}
	if _picker != null and _picker.item_count > 0:
		payload["selectedCharacterId"] = String(_picker.get_selected_metadata())
	payload_submitted.emit(payload)


func _refresh_selected_character() -> void:
	if _picker == null or _picker.item_count < 1:
		_summary.text = "No eligible character was supplied."
		for button: Button in _service_buttons.values():
			button.disabled = true
			button.tooltip_text = "No eligible character was supplied."
		return
	var character_id := String(_picker.get_selected_metadata())
	var character: Dictionary = {}
	for candidate: Dictionary in _characters:
		if candidate.get("id") == character_id:
			character = candidate
			break
	var condition_names: Array[String] = []
	var conditions: Variant = character.get("conditions", [])
	if conditions is Array:
		for condition: Variant in conditions:
			if condition is Dictionary:
				condition_names.append(String(condition.get("name", "Condition")))
	var condition_text := "None shown" if condition_names.is_empty() else ", ".join(condition_names)
	_summary.text = "%s • HP %d/%d • personal gold %d • load %d/%d\nConditions: %s" % [
		character.get("name", "Character"),
		int(character.get("currentHealth", 0)),
		int(character.get("maximumHealth", 0)),
		int(character.get("personalGold", 0)),
		int(character.get("load", 0)),
		int(character.get("maximumLoad", 0)),
		condition_text,
	]
	var available := int(character.get("availableGold", _pooled_gold + int(character.get("personalGold", 0))))
	for service: Dictionary in _services:
		var service_id := String(service.get("id", ""))
		var button: Button = _service_buttons.get(service_id)
		if button == null:
			continue
		var cost := int(service.get("cost", 0))
		button.disabled = cost > available
		button.tooltip_text = "Requires %d gold from the pool and selected character." % cost if button.disabled else String(service.get("description", ""))
