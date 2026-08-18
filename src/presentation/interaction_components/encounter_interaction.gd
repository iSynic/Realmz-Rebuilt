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


func build(request: InteractionRequest) -> void:
	_body = request.body as InteractionRequest.ComplexEncounterRequestBody
	if _body == null:
		return
	_classify_actions()
	var strip := GridContainer.new()
	strip.name = "EncounterCommandStrip"
	strip.columns = 6
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_theme_constant_override("h_separation", 6)
	add_child(strip)
	_add_command(strip, &"action", &"encounter.action", "Action", not _choice_actions.is_empty(), "No authored actions are available.")
	_add_command(strip, &"item", &"encounter.items", "Items", _item_action != null and not _body.items.is_empty(), "No eligible item is available.")
	_add_command(strip, &"thief", &"encounter.skills", "Skills", _thief_action != null, "No thief action is available.")
	_add_command(strip, &"word", &"encounter.speak", "Speak", _word_action != null, "This encounter accepts no spoken response.")
	_add_command(strip, &"spell", &"command.spells", "Spells", _spell_action != null and not _body.spells.is_empty(), "No eligible spell is available.")
	_add_command(strip, &"back", &"encounter.stop", "Stop", _back_action != null, "This encounter cannot be left yet.")
	_context = VBoxContainer.new()
	_context.name = "EncounterContextPane"
	_context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_context.add_theme_constant_override("separation", 5)
	add_child(_context)
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_context.add_child(row)
	var word := LineEdit.new()
	word.name = "EncounterWord"
	word.placeholder_text = "Speak a word"
	word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(word)
	var submit := Button.new()
	submit.text = _word_action.label if not _word_action.label.is_empty() else "Speak"
	submit.custom_minimum_size = Vector2(120.0, 36.0)
	submit.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(&"word", -1, word.text)))
	row.add_child(submit)
	word.text_submitted.connect(func(_value: String) -> void: submit.pressed.emit())


func _show_catalog(kind: StringName, entries: Array[InteractionRequestValue.EncounterCatalogEntry]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_context.add_child(row)
	var catalog := OptionButton.new()
	catalog.name = "EncounterCatalog"
	catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry: InteractionRequestValue.EncounterCatalogEntry in entries:
		catalog.add_item(entry.name)
		catalog.set_item_metadata(catalog.item_count - 1, entry.classic_id)
	row.add_child(catalog)
	var submit := Button.new()
	submit.text = "Use item" if kind == &"item" else "Cast spell"
	submit.custom_minimum_size = Vector2(120.0, 36.0)
	submit.pressed.connect(func() -> void:
		var classic_id := int(catalog.get_selected_metadata())
		var response := InteractionResponse.ComplexEncounterBody.new(kind, -1, "", classic_id if kind == &"spell" else 0, classic_id if kind == &"item" else 0)
		response_body_submitted.emit(response)
	)
	row.add_child(submit)


func _clear_context() -> void:
	for child: Node in _context.get_children():
		_context.remove_child(child)
		child.queue_free()
