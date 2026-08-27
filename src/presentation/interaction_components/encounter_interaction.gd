class_name EncounterInteraction
extends InteractionComponent

const ClassicSpellLevelScript := preload("res://src/presentation/classic_spell_level.gd")
const SpellSelectionChrome := preload("res://src/presentation/controllers/classic_spell_selection_chrome.gd")
const ContentIconScript := preload("res://src/presentation/classic_content_icon.gd")
const SpellsWorkspaceControllerScript := preload("res://src/presentation/controllers/spells_workspace_controller.gd")

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
var _catalog_entries: Array[InteractionRequestValue.EncounterCatalogEntry] = []
var _catalog_selection: int = 0
var _catalog_record: VBoxContainer
var _catalog_list: VBoxContainer
var _catalog_buttons: Array[Button] = []
var _catalog_level: int = 1
var _catalog_level_buttons: Array[Button] = []
var _selected_action_slots: Array[int] = []
var _catalog_character_index: int = 0
var _catalog_character_name: Label
var _catalog_character_portrait: TextureRect
var _catalog_confirm: Button
var _spell_workspace: SpellsWorkspaceController


func configure(media: ClassicMediaCatalog, game_view: GameView = null, compact: bool = false) -> void:
	_media = media
	_game_view = game_view
	_compact = compact


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or _spell_workspace == null:
		return
	if _spell_workspace.refresh_requested.is_connected(_render_standard_spell_catalog):
		_spell_workspace.refresh_requested.disconnect(_render_standard_spell_catalog)
	if _spell_workspace.encounter_spell_selected.is_connected(_submit_standard_encounter_spell):
		_spell_workspace.encounter_spell_selected.disconnect(_submit_standard_encounter_spell)
	_spell_workspace = null


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
		&"spell": _show_standard_spell_catalog()


func _show_standard_spell_catalog() -> void:
	_catalog_kind = &"spell"
	_render_standard_spell_catalog()


func _render_standard_spell_catalog() -> void:
	_dispose_context_children()
	var workspace := PanelContainer.new()
	workspace.name = "EncounterStandardSpellWorkspace"
	workspace.theme_type_variation = &"ClassicInset"
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	workspace.add_child(column)
	_context.add_child(workspace)
	if _spell_workspace == null:
		_spell_workspace = SpellsWorkspaceControllerScript.new()
		_spell_workspace.set_layout_profile(UiLayoutProfile.COMPACT if _compact else UiLayoutProfile.WIDE)
		_spell_workspace.refresh_requested.connect(_render_standard_spell_catalog, CONNECT_DEFERRED)
		_spell_workspace.encounter_spell_selected.connect(_submit_standard_encounter_spell)
	_spell_workspace.present_encounter(column, _game_view, _media, 1.0, _body.spells)
	var cancel := Button.new()
	cancel.name = "EncounterCatalogCancel"
	cancel.text = "Cancel"
	cancel.custom_minimum_size.y = 36.0
	cancel.pressed.connect(_cancel_catalog)
	column.add_child(cancel)


func _submit_standard_encounter_spell(character_id: String, classic_spell_id: int) -> void:
	for entry: InteractionRequestValue.EncounterCatalogEntry in _body.spells:
		if entry.character_id == character_id and entry.classic_id == classic_spell_id:
			response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(&"spell", -1, "", classic_spell_id, 0, -1, character_id))
			return


func _show_choices() -> void:
	_selected_action_slots.clear()
	var instruction := Label.new()
	instruction.name = "EncounterActionInstruction"
	instruction.text = _action_selection_hint()
	instruction.add_theme_color_override("font_color", Color("d5b45d"))
	_context.add_child(instruction)
	var grid := GridContainer.new()
	grid.name = "EncounterChoiceGrid"
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 5)
	_context.add_child(grid)
	for index: int in _choice_actions.size():
		var entry := _choice_actions[index]
		var button := Button.new()
		button.text = "%d · %s" % [index + 1, entry.label]
		button.toggle_mode = true
		button.pressed.connect(_toggle_action_slot.bind(entry.slot, button))
		grid.add_child(button)
	var done := Button.new()
	done.name = "EncounterChoiceDone"
	done.text = "Done"
	done.disabled = _body.action_selection_count != 0
	done.tooltip_text = _action_selection_hint()
	done.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(&"choice", -1, "", 0, 0, -1, "", _selected_action_slots)))
	_context.add_child(done)
	set_meta("encounter_choice_done", done)


func _toggle_action_slot(slot: int, button: Button) -> void:
	if button.button_pressed:
		_selected_action_slots.append(slot)
	else:
		_selected_action_slots.erase(slot)
	_selected_action_slots.sort()
	var done := get_meta("encounter_choice_done", null) as Button
	if done != null:
		done.disabled = _selected_action_slots.size() != _body.action_selection_count
		done.tooltip_text = _action_selection_hint()


func _action_selection_hint() -> String:
	return "Choose %d action%s, then press Done." % [_body.action_selection_count, "" if _body.action_selection_count == 1 else "s"]


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


func _show_catalog(kind: StringName, entries: Array[InteractionRequestValue.EncounterCatalogEntry]) -> void:
	_catalog_kind = kind
	_catalog_entries.assign(entries)
	_catalog_selection = 0
	_catalog_buttons.clear()
	_catalog_level_buttons.clear()
	_select_first_catalog_character()
	_select_first_catalog_entry()
	if kind == &"spell" and not entries.is_empty():
		_catalog_level = ClassicSpellLevelScript.from_classic_id(entries[_catalog_selection].classic_id)
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
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(heading)
	column.add_child(_build_catalog_character_navigator())
	if kind == &"spell":
		column.add_child(_build_spell_level_rail())
	var list_panel := PanelContainer.new()
	list_panel.name = "EncounterCatalogList"
	list_panel.theme_type_variation = &"ClassicItemLedger" if kind == &"item" else &"ClassicTextWell"
	list_panel.custom_minimum_size.y = 84.0
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_catalog_list = VBoxContainer.new()
	_catalog_list.name = "EncounterCatalogEntries"
	_catalog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_catalog_list)
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
	_catalog_confirm = submit
	submit.name = "EncounterCatalogConfirm"
	submit.text = "Use item" if kind == &"item" else "Cast spell"
	submit.custom_minimum_size.y = 36.0
	submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	submit.pressed.connect(_submit_catalog_entry)
	actions.add_child(submit)
	var cancel := Button.new()
	cancel.name = "EncounterCatalogCancel"
	cancel.text = "Cancel"
	cancel.custom_minimum_size.y = 36.0
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_cancel_catalog)
	actions.add_child(cancel)
	column.add_child(actions)
	_context.add_child(workspace)
	_rebuild_catalog_list()
	_render_catalog_record()


func _build_catalog_character_navigator() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "EncounterCatalogCharacterNavigator"
	panel.theme_type_variation = &"ClassicInset"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var previous := Button.new()
	previous.name = "EncounterCatalogPreviousCharacter"
	previous.text = "‹"
	previous.custom_minimum_size = Vector2(42.0, 42.0)
	previous.disabled = _body.characters.size() < 2
	previous.pressed.connect(_shift_catalog_character.bind(-1))
	row.add_child(previous)
	_catalog_character_portrait = TextureRect.new()
	_catalog_character_portrait.custom_minimum_size = Vector2(42.0, 42.0)
	_catalog_character_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_catalog_character_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_catalog_character_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(_catalog_character_portrait)
	_catalog_character_name = Label.new()
	_catalog_character_name.theme_type_variation = &"ClassicHeading"
	_catalog_character_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_character_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_catalog_character_name)
	var next := Button.new()
	next.name = "EncounterCatalogNextCharacter"
	next.text = "›"
	next.custom_minimum_size = Vector2(42.0, 42.0)
	next.disabled = _body.characters.size() < 2
	next.pressed.connect(_shift_catalog_character.bind(1))
	row.add_child(next)
	_render_catalog_character()
	return panel


func _build_spell_level_rail() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "EncounterSpellLevelRail"
	panel.theme_type_variation = &"ClassicInset"
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	panel.add_child(grid)
	grid.add_child(SpellSelectionChrome.level_heading())
	var available := _catalog_spell_levels()
	for level: int in range(1, 8):
		var button := SpellSelectionChrome.level_button(level, level == _catalog_level, available.has(level), _select_catalog_level.bind(level), "No eligible level %d spells" % level)
		button.name = "EncounterSpellLevel%d" % level
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(button)
		_catalog_level_buttons.append(button)
	return panel


func _catalog_spell_levels() -> Array[int]:
	var result: Array[int] = []
	for entry: InteractionRequestValue.EncounterCatalogEntry in _catalog_entries:
		if entry.character_id != _catalog_character_id():
			continue
		var level := ClassicSpellLevelScript.from_classic_id(entry.classic_id)
		if not result.has(level):
			result.append(level)
	result.sort()
	return result


func _rebuild_catalog_list() -> void:
	if _catalog_list == null:
		return
	for child: Node in _catalog_list.get_children():
		_catalog_list.remove_child(child)
		child.queue_free()
	_catalog_buttons.clear()
	for index: int in _catalog_entries.size():
		var entry := _catalog_entries[index]
		if entry.character_id != _catalog_character_id():
			continue
		if _catalog_kind == &"spell" and ClassicSpellLevelScript.from_classic_id(entry.classic_id) != _catalog_level:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		if _catalog_kind == &"item":
			var icon := ContentIconScript.new() as ClassicContentIcon
			icon.configure(entry.icon_resource_type, entry.icon_id, _media, 36.0, entry.name)
			row.add_child(icon)
		var button := Button.new()
		button.text = entry.name
		button.name = "EncounterCatalogEntry_%s" % (entry.instance_id if _catalog_kind == &"item" else str(entry.classic_id))
		button.theme_type_variation = &"ClassicItemLedgerButton" if _catalog_kind == &"item" else &"Button"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_pressed = index == _catalog_selection
		button.set_meta("catalog_index", index)
		button.pressed.connect(_select_catalog_entry.bind(index))
		row.add_child(button)
		_catalog_list.add_child(row)
		_catalog_buttons.append(button)


func _select_catalog_level(level: int) -> void:
	_catalog_level = level
	for index: int in _catalog_entries.size():
		if _catalog_entries[index].character_id == _catalog_character_id() and ClassicSpellLevelScript.from_classic_id(_catalog_entries[index].classic_id) == level:
			_catalog_selection = index
			break
	for button_index: int in _catalog_level_buttons.size():
		_catalog_level_buttons[button_index].button_pressed = button_index + 1 == level
	_rebuild_catalog_list()
	_render_catalog_record()


func _select_catalog_entry(index: int) -> void:
	_catalog_selection = clampi(index, 0, _catalog_entries.size() - 1)
	for button: Button in _catalog_buttons:
		button.button_pressed = int(button.get_meta("catalog_index", -1)) == _catalog_selection
	_render_catalog_record()


func _shift_catalog_character(delta: int) -> void:
	if _body.characters.is_empty():
		return
	_catalog_character_index = posmod(_catalog_character_index + delta, _body.characters.size())
	_select_first_catalog_entry()
	_render_catalog_character()
	_refresh_catalog_level_buttons()
	_rebuild_catalog_list()
	_render_catalog_record()


func _select_first_catalog_character() -> void:
	_catalog_character_index = 0
	for character_index: int in _body.characters.size():
		var character := _body.characters[character_index]
		if _catalog_entries.any(func(entry: InteractionRequestValue.EncounterCatalogEntry) -> bool: return entry.character_id == character.id):
			_catalog_character_index = character_index
			return


func _select_first_catalog_entry() -> void:
	_catalog_selection = -1
	for index: int in _catalog_entries.size():
		if _catalog_entries[index].character_id == _catalog_character_id():
			_catalog_selection = index
			if _catalog_kind == &"spell":
				_catalog_level = ClassicSpellLevelScript.from_classic_id(_catalog_entries[index].classic_id)
			return


func _refresh_catalog_level_buttons() -> void:
	var available := _catalog_spell_levels()
	for button_index: int in _catalog_level_buttons.size():
		var level := button_index + 1
		_catalog_level_buttons[button_index].disabled = not available.has(level)
		_catalog_level_buttons[button_index].button_pressed = level == _catalog_level
		_catalog_level_buttons[button_index].tooltip_text = "No eligible level %d spells" % level if not available.has(level) else "Show level %d spells" % level


func _catalog_character_id() -> String:
	return _body.characters[_catalog_character_index].id if not _body.characters.is_empty() else ""


func _render_catalog_character() -> void:
	if _body.characters.is_empty() or _catalog_character_name == null:
		return
	var character := _body.characters[_catalog_character_index]
	_catalog_character_name.text = "%s · %s" % [character.name, "Items" if _catalog_kind == &"item" else "Spells"]
	_catalog_character_portrait.texture = _media.image_texture(_media.asset_by_id(character.portrait_id)) if _media != null and not character.portrait_id.is_empty() else null
	if _catalog_confirm != null:
		_catalog_confirm.disabled = _catalog_selection < 0
		_catalog_confirm.tooltip_text = "This character has no eligible %s." % ("items" if _catalog_kind == &"item" else "spells") if _catalog_selection < 0 else ""


func _render_catalog_record() -> void:
	if _catalog_record == null:
		return
	for child: Node in _catalog_record.get_children():
		_catalog_record.remove_child(child)
		if child.is_inside_tree(): child.queue_free()
		else: child.free()
	if _catalog_selection < 0 or _catalog_selection >= _catalog_entries.size():
		return
	var entry := _catalog_entries[_catalog_selection]
	var title := Label.new()
	title.text = entry.name
	title.theme_type_variation = &"ClassicHeading"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_catalog_record.add_child(title)
	var role := Label.new()
	role.text = "%s%s" % ["Equipped" if entry.equipped else "Carried", " · %d charges" % entry.charges if entry.charges > 0 else ""] if _catalog_kind == &"item" else "Level %d  •  %s's memorized spell" % [ClassicSpellLevelScript.from_classic_id(entry.classic_id), _body.characters[_catalog_character_index].name]
	role.add_theme_color_override("font_color", Color("9ca3ad"))
	role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_catalog_record.add_child(role)


func _submit_catalog_entry() -> void:
	if _catalog_selection < 0 or _catalog_selection >= _catalog_entries.size():
		return
	var classic_id := _catalog_entries[_catalog_selection].classic_id
	var entry := _catalog_entries[_catalog_selection]
	response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(_catalog_kind, -1, "", classic_id if _catalog_kind == &"spell" else 0, classic_id if _catalog_kind == &"item" else 0, -1, entry.character_id, [], entry.instance_id))


func _cancel_catalog() -> void:
	_clear_context()
	var hint := Label.new()
	hint.text = "Choose an encounter command."
	hint.add_theme_color_override("font_color", Color("d5b45d"))
	_context.add_child(hint)


func _clear_context() -> void:
	_catalog_kind = &""
	_catalog_entries.clear()
	_catalog_buttons.clear()
	_catalog_level_buttons.clear()
	_catalog_list = null
	_catalog_record = null
	_catalog_confirm = null
	_dispose_context_children()


func _dispose_context_children() -> void:
	for child: Node in _context.get_children():
		_context.remove_child(child)
		if child.is_inside_tree(): child.queue_free()
		else: child.free()
