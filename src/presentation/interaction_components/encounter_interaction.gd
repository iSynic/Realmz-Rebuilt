class_name EncounterInteraction
extends InteractionComponent

const SpellsWorkspaceControllerScript := preload("res://src/presentation/controllers/spells_workspace_controller.gd")
const InventoryWorkspaceControllerScript := preload("res://src/presentation/controllers/inventory_workspace_controller.gd")

var _media: ClassicMediaCatalog
var _game_view: GameView
var _compact: bool
var _body: InteractionRequest.ComplexEncounterRequestBody
var _context: VBoxContainer
var _choice_actions: Array[InteractionRequestValue.EncounterAction] = []
var _word_action: InteractionRequestValue.EncounterAction
var _item_action: InteractionRequestValue.EncounterAction
var _spell_action: InteractionRequestValue.EncounterAction
var _thief_action: InteractionRequestValue.EncounterAction
var _back_action: InteractionRequestValue.EncounterAction
var _catalog_kind: StringName = &""
var _selected_action_slots: Array[int] = []
var _spell_workspace: SpellsWorkspaceController
var _inventory_workspace: InventoryWorkspaceController
var _inventory_workspace_content: VBoxContainer


func configure(media: ClassicMediaCatalog, game_view: GameView = null, compact: bool = false) -> void:
	_media = media
	_game_view = game_view
	_compact = compact


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if _spell_workspace != null:
		if _spell_workspace.refresh_requested.is_connected(_render_standard_spell_catalog):
			_spell_workspace.refresh_requested.disconnect(_render_standard_spell_catalog)
		if _spell_workspace.encounter_spell_selected.is_connected(_submit_standard_encounter_spell):
			_spell_workspace.encounter_spell_selected.disconnect(_submit_standard_encounter_spell)
		_spell_workspace = null
	if _inventory_workspace != null:
		if _inventory_workspace.refresh_requested.is_connected(_render_standard_item_workspace):
			_inventory_workspace.refresh_requested.disconnect(_render_standard_item_workspace)
		if _inventory_workspace.encounter_item_selected.is_connected(_submit_standard_encounter_item):
			_inventory_workspace.encounter_item_selected.disconnect(_submit_standard_encounter_item)
		_inventory_workspace = null


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
	encounter_dock_requested.emit(command_deck)


func handle_back() -> bool:
	if not _catalog_kind.is_empty():
		_cancel_catalog()
		return true
	if _back_action != null:
		response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(&"back"))
		return true
	return false


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


func _show_mode(mode: StringName) -> void:
	_clear_context()
	match mode:
		&"action": _show_choices()
		&"item": _show_standard_item_workspace()
		&"word": _show_word()
		&"spell": _show_standard_spell_catalog()


func _show_standard_item_workspace() -> void:
	_catalog_kind = &"item"
	var workspace := VBoxContainer.new()
	workspace.name = "EncounterStandardItemWorkspace"
	workspace.add_theme_constant_override("separation", 6)
	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "Items"
	title.theme_type_variation = &"ClassicHeading"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var back := Button.new()
	back.name = "EncounterItemsBack"
	back.text = "Back to encounter"
	back.custom_minimum_size = Vector2(180.0, 36.0)
	back.pressed.connect(_cancel_catalog)
	heading.add_child(back)
	workspace.add_child(heading)
	_inventory_workspace_content = VBoxContainer.new()
	_inventory_workspace_content.name = "EncounterInventoryContent"
	_inventory_workspace_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_workspace_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_inventory_workspace_content)
	if _inventory_workspace == null:
		_inventory_workspace = InventoryWorkspaceControllerScript.new()
		_inventory_workspace.set_layout_profile(UiLayoutProfile.COMPACT if _compact else UiLayoutProfile.WIDE)
		_inventory_workspace.refresh_requested.connect(_render_standard_item_workspace, CONNECT_DEFERRED)
		_inventory_workspace.encounter_item_selected.connect(_submit_standard_encounter_item)
	application_workspace_requested.emit(workspace)
	_render_standard_item_workspace()


func _render_standard_item_workspace() -> void:
	if _inventory_workspace == null or _inventory_workspace_content == null or not is_instance_valid(_inventory_workspace_content):
		return
	_inventory_workspace.present_encounter(_inventory_workspace_content, _game_view, _media, 1.0, _body.items)


func _submit_standard_encounter_item(character_id: String, instance_id: String, classic_item_id: int) -> void:
	application_workspace_closed.emit()
	response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(&"item", -1, "", 0, classic_item_id, -1, character_id, [], instance_id))


func _show_standard_spell_catalog() -> void:
	_catalog_kind = &"spell"
	_render_standard_spell_catalog()


func _render_standard_spell_catalog() -> void:
	_dispose_context_children()
	var workspace := VBoxContainer.new()
	workspace.name = "EncounterStandardSpellWorkspace"
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 5)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	workspace.add_child(column)
	if _spell_workspace == null:
		_spell_workspace = SpellsWorkspaceControllerScript.new()
		_spell_workspace.set_layout_profile(UiLayoutProfile.COMPACT)
		_spell_workspace.refresh_requested.connect(_render_standard_spell_catalog, CONNECT_DEFERRED)
		_spell_workspace.encounter_spell_selected.connect(_submit_standard_encounter_spell)
	_spell_workspace.present_encounter(column, _game_view, _media, 1.0, _body.spells)
	var cancel := Button.new()
	cancel.name = "EncounterCatalogCancel"
	cancel.text = "Back to encounter"
	cancel.custom_minimum_size.y = 36.0
	cancel.pressed.connect(_cancel_catalog)
	column.add_child(cancel)
	side_workspace_requested.emit(workspace)


func _submit_standard_encounter_spell(character_id: String, classic_spell_id: int) -> void:
	for entry: InteractionRequestValue.EncounterCatalogEntry in _body.spells:
		if entry.character_id == character_id and entry.classic_id == classic_spell_id:
			side_workspace_closed.emit()
			response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(&"spell", -1, "", classic_spell_id, 0, -1, character_id))
			return


func _show_choices() -> void:
	_catalog_kind = &"action"
	_selected_action_slots.clear()
	var workspace := VBoxContainer.new()
	workspace.name = "EncounterActionWorkspace"
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 6)
	var instruction := Label.new()
	instruction.name = "EncounterActionInstruction"
	instruction.text = _action_selection_hint()
	instruction.add_theme_color_override("font_color", Color("d5b45d"))
	workspace.add_child(instruction)
	var grid := GridContainer.new()
	grid.name = "EncounterChoiceGrid"
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 5)
	var choice_scroll := ScrollContainer.new()
	choice_scroll.name = "EncounterChoiceScroll"
	choice_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choice_scroll.add_child(grid)
	workspace.add_child(choice_scroll)
	for index: int in _choice_actions.size():
		var entry := _choice_actions[index]
		var button := Button.new()
		button.text = "%d · %s" % [index + 1, entry.label]
		button.toggle_mode = true
		button.pressed.connect(_toggle_action_slot.bind(entry.slot, button))
		grid.add_child(button)
	var visible_choice_count := mini(grid.get_child_count(), 6 if _compact else 8)
	var visible_choice_height := 0.0
	for index: int in visible_choice_count:
		visible_choice_height += (grid.get_child(index) as Control).get_combined_minimum_size().y
	visible_choice_height += maxi(0, visible_choice_count - 1) * grid.get_theme_constant("v_separation")
	choice_scroll.custom_minimum_size.y = visible_choice_height
	var footer := HBoxContainer.new()
	footer.name = "EncounterActionFooter"
	footer.alignment = BoxContainer.ALIGNMENT_BEGIN
	footer.add_theme_constant_override("separation", 6)
	workspace.add_child(footer)
	var done := ClassicBitmapButton.new()
	done.name = "EncounterChoiceDone"
	done.configure({"id": &"done", "asset_id": &"", "tooltip": "Commit the selected action", "label": "Done"}, 1)
	done.disabled = _body.action_selection_count != 0
	done.tooltip_text = _action_selection_hint()
	done.command_requested.connect(func(_command_id: StringName) -> void: response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(&"choice", -1, "", 0, 0, -1, "", _selected_action_slots)))
	footer.add_child(done)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var stop := ClassicBitmapButton.new()
	stop.name = "EncounterChoiceStop"
	stop.configure({"id": &"stop", "asset_id": &"encounter.stop", "tooltip": "Return to the encounter", "label": "Stop"}, 1)
	stop.command_requested.connect(func(_command_id: StringName) -> void: _cancel_catalog())
	footer.add_child(stop)
	set_meta("encounter_choice_done", done)
	side_workspace_requested.emit(workspace)


func _toggle_action_slot(slot: int, button: Button) -> void:
	if button.button_pressed:
		_selected_action_slots.append(slot)
	else:
		_selected_action_slots.erase(slot)
	_selected_action_slots.sort()
	var done := get_meta("encounter_choice_done", null) as ClassicBitmapButton
	if done != null:
		done.disabled = _selected_action_slots.size() != _body.action_selection_count
		done.tooltip_text = _action_selection_hint()


func _action_selection_hint() -> String:
	return "Choose %d action%s, then press Done." % [_body.action_selection_count, "" if _body.action_selection_count == 1 else "s"]


func _show_word() -> void:
	_ensure_context()
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
	word.theme_type_variation = &"ClassicTheldrowLineEdit"
	word.custom_minimum_size = Vector2(300.0, 34.0)
	word.size_flags_horizontal = Control.SIZE_FILL
	entry_row.add_child(word)
	var submit := Button.new()
	submit.name = "EncounterWordSubmit"
	submit.text = _word_action.label if not _word_action.label.is_empty() else "Speak"
	submit.theme_type_variation = &"ClassicTheldrowButton"
	submit.custom_minimum_size = Vector2(68.0, 32.0)
	submit.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(&"word", -1, word.text)))
	entry_row.add_child(submit)
	word.text_submitted.connect(func(_value: String) -> void: submit.pressed.emit())
	word.call_deferred("grab_focus")


func _cancel_catalog() -> void:
	_clear_context()


func _clear_context() -> void:
	side_workspace_closed.emit()
	application_workspace_closed.emit()
	_inventory_workspace_content = null
	_catalog_kind = &""
	_dispose_context_children()
	if _context != null:
		var context_deck := _context.get_parent()
		_context = null
		remove_child(context_deck)
		if context_deck.is_inside_tree(): context_deck.queue_free()
		else: context_deck.free()


func _dispose_context_children() -> void:
	if _context == null:
		return
	for child: Node in _context.get_children():
		_context.remove_child(child)
		if child.is_inside_tree(): child.queue_free()
		else: child.free()


func _ensure_context() -> void:
	if _context != null:
		return
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
