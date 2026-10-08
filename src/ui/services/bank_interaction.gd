## Binds a typed bank request to the shared Party Wealth workspace.
class_name BankInteraction
extends InteractionComponent

var _compact := false
var _body: BankRequestBody
var _departure_mode := false
var _characters: Array[InteractionRequestValue.ServiceCharacter] = []
var _selected_character_id := ""
var _media: ClassicMediaCatalog
var _game_view: GameView
var _workspace: ServicesWorkspace
var _character_group := ButtonGroup.new()


func configure(compact: bool, media: ClassicMediaCatalog, game_view: GameView) -> void:
	_compact = compact
	_media = media
	_game_view = game_view


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
	_workspace = $ServicesWorkspace as ServicesWorkspace
	_workspace.prepare(_compact)
	_workspace.changing_pane().visible = false
	_bind_pool_summary()
	_bind_pool_actions()
	_bind_done()
	_populate_character_rows()
	_bind_character_picker()
	_refresh_selected_character()


func set_layout_profile(compact: bool) -> void:
	if _body == null or _compact == compact:
		return
	var focus_owner := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	var row_had_focus := focus_owner != null and _workspace.character_rows().is_ancestor_of(focus_owner)
	var picker_had_focus := focus_owner == _workspace.character_picker()
	_compact = compact
	_workspace.prepare(_compact)
	if _compact and row_had_focus:
		_workspace.character_picker().call_deferred("grab_focus")
	elif not _compact and picker_had_focus:
		var selected_row := _row_for_character(_selected_character_id)
		if selected_row != null:
			selected_row.call_deferred("grab_focus")


func preferred_initial_focus() -> Control:
	if _workspace == null:
		return null
	if _compact:
		return _workspace.character_picker() if not _characters.is_empty() else _workspace.done_button()
	var selected_row := _row_for_character(_selected_character_id)
	return selected_row if selected_row != null else _workspace.done_button()


func _bind_pool_summary() -> void:
	var pool := _body.pooled_wealth
	var values := _workspace.pool_pane().get_node("Content/MoneyPoolSummary/MoneyPoolValues")
	(values.get_node("Gold") as WealthChip).bind(&"gold", pool.gold, _media)
	(values.get_node("Gems") as WealthChip).bind(&"gems", pool.gems, _media)
	(values.get_node("Jewelry") as WealthChip).bind(&"jewelry", pool.jewelry, _media)
	var identity := _workspace.pool_pane().get_node("Content/MoneyPoolSummary/Identity")
	(identity.get_node("Heading") as Label).text = "Distribute pooled wealth before leaving" if _departure_mode else "Party Pool"
	var banked := identity.get_node("Banked") as Label
	if _departure_mode:
		banked.text = "Done leaves any unassigned wealth behind and continues this movement attempt."
	else:
		banked.text = "Banked separately: %s. Opening imports banked wealth; leaving returns the remaining pool." % _wealth_text(_body.banked_wealth)
	var explanation := _workspace.pool_pane().get_node("Content/MoneyPoolSummary/Identity/Banked") as Label
	# The visible Banked line carries these request-specific import and exit facts.
	explanation.tooltip_text = "Done continues this movement attempt." if _departure_mode else "Opening imports banked wealth into the pool; leaving returns the remainder."


func _bind_pool_actions() -> void:
	var actions := _workspace.pool_pane().get_node("Content/MoneyPoolSummary/MoneyPoolActions")
	var pool_button := actions.get_node("Pool") as Button
	var share_button := actions.get_node("Share") as Button
	_bind_action(pool_button, InteractionResponse.BankBody.new(&"pool"), _body.pool)
	_bind_action(share_button, InteractionResponse.BankBody.new(&"share"), _body.share)


func _bind_done() -> void:
	var done := _workspace.done_button()
	done.text = "Done"
	if not done.pressed.is_connected(_submit_leave):
		done.pressed.connect(_submit_leave)


func _submit_leave() -> void:
	response_body_submitted.emit(InteractionResponse.BankBody.new(&"leave"))


func _bind_action(button: Button, body: InteractionResponse.BankBody, availability: InteractionRequestValue.Availability) -> void:
	button.disabled = not availability.enabled
	button.tooltip_text = availability.reason
	button.pressed.connect(func() -> void: response_body_submitted.emit(body))


func _populate_character_rows() -> void:
	var rows := _workspace.character_rows()
	var row_scene := _workspace.money_character_row_scene
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		var row := row_scene.instantiate() as MoneyCharacterRow
		row.name = "MoneyCharacter_%s" % character.id.replace(".", "_")
		row.button_group = _character_group
		row.set_meta(&"character_id", character.id)
		row.get_node("Content/Portrait").texture = _portrait_texture(character.id)
		(row.get_node("Content/Facts/Name") as Label).text = character.name
		(row.get_node("Content/Facts/Wealth") as Label).text = _wealth_text(character.wealth)
		row.pressed.connect(_select_character.bind(character.id))
		rows.add_child(row)
		row.set_pressed_no_signal(character.id == _selected_character_id)
	var party_content := _workspace.party_pane().get_node("Content")
	(party_content.get_node("Header/Count") as Label).text = str(_characters.size())
	rows.visible = not _characters.is_empty()


func _bind_character_picker() -> void:
	var picker := _workspace.character_picker()
	picker.clear()
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		picker.add_item(character.name)
		picker.set_item_metadata(picker.item_count - 1, character.id)
		if character.id == _selected_character_id:
			picker.select(picker.item_count - 1)
	if not picker.item_selected.is_connected(_on_picker_selected):
		picker.item_selected.connect(_on_picker_selected)


func _on_picker_selected(index: int) -> void:
	var picker := _workspace.character_picker()
	if index >= 0 and index < picker.item_count:
		_select_character(String(picker.get_item_metadata(index)))


func _select_character(character_id: String) -> void:
	_selected_character_id = character_id
	for index: int in range(_workspace.character_picker().item_count):
		if String(_workspace.character_picker().get_item_metadata(index)) == character_id:
			_workspace.character_picker().select(index)
			break
	for row: Node in _workspace.character_rows().get_children():
		(row as BaseButton).set_pressed_no_signal(String(row.get_meta(&"character_id", "")) == character_id)
	_refresh_selected_character()


func _refresh_selected_character() -> void:
	var exchange_body := _workspace.swap_pane().get_node("Content/MoneyExchangeScroll/MoneyExchangeBody")
	var character := _character_by_id(_selected_character_id)
	var available := character != null and character.wealth != null
	var heading := exchange_body.get_node("Header/Heading") as Label
	var selected_name := exchange_body.get_node("Header/SelectedName") as Label
	var portrait := exchange_body.get_node("Header/SelectedPortrait") as TextureRect
	var selected_summary := _workspace.selected_summary()
	var transfer_rows := _workspace.transfer_rows()
	heading.text = "Bank" if not _departure_mode else "Distribute wealth"
	selected_name.text = character.name if character != null else "No adventurer"
	portrait.texture = _portrait_texture(character.id) if available else null
	selected_summary.visible = available
	(exchange_body.get_node("Header/SelectedName") as Label).tooltip_text = "No eligible adventurer was supplied." if not available else ""
	for child: Node in transfer_rows.get_children():
		transfer_rows.remove_child(child)
		child.queue_free()
	if not available:
		return
	var wealth := character.wealth
	(selected_summary.get_node("Gold") as WealthChip).bind(&"gold", wealth.gold, _media)
	(selected_summary.get_node("Gems") as WealthChip).bind(&"gems", wealth.gems, _media)
	(selected_summary.get_node("Jewelry") as WealthChip).bind(&"jewelry", wealth.jewelry, _media)
	(selected_summary.get_node("Load") as Label).text = "Load %d/%d" % [character.load, character.maximum_load]
	for transfer: InteractionRequestValue.Transfer in character.transfers:
		_add_transfer_row(transfer_rows, character, transfer)


func _add_transfer_row(parent: VBoxContainer, character: InteractionRequestValue.ServiceCharacter, transfer: InteractionRequestValue.Transfer) -> void:
	var row := _workspace.money_transfer_row_scene.instantiate() as MoneyTransferRow
	var denomination := String(transfer.denomination)
	row.bind(MoneyTransferView.new(transfer.denomination, transfer.amount, null, null), int(_denomination_value(_body.pooled_wealth, transfer.denomination)), int(_denomination_value(character.wealth, transfer.denomination)), _media)
	var to_pool := row.to_pool_button()
	to_pool.disabled = not transfer.to_pool.enabled
	to_pool.tooltip_text = transfer.to_pool.reason
	to_pool.pressed.connect(func() -> void:
		response_body_submitted.emit(InteractionResponse.BankBody.new(&"to-pool", character.id, denomination, transfer.amount))
	)
	var to_character := row.to_character_button()
	to_character.disabled = not transfer.to_character.enabled
	to_character.tooltip_text = transfer.to_character.reason
	to_character.pressed.connect(func() -> void:
		response_body_submitted.emit(InteractionResponse.BankBody.new(&"to-character", character.id, denomination, transfer.amount))
	)
	parent.add_child(row)


func _row_for_character(character_id: String) -> Control:
	for child: Node in _workspace.character_rows().get_children():
		if String(child.get_meta(&"character_id", "")) == character_id:
			return child as Control
	return null


func _character_by_id(character_id: String) -> InteractionRequestValue.ServiceCharacter:
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		if character.id == character_id:
			return character
	return null


func _portrait_texture(character_id: String) -> Texture2D:
	# Bank payloads omit portrait identity; resolve only from the exact stable member in the detached GameView.
	if _game_view == null or _media == null:
		return null
	for member: CharacterView in _game_view.party_members:
		if member.id == character_id and not member.portrait_id.is_empty():
			return _media.image_texture(_media.asset_by_id(member.portrait_id))
	return null


func _denomination_value(wealth: InteractionRequestValue.Wealth, denomination: StringName) -> String:
	if wealth == null:
		return "0"
	match denomination:
		&"gold": return str(wealth.gold)
		&"gems": return str(wealth.gems)
		&"jewelry": return str(wealth.jewelry)
	return "0"


func _wealth_text(wealth: InteractionRequestValue.Wealth) -> String:
	return "%d gold  •  %d gems  •  %d jewelry" % [wealth.gold, wealth.gems, wealth.jewelry] if wealth != null else "No wealth record"
