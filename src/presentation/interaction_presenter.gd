class_name InteractionPresenter
extends PanelContainer

signal response_submitted(response: InteractionResponse)

@onready var _prompt: Label = %InteractionPrompt
@onready var _options: VBoxContainer = %InteractionOptions

var _request: InteractionRequest
var _character_checks: Array[CheckButton] = []
var _word_entry: LineEdit
var _catalog: OptionButton
var _character_picker: OptionButton
var _amount: SpinBox


func present(request: InteractionRequest) -> void:
	_request = request
	_clear_options()
	visible = request != null
	if request == null:
		_prompt.text = ""
		return
	if not request.is_supported_kind():
		_prompt.text = "Unsupported Realmz interaction: %s" % String(request.kind)
		_add_hint("This package cannot continue because its interaction contract is unavailable.")
		return
	_prompt.text = String(request.payload.get("prompt", _title_for_kind(request.kind)))
	match request.kind:
		&"encounter_choice", &"scenario_choice":
			_build_index_choices(request.payload.get("options", []))
		&"yes_no":
			_add_response_button(String(request.payload.get("yesLabel", "Yes")), {"accepted": true})
			_add_response_button(String(request.payload.get("noLabel", "No")), {"accepted": false})
		&"acknowledge":
			_add_response_button("Continue", {})
		&"character_selection":
			_build_character_selection()
		&"ally_selection":
			_build_ally_selection()
		&"complex_encounter":
			_build_complex_encounter()
		&"shop_action":
			_build_shop()
		&"temple_action":
			_build_temple()
		&"bank_action":
			_build_bank()
		&"combat_action":
			_build_combat()
		_:
			_prompt.text = "Unsupported Realmz interaction: %s" % String(request.kind)
	if _options.get_child_count() > 0:
		var first := _first_focusable(_options)
		if first != null:
			first.grab_focus()


func present_passive_classic_text(text: String) -> void:
	if _request != null:
		return
	_clear_options()
	_prompt.text = text
	visible = not text.is_empty()


func _build_index_choices(value: Variant) -> void:
	if value is Array:
		for index: int in value.size():
			var option: Variant = value[index]
			if option is Dictionary:
				_add_response_button(String(option.get("label", "Option %d" % (index + 1))), {"index": index})
	if _request.kind == &"encounter_choice" and bool(_request.payload.get("canBackOut", false)):
		_add_response_button("Back out", {"cancelled": true})


func _build_character_selection() -> void:
	_character_checks.clear()
	var required := int(_request.payload.get("count", 1))
	_add_hint("Choose %d character%s." % [required, "" if required == 1 else "s"])
	var eligible: Variant = _request.payload.get("eligible", [])
	if eligible is Array:
		for entry: Variant in eligible:
			if not entry is Dictionary:
				continue
			var check := CheckButton.new()
			check.text = "%s • HP %d" % [entry.get("name", "Character"), int(entry.get("currentHealth", 0))]
			check.set_meta("character_id", String(entry.get("id", "")))
			_character_checks.append(check)
			_options.add_child(check)
	var submit := Button.new()
	submit.text = "Choose"
	submit.pressed.connect(_submit_characters.bind(required))
	_options.add_child(submit)


func _submit_characters(required: int) -> void:
	var ids: Array[String] = []
	for check: CheckButton in _character_checks:
		if check.button_pressed:
			ids.append(String(check.get_meta("character_id")))
	if ids.size() != required:
		_prompt.text = "Choose exactly %d character%s." % [required, "" if required == 1 else "s"]
		return
	_submit_payload({"characterIds": ids})


func _build_ally_selection() -> void:
	_character_checks.clear()
	var maximum := int(_request.payload.get("maximum", 0))
	var selected: Variant = _request.payload.get("selectedIds", [])
	var candidates: Variant = _request.payload.get("candidates", [])
	_add_hint("Choose up to %d surviving allies. Required allies stay selected." % maximum)
	if candidates is Array:
		for entry: Variant in candidates:
			if not entry is Dictionary:
				continue
			var check := CheckButton.new()
			var ally_id := String(entry.get("id", ""))
			var required := bool(entry.get("required", false))
			check.text = "%s • HP %d/%d%s" % [entry.get("name", "Ally"), int(entry.get("currentHealth", 0)), int(entry.get("maximumHealth", 0)), " • Required" if required else ""]
			check.set_meta("character_id", ally_id)
			check.set_meta("required", required)
			check.button_pressed = required or selected is Array and selected.has(ally_id)
			check.disabled = required
			_character_checks.append(check)
			_options.add_child(check)
	var submit := Button.new()
	submit.text = "Continue"
	submit.pressed.connect(_submit_allies.bind(maximum))
	_options.add_child(submit)


func _submit_allies(maximum: int) -> void:
	var ids: Array[String] = []
	for check: CheckButton in _character_checks:
		if check.button_pressed:
			ids.append(String(check.get_meta("character_id")))
	if ids.size() > maximum:
		_prompt.text = "Choose no more than %d allies." % maximum
		return
	_submit_payload({"selectedIds": ids})


func _build_complex_encounter() -> void:
	var actions: Variant = _request.payload.get("actions", [])
	if not actions is Array:
		return
	for entry: Variant in actions:
		if not entry is Dictionary:
			continue
		var kind := String(entry.get("kind", ""))
		match kind:
			"choice":
				_add_response_button(String(entry.get("label", "Choose")), {"action": "choice", "slot": int(entry.get("slot", 0))})
			"back":
				_add_response_button(String(entry.get("label", "Back out")), {"action": "back"})
			"word":
				_word_entry = LineEdit.new()
				_word_entry.placeholder_text = "Speak a word"
				_options.add_child(_word_entry)
				var speak := Button.new()
				speak.text = String(entry.get("label", "Speak"))
				speak.pressed.connect(func() -> void: _submit_payload({"action": "word", "word": _word_entry.text}))
				_options.add_child(speak)
			"item":
				_build_catalog_action("item", "classicItemId", _request.payload.get("items", []), String(entry.get("label", "Use an item")))
			"spell":
				_build_catalog_action("spell", "classicSpellId", _request.payload.get("spells", []), String(entry.get("label", "Cast a spell")))
			"thief":
				_build_thief_action(entry)


func _build_catalog_action(action: String, id_field: String, values: Variant, label: String) -> void:
	_catalog = OptionButton.new()
	if values is Array:
		for entry: Variant in values:
			if entry is Dictionary and entry.has(id_field):
				_catalog.add_item(String(entry.get("name", "Option")))
				_catalog.set_item_metadata(_catalog.item_count - 1, int(entry[id_field]))
	_options.add_child(_catalog)
	var submit := Button.new()
	submit.text = label
	submit.disabled = _catalog.item_count == 0
	submit.pressed.connect(_submit_catalog.bind(action, id_field, _catalog))
	_options.add_child(submit)


func _submit_catalog(action: String, id_field: String, catalog: OptionButton) -> void:
	if catalog.item_count == 0:
		return
	var payload := {"action": action}
	payload[id_field] = int(catalog.get_selected_metadata())
	_submit_payload(payload)


func _build_thief_action(entry: Dictionary) -> void:
	_character_picker = _character_option(_request.payload.get("characters", []))
	_options.add_child(_character_picker)
	var button := Button.new()
	button.text = String(entry.get("label", "Thief action"))
	button.disabled = _character_picker.item_count == 0
	button.pressed.connect(_submit_thief.bind(int(entry.get("actionIndex", 0)), _character_picker))
	_options.add_child(button)


func _submit_thief(action_index: int, picker: OptionButton) -> void:
	if picker.item_count == 0:
		return
	_submit_payload({"action": "thief", "actionIndex": action_index, "characterId": String(picker.get_selected_metadata())})


func _build_shop() -> void:
	_prompt.text = "Shop • inflation %d%%" % int(_request.payload.get("inflationPercent", 100))
	_character_picker = _character_option(_request.payload.get("characters", []))
	_options.add_child(_character_picker)
	_add_hint("Buy")
	var stock: Variant = _request.payload.get("stock", [])
	if stock is Array:
		for entry: Variant in stock:
			if not entry is Dictionary:
				continue
			var button := Button.new()
			button.text = "%s • %d gold • %d left" % [entry.get("name", "Item"), int(entry.get("buyPrice", 0)), int(entry.get("quantity", 0))]
			button.disabled = int(entry.get("quantity", 0)) < 1 or _character_picker.item_count == 0
			button.pressed.connect(_shop_buy.bind(int(entry.get("index", -1))))
			_options.add_child(button)
	_add_hint("Sell")
	var characters: Variant = _request.payload.get("characters", [])
	if characters is Array:
		for character: Variant in characters:
			if not character is Dictionary or not character.get("inventory", []) is Array:
				continue
			for item: Variant in character.get("inventory", []):
				if not item is Dictionary:
					continue
				var sell := Button.new()
				sell.text = "Sell %s (%s) • %d gold" % [item.get("name", "Item"), character.get("name", "Character"), int(item.get("sellPrice", 0))]
				sell.pressed.connect(_submit_payload.bind({"action": "sell", "characterId": String(character.get("id", "")), "instanceId": String(item.get("instanceId", ""))}))
				_options.add_child(sell)
	_add_response_button("Leave shop", {"action": "leave"})


func _shop_buy(stock_index: int) -> void:
	if _character_picker.item_count == 0:
		return
	_submit_payload({"action": "buy", "stockIndex": stock_index, "characterId": String(_character_picker.get_selected_metadata())})


func _build_temple() -> void:
	_prompt.text = "Temple services"
	var characters: Variant = _request.payload.get("characters", [])
	if characters is Array:
		for character: Variant in characters:
			if not character is Dictionary:
				continue
			var button := Button.new()
			button.text = "Heal %s • HP %d/%d" % [character.get("name", "Character"), int(character.get("currentHealth", 0)), int(character.get("maximumHealth", 0))]
			button.pressed.connect(_submit_payload.bind({"action": "heal", "characterId": String(character.get("id", ""))}))
			_options.add_child(button)
	_add_response_button("Leave temple", {"action": "leave"})


func _build_bank() -> void:
	_prompt.text = "Bank • carried %d • deposited %d" % [int(_request.payload.get("carriedGold", 0)), int(_request.payload.get("bankedGold", 0))]
	_amount = SpinBox.new()
	_amount.min_value = 0
	_amount.max_value = maxi(int(_request.payload.get("carriedGold", 0)), int(_request.payload.get("bankedGold", 0)))
	_amount.value = 0
	_amount.prefix = "Gold "
	_options.add_child(_amount)
	var deposit := Button.new()
	deposit.text = "Deposit"
	deposit.pressed.connect(_submit_bank.bind("deposit"))
	_options.add_child(deposit)
	var withdraw := Button.new()
	withdraw.text = "Withdraw"
	withdraw.pressed.connect(_submit_bank.bind("withdraw"))
	_options.add_child(withdraw)
	_add_response_button("Leave bank", {"action": "leave"})


func _submit_bank(action: String) -> void:
	_submit_payload({"action": action, "amount": int(_amount.value)})


func _build_combat() -> void:
	_prompt.text = "Battle round %d" % int(_request.payload.get("round", 1))
	var actor_id := String(_request.payload.get("actorId", ""))
	var targets: Variant = _request.payload.get("targets", [])
	if targets is Array:
		for target: Variant in targets:
			if not target is Dictionary:
				continue
			var attack := Button.new()
			attack.text = "Attack %s • HP %d/%d" % [target.get("name", "Enemy"), int(target.get("currentHealth", 0)), int(target.get("maximumHealth", 0))]
			attack.pressed.connect(_submit_payload.bind({"actorId": actor_id, "action": "attack", "targetId": String(target.get("id", ""))}))
			_options.add_child(attack)
	_add_response_button("Defend", {"actorId": actor_id, "action": "defend", "targetId": ""})
	_add_response_button("Retreat", {"actorId": actor_id, "action": "retreat", "targetId": ""})


func _build_generic_actions() -> void:
	var actions: Variant = _request.payload.get("actions", [])
	if actions is Array:
		for action: Variant in actions:
			_add_response_button(String(action).capitalize(), {"action": String(action)})


func _character_option(value: Variant) -> OptionButton:
	var picker := OptionButton.new()
	if value is Array:
		for character: Variant in value:
			if character is Dictionary:
				picker.add_item(String(character.get("name", "Character")))
				picker.set_item_metadata(picker.item_count - 1, String(character.get("id", "")))
	return picker


func _add_response_button(label: String, payload: Dictionary) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(320.0, 36.0)
	button.pressed.connect(_submit_payload.bind(payload))
	_options.add_child(button)


func _add_hint(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("d5b45d"))
	_options.add_child(label)


func _submit_payload(payload: Dictionary) -> void:
	if _request == null:
		return
	var response := InteractionResponse.new(_request.request_id, _request.kind, payload)
	_request = null
	visible = false
	response_submitted.emit(response)


func _clear_options() -> void:
	_character_checks.clear()
	for child: Node in _options.get_children():
		_options.remove_child(child)
		child.queue_free()


static func _title_for_kind(kind: StringName) -> String:
	return String(kind).replace("_", " ").capitalize()


static func _first_focusable(parent: Node) -> Control:
	for child: Node in parent.get_children():
		if child is Control and (child as Control).focus_mode != Control.FOCUS_NONE:
			return child as Control
		var nested := _first_focusable(child)
		if nested != null:
			return nested
	return null
