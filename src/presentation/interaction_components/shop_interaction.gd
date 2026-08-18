class_name ShopInteraction
extends InteractionComponent

var _body: InteractionRequest.ShopRequestBody
var _characters: Array[InteractionRequestValue.ServiceCharacter] = []
var _stock: Array[InteractionRequestValue.ShopStock] = []
var _selected_character_id: String
var _selected_stock: InteractionRequestValue.ShopStock
var _selected_item: InteractionRequestValue.InventoryItem

var _inventory_rows: VBoxContainer
var _selected_character_label: Label
var _inspector_facts: VBoxContainer
var _buy_button: Button
var _sell_button: Button
var _identify_button: Button
var _shopper_group := ButtonGroup.new()
var _stock_group := ButtonGroup.new()
var _inventory_group := ButtonGroup.new()


func build(request: InteractionRequest) -> void:
	_body = request.body as InteractionRequest.ShopRequestBody
	if _body == null:
		return
	_characters = _body.characters.duplicate()
	_stock = _body.stock.duplicate()
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 500.0)
	add_theme_constant_override("separation", 6)
	add_hint("Party gold: %d • Shop rate: %d%%" % [_body.party_gold, _body.inflation_percent])
	_build_shopper_strip()
	_build_shop_columns()
	if not _stock.is_empty():
		_select_stock(_stock[0].stock_key)
	elif not _characters.is_empty() and not _characters[0].inventory.is_empty():
		_select_character(_characters[0].id)
		_select_item(_characters[0].id, _characters[0].inventory[0].instance_id)
	else:
		_refresh_inspector()


func _build_shopper_strip() -> void:
	var panel := _panel("ShopperStrip")
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var content := VBoxContainer.new()
	content.add_child(_heading("Shoppers"))
	var row := HBoxContainer.new()
	row.name = "ShopperButtons"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)
	content.add_child(row)
	panel.add_child(content)
	add_child(panel)
	if _characters.is_empty():
		row.add_child(_empty_label("No party characters were supplied."))
		return
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		var button := Button.new()
		button.name = "Shopper_%s" % character.id.replace(".", "_")
		button.text = character.name
		button.clip_text = true
		button.tooltip_text = ""
		button.custom_minimum_size = Vector2(72.0, 32.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_ALL
		button.toggle_mode = true
		button.button_group = _shopper_group
		button.pressed.connect(_select_character.bind(character.id))
		row.add_child(button)
	if row.get_child_count() > 0:
		(row.get_child(0) as Button).set_pressed_no_signal(true)
		_selected_character_id = _characters[0].id


func _build_shop_columns() -> void:
	var columns := HBoxContainer.new()
	columns.name = "ShopColumns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.custom_minimum_size.y = 300.0
	columns.add_theme_constant_override("separation", 6)
	add_child(columns)
	_build_stock_column(columns)
	_build_inventory_column(columns)
	_build_inspector_rail(columns)


func _build_stock_column(parent: Container) -> void:
	var panel := _panel("ShopStockColumn")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	var content := VBoxContainer.new()
	content.add_child(_heading("Shop stock"))
	var scroll := _scroll("ShopStockScroll")
	var rows := VBoxContainer.new()
	rows.name = "ShopStockRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	content.add_child(scroll)
	panel.add_child(content)
	parent.add_child(panel)
	if _stock.is_empty():
		rows.add_child(_empty_label("No stock was supplied."))
		return
	for entry: InteractionRequestValue.ShopStock in _stock:
		var button := Button.new()
		button.name = "Stock_%s" % entry.stock_key.replace(":", "_").replace(".", "_")
		button.text = "%s • %d gold • %d left" % [entry.name, entry.buy_price, entry.quantity]
		button.clip_text = true
		button.tooltip_text = ""
		button.custom_minimum_size.y = 32.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_ALL
		button.toggle_mode = true
		button.button_group = _stock_group
		button.pressed.connect(_select_stock.bind(entry.stock_key))
		rows.add_child(button)
	(rows.get_child(0) as Button).set_pressed_no_signal(true)


func _build_inventory_column(parent: Container) -> void:
	var panel := _panel("SelectedInventoryColumn")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	var content := VBoxContainer.new()
	content.add_child(_heading("Selected character pack"))
	_selected_character_label = _empty_label("")
	_selected_character_label.name = "SelectedCharacter"
	content.add_child(_selected_character_label)
	var scroll := _scroll("InventoryScroll")
	_inventory_rows = VBoxContainer.new()
	_inventory_rows.name = "InventoryRows"
	_inventory_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_inventory_rows)
	content.add_child(scroll)
	panel.add_child(content)
	parent.add_child(panel)
	_refresh_inventory()


func _build_inspector_rail(parent: Container) -> void:
	var panel := _panel("ItemInspectorRail")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.85
	var content := VBoxContainer.new()
	content.add_child(_heading("Item inspector"))
	_inspector_facts = VBoxContainer.new()
	_inspector_facts.name = "InspectorFacts"
	_inspector_facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_facts.add_theme_constant_override("separation", 2)
	content.add_child(_inspector_facts)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	_buy_button = _action_button("ShopBuy", "Buy", _submit_buy)
	_sell_button = _action_button("ShopSellSelected", "Sell selected", _submit_sell)
	_identify_button = _action_button("ShopIdentify", "Identify", _submit_identify)
	content.add_child(_buy_button)
	content.add_child(_sell_button)
	content.add_child(_identify_button)
	var separator := HSeparator.new()
	separator.name = "InspectorActionSeparator"
	content.add_child(separator)
	var leave := _action_button("ShopLeave", "Leave shop", _submit_leave)
	content.add_child(leave)
	panel.add_child(content)
	parent.add_child(panel)


func _select_character(character_id: String) -> void:
	_selected_character_id = character_id
	_selected_stock = null
	_selected_item = null
	_refresh_inventory()
	_refresh_inspector()


func _select_stock(stock_key: String) -> void:
	_selected_stock = null
	_selected_item = null
	for entry: InteractionRequestValue.ShopStock in _stock:
		if entry.stock_key == stock_key:
			_selected_stock = entry
			break
	_refresh_inspector()


func _select_item(character_id: String, instance_id: String) -> void:
	_selected_stock = null
	_selected_item = null
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		if character.id != character_id:
			continue
		for item: InteractionRequestValue.InventoryItem in character.inventory:
			if item.instance_id == instance_id:
				_selected_item = item
				_selected_character_id = character.id
				break
		break
	_refresh_inspector()


func _refresh_inventory() -> void:
	if _inventory_rows == null:
		return
	for child: Node in _inventory_rows.get_children():
		_inventory_rows.remove_child(child)
		child.free()
	_selected_character_label.text = ""
	var character := _character_by_id(_selected_character_id)
	if character == null:
		_inventory_rows.add_child(_empty_label("No selected character."))
		return
	_selected_character_label.text = character.name
	if character.inventory.is_empty():
		_inventory_rows.add_child(_empty_label("No carried items were supplied."))
		return
	for item: InteractionRequestValue.InventoryItem in character.inventory:
		var button := Button.new()
		button.name = "Inventory_%s" % item.instance_id.replace(".", "_")
		button.text = "%s • sell %d gold" % [item.name, item.sell_price]
		button.clip_text = true
		button.tooltip_text = ""
		button.custom_minimum_size.y = 32.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_ALL
		button.toggle_mode = true
		button.button_group = _inventory_group
		button.pressed.connect(_select_item.bind(character.id, item.instance_id))
		_inventory_rows.add_child(button)


func _refresh_inspector() -> void:
	if _inspector_facts == null:
		return
	for child: Node in _inspector_facts.get_children():
		_inspector_facts.remove_child(child)
		child.free()
	_buy_button.disabled = _selected_stock == null or _selected_character_id.is_empty() or not _selected_stock.can_buy
	_sell_button.disabled = _selected_item == null or not _selected_item.can_sell
	_identify_button.disabled = _selected_item == null or not _selected_item.can_identify
	_buy_button.tooltip_text = "Select shop stock." if _selected_stock == null else "No shopper is available." if _selected_character_id.is_empty() else _selected_stock.buy_reason if not _selected_stock.can_buy else ""
	_sell_button.tooltip_text = "Select a carried item." if _selected_item == null else _selected_item.sell_reason if not _selected_item.can_sell else ""
	_identify_button.tooltip_text = "Select a carried item." if _selected_item == null else _selected_item.identify_reason if not _selected_item.can_identify else ""
	if _selected_stock != null:
		_add_fact("Item: %s" % _selected_stock.name)
		_add_fact("Price: %d gold" % _selected_stock.buy_price)
		_add_fact("Quantity: %d" % _selected_stock.quantity)
		_add_availability("Buy", _selected_stock.can_buy, _selected_stock.buy_reason)
		return
	if _selected_item != null:
		_add_fact("Item: %s" % _selected_item.name)
		_add_fact("Sell price: %d gold" % _selected_item.sell_price)
		_add_fact("Identify price: %d gold" % _body.identify_price)
		_add_availability("Sell", _selected_item.can_sell, _selected_item.sell_reason)
		_add_availability("Identify", _selected_item.can_identify, _selected_item.identify_reason)
		return
	_inspector_facts.add_child(_empty_label("Select stock or a carried item."))


func _submit_buy() -> void:
	if _selected_stock == null or _selected_character_id.is_empty() or not _selected_stock.can_buy:
		return
	response_body_submitted.emit(InteractionResponse.ShopBody.new(&"buy", _selected_character_id, "", _selected_stock.stock_key))


func _submit_sell() -> void:
	if _selected_item == null or not _selected_item.can_sell:
		return
	response_body_submitted.emit(InteractionResponse.ShopBody.new(&"sell", _selected_character_id, _selected_item.instance_id))


func _submit_identify() -> void:
	if _selected_item == null or not _selected_item.can_identify:
		return
	response_body_submitted.emit(InteractionResponse.ShopBody.new(&"identify", _selected_character_id, _selected_item.instance_id))


func _submit_leave() -> void:
	response_body_submitted.emit(InteractionResponse.ShopBody.new(&"leave"))


func _character_by_id(character_id: String) -> InteractionRequestValue.ServiceCharacter:
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		if character.id == character_id:
			return character
	return null


func _panel(panel_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.theme_type_variation = &"ClassicTextWell"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return panel


func _scroll(scroll_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = scroll_name
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size.y = 206.0
	return scroll


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"ClassicHeading"
	label.add_theme_font_size_override("font_size", 15)
	return label


func _empty_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _add_fact(text: String) -> void:
	_inspector_facts.add_child(_empty_label(text))


func _add_availability(action: String, enabled: bool, reason: String) -> void:
	if enabled:
		_add_fact("%s: available" % action)
	else:
		_add_fact("%s unavailable: %s" % [action, reason])


func _action_button(button_name: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.custom_minimum_size.y = 34.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(callback)
	return button
