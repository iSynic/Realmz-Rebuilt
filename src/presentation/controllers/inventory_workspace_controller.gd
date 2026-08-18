class_name InventoryWorkspaceController
extends RefCounted

signal intent_submitted(intent: PlayerIntent)
signal refresh_requested

const GOLD := Color("d5b45d")
const TEXT := Color("e0e2e5")
const MUTED := Color("9aa0a8")
const WARNING := Color("dca9a9")

var _query: String = ""
var _selected_character_id: String = ""
var _selected_item_instance_id: String = ""
var _trade_mode: bool = false
var _selected_trade_target_id: String = ""
var _trade_status: String = ""
var _pending_item_action: StringName = &""
var _pending_item_action_label: String = ""
var _pending_item_intent: PlayerIntent
var _text_scale: float = 1.0


func reset() -> void:
	_query = ""
	_selected_character_id = ""
	_selected_item_instance_id = ""
	_trade_mode = false
	_selected_trade_target_id = ""
	_trade_status = ""
	_clear_pending_action()


func present(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	if parent == null:
		return
	_clear(parent)
	_text_scale = maxf(text_scale, 0.1)
	if view == null:
		return
	if view.party_members.is_empty():
		_add_empty_state(parent, "No party inventory", "The party has no characters.")
		return
	var selected_character := _selected_character(view)
	if selected_character == null:
		selected_character = view.party_members[0]
		_selected_character_id = selected_character.id
		_selected_item_instance_id = ""
		_trade_mode = false
		_selected_trade_target_id = ""
		_trade_status = ""
		_clear_pending_action()
	_add_character_selector(parent, view, selected_character, media)
	_add_header(parent, selected_character)
	var visible_items := _visible_items(selected_character)
	var selected_item := _selected_item(visible_items)
	if selected_item == null and not visible_items.is_empty():
		selected_item = visible_items[0]
		_selected_item_instance_id = selected_item.instance_id
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(_build_item_browser(selected_character, visible_items, selected_item, media))
	columns.add_child(_build_item_inspector(view, selected_character, selected_item, media))
	parent.add_child(columns)


func _add_character_selector(parent: VBoxContainer, view: GameView, selected: CharacterView, media: ClassicMediaCatalog) -> void:
	var panel := PanelContainer.new()
	panel.name = "InventoryCharacterSelector"
	panel.theme_type_variation = &"ClassicInset"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	panel.add_child(row)
	for character: CharacterView in view.party_members:
		var button := Button.new()
		button.text = character.name
		button.icon = _appearance_texture(character.portrait_id, media)
		button.expand_icon = true
		button.toggle_mode = true
		button.button_pressed = character.id == selected.id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 44.0
		button.tooltip_text = "%s • Load %d/%d" % [character.name, character.carried_load, character.maximum_load]
		button.pressed.connect(_select_character.bind(character.id))
		row.add_child(button)
	parent.add_child(panel)


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


func _add_header(parent: VBoxContainer, character: CharacterView) -> void:
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	var title := _label("Inventory · %s" % character.name, GOLD, 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var load := _label("Load %d / %d" % [character.carried_load, character.maximum_load], MUTED, 13)
	load.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(load)
	parent.add_child(heading)
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	var search := LineEdit.new()
	search.placeholder_text = "Filter items"
	search.text = _query
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_submitted.connect(_set_query)
	filter_row.add_child(search)
	var clear_filter := Button.new()
	clear_filter.text = "Clear"
	clear_filter.disabled = _query.is_empty()
	clear_filter.pressed.connect(_clear_query)
	filter_row.add_child(clear_filter)
	parent.add_child(filter_row)


func _build_item_browser(character: CharacterView, items: Array[ItemView], selected: ItemView, media: ClassicMediaCatalog) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "InventoryItemBrowser"
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size = Vector2(300.0, 340.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.85
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	_add_section_heading(column, "%s's items" % character.name, "%d carried" % items.size())
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	column.add_child(scroll)
	if items.is_empty():
		_add_label(list, "No items match the filter." if not _query.is_empty() else "No carried items.", MUTED)
		return panel
	for item: ItemView in items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(_content_icon(item.icon_resource_type, item.icon_id, media, 38.0))
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 40.0
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = selected != null and selected.instance_id == item.instance_id
		button.text = "%s%s%s" % ["◆ " if item.equipped else "", item.name, " · %d charges" % item.charges if item.charges > 0 else ""]
		button.tooltip_text = "Equipped" if item.equipped else "Carried"
		button.pressed.connect(_select_item.bind(item.instance_id))
		row.add_child(button)
		list.add_child(row)
	return panel


func _build_item_inspector(view: GameView, character: CharacterView, item: ItemView, media: ClassicMediaCatalog) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "InventoryItemInspector"
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size = Vector2(320.0, 340.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.15
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	_add_section_heading(column, "Item record")
	if item == null:
		_add_label(column, "Select an item to inspect it.", MUTED)
		return panel
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	scroll.add_child(detail)
	column.add_child(scroll)
	_render_item_detail(detail, item, character, media)
	column.add_child(HSeparator.new())
	_render_item_actions(column, view, item, character, media)
	return panel


func _render_item_detail(parent: VBoxContainer, item: ItemView, character: CharacterView, media: ClassicMediaCatalog) -> void:
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	title_row.add_child(_content_icon(item.icon_resource_type, item.icon_id, media, 58.0))
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_label(title_box, item.name, GOLD, 20)
	_add_label(title_box, "%s · Weight %d · Charges %d" % ["Equipped" if item.equipped else "Carried", item.weight, item.charges], MUTED, 13)
	title_row.add_child(title_box)
	parent.add_child(title_row)
	_add_label(parent, item.description, TEXT)
	_add_label(parent, "Value %s" % [str(item.value) if item.identified else "Unknown until identified"], MUTED, 13)
	if not item.facts.is_empty():
		var facts := GridContainer.new()
		facts.columns = 2
		facts.add_theme_constant_override("h_separation", 14)
		facts.add_theme_constant_override("v_separation", 3)
		for fact: ItemFactView in item.facts:
			var fact_name := _label(fact.label, MUTED, 13)
			fact_name.custom_minimum_size.x = 150.0
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
	if not _pending_item_action.is_empty():
		_render_operation_stage(parent, item, character)
		return
	var actions := GridContainer.new()
	actions.name = "InventoryActionDock"
	actions.columns = 4
	actions.add_theme_constant_override("h_separation", 5)
	actions.add_theme_constant_override("v_separation", 5)
	if item.equipped:
		_add_item_intent_action(actions, &"inventory.action.equipped", "Unequip", item.actions.unequip, PlayerIntent.item_action(PlayerIntent.Kind.UNEQUIP_ITEM, item.instance_id, character.id), item, character)
	else:
		_add_item_intent_action(actions, &"inventory.action.equipped", "Equip", item.actions.equip, PlayerIntent.item_action(PlayerIntent.Kind.EQUIP_ITEM, item.instance_id, character.id), item, character)
	_add_item_intent_action(actions, &"inventory.action.use", "Use", item.actions.use, PlayerIntent.use_item(item.instance_id, character.id), item, character)
	_add_item_intent_action(actions, &"inventory.action.identify", "Identify", item.actions.identify, PlayerIntent.identify_carried_items(item.actions.identify_spell_id, item.actions.identify_caster_id, character.id), item, character)
	_add_item_intent_action(actions, &"inventory.action.join", "Join", item.actions.join, PlayerIntent.item_action(PlayerIntent.Kind.JOIN_ITEM, item.instance_id, character.id), item, character)
	_add_item_intent_action(actions, &"inventory.action.split", "Split", item.actions.split, PlayerIntent.item_action(PlayerIntent.Kind.SPLIT_ITEM, item.instance_id, character.id), item, character)
	_add_item_intent_action(actions, &"inventory.action.drop", "Drop", item.actions.drop, PlayerIntent.item_action(PlayerIntent.Kind.DROP_ITEM, item.instance_id, character.id), item, character)
	_add_trade_action(actions, item.actions.trade)
	parent.add_child(actions)
	if _trade_mode:
		_render_trade_targets(parent, view, item, character, media)
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


func _render_trade_targets(parent: VBoxContainer, view: GameView, item: ItemView, source: CharacterView, media: ClassicMediaCatalog) -> void:
	var panel := PanelContainer.new()
	panel.name = "InventoryTradeRecipients"
	panel.theme_type_variation = &"ClassicInset"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	_add_section_heading(column, "Transfer %s" % item.name, "%s · Load %d/%d" % [source.name, source.carried_load, source.maximum_load])
	var recipients := VBoxContainer.new()
	recipients.name = "InventoryTradeRecipientList"
	recipients.add_theme_constant_override("separation", 3)
	column.add_child(recipients)
	for target: ItemTransferTargetView in item.actions.trade_targets:
		if target.character_id == source.id:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var target_character := _character_by_id(view, target.character_id)
		if target_character != null:
			row.add_child(_portrait_icon(target_character.portrait_id, media))
		var button := Button.new()
		button.text = target.character_name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = target.character_id == _selected_trade_target_id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not target.enabled
		button.tooltip_text = target.reason if button.disabled else "Select this recipient."
		if not button.disabled:
			button.pressed.connect(_select_trade_target.bind(target.character_id, item.name, target.character_name))
		row.add_child(button)
		var load := _label("Load unavailable", MUTED, 12)
		if target.has_load_facts:
			load.text = "%d → %d / %d" % [target.current_load, target.resulting_load, target.maximum_load]
		load.custom_minimum_size.x = 118.0
		load.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		load.tooltip_text = target.reason if not target.enabled else "Current load → load after transfer / capacity"
		row.add_child(load)
		recipients.add_child(row)
		if not target.enabled and not target.reason.is_empty():
			_add_label(recipients, target.reason, WARNING, 12)
	var actions := HBoxContainer.new()
	actions.name = "InventoryTradeActions"
	actions.add_theme_constant_override("separation", 6)
	var transfer := Button.new()
	transfer.text = "Transfer"
	transfer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transfer.disabled = _selected_trade_target_id.is_empty()
	transfer.tooltip_text = "Choose a recipient." if transfer.disabled else "Transfer this exact item instance."
	if not transfer.disabled:
		transfer.pressed.connect(_confirm_trade.bind(item.instance_id, source.id))
	actions.add_child(transfer)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_cancel_trade)
	actions.add_child(cancel)
	column.add_child(actions)
	parent.add_child(panel)


func _select_trade_target(character_id: String, item_name: String, character_name: String) -> void:
	_selected_trade_target_id = character_id
	_trade_status = "Ready to transfer %s to %s." % [item_name, character_name]
	refresh_requested.emit()


func _confirm_trade(instance_id: String, source_id: String) -> void:
	if _selected_trade_target_id.is_empty():
		return
	_submit_trade(instance_id, source_id, _selected_trade_target_id)


func _submit_trade(instance_id: String, source_id: String, target_id: String) -> void:
	_trade_mode = false
	_selected_trade_target_id = ""
	_trade_status = ""
	intent_submitted.emit(PlayerIntent.trade_item(instance_id, source_id, target_id))


func _selected_character(view: GameView) -> CharacterView:
	for character: CharacterView in view.party_members:
		if character.id == _selected_character_id:
			return character
	return null


func _visible_items(character: CharacterView) -> Array[ItemView]:
	var result: Array[ItemView] = []
	for item: ItemView in character.items:
		if _query.is_empty() or item.name.findn(_query) >= 0:
			result.append(item)
	return result


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
	_clear_pending_action()
	refresh_requested.emit()


func _set_query(value: String) -> void:
	_query = value.strip_edges()
	_selected_item_instance_id = ""
	_trade_mode = false
	_selected_trade_target_id = ""
	_trade_status = ""
	_clear_pending_action()
	refresh_requested.emit()


func _clear_query() -> void:
	_set_query("")


func _select_item(instance_id: String) -> void:
	_selected_item_instance_id = instance_id
	_trade_mode = false
	_selected_trade_target_id = ""
	_trade_status = ""
	_clear_pending_action()
	refresh_requested.emit()


func _begin_trade() -> void:
	_trade_mode = true
	_selected_trade_target_id = ""
	_trade_status = ""
	_clear_pending_action()
	refresh_requested.emit()


func _cancel_trade() -> void:
	_trade_mode = false
	_selected_trade_target_id = ""
	_trade_status = ""
	refresh_requested.emit()


func _add_trade_action(parent: Container, availability: ActionAvailabilityView) -> void:
	var button := Button.new()
	button.text = "Trade"
	button.custom_minimum_size = Vector2(64.0, 56.0)
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if not availability.enabled else "Choose a recipient from the Party roster"
	if not button.disabled:
		button.pressed.connect(_begin_trade)
	parent.add_child(button)


func _content_icon(resource_type: String, resource_id: int, media: ClassicMediaCatalog, side: float = 52.0) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(side, side)
	var asset: MediaAsset = media.asset_by_resource(resource_type, resource_id) if media != null and resource_id != 0 else null
	if asset != null:
		var bytes := media.read_bytes(asset)
		var image := Image.new()
		var error := ERR_UNAVAILABLE
		match asset.path.get_extension().to_lower():
			"png": error = image.load_png_from_buffer(bytes)
			"jpg", "jpeg": error = image.load_jpg_from_buffer(bytes)
			"webp": error = image.load_webp_from_buffer(bytes)
		if error == OK:
			var texture := TextureRect.new()
			texture.texture = ImageTexture.create_from_image(image)
			texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			texture.tooltip_text = asset.label
			frame.add_child(texture)
			return frame
	var fallback := Label.new()
	fallback.text = "◈\n%d" % resource_id if resource_id != 0 else "◈"
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_theme_color_override("font_color", MUTED)
	frame.add_child(fallback)
	return frame


func _appearance_texture(asset_id: String, media: ClassicMediaCatalog) -> Texture2D:
	if media == null or asset_id.is_empty():
		return null
	return media.image_texture(media.asset_by_id(asset_id))


func _portrait_icon(asset_id: String, media: ClassicMediaCatalog) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(36.0, 36.0)
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
	var button: BaseButton
	if ClassicUiAssetCatalog.definition(asset_id).is_empty():
		var text_button := Button.new()
		text_button.text = label
		text_button.custom_minimum_size = Vector2(64.0, 56.0)
		button = text_button
	else:
		button = _bitmap_button(asset_id, label)
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if not availability.enabled else label
	if not button.disabled:
		if button is ClassicBitmapButton:
			(button as ClassicBitmapButton).command_requested.connect(func(_command_id: StringName) -> void: _begin_item_action(StringName(label.to_snake_case()), label, intent, item, character))
		else:
			button.pressed.connect(func() -> void: _begin_item_action(StringName(label.to_snake_case()), label, intent, item, character))
	parent.add_child(button)
	return button


func _bitmap_button(asset_id: StringName, label: String) -> ClassicBitmapButton:
	var button := ClassicBitmapButton.new()
	button.configure({"id": asset_id, "asset_id": asset_id, "tooltip": label, "accelerator": ""}, 1)
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
