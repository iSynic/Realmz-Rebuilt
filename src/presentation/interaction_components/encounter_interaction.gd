class_name EncounterInteraction
extends InteractionComponent

var _body: InteractionRequest.ComplexEncounterRequestBody
var _context: VBoxContainer
var _choice_actions: Array[InteractionRequestValue.EncounterAction] = []
var _word_action: InteractionRequestValue.EncounterAction
var _item_action: InteractionRequestValue.EncounterAction
var _spell_action: InteractionRequestValue.EncounterAction
var _thief_action: InteractionRequestValue.EncounterAction
var _back_action: InteractionRequestValue.EncounterAction
var _catalog_kind: StringName = &""
var _catalog_entries: Array[InteractionRequestValue.EncounterCatalogEntry] = []
var _catalog_selection: int = 0
var _catalog_record: VBoxContainer
var _catalog_buttons: Array[Button] = []


func build(request: InteractionRequest) -> void:
	_body = request.body as InteractionRequest.ComplexEncounterRequestBody
	if _body == null:
		return
	_classify_actions()
	var command_deck := PanelContainer.new()
	command_deck.name = "EncounterCommandDeck"
	command_deck.theme_type_variation = &"ClassicInset"
	command_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(command_deck)
	var strip := GridContainer.new()
	strip.name = "EncounterCommandStrip"
	strip.columns = 6
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_theme_constant_override("h_separation", 6)
	command_deck.add_child(strip)
	_add_command(strip, &"action", &"encounter.action", "Action", not _choice_actions.is_empty(), "No authored actions are available.")
	_add_command(strip, &"item", &"encounter.items", "Items", _item_action != null and not _body.items.is_empty(), "No eligible item is available.")
	_add_command(strip, &"thief", &"encounter.skills", "Skills", _thief_action != null, "No thief action is available.")
	_add_command(strip, &"word", &"encounter.speak", "Speak", _word_action != null, "This encounter accepts no spoken response.")
	_add_command(strip, &"spell", &"command.spells", "Spells", _spell_action != null and not _body.spells.is_empty(), "No eligible spell is available.")
	_add_command(strip, &"back", &"encounter.stop", "Stop", _back_action != null, "This encounter cannot be left yet.")
	var context_deck := PanelContainer.new()
	context_deck.name = "EncounterContextDeck"
	context_deck.theme_type_variation = &"ClassicInset"
	context_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_deck.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(context_deck)
	_context = VBoxContainer.new()
	_context.name = "EncounterContextPane"
	_context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_context.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_context.add_theme_constant_override("separation", 5)
	context_deck.add_child(_context)
	_show_first_available()


func _classify_actions() -> void:
	for entry: InteractionRequestValue.EncounterAction in _body.actions:
		match entry.kind:
			&"choice": _choice_actions.append(entry)
			&"word": _word_action = entry
			&"item": _item_action = entry
			&"spell": _spell_action = entry
			&"thief": _thief_action = entry
			&"back": _back_action = entry


func _add_command(parent: GridContainer, mode: StringName, asset_id: StringName, label: String, enabled: bool, reason: String) -> void:
	var button := ClassicBitmapButton.new()
	button.name = "EncounterCommand%s" % String(mode).capitalize()
	button.configure({"id": mode, "asset_id": asset_id, "tooltip": label, "accelerator": ""}, 1)
	button.disabled = not enabled
	if not enabled:
		button.tooltip_text = reason
	button.command_requested.connect(_on_command_requested)
	parent.add_child(button)


func _on_command_requested(mode: StringName) -> void:
	match mode:
		&"action", &"item", &"word", &"spell": _show_mode(mode)
		&"thief": response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(&"thief"))
		&"back": response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(&"back"))


func _show_first_available() -> void:
	for mode: StringName in [&"action", &"item", &"word", &"spell"]:
		if _mode_available(mode):
			_show_mode(mode)
			return
	var label := Label.new()
	label.text = "Choose an available encounter command."
	label.add_theme_color_override("font_color", Color("d5b45d"))
	_context.add_child(label)


func _mode_available(mode: StringName) -> bool:
	match mode:
		&"action": return not _choice_actions.is_empty()
		&"item": return _item_action != null and not _body.items.is_empty()
		&"word": return _word_action != null
		&"spell": return _spell_action != null and not _body.spells.is_empty()
	return false


func _show_mode(mode: StringName) -> void:
	_clear_context()
	match mode:
		&"action": _show_choices()
		&"item": _show_catalog(&"item", _body.items)
		&"word": _show_word()
		&"spell": _show_catalog(&"spell", _body.spells)


func _show_choices() -> void:
	var grid := GridContainer.new()
	grid.name = "EncounterChoiceGrid"
	grid.columns = 2 if _choice_actions.size() > 1 else 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 5)
	_context.add_child(grid)
	for index: int in _choice_actions.size():
		var entry := _choice_actions[index]
		var response := InteractionResponse.ComplexEncounterBody.new(&"choice", entry.slot)
		add_response_to(grid, "%d · %s" % [index + 1, entry.label], response)


func _show_word() -> void:
	var workspace := VBoxContainer.new()
	workspace.name = "EncounterWordWorkspace"
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 3)
	_context.add_child(workspace)
	var entry_row := HBoxContainer.new()
	entry_row.name = "EncounterWordActions"
	entry_row.add_theme_constant_override("separation", 6)
	workspace.add_child(entry_row)
	var label := Label.new()
	label.text = "Response"
	label.custom_minimum_size.x = 72.0
	entry_row.add_child(label)
	var word := LineEdit.new()
	word.name = "EncounterWord"
	word.placeholder_text = "Word or phrase"
	word.max_length = 39
	word.custom_minimum_size = Vector2(300.0, 34.0)
	word.size_flags_horizontal = Control.SIZE_FILL
	entry_row.add_child(word)
	var submit := Button.new()
	submit.name = "EncounterWordSubmit"
	submit.text = _word_action.label if not _word_action.label.is_empty() else "Speak"
	submit.custom_minimum_size = Vector2(68.0, 32.0)
	submit.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(&"word", -1, word.text)))
	entry_row.add_child(submit)
	word.text_submitted.connect(func(_value: String) -> void: submit.pressed.emit())
	word.call_deferred("grab_focus")


func _show_catalog(kind: StringName, entries: Array[InteractionRequestValue.EncounterCatalogEntry]) -> void:
	_catalog_kind = kind
	_catalog_entries.assign(entries)
	_catalog_selection = 0
	_catalog_buttons.clear()
	var workspace := PanelContainer.new()
	workspace.name = "EncounterCatalogWorkspace"
	workspace.theme_type_variation = &"ClassicInset"
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	workspace.add_child(column)
	var heading := Label.new()
	heading.text = "Choose an encounter item" if kind == &"item" else "Choose a memorized spell"
	heading.theme_type_variation = &"ClassicHeading"
	column.add_child(heading)
	var list_panel := PanelContainer.new()
	list_panel.name = "EncounterCatalogList"
	list_panel.theme_type_variation = &"ClassicTextWell"
	list_panel.custom_minimum_size.y = 84.0
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	for index: int in entries.size():
		var entry := entries[index]
		var button := Button.new()
		button.text = entry.name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = index == _catalog_selection
		button.pressed.connect(_select_catalog_entry.bind(index))
		list.add_child(button)
		_catalog_buttons.append(button)
	scroll.add_child(list)
	list_panel.add_child(scroll)
	column.add_child(list_panel)
	var record_panel := PanelContainer.new()
	record_panel.name = "EncounterCatalogRecord"
	record_panel.theme_type_variation = &"ClassicInset"
	_catalog_record = VBoxContainer.new()
	_catalog_record.add_theme_constant_override("separation", 2)
	record_panel.add_child(_catalog_record)
	column.add_child(record_panel)
	var actions := HBoxContainer.new()
	actions.name = "EncounterCatalogActions"
	actions.add_theme_constant_override("separation", 6)
	var submit := Button.new()
	submit.name = "EncounterCatalogConfirm"
	submit.text = "Use item" if kind == &"item" else "Cast spell"
	submit.custom_minimum_size = Vector2(120.0, 36.0)
	submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	submit.pressed.connect(_submit_catalog_entry)
	actions.add_child(submit)
	var cancel := Button.new()
	cancel.name = "EncounterCatalogCancel"
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(90.0, 36.0)
	cancel.pressed.connect(_cancel_catalog)
	actions.add_child(cancel)
	column.add_child(actions)
	_context.add_child(workspace)
	_render_catalog_record()


func _select_catalog_entry(index: int) -> void:
	_catalog_selection = clampi(index, 0, _catalog_entries.size() - 1)
	for button_index: int in _catalog_buttons.size():
		_catalog_buttons[button_index].button_pressed = button_index == _catalog_selection
	_render_catalog_record()


func _render_catalog_record() -> void:
	if _catalog_record == null:
		return
	for child: Node in _catalog_record.get_children():
		_catalog_record.remove_child(child)
		child.queue_free()
	if _catalog_entries.is_empty():
		return
	var entry := _catalog_entries[_catalog_selection]
	var title := Label.new()
	title.text = entry.name
	title.theme_type_variation = &"ClassicHeading"
	_catalog_record.add_child(title)
	var role := Label.new()
	role.text = "Carried encounter item" if _catalog_kind == &"item" else "Eligible memorized spell"
	role.add_theme_color_override("font_color", Color("9ca3ad"))
	_catalog_record.add_child(role)


func _submit_catalog_entry() -> void:
	if _catalog_entries.is_empty():
		return
	var classic_id := _catalog_entries[_catalog_selection].classic_id
	response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(_catalog_kind, -1, "", classic_id if _catalog_kind == &"spell" else 0, classic_id if _catalog_kind == &"item" else 0))


func _cancel_catalog() -> void:
	_clear_context()
	var hint := Label.new()
	hint.text = "Choose an encounter command."
	hint.add_theme_color_override("font_color", Color("d5b45d"))
	_context.add_child(hint)


func _clear_context() -> void:
	_catalog_entries.clear()
	_catalog_buttons.clear()
	_catalog_record = null
	for child: Node in _context.get_children():
		_context.remove_child(child)
		child.queue_free()
