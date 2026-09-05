## Binds detached item records and item actions to Inventory screen regions.
class_name InventoryScreenController
extends RefCounted

signal intent_submitted(intent: PlayerIntent)
signal refresh_requested
signal route_requested(screen_id: StringName)
signal back_requested
signal encounter_item_selected(character_id: String, instance_id: String, classic_item_id: int)

const GOLD := Color("d5b45d")
const TEXT := Color("e0e2e5")
const MUTED := Color("9aa0a8")
const WARNING := Color("dca9a9")
const LEDGER_INK := Color("151512")
const LEDGER_MUTED := Color("50575b")
const LEDGER_BLUE := Color("2457bd")
const LEDGER_RED := Color("ad2721")
const ITEM_DETAIL_POPOVER_SCENE_PATH := "res://src/ui/inventory/classic_item_detail_popover.tscn"
const WORKSPACE_SCENE_PATH := "res://src/ui/inventory/inventory_workspace.tscn"

var _scene_binding := InventorySceneBinding.new()
var _selected_character_id: String = ""
var _selected_item_instance_id: String = ""
var _trade_mode: bool = false
var _selected_trade_target_id: String = ""
var _trade_status: String = ""
var _pending_item_action: StringName = &""
var _pending_item_action_label: String = ""
var _pending_item_intent: PlayerIntent
var _text_scale: float = 1.0
var _layout_profile: StringName = UiLayoutProfile.WIDE
var _encounter_mode: bool = false
var _encounter_items: Dictionary = {}
var _rendered_character_id: String = ""
var _item_scroll_position: int = 0


func set_layout_profile(profile_id: StringName) -> void:
	_layout_profile = profile_id


func trade_mode_open() -> bool:
	return _trade_mode


func reset() -> void:
	_selected_character_id = ""
	_selected_item_instance_id = ""
	_trade_mode = false
	_selected_trade_target_id = ""
	_trade_status = ""
	_clear_pending_action()
	_encounter_mode = false
	_encounter_items.clear()
	_rendered_character_id = ""
	_item_scroll_position = 0


func present(target: Control, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	if target == null:
		return
	_encounter_mode = false
	_encounter_items.clear()
	if target is InventoryScreen:
		var screen := target as InventoryScreen
		_present(screen.body_control(), view, media, text_scale, screen)
		return
	_present(target as VBoxContainer, view, media, text_scale)


func present_encounter(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float, entries: Array[InteractionRequestValue.EncounterCatalogEntry]) -> void:
	_encounter_mode = true
	_encounter_items.clear()
	for entry: InteractionRequestValue.EncounterCatalogEntry in entries:
		if not _encounter_items.has(entry.character_id):
			_encounter_items[entry.character_id] = {}
		(_encounter_items[entry.character_id] as Dictionary)[entry.instance_id] = entry.classic_id
	_present(parent, view, media, text_scale)


func _present(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float, screen: InventoryScreen = null) -> void:
	if parent == null:
		return
	_item_scroll_position = _scene_binding.capture_item_scroll(parent, _rendered_character_id, _selected_character_id, _item_scroll_position)
	var workspace: InventoryWorkspace
	if screen != null:
		workspace = screen.workspace()
		workspace.clear_rendered_content()
	else:
		_scene_binding.clear_children(parent)
		workspace = (load(WORKSPACE_SCENE_PATH) as PackedScene).instantiate() as InventoryWorkspace
		parent.add_child(workspace)
	_text_scale = maxf(text_scale, 0.1)
	_scene_binding.text_scale = _text_scale
	if view == null:
		return
	if view.party_members.is_empty():
		_present_empty(workspace, "No party inventory", "The party has no characters.", true)
		return
	var available_characters := InventoryViewQueries.eligible_characters(view, _encounter_mode, _encounter_items)
	if available_characters.is_empty():
		_present_empty(workspace, "No encounter items", "No carried item can be selected for this encounter.", not _encounter_mode)
		return
	var selected_character := InventoryViewQueries.selected_character(view, _selected_character_id, _encounter_mode, _encounter_items)
	if selected_character == null:
		selected_character = available_characters[0]
		_selected_character_id = selected_character.id
		_selected_item_instance_id = ""
		_item_scroll_position = 0
		_trade_mode = false
		_selected_trade_target_id = ""
		_trade_status = ""
		_clear_pending_action()
	_rendered_character_id = selected_character.id
	var visible_items := InventoryViewQueries.eligible_items(selected_character, _encounter_mode, _encounter_items)
	var selected_item := InventoryViewQueries.selected_item(visible_items, _selected_item_instance_id)
	if selected_item == null and not visible_items.is_empty():
		selected_item = visible_items[0]
		_selected_item_instance_id = selected_item.instance_id
	if _trade_mode:
		var target := InventoryViewQueries.character_by_id(view, _selected_trade_target_id)
		if target == null:
			_cancel_trade()
			return
		var trade_host := workspace.prepare_alternate_layout()
		var trade_popover := _create_detail_popover(workspace, media)
		var trade_workspace := workspace.trade_workspace_scene.instantiate() as InventoryTradeWorkspace
		trade_host.add_child(trade_workspace)
		_bind_trade_workspace(trade_workspace, view, selected_character, target, selected_item, media, trade_popover)
		return
	workspace.prepare_normal_layout(_layout_profile == UiLayoutProfile.COMPACT)
	var detail_popover := _create_detail_popover(workspace, media)
	_bind_item_browser(workspace.item_browser_content(), selected_character, visible_items, selected_item, media, detail_popover)
	_bind_character_command_rail(workspace.command_rail_content(), view, selected_character, selected_item, media)
	_bind_item_record(workspace.item_inspector_content(), selected_character, selected_item, media)


func _create_detail_popover(parent: Control, media: ClassicMediaCatalog) -> CanvasLayer:
	var detail_popover := (load(ITEM_DETAIL_POPOVER_SCENE_PATH) as PackedScene).instantiate() as ClassicItemDetailPopover
	detail_popover.name = "InventoryItemDetailPopover"
	parent.add_child(detail_popover)
	detail_popover.configure(media, parent.get_theme())
	return detail_popover


func _present_empty(workspace: InventoryWorkspace, title: String, detail: String, show_done: bool) -> void:
	var host := workspace.prepare_alternate_layout()
	var empty := workspace.empty_state_scene.instantiate() as InventoryEmptyState
	empty.bind(title, detail, show_done)
	_scene_binding.clear_pressed_connections(empty.done_button())
	if show_done:
		empty.done_button().pressed.connect(_request_inventory_back)
	host.add_child(empty)


func _bind_character_selector(selector: InventoryCharacterSelector, view: GameView, selected: CharacterView, media: ClassicMediaCatalog) -> void:
	selector.clear_characters()
	var characters := InventoryViewQueries.eligible_characters(view, _encounter_mode, _encounter_items)
	var row := selector.characters()
	row.columns = mini(3, characters.size()) if _layout_profile == UiLayoutProfile.COMPACT else characters.size()
	for character: CharacterView in characters:
		var button := selector.character_button_scene.instantiate() as Button
		button.name = "InventoryCharacter_%s" % character.id
		button.text = character.name if characters.size() == 1 else ""
		button.icon = _scene_binding.appearance_texture(character.portrait_id, media)
		button.button_pressed = character.id == selected.id
		button.tooltip_text = "%s • %s / %s • Load %d/%d" % [character.name, character.race_name, character.caste_name, character.carried_load, character.maximum_load]
		button.accessibility_name = "Select %s" % character.name
		button.pressed.connect(_select_character.bind(character.id))
		row.add_child(button)


func select_roster_character(character_id: String, view: GameView) -> bool:
	if view == null or view.party_members.is_empty():
		return false
	var character: CharacterView = null
	for candidate: CharacterView in view.party_members:
		if candidate.id == character_id:
			character = candidate
			break
	if character == null:
		return false
	if not _trade_mode:
		_select_character(character.id)
		return true
	var source := InventoryViewQueries.selected_character(view, _selected_character_id, _encounter_mode, _encounter_items)
	var selected_item: ItemView = null
	if source != null:
		for item: ItemView in source.items:
			if item.instance_id == _selected_item_instance_id:
				selected_item = item
				break
	if source == null or selected_item == null or selected_item.actions == null:
		_trade_status = "The selected item is no longer available."
		refresh_requested.emit()
		return true
	for target: ItemTransferTargetView in selected_item.actions.trade_targets:
		if target.character_id != character.id:
			continue
		if not target.enabled:
			_trade_status = target.reason
			refresh_requested.emit()
			return true
		_selected_trade_target_id = target.character_id
		_trade_status = "Ready to transfer %s to %s." % [selected_item.name, target.character_name]
		refresh_requested.emit()
		return true
	_trade_status = "Choose another current party member."
	refresh_requested.emit()
	return true


func _bind_item_browser(content: InventoryItemBrowser, character: CharacterView, items: Array[ItemView], selected: ItemView, media: ClassicMediaCatalog, detail_popover: CanvasLayer) -> void:
	content.clear_dynamic_content()
	content.title_label().text = "%s's items" % character.name
	content.count_label().text = "%d carried" % items.size()
	var scroll := content.item_scroll()
	var list := content.item_list()
	_scene_binding.restore_item_scroll(scroll, _item_scroll_position)
	if items.is_empty():
		content.empty_label().visible = true
		return
	for item: ItemView in items:
		var row_panel := content.item_row_scene.instantiate() as PanelContainer
		row_panel.name = "InventoryItemRow_%s" % item.instance_id
		row_panel.theme_type_variation = &"ClassicItemLedgerSelectedRow" if selected != null and selected.instance_id == item.instance_id else &"ClassicItemLedgerRow"
		var icon := row_panel.get_node("Row/ContentIcon") as ClassicContentIcon
		icon.configure(item.icon_resource_type, item.icon_id, media, 38.0, item.name)
		var button := row_panel.get_node("Row/ItemText/SelectItem") as Button
		button.name = "InventoryItem_%s" % item.instance_id
		button.button_pressed = selected != null and selected.instance_id == item.instance_id
		button.text = item.name
		button.tooltip_text = "%s%s" % ["Equipped" if item.equipped else "Carried", " • %d charges" % item.charges if item.charges > 0 else ""]
		button.pressed.connect(_select_item.bind(item.instance_id))
		var line_fact := InventoryItemText.line_fact(item)
		var fact_label := row_panel.get_node("Row/ItemText/InventoryItemLineFact") as Label
		fact_label.visible = line_fact != null
		if line_fact != null:
			_scene_binding.bind_label(fact_label, "%s %s" % [line_fact.label, line_fact.value], LEDGER_RED if line_fact.id == &"damage-range" else LEDGER_BLUE, 11)
		detail_popover.bind_hover(icon, InventoryItemText.detail(item))
		detail_popover.bind_hover(button, InventoryItemText.detail(item))
		var state_parts: Array[String] = []
		if item.equipped:
			state_parts.append("Equipped")
		if item.charges > 0:
			state_parts.append("%d charge%s" % [item.charges, "" if item.charges == 1 else "s"])
		var state := row_panel.get_node("Row/State") as Label
		_scene_binding.bind_label(state, " · ".join(state_parts), LEDGER_BLUE if item.equipped else LEDGER_RED if item.charges > 0 else LEDGER_MUTED, 12)
		state.tooltip_text = button.tooltip_text
		list.add_child(row_panel)


func _bind_character_command_rail(content: InventoryCommandRail, view: GameView, character: CharacterView, item: ItemView, media: ClassicMediaCatalog) -> void:
	content.clear_dynamic_content()
	_render_character_record(content.character_record(), character, media)
	if item == null:
		content.item_actions().show_selection_hint()
		_bind_character_selector(content.character_selector(), view, character, media)
		return
	_render_item_actions(content.item_actions(), view, item, character, media)
	_bind_character_selector(content.character_selector(), view, character, media)


func _render_character_record(parent: VBoxContainer, character: CharacterView, media: ClassicMediaCatalog) -> void:
	(parent.get_node("InventoryCharacterIdentity/Portrait") as TextureRect).texture = _scene_binding.appearance_texture(character.portrait_id, media)
	_scene_binding.bind_label(parent.get_node("InventoryCharacterIdentity/IdentityText/Name") as Label, character.name, GOLD, 19)
	_scene_binding.bind_label(parent.get_node("InventoryCharacterIdentity/IdentityText/Role") as Label, "%s / %s • Level %d" % [character.race_name, character.caste_name, character.level], TEXT, 12)
	var facts := parent.get_node("InventoryCharacterFacts") as GridContainer
	var values: Array[String] = ["ST %d/%d" % [character.current_health, character.maximum_health], "SP %d/%d" % [character.spell_points, character.maximum_spell_points], "AR %d" % character.armor, "Attacks %s" % character.attacks_per_round, "Movement %d/%d" % [character.movement, character.maximum_movement], "Load %d/%d" % [character.carried_load, character.maximum_load]]
	for index: int in values.size():
		_scene_binding.bind_label(facts.get_child(index) as Label, values[index], TEXT, 12)
	var condition_text := "Conditions: None"
	if not character.conditions.is_empty():
		var names: Array[String] = []
		for condition: CharacterMetricView in character.conditions:
			names.append(condition.name)
		condition_text = "Conditions: %s" % ", ".join(names)
	_scene_binding.bind_label(parent.get_node("Conditions") as Label, condition_text, WARNING if not character.conditions.is_empty() else MUTED, 11)


func _bind_item_record(content: InventoryItemInspector, character: CharacterView, item: ItemView, media: ClassicMediaCatalog) -> void:
	content.clear_dynamic_content()
	var record := content.record()
	record.set_compact(_layout_profile == UiLayoutProfile.COMPACT)
	content.done_column().visible = not _encounter_mode
	var done := content.done_column().done_button()
	_scene_binding.clear_pressed_connections(done)
	if not _encounter_mode:
		done.pressed.connect(_request_inventory_back)
	if item == null:
		record.show_empty("Select an item to inspect it.")
		return
	record.show_record()
	_render_item_detail(record, item, character, media)
	_render_item_facts(record, item)


func _request_inventory_back() -> void:
	back_requested.emit()


func _bind_trade_item_record(record: InventorySelectedItemRecord, character: CharacterView, item: ItemView, media: ClassicMediaCatalog) -> void:
	record.set_compact(false)
	if item == null:
		record.show_empty("Drag an item between packs, or select one to inspect it.")
		return
	record.show_record()
	_render_item_detail(record, item, character, media)
	_render_item_facts(record, item)


func _render_item_detail(record: InventorySelectedItemRecord, item: ItemView, character: CharacterView, media: ClassicMediaCatalog) -> void:
	record.item_icon().configure(item.icon_resource_type, item.icon_id, media, 58.0, item.name)
	_scene_binding.bind_label(record.get_node("Narrative/TitleRow/TitleText/Name") as Label, item.name, GOLD, 20)
	_scene_binding.bind_label(record.get_node("Narrative/TitleRow/TitleText/Summary") as Label, "%s · Weight %d · Charges %d" % ["Equipped" if item.equipped else "Carried", item.weight, item.charges], MUTED, 13)
	_scene_binding.bind_label(record.get_node("Narrative/Description") as Label, item.description, TEXT, 15)
	_scene_binding.bind_label(record.get_node("Narrative/CharacterLoad") as Label, "%s • Load %d/%d" % [character.name, character.carried_load, character.maximum_load], MUTED, 12)


func _render_item_facts(record: InventorySelectedItemRecord, item: ItemView) -> void:
	_scene_binding.bind_label(record.get_node("Facts/Header/Value") as Label, "Value %s" % [str(item.value) if item.identified else "unknown"], MUTED, 12)
	for fact: ItemFactView in item.facts:
		var row := record.fact_row_scene.instantiate() as HBoxContainer
		_scene_binding.bind_label(row.get_node("Name") as Label, fact.label, MUTED, 13)
		_scene_binding.bind_label(row.get_node("Value") as Label, fact.value, TEXT, 13)
		record.fact_rows().add_child(row)
	for property: String in item.properties:
		_scene_binding.add_text_row(record.properties(), record.text_row_scene, "• %s" % property, TEXT)
	for restriction: String in item.restrictions:
		_scene_binding.add_text_row(record.restrictions(), record.text_row_scene, restriction, WARNING)


func _render_item_actions(panel: InventoryActionPanel, view: GameView, item: ItemView, character: CharacterView, _media: ClassicMediaCatalog) -> void:
	if _encounter_mode:
		panel.show_actions(true)
		var choose := panel.encounter_button()
		_bind_bitmap_button(choose, &"inventory.action.use", "Use in encounter")
		choose.command_requested.connect(func(_command_id: StringName) -> void: _submit_encounter_item(character.id, item.instance_id))
		return
	if not _pending_item_action.is_empty():
		_render_operation_stage(panel, item, character)
		return
	panel.show_actions(false)
	if item.equipped:
		_bind_item_intent_action(panel.action_button("EquippedAction"), &"inventory.action.equipped", "Unequip", item.actions.unequip, InventoryIntents.unequip(item.instance_id, character.id), item, character)
	else:
		_bind_item_intent_action(panel.action_button("EquippedAction"), &"inventory.action.equipped", "Equip", item.actions.equip, InventoryIntents.equip(item.instance_id, character.id), item, character)
	_bind_item_intent_action(panel.action_button("UseAction"), &"inventory.action.use", "Use", item.actions.use, InventoryIntents.use(item.instance_id, character.id), item, character)
	_bind_item_intent_action(panel.action_button("IdentifyAction"), &"inventory.action.identify", "Identify", item.actions.identify, MagicIntents.identify_carried_items(item.actions.identify_spell_id, item.actions.identify_caster_id, character.id), item, character)
	_bind_trade_action(panel.action_button("TradeAction"), item)
	_bind_item_intent_action(panel.action_button("JoinAction"), &"inventory.action.join", "Join", item.actions.join, InventoryIntents.join(item.instance_id, character.id), item, character)
	_bind_item_intent_action(panel.action_button("SplitAction"), &"inventory.action.split", "Split", item.actions.split, InventoryIntents.split(item.instance_id, character.id), item, character)
	_bind_item_intent_action(panel.action_button("DropAction"), &"inventory.action.drop", "Drop", item.actions.drop, InventoryIntents.drop(item.instance_id, character.id), item, character)
	panel.trade_status().visible = not _trade_status.is_empty()
	_scene_binding.bind_label(panel.trade_status(), _trade_status, WARNING, 13)


func _render_operation_stage(panel: InventoryActionPanel, item: ItemView, character: CharacterView) -> void:
	panel.show_operation()
	var column := panel.operation_stage().get_node("Content") as VBoxContainer
	_scene_binding.bind_label(column.get_node("Header/Title") as Label, "%s · %s" % [_pending_item_action_label, item.name], GOLD, 17)
	_scene_binding.bind_label(column.get_node("Header/Detail") as Label, "%s · %s" % [character.name, "Equipped" if item.equipped else "Carried"], MUTED, 12)
	var facts: Array[String] = ["Weight %d" % item.weight]
	facts.append("Unlimited charges" if item.charges < 0 else "%d charge%s" % [item.charges, "" if item.charges == 1 else "s"])
	_scene_binding.bind_label(column.get_node("Facts") as Label, " • ".join(facts), MUTED, 13)
	_scene_binding.bind_label(column.get_node("Description") as Label, InventoryItemText.operation_description(_pending_item_action, item, character), TEXT, 13)
	var confirm := column.get_node("InventoryOperationActions/Confirm") as Button
	confirm.text = _pending_item_action_label
	_scene_binding.clear_pressed_connections(confirm)
	confirm.pressed.connect(_confirm_item_action)
	var cancel := column.get_node("InventoryOperationActions/Cancel") as Button
	_scene_binding.clear_pressed_connections(cancel)
	cancel.pressed.connect(_cancel_item_action)


func _begin_item_action(action: StringName, label: String, intent: PlayerIntent, _item: ItemView, _character: CharacterView) -> void:
	_pending_item_action = action
	_pending_item_action_label = label
	_pending_item_intent = intent
	_trade_mode = false
	_selected_trade_target_id = ""
	_trade_status = ""
	refresh_requested.emit()


func _confirm_item_action() -> void:
	var intent := _pending_item_intent
	_clear_pending_action()
	if intent != null:
		intent_submitted.emit(intent)


func _cancel_item_action() -> void:
	_clear_pending_action()
	refresh_requested.emit()


func _clear_pending_action() -> void:
	_pending_item_action = &""
	_pending_item_action_label = ""
	_pending_item_intent = null


func _bind_trade_workspace(workspace: InventoryTradeWorkspace, view: GameView, source: CharacterView, target: CharacterView, selected_item: ItemView, media: ClassicMediaCatalog, detail_popover: CanvasLayer) -> void:
	workspace.ledgers().vertical = _layout_profile == UiLayoutProfile.COMPACT
	_bind_trade_ledger(workspace.source_ledger(), view, source, target.id, media, detail_popover)
	_bind_trade_control_spine(workspace.divider(), view, source, target, media)
	_bind_trade_ledger(workspace.target_ledger(), view, target, source.id, media, detail_popover)
	workspace.status_label().visible = not _trade_status.is_empty()
	_scene_binding.bind_label(workspace.status_label(), _trade_status, WARNING, 12)
	_bind_trade_item_record(workspace.item_record(), source, selected_item, media)


func _bind_trade_ledger(ledger: InventoryTradeLedger, view: GameView, character: CharacterView, other_id: String, media: ClassicMediaCatalog, detail_popover: CanvasLayer) -> void:
	ledger.name = "InventoryTradeLedger_%s" % character.id
	ledger.configure_drop(&"inventory-trade-item", character.id)
	ledger.item_dropped.connect(func(payload: Dictionary, target_id: String) -> void: _drop_trade_item(view, payload, target_id))
	_scene_binding.bind_label(ledger.title_label(), "%s's items" % character.name, LEDGER_INK, 17)
	_scene_binding.bind_label(ledger.load_label(), "Load %d/%d" % [character.carried_load, character.maximum_load], LEDGER_MUTED, 12)
	ledger.clear_rows()
	var rows := ledger.rows()
	for item: ItemView in character.items:
		var row := ledger.item_row_scene.instantiate() as HBoxContainer
		var icon := row.get_node("ContentIcon") as ClassicContentIcon
		icon.configure(item.icon_resource_type, item.icon_id, media, 34.0, item.name)
		var button := row.get_node("SelectItem") as ClassicExchangeItemButton
		button.name = "InventoryTradeItem_%s" % item.instance_id
		button.text = "%s\n%s" % [item.name, InventoryItemText.trade_line(item)]
		button.pressed.connect(_select_trade_item.bind(view, character.id, item.instance_id, other_id))
		button.configure_drag({"kind": &"inventory-trade-item", "sourceId": character.id, "instanceId": item.instance_id})
		detail_popover.bind_hover(icon, InventoryItemText.detail(item))
		detail_popover.bind_hover(button, InventoryItemText.detail(item))
		rows.add_child(row)
	if character.items.is_empty():
		_scene_binding.add_text_row(rows, ledger.empty_row_scene, "No carried items.", LEDGER_MUTED, 12)


func _bind_trade_control_spine(divider: InventoryTradeDivider, view: GameView, source: CharacterView, target: CharacterView, media: ClassicMediaCatalog) -> void:
	divider.clear_portraits()
	for character: CharacterView in view.party_members:
		divider.portraits().add_child(_trade_portrait(divider, character, true, character.id == source.id, media))
		divider.portraits().add_child(_trade_portrait(divider, character, false, character.id == target.id, media))
	_scene_binding.clear_pressed_connections(divider.money_button())
	divider.money_button().pressed.connect(func() -> void: route_requested.emit(&"services"))
	_scene_binding.clear_pressed_connections(divider.items_button())
	divider.items_button().pressed.connect(_cancel_trade)
	_scene_binding.clear_pressed_connections(divider.done_button())
	divider.done_button().pressed.connect(func() -> void: back_requested.emit())


func _trade_portrait(divider: InventoryTradeDivider, character: CharacterView, left_side: bool, selected: bool, media: ClassicMediaCatalog) -> Button:
	var button := divider.portrait_button_scene.instantiate() as Button
	button.name = "InventoryTrade%s_%s" % ["Left" if left_side else "Right", character.id]
	button.icon = _scene_binding.appearance_texture(character.portrait_id, media)
	button.button_pressed = selected
	button.tooltip_text = "%s pack: %s" % ["Left" if left_side else "Right", character.name]
	button.pressed.connect(_select_trade_character.bind(character.id, left_side))
	return button


func _select_trade_character(character_id: String, left_side: bool) -> void:
	if left_side:
		if character_id == _selected_trade_target_id:
			_selected_trade_target_id = _selected_character_id
		_selected_character_id = character_id
		_selected_item_instance_id = ""
	elif character_id == _selected_character_id:
		_selected_character_id = _selected_trade_target_id
		_selected_item_instance_id = ""
		_selected_trade_target_id = character_id
	else:
		_selected_trade_target_id = character_id
	_trade_status = "Drag an item between the selected packs."
	refresh_requested.emit()


func _select_trade_item(view: GameView, character_id: String, instance_id: String, preferred_target_id: String) -> void:
	var character := InventoryViewQueries.character_by_id(view, character_id)
	if character == null:
		return
	var item := InventoryViewQueries.item_by_id(character, instance_id)
	if item == null:
		return
	_selected_character_id = character_id
	_selected_item_instance_id = instance_id
	_selected_trade_target_id = InventoryViewQueries.first_enabled_trade_target(item, preferred_target_id)
	_trade_status = "Choose a destination for %s." % item.name if _selected_trade_target_id.is_empty() else "Ready to transfer %s." % item.name
	refresh_requested.emit()


func _drop_trade_item(view: GameView, payload: Dictionary, target_id: String) -> void:
	var source_id := String(payload.get("sourceId", ""))
	var instance_id := String(payload.get("instanceId", ""))
	var source := InventoryViewQueries.character_by_id(view, source_id)
	var item := InventoryViewQueries.item_by_id(source, instance_id)
	var availability := InventoryViewQueries.trade_target(item, target_id)
	if availability == null or not availability.enabled:
		_trade_status = "This item cannot be transferred there." if availability == null else availability.reason
		refresh_requested.emit()
		return
	_submit_trade(instance_id, source_id, target_id)


func _submit_trade(instance_id: String, source_id: String, target_id: String) -> void:
	_trade_status = "Transferring item…"
	intent_submitted.emit(InventoryIntents.trade(instance_id, source_id, target_id))


func _submit_encounter_item(character_id: String, instance_id: String) -> void:
	var instances := _encounter_items.get(character_id, {}) as Dictionary
	if instances.has(instance_id):
		encounter_item_selected.emit(character_id, instance_id, int(instances[instance_id]))


func _select_character(character_id: String) -> void:
	_selected_character_id = character_id
	_selected_item_instance_id = ""
	_trade_mode = false
	_selected_trade_target_id = ""
	_trade_status = ""
	_item_scroll_position = 0
	_clear_pending_action()
	refresh_requested.emit()


func _select_item(instance_id: String) -> void:
	_selected_item_instance_id = instance_id
	_trade_mode = false
	_selected_trade_target_id = ""
	_trade_status = ""
	_clear_pending_action()
	refresh_requested.emit()


func _begin_trade(item: ItemView) -> void:
	_trade_mode = true
	_selected_trade_target_id = InventoryViewQueries.first_enabled_trade_target(item)
	_trade_status = ""
	_clear_pending_action()
	refresh_requested.emit()


func _cancel_trade() -> void:
	_trade_mode = false
	_selected_trade_target_id = ""
	_trade_status = ""
	refresh_requested.emit()


func _bind_trade_action(button: ClassicBitmapButton, item: ItemView) -> void:
	var availability := item.actions.trade if item != null and item.actions != null else null
	_bind_bitmap_button(button, &"inventory.action.trade", "Trade")
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if not availability.enabled else "Open the two-pack Trade workspace"
	if not button.disabled:
		button.command_requested.connect(func(_command_id: StringName) -> void: _begin_trade(item))


func _bind_item_intent_action(button: ClassicBitmapButton, asset_id: StringName, label: String, availability: ActionAvailabilityView, intent: PlayerIntent, item: ItemView, character: CharacterView) -> void:
	_bind_bitmap_button(button, asset_id, label)
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if not availability.enabled else label
	if not button.disabled:
		button.command_requested.connect(func(_command_id: StringName) -> void: _begin_item_action(StringName(label.to_snake_case()), label, intent, item, character))


func _bind_bitmap_button(button: ClassicBitmapButton, asset_id: StringName, label: String) -> void:
	_scene_binding.clear_command_connections(button)
	# Castle inventory artwork baked each word into a different legacy slab.
	# Rebuilt retains the command identity but renders one consistent slate control.
	button.configure({"id": asset_id, "asset_id": &"", "label": label, "tooltip": label, "accelerator": ""}, 1)
