class_name ShopInteraction
extends InteractionComponent

const GOLD := Color("e5c45c")
const CYAN := Color("8fcfd1")
const MUTED := Color("aeb6ba")
const CONTENT_ICON_SCRIPT := preload("res://src/presentation/classic_content_icon.gd")

var _compact := false
var _media: ClassicMediaCatalog
var _body: InteractionRequest.ShopRequestBody
var _characters: Array[InteractionRequestValue.ServiceCharacter] = []
var _stock: Array[InteractionRequestValue.ShopStock] = []
var _selected_character_id: String
var _selected_stock: InteractionRequestValue.ShopStock
var _selected_item: InteractionRequestValue.InventoryItem
var _shopper_picker: OptionButton
var _inventory_rows: VBoxContainer
var _inspector_facts: VBoxContainer
var _buy_button: Button
var _sell_button: Button
var _identify_button: Button
var _stock_group := ButtonGroup.new()
var _inventory_group := ButtonGroup.new()


func configure(media: ClassicMediaCatalog, compact: bool) -> void:
	_media = media
	_compact = compact


func build(request: InteractionRequest) -> void:
	_body = request.body as InteractionRequest.ShopRequestBody
	if _body == null:
		add_hint("The shop request is malformed.")
		return
	_characters = _body.characters.duplicate()
	_stock = _body.stock.duplicate()
	if not _characters.is_empty():
		_selected_character_id = _characters[0].id
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 500.0)
	add_theme_constant_override("separation", 6)
	_build_header()
	_build_workspace()
	_build_footer()
	if not _stock.is_empty():
		_select_stock(_stock[0].stock_key)
	elif not _characters.is_empty() and not _characters[0].inventory.is_empty():
		_select_item(_characters[0].id, _characters[0].inventory[0].instance_id)
	else:
		_refresh_inventory()
		_refresh_inspector()


func _build_header() -> void:
	var row := HBoxContainer.new()
	row.name = "ShopHeader"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)
	var title := _label("Shop", GOLD)
	title.theme_type_variation = &"ClassicHeading"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var facts := _label("%d gold  •  prices %d%%" % [_body.party_gold, _body.inflation_percent], CYAN)
	facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(facts)


func _build_workspace() -> void:
	var columns := HBoxContainer.new()
	columns.name = "ShopColumns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 6)
	add_child(columns)
	if _compact:
		_build_compact_browser(columns)
	else:
		_build_stock_pane(columns)
		_build_pack_pane(columns)
	_build_inspector_pane(columns)


func _build_compact_browser(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "ShopCompactBrowser"
	panel.theme_type_variation = &"ClassicTextWell"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.15
	parent.add_child(panel)
	var tabs := TabContainer.new()
	tabs.name = "ShopBrowserTabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(tabs)
	var stock := VBoxContainer.new()
	stock.name = "Stock"
	stock.add_theme_constant_override("separation", 4)
	tabs.add_child(stock)
	_build_stock_content(stock)
	var pack := VBoxContainer.new()
	pack.name = "Pack"
	pack.add_theme_constant_override("separation", 4)
	tabs.add_child(pack)
	_build_pack_content(pack)


func _build_stock_pane(parent: HBoxContainer) -> void:
	_build_stock_content(_pane(parent, "ShopStockColumn", "Shop Stock", 1.05))


func _build_stock_content(content: VBoxContainer) -> void:
	var scroll := _scroll("ShopStockScroll")
	content.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "ShopStockRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 3)
	scroll.add_child(rows)
	if _stock.is_empty():
		rows.add_child(_label("No stock is available.", MUTED))
		return
	var first_button: Button
	for entry: InteractionRequestValue.ShopStock in _stock:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var icon := CONTENT_ICON_SCRIPT.new() as Control
		icon.name = "StockIcon_%s" % entry.stock_key.replace(":", "_").replace(".", "_")
		icon.configure(entry.icon_resource_type, entry.icon_id, _media, 46.0, entry.name)
		row.add_child(icon)
		var button := Button.new()
		button.name = "Stock_%s" % entry.stock_key.replace(":", "_").replace(".", "_")
		button.text = "%s\n%d gold  •  %d left" % [entry.name, entry.buy_price, entry.quantity]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.custom_minimum_size.y = 46.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = _stock_group
		button.pressed.connect(_select_stock.bind(entry.stock_key))
		row.add_child(button)
		rows.add_child(row)
		if first_button == null:
			first_button = button
	first_button.set_pressed_no_signal(true)


func _build_pack_pane(parent: HBoxContainer) -> void:
	_build_pack_content(_pane(parent, "SelectedInventoryColumn", "Adventurer Pack", 1.0))


func _build_pack_content(content: VBoxContainer) -> void:
	_shopper_picker = character_option(_characters)
	_shopper_picker.name = "ShopperPicker"
	_shopper_picker.item_selected.connect(_select_shopper_index)
	content.add_child(_shopper_picker)
	var scroll := _scroll("InventoryScroll")
	content.add_child(scroll)
	_inventory_rows = VBoxContainer.new()
	_inventory_rows.name = "InventoryRows"
	_inventory_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_rows.add_theme_constant_override("separation", 3)
	scroll.add_child(_inventory_rows)
	_refresh_inventory()


func _build_inspector_pane(parent: HBoxContainer) -> void:
	var content := _pane(parent, "ItemInspectorRail", "Selected Item", 1.05)
	_inspector_facts = VBoxContainer.new()
	_inspector_facts.name = "InspectorFacts"
	_inspector_facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_facts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector_facts.add_theme_constant_override("separation", 4)
	content.add_child(_inspector_facts)


func _build_footer() -> void:
	var footer := HBoxContainer.new()
	footer.name = "ShopFooter"
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 5)
	add_child(footer)
	_buy_button = _action_button("ShopBuy", "Buy", _submit_buy)
	_sell_button = _action_button("ShopSellSelected", "Sell", _submit_sell)
	_identify_button = _action_button("ShopIdentify", "Identify", _submit_identify)
	footer.add_child(_buy_button)
	footer.add_child(_sell_button)
	footer.add_child(_identify_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var leave := _action_button("ShopLeave", "Leave Shop", _submit_leave)
	leave.custom_minimum_size.x = 150.0
	footer.add_child(leave)


func _select_shopper_index(_index: int) -> void:
	_select_character(String(_shopper_picker.get_selected_metadata()))


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
	var character := _character_by_id(_selected_character_id)
	if character == null:
		_inventory_rows.add_child(_label("No adventurer is selected.", MUTED))
		return
	for item: InteractionRequestValue.InventoryItem in character.inventory:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var icon := CONTENT_ICON_SCRIPT.new() as Control
		icon.name = "InventoryIcon_%s" % item.instance_id.replace(".", "_")
		icon.configure(item.icon_resource_type, item.icon_id, _media, 46.0, item.name)
		row.add_child(icon)
		var button := Button.new()
		button.name = "Inventory_%s" % item.instance_id.replace(".", "_")
		button.text = "%s\n%s  •  sell %d gold" % [item.name, "Equipped" if item.equipped else "Carried", item.sell_price]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.custom_minimum_size.y = 46.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = _inventory_group
		button.pressed.connect(_select_item.bind(character.id, item.instance_id))
		row.add_child(button)
		_inventory_rows.add_child(row)
	if character.inventory.is_empty():
		_inventory_rows.add_child(_label("%s carries no items." % character.name, MUTED))


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
		_add_inspector_record(_selected_stock.name, ["Buy for %d gold" % _selected_stock.buy_price, "%d remaining" % _selected_stock.quantity], _selected_stock.can_buy, _selected_stock.buy_reason, _selected_stock.icon_resource_type, _selected_stock.icon_id)
	elif _selected_item != null:
		var state := "Equipped" if _selected_item.equipped else "Carried"
		var knowledge := "Identified" if _selected_item.identified else "Unidentified"
		_add_inspector_record(_selected_item.name, ["%s  •  %s" % [state, knowledge], "Sell for %d gold" % _selected_item.sell_price, "Identify for %d gold" % _body.identify_price], _selected_item.can_sell or _selected_item.can_identify, _selected_item.sell_reason if not _selected_item.can_sell else _selected_item.identify_reason, _selected_item.icon_resource_type, _selected_item.icon_id)
	else:
		_inspector_facts.add_child(_label("Choose stock to buy or an item from the selected adventurer's pack.", MUTED))


func _add_inspector_record(title: String, facts: Array[String], available: bool, reason: String, resource_type: String, resource_id: int) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var icon := CONTENT_ICON_SCRIPT.new() as Control
	icon.name = "ShopSelectedItemIcon"
	icon.configure(resource_type, resource_id, _media, 58.0, title)
	header.add_child(icon)
	var record := VBoxContainer.new()
	record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record.add_child(_label(title, GOLD))
	for fact: String in facts:
		record.add_child(_label(fact, CYAN))
	header.add_child(record)
	_inspector_facts.add_child(header)
	if not available and not reason.is_empty():
		_inspector_facts.add_child(_label(reason, Color("d48a78")))


func _submit_buy() -> void:
	if _selected_stock != null and not _selected_character_id.is_empty() and _selected_stock.can_buy:
		response_body_submitted.emit(InteractionResponse.ShopBody.new(&"buy", _selected_character_id, "", _selected_stock.stock_key))


func _submit_sell() -> void:
	if _selected_item != null and _selected_item.can_sell:
		response_body_submitted.emit(InteractionResponse.ShopBody.new(&"sell", _selected_character_id, _selected_item.instance_id))


func _submit_identify() -> void:
	if _selected_item != null and _selected_item.can_identify:
		response_body_submitted.emit(InteractionResponse.ShopBody.new(&"identify", _selected_character_id, _selected_item.instance_id))


func _submit_leave() -> void:
	response_body_submitted.emit(InteractionResponse.ShopBody.new(&"leave"))


func _character_by_id(character_id: String) -> InteractionRequestValue.ServiceCharacter:
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		if character.id == character_id:
			return character
	return null


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


func _action_button(button_name: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.custom_minimum_size = Vector2(112.0, 38.0)
	button.pressed.connect(callback)
	return button
