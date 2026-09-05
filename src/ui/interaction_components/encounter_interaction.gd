## Presents the dynamic encounter interaction without owning gameplay state.

class_name EncounterInteraction
extends InteractionComponent


@export var action_workspace_scene: PackedScene
@export var item_workspace_scene: PackedScene
@export var spell_workspace_scene: PackedScene
@export var word_workspace_scene: PackedScene
@export var choice_button_scene: PackedScene

var _media: ClassicMediaCatalog
var _game_view: GameView
var _compact: bool
var _body: ComplexEncounterRequestBody
var _context: VBoxContainer
var _choice_actions: Array[InteractionRequestValue.EncounterAction] = []
var _word_action: InteractionRequestValue.EncounterAction
var _item_action: InteractionRequestValue.EncounterAction
var _spell_action: InteractionRequestValue.EncounterAction
var _thief_action: InteractionRequestValue.EncounterAction
var _back_action: InteractionRequestValue.EncounterAction
var _catalog_kind: StringName = &""
var _selected_action_slots: Array[int] = []
var _spell_screen_controller: SpellsScreenController
var _inventory_screen_controller: InventoryScreenController
var _inventory_screen_controller_content: VBoxContainer
var _choice_done_button: ClassicBitmapButton


func configure(media: ClassicMediaCatalog, game_view: GameView = null, compact: bool = false) -> void:
	_media = media
	_game_view = game_view
	_compact = compact


func set_layout_profile(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	if _inventory_screen_controller != null:
		_inventory_screen_controller.set_layout_profile(UiLayoutProfile.COMPACT if compact else UiLayoutProfile.WIDE)
		if _catalog_kind == &"item":
			_render_standard_item_workspace()


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if _spell_screen_controller != null:
		if _spell_screen_controller.refresh_requested.is_connected(_render_standard_spell_catalog):
			_spell_screen_controller.refresh_requested.disconnect(_render_standard_spell_catalog)
		if _spell_screen_controller.encounter_spell_selected.is_connected(_submit_standard_encounter_spell):
			_spell_screen_controller.encounter_spell_selected.disconnect(_submit_standard_encounter_spell)
		_spell_screen_controller = null
	if _inventory_screen_controller != null:
		if _inventory_screen_controller.refresh_requested.is_connected(_render_standard_item_workspace):
			_inventory_screen_controller.refresh_requested.disconnect(_render_standard_item_workspace)
		if _inventory_screen_controller.encounter_item_selected.is_connected(_submit_standard_encounter_item):
			_inventory_screen_controller.encounter_item_selected.disconnect(_submit_standard_encounter_item)
		_inventory_screen_controller = null


func build(request: InteractionRequest) -> void:
	_body = request.body as ComplexEncounterRequestBody
	if _body == null:
		return
	_classify_actions()
	_configure_command(%EncounterCommandAction, &"action", &"encounter.action", "Action", not _choice_actions.is_empty(), "No authored actions are available.")
	_configure_command(%EncounterCommandItem, &"item", &"encounter.items", "Items", _item_action != null and not _body.items.is_empty(), "No eligible item is available.")
	_configure_command(%EncounterCommandThief, &"thief", &"encounter.skills", "Skills", _thief_action != null, "No thief action is available.")
	_configure_command(%EncounterCommandWord, &"word", &"encounter.speak", "Speak", _word_action != null, "This encounter accepts no spoken response.")
	_configure_command(%EncounterCommandSpell, &"spell", &"command.spells", "Spells", _spell_action != null and not _body.spells.is_empty(), "No eligible spell is available.")
	_configure_command(%EncounterCommandBack, &"back", &"encounter.stop", "Stop", _back_action != null, "This encounter cannot be left yet.")
	encounter_dock_requested.emit(%EncounterCommandDeck)


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


func _configure_command(button: ClassicBitmapButton, mode: StringName, asset_id: StringName, label: String, enabled: bool, reason: String) -> void:
	button.configure({"id": mode, "asset_id": asset_id, "tooltip": label, "accelerator": ""}, 1)
	button.disabled = not enabled
	if not enabled:
		button.tooltip_text = reason
	button.command_requested.connect(_on_command_requested)


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
	var workspace := item_workspace_scene.instantiate() as VBoxContainer
	_inventory_screen_controller_content = workspace.get_node("%EncounterInventoryContent") as VBoxContainer
	(workspace.get_node("%EncounterItemsBack") as Button).pressed.connect(_cancel_catalog)
	if _inventory_screen_controller == null:
		_inventory_screen_controller = InventoryScreenController.new()
		_inventory_screen_controller.refresh_requested.connect(_render_standard_item_workspace, CONNECT_DEFERRED)
		_inventory_screen_controller.encounter_item_selected.connect(_submit_standard_encounter_item)
	_inventory_screen_controller.set_layout_profile(UiLayoutProfile.COMPACT if _compact else UiLayoutProfile.WIDE)
	application_workspace_requested.emit(workspace)
	_render_standard_item_workspace()


func _render_standard_item_workspace() -> void:
	if _inventory_screen_controller == null or _inventory_screen_controller_content == null or not is_instance_valid(_inventory_screen_controller_content):
		return
	_inventory_screen_controller.present_encounter(_inventory_screen_controller_content, _game_view, _media, 1.0, _body.items)


func _submit_standard_encounter_item(character_id: String, instance_id: String, classic_item_id: int) -> void:
	application_workspace_closed.emit()
	response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(&"item", -1, "", 0, classic_item_id, -1, character_id, [], instance_id))


func _show_standard_spell_catalog() -> void:
	_catalog_kind = &"spell"
	_render_standard_spell_catalog()


func _render_standard_spell_catalog() -> void:
	var workspace := spell_workspace_scene.instantiate() as VBoxContainer
	var column := workspace.get_node("%EncounterSpellContent") as VBoxContainer
	if _spell_screen_controller == null:
		_spell_screen_controller = SpellsScreenController.new()
		_spell_screen_controller.set_layout_profile(UiLayoutProfile.COMPACT)
		_spell_screen_controller.refresh_requested.connect(_render_standard_spell_catalog, CONNECT_DEFERRED)
		_spell_screen_controller.encounter_spell_selected.connect(_submit_standard_encounter_spell)
	_spell_screen_controller.present_encounter(column, _game_view, _media, 1.0, _body.spells)
	var cancel := workspace.get_node("%EncounterCatalogCancel") as Button
	cancel.pressed.connect(_cancel_catalog)
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
	var workspace := action_workspace_scene.instantiate() as VBoxContainer
	var instruction := workspace.get_node("%EncounterActionInstruction") as Label
	instruction.text = _action_selection_hint()
	var grid := workspace.get_node("%EncounterChoiceGrid") as GridContainer
	var choice_scroll := workspace.get_node("%EncounterChoiceScroll") as ScrollContainer
	for index: int in _choice_actions.size():
		var entry := _choice_actions[index]
		var button := choice_button_scene.instantiate() as Button
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
	_choice_done_button = workspace.get_node("%EncounterChoiceDone") as ClassicBitmapButton
	_choice_done_button.configure({"id": &"done", "asset_id": &"", "tooltip": "Commit the selected action", "label": "Done"}, 1)
	_choice_done_button.disabled = _body.action_selection_count != 0
	_choice_done_button.tooltip_text = _action_selection_hint()
	_choice_done_button.command_requested.connect(func(_command_id: StringName) -> void: response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(&"choice", -1, "", 0, 0, -1, "", _selected_action_slots)))
	var stop := workspace.get_node("%EncounterChoiceStop") as ClassicBitmapButton
	stop.configure({"id": &"stop", "asset_id": &"encounter.stop", "tooltip": "Return to the encounter", "label": "Stop"}, 1)
	stop.command_requested.connect(func(_command_id: StringName) -> void: _cancel_catalog())
	side_workspace_requested.emit(workspace)


func _toggle_action_slot(slot: int, button: Button) -> void:
	if button.button_pressed:
		_selected_action_slots.append(slot)
	else:
		_selected_action_slots.erase(slot)
	_selected_action_slots.sort()
	if _choice_done_button != null:
		_choice_done_button.disabled = _selected_action_slots.size() != _body.action_selection_count
		_choice_done_button.tooltip_text = _action_selection_hint()


func _action_selection_hint() -> String:
	return "Choose %d action%s, then press Done." % [_body.action_selection_count, "" if _body.action_selection_count == 1 else "s"]


func _show_word() -> void:
	var context_deck := word_workspace_scene.instantiate() as PanelContainer
	_context = context_deck.get_node("%EncounterContextPane") as VBoxContainer
	add_child(context_deck)
	var word := context_deck.get_node("%EncounterWord") as LineEdit
	var submit := context_deck.get_node("%EncounterWordSubmit") as Button
	submit.text = _word_action.label if not _word_action.label.is_empty() else "Speak"
	submit.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.ComplexEncounterBody.new(&"word", -1, word.text)))
	word.text_submitted.connect(func(_value: String) -> void: submit.pressed.emit())
	word.call_deferred("grab_focus")


func _cancel_catalog() -> void:
	_clear_context()


func _clear_context() -> void:
	side_workspace_closed.emit()
	application_workspace_closed.emit()
	_inventory_screen_controller_content = null
	_choice_done_button = null
	_catalog_kind = &""
	if _context != null:
		var context_deck := _context.get_parent()
		_context = null
		remove_child(context_deck)
		if context_deck.is_inside_tree(): context_deck.queue_free()
		else: context_deck.free()
