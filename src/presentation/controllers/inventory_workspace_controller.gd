class_name InventoryWorkspaceController
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
const CONTENT_ICON_SCRIPT := preload("res://src/presentation/classic_content_icon.gd")
const EXCHANGE_ITEM_BUTTON_SCRIPT := preload("res://src/presentation/interaction_components/classic_exchange_item_button.gd")
const EXCHANGE_LEDGER_SCRIPT := preload("res://src/presentation/interaction_components/classic_exchange_ledger.gd")
const ITEM_DETAIL_POPOVER_SCRIPT := preload("res://src/presentation/classic_item_detail_popover.gd")

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


func present(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	_encounter_mode = false
	_encounter_items.clear()
	_present(parent, view, media, text_scale)


func present_encounter(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float, entries: Array[InteractionRequestValue.EncounterCatalogEntry]) -> void:
	_encounter_mode = true
	_encounter_items.clear()
	for entry: InteractionRequestValue.EncounterCatalogEntry in entries:
		if not _encounter_items.has(entry.character_id):
			_encounter_items[entry.character_id] = {}
		(_encounter_items[entry.character_id] as Dictionary)[entry.instance_id] = entry.classic_id
	_present(parent, view, media, text_scale)


func _present(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	if parent == null:
		return
	_capture_item_scroll(parent)
	_clear(parent)
	_text_scale = maxf(text_scale, 0.1)
	if view == null:
		return
	if view.party_members.is_empty():
		_add_empty_state(parent, "No party inventory", "The party has no characters.")
		_add_inventory_done(parent)
		return
	var available_characters := _eligible_characters(view)
	if available_characters.is_empty():
		_add_empty_state(parent, "No encounter items", "No carried item can be selected for this encounter.")
		if not _encounter_mode:
			_add_inventory_done(parent)
		return
	var selected_character := _selected_character(view)
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
	var visible_items := _eligible_items(selected_character)
	var detail_popover := ITEM_DETAIL_POPOVER_SCRIPT.new() as CanvasLayer
	parent.add_child(detail_popover)
	detail_popover.configure(media, parent.get_theme())
	var selected_item := _selected_item(visible_items)
	if selected_item == null and not visible_items.is_empty():
		selected_item = visible_items[0]
		_selected_item_instance_id = selected_item.instance_id
	if _trade_mode:
		var target := _character_by_id(view, _selected_trade_target_id)
		if target == null:
			_cancel_trade()
			return
		parent.add_child(_build_trade_workspace(view, selected_character, target, selected_item, media, detail_popover))
		parent.add_child(_build_trade_item_record(selected_character, selected_item, media))
		return
	var main_split := HBoxContainer.new()
	main_split.name = "CastleInventoryMainSplit"
	main_split.add_theme_constant_override("separation", 8)
	main_split.custom_minimum_size.y = 300.0 if _layout_profile == UiLayoutProfile.COMPACT else 410.0
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.size_flags_vertical = Control.SIZE_FILL if _layout_profile == UiLayoutProfile.COMPACT else Control.SIZE_EXPAND_FILL
	main_split.add_child(_build_item_browser(selected_character, visible_items, selected_item, media, detail_popover))
	main_split.add_child(_build_character_command_rail(view, selected_character, selected_item, media))
	parent.add_child(main_split)
	parent.add_child(_build_item_record(selected_character, selected_item, media))


func _build_character_selector(view: GameView, selected: CharacterView, media: ClassicMediaCatalog) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "InventoryCharacterSelector"
	panel.theme_type_variation = &"ClassicInset"
	var row := GridContainer.new()
	var characters := _eligible_characters(view)
	row.columns = mini(3, characters.size()) if _layout_profile == UiLayoutProfile.COMPACT else characters.size()
	row.add_theme_constant_override("h_separation", 3)
	panel.add_child(row)
	for character: CharacterView in characters:
		var button := Button.new()
		button.name = "InventoryCharacter_%s" % character.id
		button.icon = _appearance_texture(character.portrait_id, media)
		button.expand_icon = true
		button.toggle_mode = true
		button.button_pressed = character.id == selected.id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 46.0
		button.tooltip_text = "%s • %s / %s • Load %d/%d" % [character.name, character.race_name, character.caste_name, character.carried_load, character.maximum_load]
		button.accessibility_name = "Select %s" % character.name
		button.pressed.connect(_select_character.bind(character.id))
		row.add_child(button)
	return panel


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
	var source := _selected_character(view)
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


func _build_item_browser(character: CharacterView, items: Array[ItemView], selected: ItemView, media: ClassicMediaCatalog, detail_popover: CanvasLayer) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "InventoryItemBrowser"
	panel.theme_type_variation = &"ClassicItemLedger"
	panel.custom_minimum_size = Vector2(390.0 if _layout_profile == UiLayoutProfile.COMPACT else 620.0, 280.0 if _layout_profile == UiLayoutProfile.COMPACT else 330.0)
	panel.size_flags_horizontal = Control.SIZE_FILL if _layout_profile == UiLayoutProfile.COMPACT else Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.45
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	var title := _label("%s's items" % character.name, LEDGER_INK, 17)
	title.theme_type_variation = &"ClassicHeading"
	title.add_theme_color_override("font_color", LEDGER_INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var count := _label("%d carried" % items.size(), LEDGER_MUTED, 12)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(count)
	column.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.name = "InventoryItemScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	scroll.add_child(list)
	_bind_item_scroll(scroll)
	column.add_child(scroll)
	if items.is_empty():
		_add_label(list, "No carried items.", LEDGER_MUTED)
		return panel
	for item: ItemView in items:
		var row_panel := PanelContainer.new()
		row_panel.name = "InventoryItemRow_%s" % item.instance_id
		row_panel.theme_type_variation = &"ClassicItemLedgerSelectedRow" if selected != null and selected.instance_id == item.instance_id else &"ClassicItemLedgerRow"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var icon := _content_icon(item.icon_resource_type, item.icon_id, media, 38.0, item.name)
		row.add_child(icon)
		var item_text := VBoxContainer.new()
		item_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_text.add_theme_constant_override("separation", -2)
		var button := Button.new()
		button.name = "InventoryItem_%s" % item.instance_id
		button.theme_type_variation = &"ClassicItemLedgerButton"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 24.0
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = selected != null and selected.instance_id == item.instance_id
		button.text = item.name
		button.tooltip_text = "%s%s" % ["Equipped" if item.equipped else "Carried", " • %d charges" % item.charges if item.charges > 0 else ""]
		button.pressed.connect(_select_item.bind(item.instance_id))
		item_text.add_child(button)
		var line_fact := _item_line_fact(item)
		if line_fact != null:
			var fact_label := _label("%s %s" % [line_fact.label, line_fact.value], LEDGER_RED if line_fact.id == &"damage-range" else LEDGER_BLUE, 11)
			fact_label.name = "InventoryItemLineFact"
			fact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			item_text.add_child(fact_label)
		row.add_child(item_text)
		detail_popover.bind_hover(icon, _item_detail(item))
		detail_popover.bind_hover(button, _item_detail(item))
		var state_parts: Array[String] = []
		if item.equipped:
			state_parts.append("Equipped")
		if item.charges > 0:
			state_parts.append("%d charge%s" % [item.charges, "" if item.charges == 1 else "s"])
		var state := _label(" · ".join(state_parts), LEDGER_BLUE if item.equipped else LEDGER_RED if item.charges > 0 else LEDGER_MUTED, 12)
		state.custom_minimum_size.x = 112.0
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		state.tooltip_text = button.tooltip_text
		row.add_child(state)
		row_panel.add_child(row)
		list.add_child(row_panel)
	return panel


static func _item_detail(item: ItemView) -> Dictionary:
	var facts: Array[Dictionary] = []
	for fact: ItemFactView in item.facts:
		facts.append({"label": fact.label, "value": fact.value})
	return {"title": item.name, "subtitle": "%s  •  Weight %d  •  %s" % ["Equipped" if item.equipped else "Carried", item.weight, "Unlimited charges" if item.charges < 0 else "%d charges" % item.charges], "description": item.description, "facts": facts, "properties": item.properties.duplicate(), "restrictions": item.restrictions.duplicate(), "iconResourceType": item.icon_resource_type, "iconId": item.icon_id}


func _item_line_fact(item: ItemView) -> ItemFactView:
	for fact_id: StringName in [&"damage-range", &"armor"]:
		for fact: ItemFactView in item.facts:
			if fact.id == fact_id:
				return fact
	return null


func _build_character_command_rail(view: GameView, character: CharacterView, item: ItemView, media: ClassicMediaCatalog) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "InventoryCharacterCommandRail"
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size = Vector2(350.0 if _layout_profile == UiLayoutProfile.COMPACT else 285.0, 280.0 if _layout_profile == UiLayoutProfile.COMPACT else 330.0)
	panel.size_flags_horizontal = Control.SIZE_FILL if _layout_profile == UiLayoutProfile.COMPACT else Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.75
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	_render_character_record(column, character, media)
	if item == null:
		_add_label(column, "Select an item to see its commands.", MUTED)
		column.add_child(_build_character_selector(view, character, media))
		return panel
	_render_item_actions(column, view, item, character, media)
	column.add_child(_build_character_selector(view, character, media))
	return panel


func _render_character_record(parent: VBoxContainer, character: CharacterView, media: ClassicMediaCatalog) -> void:
	var identity := HBoxContainer.new()
	identity.name = "InventoryCharacterIdentity"
	identity.add_theme_constant_override("separation", 8)
	identity.add_child(_portrait_icon(character.portrait_id, media, 46.0))
	var title := VBoxContainer.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_label(title, character.name, GOLD, 19)
	_add_label(title, "%s / %s • Level %d" % [character.race_name, character.caste_name, character.level], TEXT, 12)
	identity.add_child(title)
	parent.add_child(identity)
	var facts := GridContainer.new()
	facts.name = "InventoryCharacterFacts"
	facts.columns = 2
	facts.add_theme_constant_override("h_separation", 8)
	facts.add_theme_constant_override("v_separation", 2)
	for fact: String in [
		"ST %d/%d" % [character.current_health, character.maximum_health],
		"SP %d/%d" % [character.spell_points, character.maximum_spell_points],
		"AR %d" % character.armor,
		"Attacks %s" % character.attacks_per_round,
		"Movement %d/%d" % [character.movement, character.maximum_movement],
		"Load %d/%d" % [character.carried_load, character.maximum_load],
	]:
		var fact_label := _add_label(facts, fact, TEXT, 12)
		fact_label.custom_minimum_size.x = 104.0
		fact_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	parent.add_child(facts)
	var condition_text := "Conditions: None"
	if not character.conditions.is_empty():
		var names: Array[String] = []
		for condition: CharacterMetricView in character.conditions:
			names.append(condition.name)
		condition_text = "Conditions: %s" % ", ".join(names)
	var condition_label := _add_label(parent, condition_text, WARNING if not character.conditions.is_empty() else MUTED, 11)
	condition_label.max_lines_visible = 2
	condition_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _build_item_record(character: CharacterView, item: ItemView, media: ClassicMediaCatalog) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "InventoryItemInspector"
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.y = 150.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	var record: BoxContainer = VBoxContainer.new() if _layout_profile == UiLayoutProfile.COMPACT else HBoxContainer.new()
	record.name = "InventorySelectedItemRecord"
	record.add_theme_constant_override("separation", 12)
	record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(record)
	if not _encounter_mode:
		content.add_child(_build_inventory_done_column())
	if item == null:
		_add_label(record, "Select an item to inspect it.", MUTED)
		return panel
	var narrative := VBoxContainer.new()
	narrative.name = "InventoryItemNarrative"
	narrative.custom_minimum_size.x = 0.0 if _layout_profile == UiLayoutProfile.COMPACT else 470.0
	narrative.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	narrative.size_flags_stretch_ratio = 1.1
	_render_item_detail(narrative, item, character, media)
	record.add_child(narrative)
	var facts := VBoxContainer.new()
	facts.name = "InventoryItemFacts"
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.size_flags_stretch_ratio = 0.9
	_render_item_facts(facts, item)
	record.add_child(facts)
	return panel


func _add_inventory_done(parent: Container) -> void:
	var row := HBoxContainer.new()
	row.name = "InventoryEmptyActions"
	row.alignment = BoxContainer.ALIGNMENT_END
	parent.add_child(row)
	row.add_child(_build_inventory_done_column())


func _build_inventory_done_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "InventoryDoneColumn"
	column.custom_minimum_size.x = 56.0
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var done := Button.new()
	done.name = "InventoryDone"
	done.text = "Done"
	done.tooltip_text = "Return to the previous screen."
	done.custom_minimum_size = Vector2(56.0, 56.0)
	done.pressed.connect(func() -> void: back_requested.emit())
	column.add_child(done)
	return column


func _build_trade_item_record(character: CharacterView, item: ItemView, media: ClassicMediaCatalog) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "InventoryItemInspector"
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.y = 92.0
	var row := HBoxContainer.new()
	row.name = "InventorySelectedItemRecord"
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	if item == null:
		_add_label(row, "Drag an item between packs, or select one to inspect it.", MUTED, 13)
		return panel
	row.add_child(_content_icon(item.icon_resource_type, item.icon_id, media, 52.0, item.name))
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_label(detail, item.name, GOLD, 18)
	_add_label(detail, "%s • Weight %d • %s" % ["Equipped" if item.equipped else "Carried", item.weight, "Unlimited charges" if item.charges < 0 else "%d charges" % item.charges], MUTED, 12)
	_add_label(detail, item.description, TEXT, 12)
	row.add_child(detail)
	var facts := VBoxContainer.new()
	facts.custom_minimum_size.x = 230.0
	_add_section_heading(facts, "Item facts", "Value %s" % [str(item.value) if item.identified else "unknown"])
	_add_label(facts, " • ".join(item.facts.map(func(fact: ItemFactView) -> String: return "%s %s" % [fact.label, fact.value])), TEXT, 12)
	row.add_child(facts)
	return panel


func _render_item_detail(parent: VBoxContainer, item: ItemView, character: CharacterView, media: ClassicMediaCatalog) -> void:
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	title_row.add_child(_content_icon(item.icon_resource_type, item.icon_id, media, 58.0, item.name))
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_label(title_box, item.name, GOLD, 20)
	_add_label(title_box, "%s · Weight %d · Charges %d" % ["Equipped" if item.equipped else "Carried", item.weight, item.charges], MUTED, 13)
	title_row.add_child(title_box)
	parent.add_child(title_row)
	_add_label(parent, item.description, TEXT)
	_add_label(parent, "%s • Load %d/%d" % [character.name, character.carried_load, character.maximum_load], MUTED, 12)


func _render_item_facts(parent: VBoxContainer, item: ItemView) -> void:
	_add_section_heading(parent, "Item facts", "Value %s" % [str(item.value) if item.identified else "unknown"])
	if not item.facts.is_empty():
		var facts := GridContainer.new()
		facts.columns = 2
		facts.add_theme_constant_override("h_separation", 14)
		facts.add_theme_constant_override("v_separation", 3)
		for fact: ItemFactView in item.facts:
			var fact_name := _label(fact.label, MUTED, 13)
			fact_name.custom_minimum_size.x = 112.0
			facts.add_child(fact_name)
			var fact_value := _label(fact.value, TEXT, 13)
			fact_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fact_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			facts.add_child(fact_value)
		parent.add_child(facts)
	for property: String in item.properties:
		_add_label(parent, "• %s" % property, TEXT, 13)
	for restriction: String in item.restrictions:
		_add_label(parent, restriction, WARNING, 13)


func _render_item_actions(parent: VBoxContainer, view: GameView, item: ItemView, character: CharacterView, media: ClassicMediaCatalog) -> void:
	if _encounter_mode:
		var actions := GridContainer.new()
		actions.name = "InventoryActionDock"
		actions.columns = 1
		var choose := _bitmap_button(&"inventory.action.use", "Use in encounter")
		choose.name = "EncounterItemChoose"
		choose.custom_minimum_size.x = 150.0
		choose.command_requested.connect(func(_command_id: StringName) -> void: _submit_encounter_item(character.id, item.instance_id))
		actions.add_child(choose)
		parent.add_child(actions)
		return
	if not _pending_item_action.is_empty():
		_render_operation_stage(parent, item, character)
		return
	var actions := GridContainer.new()
	actions.name = "InventoryActionDock"
	actions.columns = 3 if _layout_profile == UiLayoutProfile.COMPACT else 4
	actions.add_theme_constant_override("h_separation", 5)
	actions.add_theme_constant_override("v_separation", 5)
	if item.equipped:
		_add_item_intent_action(actions, &"inventory.action.equipped", "Unequip", item.actions.unequip, PlayerIntent.item_action(PlayerIntent.Kind.UNEQUIP_ITEM, item.instance_id, character.id), item, character)
	else:
		_add_item_intent_action(actions, &"inventory.action.equipped", "Equip", item.actions.equip, PlayerIntent.item_action(PlayerIntent.Kind.EQUIP_ITEM, item.instance_id, character.id), item, character)
	_add_item_intent_action(actions, &"inventory.action.use", "Use", item.actions.use, PlayerIntent.use_item(item.instance_id, character.id), item, character)
	_add_item_intent_action(actions, &"inventory.action.identify", "Identify", item.actions.identify, PlayerIntent.identify_carried_items(item.actions.identify_spell_id, item.actions.identify_caster_id, character.id), item, character)
	_add_trade_action(actions, item)
	_add_item_intent_action(actions, &"inventory.action.join", "Join", item.actions.join, PlayerIntent.item_action(PlayerIntent.Kind.JOIN_ITEM, item.instance_id, character.id), item, character)
	_add_item_intent_action(actions, &"inventory.action.split", "Split", item.actions.split, PlayerIntent.item_action(PlayerIntent.Kind.SPLIT_ITEM, item.instance_id, character.id), item, character)
	_add_item_intent_action(actions, &"inventory.action.drop", "Drop", item.actions.drop, PlayerIntent.item_action(PlayerIntent.Kind.DROP_ITEM, item.instance_id, character.id), item, character)
	parent.add_child(actions)
	if not _trade_status.is_empty():
		_add_label(parent, _trade_status, WARNING, 13)


func _render_operation_stage(parent: VBoxContainer, item: ItemView, character: CharacterView) -> void:
	var panel := PanelContainer.new()
	panel.name = "InventoryOperationStage"
	panel.theme_type_variation = &"ClassicInset"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	_add_section_heading(column, "%s · %s" % [_pending_item_action_label, item.name], "%s · %s" % [character.name, "Equipped" if item.equipped else "Carried"])
	var facts: Array[String] = ["Weight %d" % item.weight]
	facts.append("Unlimited charges" if item.charges < 0 else "%d charge%s" % [item.charges, "" if item.charges == 1 else "s"])
	_add_label(column, " • ".join(facts), MUTED, 13)
	_add_label(column, _operation_description(_pending_item_action, item, character), TEXT, 13)
	var actions := HBoxContainer.new()
	actions.name = "InventoryOperationActions"
	actions.add_theme_constant_override("separation", 6)
	var confirm := Button.new()
	confirm.text = _pending_item_action_label
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(_confirm_item_action)
	actions.add_child(confirm)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_cancel_item_action)
	actions.add_child(cancel)
	column.add_child(actions)
	parent.add_child(panel)


static func _operation_description(action: StringName, item: ItemView, character: CharacterView) -> String:
	match action:
		&"equip": return "Move this exact carried item into its legal equipment position."
		&"unequip": return "Return this exact equipped item to the carried pack."
		&"use": return "Use this exact carried item through its source-backed field effect."
		&"identify": return "Cast Identify Objects on every carried item owned by %s." % character.name
		&"join": return "Join this charged record with the first compatible carried stack."
		&"split": return "Split this charged record into two stable carried instances."
		&"drop": return "Continue to the required source-backed drop confirmation for this exact item."
	return "Apply %s to this exact item." % String(action)


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


func _build_trade_workspace(view: GameView, source: CharacterView, target: CharacterView, selected_item: ItemView, media: ClassicMediaCatalog, detail_popover: CanvasLayer) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "InventoryTradeWorkspace"
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	_add_section_heading(column, "Trade", "Drag an item from one pack to the other")
	var ledgers := HBoxContainer.new()
	ledgers.name = "InventoryTradeLedgers"
	ledgers.add_theme_constant_override("separation", 8)
	ledgers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ledgers.add_child(_build_trade_ledger(view, source, target.id, media, detail_popover))
	ledgers.add_child(_build_trade_control_spine(view, source, target, media))
	ledgers.add_child(_build_trade_ledger(view, target, source.id, media, detail_popover))
	column.add_child(ledgers)
	if not _trade_status.is_empty():
		_add_label(column, _trade_status, WARNING, 12)
	return panel


func _build_trade_ledger(view: GameView, character: CharacterView, other_id: String, media: ClassicMediaCatalog, detail_popover: CanvasLayer) -> PanelContainer:
	var ledger := EXCHANGE_LEDGER_SCRIPT.new()
	ledger.name = "InventoryTradeLedger_%s" % character.id
	ledger.theme_type_variation = &"ClassicItemLedger"
	ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ledger.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ledger.size_flags_stretch_ratio = 1.0
	ledger.configure_drop(&"inventory-trade-item", character.id)
	ledger.item_dropped.connect(func(payload: Dictionary, target_id: String) -> void: _drop_trade_item(view, payload, target_id))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	ledger.add_child(column)
	var heading := HBoxContainer.new()
	var title := _label("%s's items" % character.name, LEDGER_INK, 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(_label("Load %d/%d" % [character.carried_load, character.maximum_load], LEDGER_MUTED, 12))
	column.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 0)
	scroll.add_child(rows)
	for item: ItemView in character.items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var icon := _content_icon(item.icon_resource_type, item.icon_id, media, 34.0, item.name)
		row.add_child(icon)
		var button := EXCHANGE_ITEM_BUTTON_SCRIPT.new()
		button.name = "InventoryTradeItem_%s" % item.instance_id
		button.theme_type_variation = &"ClassicItemLedgerButton"
		button.text = "%s\n%s" % [item.name, _trade_line(item)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = false
		button.pressed.connect(_select_trade_item.bind(view, character.id, item.instance_id, other_id))
		button.configure_drag({"kind": &"inventory-trade-item", "sourceId": character.id, "instanceId": item.instance_id})
		row.add_child(button)
		detail_popover.bind_hover(icon, _item_detail(item))
		detail_popover.bind_hover(button, _item_detail(item))
		rows.add_child(row)
	if character.items.is_empty():
		_add_label(rows, "No carried items.", LEDGER_MUTED, 12)
	return ledger


func _build_trade_control_spine(view: GameView, source: CharacterView, target: CharacterView, media: ClassicMediaCatalog) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.name = "InventoryTradeDivider"
	panel.custom_minimum_size.x = 150.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	var portraits := GridContainer.new()
	portraits.name = "InventoryTradePortraitMatrix"
	portraits.columns = 2
	portraits.add_theme_constant_override("h_separation", 4)
	portraits.add_theme_constant_override("v_separation", 3)
	column.add_child(portraits)
	for character: CharacterView in view.party_members:
		portraits.add_child(_trade_portrait(character, true, character.id == source.id, media))
		portraits.add_child(_trade_portrait(character, false, character.id == target.id, media))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	for route: Dictionary in [{"name": "InventoryTradeMoney", "text": "Money", "call": func() -> void: route_requested.emit(&"services")}, {"name": "InventoryTradeItems", "text": "Items", "call": _cancel_trade}, {"name": "InventoryTradeDone", "text": "Done", "call": func() -> void: back_requested.emit()}]:
		var button := Button.new()
		button.name = route["name"]
		button.text = route["text"]
		button.custom_minimum_size.y = 36.0
		button.pressed.connect(route["call"])
		column.add_child(button)
	return panel


func _trade_portrait(character: CharacterView, left_side: bool, selected: bool, media: ClassicMediaCatalog) -> Button:
	var button := Button.new()
	button.name = "InventoryTrade%s_%s" % ["Left" if left_side else "Right", character.id]
	button.icon = _appearance_texture(character.portrait_id, media)
	button.expand_icon = true
	button.toggle_mode = true
	button.button_pressed = selected
	button.custom_minimum_size = Vector2(58.0, 44.0)
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
	var character := _character_by_id(view, character_id)
	if character == null:
		return
	var item := _item_by_id(character, instance_id)
	if item == null:
		return
	_selected_character_id = character_id
	_selected_item_instance_id = instance_id
	_selected_trade_target_id = _first_enabled_trade_target(item, preferred_target_id)
	_trade_status = "Choose a destination for %s." % item.name if _selected_trade_target_id.is_empty() else "Ready to transfer %s." % item.name
	refresh_requested.emit()


func _drop_trade_item(view: GameView, payload: Dictionary, target_id: String) -> void:
	var source_id := String(payload.get("sourceId", ""))
	var instance_id := String(payload.get("instanceId", ""))
	var source := _character_by_id(view, source_id)
	var item := _item_by_id(source, instance_id)
	var availability := _trade_target(item, target_id)
	if availability == null or not availability.enabled:
		_trade_status = "This item cannot be transferred there." if availability == null else availability.reason
		refresh_requested.emit()
		return
	_submit_trade(instance_id, source_id, target_id)


static func _trade_line(item: ItemView) -> String:
	var parts: Array[String] = ["Equipped" if item.equipped else "Carried", "Weight %d" % item.weight]
	if item.charges > 0:
		parts.append("%d charges" % item.charges)
	return " • ".join(parts)


static func _item_by_id(character: CharacterView, instance_id: String) -> ItemView:
	if character == null:
		return null
	for item: ItemView in character.items:
		if item.instance_id == instance_id:
			return item
	return null


static func _trade_target(item: ItemView, target_id: String) -> ItemTransferTargetView:
	if item == null or item.actions == null:
		return null
	for target: ItemTransferTargetView in item.actions.trade_targets:
		if target.character_id == target_id:
			return target
	return null


static func _first_enabled_trade_target(item: ItemView, preferred_id: String = "") -> String:
	var preferred := _trade_target(item, preferred_id)
	if preferred != null and preferred.enabled:
		return preferred.character_id
	if item != null and item.actions != null:
		for target: ItemTransferTargetView in item.actions.trade_targets:
			if target.enabled:
				return target.character_id
	return ""


func _submit_trade(instance_id: String, source_id: String, target_id: String) -> void:
	_trade_status = "Transferring item…"
	intent_submitted.emit(PlayerIntent.trade_item(instance_id, source_id, target_id))


func _selected_character(view: GameView) -> CharacterView:
	for character: CharacterView in view.party_members:
		if character.id == _selected_character_id and (not _encounter_mode or _encounter_items.has(character.id)):
			return character
	return null


func _eligible_characters(view: GameView) -> Array[CharacterView]:
	if not _encounter_mode:
		return view.party_members
	var result: Array[CharacterView] = []
	for character: CharacterView in view.party_members:
		if _encounter_items.has(character.id) and not _eligible_items(character).is_empty():
			result.append(character)
	return result


func _eligible_items(character: CharacterView) -> Array[ItemView]:
	if not _encounter_mode:
		return character.items
	var result: Array[ItemView] = []
	var instances := _encounter_items.get(character.id, {}) as Dictionary
	for item: ItemView in character.items:
		if instances.has(item.instance_id):
			result.append(item)
	return result


func _submit_encounter_item(character_id: String, instance_id: String) -> void:
	var instances := _encounter_items.get(character_id, {}) as Dictionary
	if instances.has(instance_id):
		encounter_item_selected.emit(character_id, instance_id, int(instances[instance_id]))


func _selected_item(items: Array[ItemView]) -> ItemView:
	for item: ItemView in items:
		if item.instance_id == _selected_item_instance_id:
			return item
	return null


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
	_selected_trade_target_id = _first_enabled_trade_target(item)
	_trade_status = ""
	_clear_pending_action()
	refresh_requested.emit()


func _cancel_trade() -> void:
	_trade_mode = false
	_selected_trade_target_id = ""
	_trade_status = ""
	refresh_requested.emit()


func _add_trade_action(parent: Container, item: ItemView) -> void:
	var availability := item.actions.trade if item != null and item.actions != null else null
	var button := _bitmap_button(&"inventory.action.trade", "Trade")
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if not availability.enabled else "Open the two-pack Trade workspace"
	if not button.disabled:
		button.command_requested.connect(func(_command_id: StringName) -> void: _begin_trade(item))
	parent.add_child(button)


func _content_icon(resource_type: String, resource_id: int, media: ClassicMediaCatalog, side: float = 52.0, semantic_label: String = "") -> Control:
	var icon := CONTENT_ICON_SCRIPT.new() as Control
	icon.configure(resource_type, resource_id, media, side, semantic_label)
	return icon


func _appearance_texture(asset_id: String, media: ClassicMediaCatalog) -> Texture2D:
	if media == null or asset_id.is_empty():
		return null
	return media.image_texture(media.asset_by_id(asset_id))


func _portrait_icon(asset_id: String, media: ClassicMediaCatalog, side: float = 36.0) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(side, side)
	icon.texture = _appearance_texture(asset_id, media)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return icon


static func _character_by_id(view: GameView, character_id: String) -> CharacterView:
	if view == null:
		return null
	for character: CharacterView in view.party_members:
		if character.id == character_id:
			return character
	return null


func _add_item_intent_action(parent: Container, asset_id: StringName, label: String, availability: ActionAvailabilityView, intent: PlayerIntent, item: ItemView, character: CharacterView) -> BaseButton:
	var button := _bitmap_button(asset_id, label)
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if not availability.enabled else label
	if not button.disabled:
		button.command_requested.connect(func(_command_id: StringName) -> void: _begin_item_action(StringName(label.to_snake_case()), label, intent, item, character))
	parent.add_child(button)
	return button


func _bitmap_button(asset_id: StringName, label: String) -> ClassicBitmapButton:
	var button := ClassicBitmapButton.new()
	# Castle inventory artwork baked each word into a different legacy slab.
	# Rebuilt retains the command identity but renders one consistent slate control.
	button.configure({"id": asset_id, "asset_id": &"", "label": label, "tooltip": label, "accelerator": ""}, 1)
	return button


func _add_section_heading(parent: Container, title: String, detail: String = "") -> void:
	var row := HBoxContainer.new()
	var heading := _label(title, GOLD, 17)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	if not detail.is_empty():
		var note := _label(detail, MUTED, 12)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(note)
	parent.add_child(row)


func _add_empty_state(parent: Container, title: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	var column := VBoxContainer.new()
	panel.add_child(column)
	_add_label(column, title, GOLD, 16)
	_add_label(column, detail, MUTED, 13)
	parent.add_child(panel)


func _label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * _text_scale)))
	return label


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := _label(text, color, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _clear(parent: Container) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _capture_item_scroll(parent: Container) -> void:
	if _rendered_character_id != _selected_character_id:
		return
	var scroll := parent.find_child("InventoryItemScroll", true, false) as ScrollContainer
	if scroll != null:
		_item_scroll_position = scroll.scroll_vertical


func _bind_item_scroll(scroll: ScrollContainer) -> void:
	var scroll_ref: WeakRef = weakref(scroll)
	var desired_position := _item_scroll_position
	var tree := Engine.get_main_loop() as SceneTree
	tree.process_frame.connect(func() -> void:
		var current_scroll := scroll_ref.get_ref() as ScrollContainer
		if current_scroll == null or not current_scroll.is_inside_tree():
			return
		var current_bar := current_scroll.get_v_scroll_bar()
		var maximum := maxi(0, int(current_bar.max_value - current_bar.page))
		current_scroll.scroll_vertical = clampi(desired_position, 0, maximum)
	, CONNECT_ONE_SHOT)
