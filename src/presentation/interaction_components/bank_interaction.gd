class_name BankInteraction
extends InteractionComponent

const GOLD := Color("e5c45c")
const CYAN := Color("8fcfd1")
const MUTED := Color("aeb6ba")

var _compact := false
var _body: InteractionRequest.BankRequestBody
var _departure_mode := false
var _characters: Array[InteractionRequestValue.ServiceCharacter] = []
var _selected_character_id: String
var _character_picker: OptionButton
var _summary: VBoxContainer
var _character_group := ButtonGroup.new()


func configure(compact: bool) -> void:
	_compact = compact


func build(request: InteractionRequest) -> void:
	_body = request.body as InteractionRequest.BankRequestBody
	if _body == null:
		add_hint("The wealth request is malformed.")
		return
	_departure_mode = request.kind == InteractionRequest.POOLED_WEALTH_DEPARTURE or _body.mode == &"departure"
	_characters = _body.characters.duplicate()
	_selected_character_id = _body.selected_character_id
	if _selected_character_id.is_empty() and not _characters.is_empty():
		_selected_character_id = _characters[0].id
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 500.0)
	add_theme_constant_override("separation", 6)
	_build_header()
	if _compact:
		_build_compact_character_picker()
	var columns := HBoxContainer.new()
	columns.name = "BankWorkspaceColumns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 6)
	add_child(columns)
	_build_account_pane(columns)
	if not _compact:
		_build_character_pane(columns)
	_build_swap_pane(columns)
	_build_footer()
	_refresh_selected_character()


func _build_header() -> void:
	var row := HBoxContainer.new()
	row.name = "BankHeader"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)
	var title := _label("Distribute pooled wealth before leaving" if _departure_mode else "Bank-backed Swap", GOLD)
	title.theme_type_variation = &"ClassicHeading"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var load_note := _label("Exact denomination transfers", CYAN)
	load_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(load_note)


func _build_compact_character_picker() -> void:
	_character_picker = character_option(_characters)
	_character_picker.name = "BankCharacterPicker"
	for index: int in _character_picker.item_count:
		if String(_character_picker.get_item_metadata(index)) == _selected_character_id:
			_character_picker.select(index)
			break
	_character_picker.item_selected.connect(func(_index: int) -> void:
		_selected_character_id = String(_character_picker.get_selected_metadata())
		_refresh_selected_character()
	)
	add_child(_character_picker)


func _build_account_pane(parent: HBoxContainer) -> void:
	var content := _pane(parent, "BankAccount", "Party Wealth", 0.8)
	content.add_child(_wealth_card("Party Pool", _body.pooled_wealth))
	if not _departure_mode:
		content.add_child(_wealth_card("Banked until departure", _body.banked_wealth))
	var explanation := "Done leaves any unassigned wealth behind, then continues this movement attempt." if _departure_mode else "Opening the bank moves banked wealth into the pool. Leaving the location returns the remaining pool to the bank."
	content.add_child(_label(explanation, MUTED))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)


func _build_character_pane(parent: HBoxContainer) -> void:
	var content := _pane(parent, "BankCharacters", "Adventurers", 0.95)
	var scroll := _scroll("BankCharacterScroll")
	content.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "BankCharacterRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 3)
	scroll.add_child(rows)
	if _characters.is_empty():
		rows.add_child(_label("No eligible adventurer was supplied.", MUTED))
		return
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		var button := Button.new()
		button.name = "BankCharacter_%s" % character.id.replace(".", "_")
		button.text = _character_row_text(character)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 52.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = _character_group
		button.pressed.connect(_select_character.bind(character.id))
		rows.add_child(button)
		button.set_pressed_no_signal(character.id == _selected_character_id)


func _build_swap_pane(parent: HBoxContainer) -> void:
	var content := _pane(parent, "BankSwap", "Selected Adventurer", 1.25)
	_summary = VBoxContainer.new()
	_summary.name = "BankSelectedSummary"
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary.add_theme_constant_override("separation", 5)
	content.add_child(_summary)


func _build_footer() -> void:
	var footer := HBoxContainer.new()
	footer.name = "BankFooter"
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 5)
	add_child(footer)
	_add_response(footer, "BankPool", "Pool party wealth", InteractionResponse.BankBody.new(&"pool"), _body.pool)
	_add_response(footer, "BankShare", "Share pooled wealth", InteractionResponse.BankBody.new(&"share"), _body.share)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var done := add_response_to(footer, "Done", InteractionResponse.BankBody.new(&"leave"))
	done.name = "BankDone"
	done.custom_minimum_size.x = 160.0


func _select_character(character_id: String) -> void:
	_selected_character_id = character_id
	_refresh_selected_character()


func _refresh_selected_character() -> void:
	if _summary == null:
		return
	for child: Node in _summary.get_children():
		_summary.remove_child(child)
		child.free()
	var character := _character_by_id(_selected_character_id)
	if character == null or character.wealth == null:
		_summary.add_child(_label("No selected adventurer is available.", MUTED))
		return
	_summary.add_child(_label(character.name, GOLD))
	_summary.add_child(_label(_wealth_text(character.wealth), CYAN))
	_summary.add_child(_label("Load %d/%d" % [character.load, character.maximum_load], MUTED))
	var separator := HSeparator.new()
	_summary.add_child(separator)
	if character.transfers.is_empty():
		_summary.add_child(_label("No exact transfer increment was supplied.", MUTED))
		return
	for transfer: InteractionRequestValue.Transfer in character.transfers:
		_add_transfer_row(character, transfer)


func _add_transfer_row(character: InteractionRequestValue.ServiceCharacter, transfer: InteractionRequestValue.Transfer) -> void:
	var panel := PanelContainer.new()
	panel.name = "BankTransfer_%s" % String(transfer.denomination)
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	var denomination := String(transfer.denomination)
	var label := _label("%s\n%d per transfer" % [denomination.capitalize(), transfer.amount], GOLD)
	label.custom_minimum_size.x = 110.0
	row.add_child(label)
	var to_pool := add_response_to(row, "To pool", InteractionResponse.BankBody.new(&"to-pool", character.id, denomination, transfer.amount), transfer.to_pool.enabled, transfer.to_pool.reason)
	to_pool.name = "BankToPool_%s" % denomination
	var to_character := add_response_to(row, "To %s" % character.name, InteractionResponse.BankBody.new(&"to-character", character.id, denomination, transfer.amount), transfer.to_character.enabled, transfer.to_character.reason)
	to_character.name = "BankToCharacter_%s" % denomination


func _character_by_id(character_id: String) -> InteractionRequestValue.ServiceCharacter:
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		if character.id == character_id:
			return character
	return null


func _character_row_text(character: InteractionRequestValue.ServiceCharacter) -> String:
	return "%s\n%s  •  Load %d/%d" % [character.name, _wealth_text(character.wealth), character.load, character.maximum_load]


func _wealth_card(title: String, wealth: InteractionRequestValue.Wealth) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content := VBoxContainer.new()
	content.add_child(_label(title, GOLD))
	content.add_child(_label(_wealth_text(wealth), CYAN))
	panel.add_child(content)
	return panel


func _pane(parent: HBoxContainer, pane_name: String, title: String, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = pane_name
	panel.theme_type_variation = &"ClassicTextWell"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	panel.add_child(content)
	var heading := _label(title, GOLD)
	heading.theme_type_variation = &"ClassicHeading"
	content.add_child(heading)
	return content


func _scroll(scroll_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = scroll_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return scroll


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", color)
	return label


func _wealth_text(wealth: InteractionRequestValue.Wealth) -> String:
	return "%d gold  •  %d gems  •  %d jewelry" % [wealth.gold, wealth.gems, wealth.jewelry] if wealth != null else "No wealth record"


func _add_response(parent: Container, name_value: String, text: String, body: InteractionResponse.BankBody, availability: InteractionRequestValue.Availability) -> void:
	var button := add_response_to(parent, text, body, availability.enabled, availability.reason)
	button.name = name_value
	button.custom_minimum_size.x = 150.0
