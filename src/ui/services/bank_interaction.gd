## Binds a bank request to the scene-authored wealth workspace.

class_name BankInteraction
extends InteractionComponent

const BANK_CHARACTER_ROW_SCENE_PATH := "res://src/ui/services/bank_character_row.tscn"
const BANK_TRANSFER_ROW_SCENE_PATH := "res://src/ui/services/bank_transfer_row.tscn"

var _compact := false
var _body: BankRequestBody
var _departure_mode := false
var _characters: Array[InteractionRequestValue.ServiceCharacter] = []
var _selected_character_id: String
var _character_picker: OptionButton
var _character_group := ButtonGroup.new()


func configure(compact: bool) -> void:
	_compact = compact


func build(request: InteractionRequest) -> void:
	_body = request.body as BankRequestBody
	if _body == null:
		add_hint("The wealth request is malformed.")
		return
	_departure_mode = request.kind == InteractionRequest.POOLED_WEALTH_DEPARTURE or _body.mode == &"departure"
	_characters = _body.characters.duplicate()
	_selected_character_id = _body.selected_character_id
	if _selected_character_id.is_empty() and not _characters.is_empty():
		_selected_character_id = _characters[0].id
	_bind_header_and_account()
	_bind_character_picker()
	_populate_character_rows()
	_bind_footer()
	_refresh_selected_character()


func _bind_header_and_account() -> void:
	(%Title as Label).text = "Distribute pooled wealth before leaving" if _departure_mode else "Bank-backed Swap"
	((%PartyPoolCard as PanelContainer).get_node("Facts/Value") as Label).text = _wealth_text(_body.pooled_wealth)
	(%BankedCard as PanelContainer).visible = not _departure_mode
	((%BankedCard as PanelContainer).get_node("Facts/Value") as Label).text = _wealth_text(_body.banked_wealth)
	(%Explanation as Label).text = (
		"Done leaves any unassigned wealth behind, then continues this movement attempt."
		if _departure_mode
		else "Opening the bank moves banked wealth into the pool. Leaving the location returns the remaining pool to the bank."
	)


func _bind_character_picker() -> void:
	_character_picker = %BankCharacterPicker
	_character_picker.visible = _compact
	(%BankCharacters as PanelContainer).visible = not _compact
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		_character_picker.add_item(character.name)
		_character_picker.set_item_metadata(_character_picker.item_count - 1, character.id)
		if character.id == _selected_character_id:
			_character_picker.select(_character_picker.item_count - 1)
	_character_picker.item_selected.connect(func(_index: int) -> void:
		_selected_character_id = String(_character_picker.get_selected_metadata())
		_refresh_selected_character()
	)


func _populate_character_rows() -> void:
	var rows := %BankCharacterRows as VBoxContainer
	(%CharacterEmpty as Label).visible = _characters.is_empty()
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		var button := (load(BANK_CHARACTER_ROW_SCENE_PATH) as PackedScene).instantiate() as Button
		button.name = "BankCharacter_%s" % character.id.replace(".", "_")
		button.text = _character_row_text(character)
		button.button_group = _character_group
		button.pressed.connect(_select_character.bind(character.id))
		rows.add_child(button)
		button.set_pressed_no_signal(character.id == _selected_character_id)


func _bind_footer() -> void:
	_bind_action(%BankPool as Button, InteractionResponse.BankBody.new(&"pool"), _body.pool)
	_bind_action(%BankShare as Button, InteractionResponse.BankBody.new(&"share"), _body.share)
	(%BankDone as Button).pressed.connect(
		func() -> void: response_body_submitted.emit(InteractionResponse.BankBody.new(&"leave"))
	)


func _bind_action(button: Button, body: InteractionResponse.BankBody, availability: InteractionRequestValue.Availability) -> void:
	button.disabled = not availability.enabled
	button.tooltip_text = availability.reason
	button.pressed.connect(func() -> void: response_body_submitted.emit(body))


func _select_character(character_id: String) -> void:
	_selected_character_id = character_id
	_refresh_selected_character()


func _refresh_selected_character() -> void:
	var transfer_rows := %TransferRows as VBoxContainer
	for child: Node in transfer_rows.get_children():
		child.queue_free()
	var character := _character_by_id(_selected_character_id)
	var has_character := character != null and character.wealth != null
	(%Unavailable as Label).visible = not has_character
	for control: Control in [%CharacterName, %CharacterWealth, %CharacterLoad, %SummarySeparator, %TransferEmpty, %TransferRows]:
		control.visible = has_character
	if not has_character:
		return
	(%CharacterName as Label).text = character.name
	(%CharacterWealth as Label).text = _wealth_text(character.wealth)
	(%CharacterLoad as Label).text = "Load %d/%d" % [character.load, character.maximum_load]
	(%TransferEmpty as Label).visible = character.transfers.is_empty()
	for transfer: InteractionRequestValue.Transfer in character.transfers:
		_add_transfer_row(transfer_rows, character, transfer)


func _add_transfer_row(parent: VBoxContainer, character: InteractionRequestValue.ServiceCharacter, transfer: InteractionRequestValue.Transfer) -> void:
	var panel := (load(BANK_TRANSFER_ROW_SCENE_PATH) as PackedScene).instantiate() as PanelContainer
	var denomination := String(transfer.denomination)
	panel.name = "BankTransfer_%s" % denomination
	(panel.get_node("Actions/Denomination") as Label).text = "%s\n%d per transfer" % [denomination.capitalize(), transfer.amount]
	var to_pool := panel.get_node("Actions/ToPool") as Button
	to_pool.name = "BankToPool_%s" % denomination
	to_pool.disabled = not transfer.to_pool.enabled
	to_pool.tooltip_text = transfer.to_pool.reason
	to_pool.pressed.connect(func() -> void:
		response_body_submitted.emit(InteractionResponse.BankBody.new(&"to-pool", character.id, denomination, transfer.amount))
	)
	var to_character := panel.get_node("Actions/ToCharacter") as Button
	to_character.name = "BankToCharacter_%s" % denomination
	to_character.text = "To %s" % character.name
	to_character.disabled = not transfer.to_character.enabled
	to_character.tooltip_text = transfer.to_character.reason
	to_character.pressed.connect(func() -> void:
		response_body_submitted.emit(InteractionResponse.BankBody.new(&"to-character", character.id, denomination, transfer.amount))
	)
	parent.add_child(panel)


func _character_by_id(character_id: String) -> InteractionRequestValue.ServiceCharacter:
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		if character.id == character_id:
			return character
	return null


func _character_row_text(character: InteractionRequestValue.ServiceCharacter) -> String:
	return "%s\n%s  •  Load %d/%d" % [character.name, _wealth_text(character.wealth), character.load, character.maximum_load]


func _wealth_text(wealth: InteractionRequestValue.Wealth) -> String:
	return "%d gold  •  %d gems  •  %d jewelry" % [wealth.gold, wealth.gems, wealth.jewelry] if wealth != null else "No wealth record"
