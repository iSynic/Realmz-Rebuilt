class_name BankInteraction
extends InteractionComponent

var _characters: Array[Dictionary] = []
var _picker: OptionButton
var _summary: Label
var _transfer_rows: VBoxContainer


func build(request: InteractionRequest) -> void:
	var pooled := request.payload.get("pooledWealth", {}) as Dictionary
	var banked := request.payload.get("bankedWealth", {}) as Dictionary
	add_hint("Bank-backed Swap")
	add_hint("Pool: %d gold • %d gems • %d jewelry" % [int(pooled.get("gold", 0)), int(pooled.get("gems", 0)), int(pooled.get("jewelry", 0))])
	add_hint("Deposited until departure: %d gold • %d gems • %d jewelry" % [int(banked.get("gold", 0)), int(banked.get("gems", 0)), int(banked.get("jewelry", 0))])
	add_hint("Opening the bank moves deposited wealth into the pool. Done closes Swap; leaving the location returns the remaining pool to the bank.")
	var characters: Variant = request.payload.get("characters", [])
	if characters is Array:
		for character: Variant in characters:
			if character is Dictionary:
				_characters.append(character.duplicate(true))
	var pool: Variant = request.payload.get("pool", {})
	var share: Variant = request.payload.get("share", {})
	add_response("Pool party wealth", {"action": "pool"}, pool is Dictionary and bool(pool.get("enabled", false)), String(pool.get("reason", "Pooling is unavailable.")) if pool is Dictionary else "Pooling is unavailable.")
	add_response("Share pooled wealth", {"action": "share"}, share is Dictionary and bool(share.get("enabled", false)), String(share.get("reason", "Sharing is unavailable.")) if share is Dictionary else "Sharing is unavailable.")
	_picker = character_option(_characters)
	var selected_character_id := String(request.payload.get("selectedCharacterId", ""))
	for index: int in _picker.item_count:
		if String(_picker.get_item_metadata(index)) == selected_character_id:
			_picker.select(index)
			break
	_picker.item_selected.connect(func(_index: int) -> void: _refresh_selected_character())
	add_child(_picker)
	_summary = add_hint("")
	_transfer_rows = VBoxContainer.new()
	add_child(_transfer_rows)
	add_response("Done", {"action": "leave"})
	_refresh_selected_character()


func _refresh_selected_character() -> void:
	for child: Node in _transfer_rows.get_children():
		_transfer_rows.remove_child(child)
		child.free()
	if _picker == null or _picker.item_count < 1:
		_summary.text = "No eligible character was supplied."
		return
	var character_id := String(_picker.get_selected_metadata())
	var character: Dictionary = {}
	for candidate: Dictionary in _characters:
		if candidate.get("id") == character_id:
			character = candidate
			break
	var wealth: Variant = character.get("wealth", {})
	var wealth_data := wealth as Dictionary if wealth is Dictionary else {}
	_summary.text = "%s • %d gold • %d gems • %d jewelry • load %d/%d" % [
		character.get("name", "Character"),
		int(wealth_data.get("gold", 0)),
		int(wealth_data.get("gems", 0)),
		int(wealth_data.get("jewelry", 0)),
		int(character.get("load", 0)),
		int(character.get("maximumLoad", 0)),
	]
	var transfers: Variant = character.get("transfers", [])
	if not transfers is Array:
		return
	for transfer: Variant in transfers:
		if not transfer is Dictionary:
			continue
		_add_transfer_row(character_id, String(character.get("name", "Character")), transfer)


func _add_transfer_row(character_id: String, character_name: String, transfer: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var denomination := String(transfer.get("denomination", ""))
	var amount := int(transfer.get("amount", 0))
	var label := Label.new()
	label.text = "%s • %d" % [denomination.capitalize(), amount]
	label.custom_minimum_size.x = 110.0
	row.add_child(label)
	var to_pool: Variant = transfer.get("toPool", {})
	var to_character: Variant = transfer.get("toCharacter", {})
	add_response_to(row, "To pool", {"action": "to-pool", "characterId": character_id, "denomination": denomination, "amount": amount}, to_pool is Dictionary and bool(to_pool.get("enabled", false)), String(to_pool.get("reason", "Transfer is unavailable.")) if to_pool is Dictionary else "Transfer is unavailable.")
	add_response_to(row, "To %s" % character_name, {"action": "to-character", "characterId": character_id, "denomination": denomination, "amount": amount}, to_character is Dictionary and bool(to_character.get("enabled", false)), String(to_character.get("reason", "Transfer is unavailable.")) if to_character is Dictionary else "Transfer is unavailable.")
	_transfer_rows.add_child(row)
