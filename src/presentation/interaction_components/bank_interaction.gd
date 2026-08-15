class_name BankInteraction
extends InteractionComponent

var _characters: Array[InteractionRequestValue.ServiceCharacter] = []
var _picker: OptionButton
var _summary: Label
var _transfer_rows: VBoxContainer


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.BankRequestBody
	if body == null: return
	var departure_mode: bool = request.kind == InteractionRequest.POOLED_WEALTH_DEPARTURE or body.mode == &"departure"
	add_hint("Distribute pooled wealth before leaving" if departure_mode else "Bank-backed Swap")
	add_hint("Pool: %d gold • %d gems • %d jewelry" % [body.pooled_wealth.gold, body.pooled_wealth.gems, body.pooled_wealth.jewelry])
	if departure_mode:
		add_hint("Done leaves any unassigned wealth behind, then continues this movement attempt.")
	else:
		add_hint("Deposited until departure: %d gold • %d gems • %d jewelry" % [body.banked_wealth.gold, body.banked_wealth.gems, body.banked_wealth.jewelry])
		add_hint("Opening the bank moves deposited wealth into the pool. Done closes Swap; leaving the location returns the remaining pool to the bank.")
	_characters = body.characters.duplicate()
	add_response("Pool party wealth", InteractionResponse.BankBody.new(&"pool"), body.pool.enabled, body.pool.reason)
	add_response("Share pooled wealth", InteractionResponse.BankBody.new(&"share"), body.share.enabled, body.share.reason)
	_picker = character_option(_characters)
	var selected_character_id := body.selected_character_id
	for index: int in _picker.item_count:
		if String(_picker.get_item_metadata(index)) == selected_character_id:
			_picker.select(index)
			break
	_picker.item_selected.connect(func(_index: int) -> void: _refresh_selected_character())
	add_child(_picker)
	_summary = add_hint("")
	_transfer_rows = VBoxContainer.new()
	add_child(_transfer_rows)
	add_response("Done", InteractionResponse.BankBody.new(&"leave"))
	_refresh_selected_character()


func _refresh_selected_character() -> void:
	for child: Node in _transfer_rows.get_children():
		_transfer_rows.remove_child(child)
		child.free()
	if _picker == null or _picker.item_count < 1:
		_summary.text = "No eligible character was supplied."
		return
	var character_id := String(_picker.get_selected_metadata())
	var character: InteractionRequestValue.ServiceCharacter
	for candidate: InteractionRequestValue.ServiceCharacter in _characters:
		if candidate.id == character_id:
			character = candidate
			break
	if character == null or character.wealth == null:
		_summary.text = "The selected character is unavailable."
		return
	_summary.text = "%s • %d gold • %d gems • %d jewelry • load %d/%d" % [
		character.name,
		character.wealth.gold,
		character.wealth.gems,
		character.wealth.jewelry,
		character.load,
		character.maximum_load,
	]
	for transfer: InteractionRequestValue.Transfer in character.transfers:
		_add_transfer_row(character_id, character.name, transfer)


func _add_transfer_row(character_id: String, character_name: String, transfer: InteractionRequestValue.Transfer) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var denomination := String(transfer.denomination)
	var amount := transfer.amount
	var label := Label.new()
	label.text = "%s • %d" % [denomination.capitalize(), amount]
	label.custom_minimum_size.x = 110.0
	row.add_child(label)
	add_response_to(row, "To pool", InteractionResponse.BankBody.new(&"to-pool", character_id, denomination, amount), transfer.to_pool.enabled, transfer.to_pool.reason)
	add_response_to(row, "To %s" % character_name, InteractionResponse.BankBody.new(&"to-character", character_id, denomination, amount), transfer.to_character.enabled, transfer.to_character.reason)
	_transfer_rows.add_child(row)
