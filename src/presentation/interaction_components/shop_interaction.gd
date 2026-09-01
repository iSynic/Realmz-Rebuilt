class_name ShopInteraction
extends InteractionComponent

const GOLD := Color("e5c45c")
const CYAN := Color("8fcfd1")
const MUTED := Color("aeb6ba")
const CONTENT_ICON_SCRIPT := preload("res://src/presentation/classic_content_icon.gd")
const EXCHANGE_ITEM_BUTTON_SCRIPT := preload("res://src/presentation/interaction_components/classic_exchange_item_button.gd")
const EXCHANGE_LEDGER_SCRIPT := preload("res://src/presentation/interaction_components/classic_exchange_ledger.gd")
const ITEM_DETAIL_POPOVER_SCRIPT := preload("res://src/presentation/classic_item_detail_popover.gd")
const CLASSIC_VISIBLE_ROWS := 9
const COMPACT_VISIBLE_ROWS := 5
const WIDE_LEDGER_ROW_HEIGHT := 34.0
const COMPACT_LEDGER_ROW_HEIGHT := 30.0
const LEDGER_ROW_SEPARATION := 2.0
const CLASSIC_CONTROL_STRIP_HEIGHT := 68.0
const CLASSIC_DETAIL_STRIP_HEIGHT := 82.0
const FILTER_RAIL_WIDTH := 68.0
const FILTER_BUTTON_SIZE := Vector2(62.0, 58.0)
const ROUTE_BUTTON_SIZE := Vector2(54.0, 54.0)
const COMPACT_ROUTE_BUTTON_SIZE := Vector2(46.0, 46.0)
const FOOTER_PORTRAIT_SIZE := Vector2(18.0, 18.0)
const COMPACT_FOOTER_PORTRAIT_SIZE := Vector2(16.0, 16.0)
const COMPACT_PORTRAIT_SIZE := Vector2(36.0, 36.0)
const STOCK_FILTERS: Array[Dictionary] = [
	{"id": &"weapons", "asset": &"inventory.category.weapons", "label": "Weapons", "region": [0, 0, 50, 34]},
	{"id": &"armor", "asset": &"inventory.category.armor", "label": "Armor", "region": [0, 0, 50, 34]},
	{"id": &"limb_armor", "asset": &"inventory.category.limb_armor", "label": "Armor", "tooltip": "Limb Armor", "region": [0, 0, 50, 34]},
	{"id": &"magic", "asset": &"inventory.category.magic", "label": "Magic", "region": [0, 0, 50, 34]},
	{"id": &"supplies", "asset": &"inventory.category.supplies", "label": "Supplies", "region": [0, 0, 50, 34]},
]

var _compact := false
var _media: ClassicMediaCatalog
var _body: InteractionRequest.ShopRequestBody
var _characters: Array[InteractionRequestValue.ServiceCharacter] = []
var _stock: Array[InteractionRequestValue.ShopStock] = []
var _selected_character_id: String
var _right_character_id: String
var _selected_item_owner_id: String
var _selected_stock: InteractionRequestValue.ShopStock
var _selected_item: InteractionRequestValue.InventoryItem
var _selected_category: StringName = &"weapons"
var _stock_rows: VBoxContainer
var _inventory_rows: VBoxContainer
var _stock_heading: Label
var _selection_summary: Label
var _left_load: Label
var _right_load: Label
var _shopper_name: Label
var _transaction_facts: Label
var _item_description: Label
var _item_stats: Label
var _selected_portrait: TextureRect
var _buy_button: Button
var _sell_button: Button
var _identify_button: Button
var _stock_group := ButtonGroup.new()
var _inventory_group := ButtonGroup.new()
var _category_group := ButtonGroup.new()
var _category_buttons: Dictionary = {}
var _shopper_buttons: Dictionary = {}
var _detail_popover: CanvasLayer


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
	custom_minimum_size = Vector2.ZERO
	add_theme_constant_override("separation", 6)
	_detail_popover = ITEM_DETAIL_POPOVER_SCRIPT.new()
	add_child(_detail_popover)
	_detail_popover.configure(_media, get_theme())
	_build_header()
	_build_workspace()
	_build_footer()
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
		columns.name = "ShopExchangeLedgers"
		_build_pack_pane(columns)
		_build_control_spine(columns)
		_build_stock_pane(columns)


func _build_compact_browser(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "ShopCompactBrowser"
	panel.theme_type_variation = &"ClassicItemLedger"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.15
	parent.add_child(panel)
	var tabs := TabContainer.new()
	tabs.name = "ShopBrowserTabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(tabs)
	var pack := VBoxContainer.new()
	pack.name = "Pack"
	pack.add_theme_constant_override("separation", 4)
	tabs.add_child(pack)
	_build_pack_content(pack, true)
	var stock := VBoxContainer.new()
	stock.name = "Stock"
	stock.add_theme_constant_override("separation", 4)
	tabs.add_child(stock)
	_build_stock_content(stock, true)


func _build_stock_pane(parent: HBoxContainer) -> void:
	var content := _exchange_pane(parent, "ShopStockColumn", "Shop Stock", &"shop-inventory-item", "shop")
	_stock_heading = content.get_child(0) as Label
	_stock_heading.name = "ShopStockHeading"
	content.get_parent().connect("item_dropped", _drop_on_shop)
	_build_stock_content(content, false)


func _build_stock_content(content: VBoxContainer, include_controls: bool) -> void:
	if include_controls:
		_build_category_filters(content)
	var scroll := _scroll("ShopStockScroll")
	content.add_child(scroll)
	_stock_rows = VBoxContainer.new()
	_stock_rows.name = "ShopStockRows"
	_stock_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stock_rows.add_theme_constant_override("separation", int(LEDGER_ROW_SEPARATION))
	scroll.add_child(_stock_rows)
	_refresh_stock()


func _refresh_stock() -> void:
	if _stock_rows == null:
		return
	for child: Node in _stock_rows.get_children():
		_stock_rows.remove_child(child)
		child.free()
	var right_character := _character_by_id(_right_character_id)
	if _stock_heading != null:
		_stock_heading.text = "Shop Stock" if right_character == null else "%s's Pack" % right_character.name
	if right_character != null:
		for item: InteractionRequestValue.InventoryItem in right_character.inventory:
			_stock_rows.add_child(_inventory_row(right_character, item, "RightInventory"))
		if right_character.inventory.is_empty(): _stock_rows.add_child(_label("%s carries no items." % right_character.name, MUTED))
		return
	var visible := _visible_stock()
	if visible.is_empty():
		_stock_rows.add_child(_label("No stock is available in this category.", MUTED))
		return
	for entry: InteractionRequestValue.ShopStock in visible:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var icon := CONTENT_ICON_SCRIPT.new() as Control
		icon.name = "StockIcon_%s" % entry.stock_key.replace(":", "_").replace(".", "_")
		icon.configure(entry.icon_resource_type, entry.icon_id, _media, _ledger_row_height(), entry.name)
		row.add_child(icon)
		var button := EXCHANGE_ITEM_BUTTON_SCRIPT.new()
		button.name = "Stock_%s" % entry.stock_key.replace(":", "_").replace(".", "_")
		button.text = "%s\n%d gold  •  %d left" % [entry.name, entry.buy_price, entry.quantity]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.custom_minimum_size.y = _ledger_row_height()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = &"ClassicItemLedgerButton"
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.button_group = _stock_group
		button.button_pressed = _selected_stock != null and _selected_stock.stock_key == entry.stock_key
		button.pressed.connect(_select_stock.bind(entry.stock_key))
		button.configure_drag({"kind": &"shop-stock-item", "sourceId": "shop", "stockKey": entry.stock_key})
		row.add_child(button)
		_detail_popover.bind_hover(icon, _stock_detail(entry))
		_detail_popover.bind_hover(button, _stock_detail(entry))
		_stock_rows.add_child(row)


func _build_pack_pane(parent: HBoxContainer) -> void:
	var content := _exchange_pane(parent, "SelectedInventoryColumn", "Adventurer Pack", &"shop-stock-item", _selected_character_id)
	content.get_parent().connect("item_dropped", _drop_on_character)
	_build_pack_content(content, false)


func _build_pack_content(content: VBoxContainer, include_controls: bool) -> void:
	if include_controls:
		content.add_child(_build_shopper_selector())
	var scroll := _scroll("InventoryScroll")
	content.add_child(scroll)
	_inventory_rows = VBoxContainer.new()
	_inventory_rows.name = "InventoryRows"
	_inventory_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_rows.add_theme_constant_override("separation", int(LEDGER_ROW_SEPARATION))
	scroll.add_child(_inventory_rows)
	_refresh_inventory()


func _build_footer() -> void:
	var lower := VBoxContainer.new()
	lower.name = "ShopLowerWorkspace"
	lower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.size_flags_vertical = Control.SIZE_SHRINK_END
	lower.add_theme_constant_override("separation", 4)
	add_child(lower)
	var control_panel := PanelContainer.new()
	control_panel.name = "ShopControlStrip"
	control_panel.theme_type_variation = &"ClassicInset"
	control_panel.custom_minimum_size.y = CLASSIC_CONTROL_STRIP_HEIGHT
	lower.add_child(control_panel)
	var footer := HBoxContainer.new()
	footer.name = "ShopControls"
	footer.add_theme_constant_override("separation", 3)
	control_panel.add_child(footer)
	var left_controls := HBoxContainer.new()
	left_controls.name = "ShopLeftControls"
	left_controls.alignment = BoxContainer.ALIGNMENT_END
	left_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_controls.size_flags_stretch_ratio = 1.0
	left_controls.add_theme_constant_override("separation", 3)
	footer.add_child(left_controls)
	var left_load_group := _footer_group(left_controls, "ShopLeftLoadPanel", 66.0 if _compact else 86.0)
	_left_load = _compact_fact("ShopLeftLoad", 62.0 if _compact else 78.0)
	left_load_group.add_child(_left_load)
	var shopper_group := _footer_group(left_controls, "ShopSelectedShopperPanel", 64.0 if _compact else 84.0)
	var shopper := VBoxContainer.new()
	shopper.name = "ShopSelectedShopper"
	shopper.custom_minimum_size.x = 56.0 if _compact else 76.0
	shopper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shopper_group.add_child(shopper)
	_selected_portrait = TextureRect.new()
	_selected_portrait.name = "ShopSelectedPortrait"
	_selected_portrait.custom_minimum_size = Vector2(40.0, 38.0)
	_selected_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_selected_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shopper.add_child(_selected_portrait)
	_shopper_name = _label("", GOLD)
	_shopper_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shopper.add_child(_shopper_name)
	var transaction_group := _footer_group(left_controls, "ShopTransactionContainer", 150.0 if _compact else 174.0)
	var transaction := VBoxContainer.new()
	transaction.name = "ShopTransactionPanel"
	transaction.custom_minimum_size.x = 142.0 if _compact else 166.0
	transaction.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	transaction_group.add_child(transaction)
	_transaction_facts = _compact_fact("ShopTransactionFacts")
	transaction.add_child(_transaction_facts)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 3)
	transaction.add_child(actions)
	_buy_button = _action_button("ShopBuy", "Buy", _submit_buy)
	_sell_button = _action_button("ShopSellSelected", "Sell", _submit_sell)
	_identify_button = _action_button("ShopIdentify", "Identify", _submit_identify)
	for button: Button in [_buy_button, _sell_button, _identify_button]: button.custom_minimum_size = Vector2(44.0, 22.0) if _compact else Vector2(52.0, 24.0); button.size_flags_vertical = Control.SIZE_SHRINK_CENTER; actions.add_child(button)
	footer.add_child(_build_shopper_selector(true))
	var right_controls := HBoxContainer.new()
	right_controls.name = "ShopRightControls"
	right_controls.alignment = BoxContainer.ALIGNMENT_BEGIN
	right_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_controls.size_flags_stretch_ratio = 1.0
	right_controls.add_theme_constant_override("separation", 3)
	footer.add_child(right_controls)
	var route_group := _footer_group(right_controls, "ShopRouteControls", 210.0 if _compact else 257.0)
	var restore := _route_button("ShopKeeperRestore", "Shop Keeper", &"command.shop_original", _restore_shopkeeper, {"asset_path": "res://src/presentation/assets/ui/commands/shop.png"})
	route_group.add_child(restore)
	for spec: Array in [["ShopItems", "Items", &"command.inventory", _show_items, [5, 2, 36, 34], [[0, 4, 4, 8]]], ["ShopMoney", "Money", &"command.money", _show_money, [5, 5, 35, 31], [[0, 0, 8, 8]]]]:
		route_group.add_child(_route_button(spec[0], spec[1], spec[2], spec[3], {"art_region": spec[4], "art_clear_regions": spec[5]}))
	var done := _action_button("ShopDone", "Done", _submit_leave)
	done.custom_minimum_size = _route_button_size()
	done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	route_group.add_child(done)
	var right_load_group := _footer_group(right_controls, "ShopRightLoadPanel", 66.0 if _compact else 86.0)
	_right_load = _compact_fact("ShopRightLoad", 62.0 if _compact else 78.0)
	right_load_group.add_child(_right_load)
	var detail := HBoxContainer.new()
	detail.name = "ShopDetailStrip"
	detail.custom_minimum_size.y = CLASSIC_DETAIL_STRIP_HEIGHT
	detail.add_theme_constant_override("separation", 4)
	lower.add_child(detail)
	var description := _pane(detail, "ShopItemDescriptionPane", "Item Description", 1.0)
	_item_description = _label("Choose an item to inspect.", MUTED)
	_item_description.name = "ShopItemDescription"
	description.add_child(_item_description)
	var stats := _pane(detail, "ShopItemStatsPane", "Item Statistics", 1.0)
	_item_stats = _label("", CYAN)
	_item_stats.name = "ShopItemStats"
	stats.add_child(_item_stats)
	_selection_summary = _item_description


func _route_button(node_name: String, caption: String, asset_id: StringName, callback: Callable, art_options: Dictionary = {}) -> ClassicBitmapButton:
	var button := ClassicBitmapButton.new()
	button.name = node_name
	var definition := {"id": StringName(node_name), "asset_id": asset_id, "tooltip": caption, "label": ""}
	definition.merge(art_options, true)
	button.configure(definition, 1)
	button.custom_minimum_size = _route_button_size()
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.command_requested.connect(func(_command_id: StringName) -> void: callback.call())
	return button


func _footer_group(parent: HBoxContainer, group_name: String, minimum_width: float) -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.name = group_name
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = minimum_width
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var content := HBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 2)
	panel.add_child(content)
	return content


func _select_character(character_id: String) -> void:
	_selected_character_id = character_id
	_selected_stock = null
	_selected_item = null
	_selected_item_owner_id = ""
	_update_shopper_buttons()
	_refresh_inventory()
	_refresh_inspector()


func _select_right_character(character_id: String) -> void:
	_right_character_id = character_id
	_selected_stock = null
	_selected_item = null
	_selected_item_owner_id = ""
	_update_shopper_buttons()
	_refresh_stock()
	_refresh_inspector()


func _restore_shopkeeper() -> void:
	_right_character_id = ""
	_selected_stock = null
	_selected_item = null
	_selected_item_owner_id = ""
	_update_shopper_buttons()
	_refresh_stock()
	_refresh_inspector()


func _select_stock(stock_key: String) -> void:
	_selected_stock = null
	_selected_item = null
	for entry: InteractionRequestValue.ShopStock in _stock:
		if entry.stock_key == stock_key:
			_selected_stock = entry
			break
	_refresh_inspector()


func _select_category(category: StringName) -> void:
	_selected_category = category
	_right_character_id = ""
	_selected_stock = null
	_selected_item = null
	_selected_item_owner_id = ""
	for id: Variant in _category_buttons:
		(_category_buttons[id] as BaseButton).set_pressed_no_signal(StringName(id) == category)
	_refresh_stock()
	_update_shopper_buttons()
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
				_selected_item_owner_id = character.id
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
		_inventory_rows.add_child(_inventory_row(character, item, "Inventory"))
	if character.inventory.is_empty():
		_inventory_rows.add_child(_label("%s carries no items." % character.name, MUTED))


func _refresh_inspector() -> void:
	if _selection_summary == null:
		return
	_buy_button.disabled = _selected_stock == null or _selected_character_id.is_empty() or not _selected_stock.can_buy
	_sell_button.disabled = _selected_item == null or _selected_item_owner_id.is_empty() or not _selected_item.can_sell
	_identify_button.disabled = _selected_item == null or _selected_item_owner_id.is_empty() or not _selected_item.can_identify
	_buy_button.tooltip_text = "Select shop stock." if _selected_stock == null else "No shopper is available." if _selected_character_id.is_empty() else _selected_stock.buy_reason if not _selected_stock.can_buy else ""
	_sell_button.tooltip_text = "Select a carried item." if _selected_item == null else _selected_item.sell_reason if not _selected_item.can_sell else ""
	_identify_button.tooltip_text = "Select a carried item." if _selected_item == null else _selected_item.identify_reason if not _selected_item.can_identify else ""
	if _selected_stock != null:
		_selection_summary.text = _selected_stock.description if not _selected_stock.description.is_empty() else _selected_stock.name
		_selection_summary.tooltip_text = _selected_stock.buy_reason
		_transaction_facts.text = "Cost %d  •  Offer —  •  Weight %d" % [_selected_stock.buy_price, _selected_stock.weight]
		_item_stats.text = _facts_text(_selected_stock.facts, "Quantity", str(_selected_stock.quantity))
	elif _selected_item != null:
		var state := "Equipped" if _selected_item.equipped else "Carried"
		var knowledge := "Identified" if _selected_item.identified else "Unidentified"
		_selection_summary.text = _selected_item.description if not _selected_item.description.is_empty() else _selected_item.name
		_selection_summary.tooltip_text = _selected_item.sell_reason if not _selected_item.can_sell else _selected_item.identify_reason if not _selected_item.can_identify else ""
		_transaction_facts.text = "Cost —  •  Offer %d  •  Weight %d" % [_selected_item.sell_price, _selected_item.weight]
		_item_stats.text = _facts_text(_selected_item.facts, "State", "%s / %s" % [state, knowledge])
	else:
		_selection_summary.text = "Choose stock or a carried item."
		_selection_summary.tooltip_text = ""
		_transaction_facts.text = "Cost —  •  Offer —  •  Weight —"
		_item_stats.text = ""
	_refresh_shopper_facts()


func _submit_buy() -> void:
	if _selected_stock != null and not _selected_character_id.is_empty() and _selected_stock.can_buy:
		response_body_submitted.emit(InteractionResponse.ShopBody.new(&"buy", _selected_character_id, "", _selected_stock.stock_key))


func _submit_sell() -> void:
	if _selected_item != null and _selected_item.can_sell:
		response_body_submitted.emit(InteractionResponse.ShopBody.new(&"sell", _selected_item_owner_id, _selected_item.instance_id))


func _submit_identify() -> void:
	if _selected_item != null and _selected_item.can_identify:
		response_body_submitted.emit(InteractionResponse.ShopBody.new(&"identify", _selected_item_owner_id, _selected_item.instance_id))


func _submit_leave() -> void:
	response_body_submitted.emit(InteractionResponse.ShopBody.new(&"leave"))


func _drop_on_character(payload: Dictionary, _character_id: String) -> void:
	if StringName(payload.get("kind", &"")) != &"shop-stock-item":
		return
	_select_character(_selected_character_id)
	_select_stock(String(payload.get("stockKey", "")))
	_submit_buy()


func _drop_on_shop(payload: Dictionary, _target_id: String) -> void:
	if StringName(payload.get("kind", &"")) != &"shop-inventory-item":
		return
	_select_item(String(payload.get("sourceId", "")), String(payload.get("instanceId", "")))
	_submit_sell()


func _character_by_id(character_id: String) -> InteractionRequestValue.ServiceCharacter:
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		if character.id == character_id:
			return character
	return null


func _build_category_filters(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "ShopCategoryFilters"
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	for filter: Dictionary in STOCK_FILTERS:
		var category_id := StringName(filter["id"])
		var definition := ClassicUiAssetCatalog.definition(filter["asset"]).duplicate(true)
		definition["asset_id"] = filter["asset"]
		definition["id"] = StringName("shop.category.%s" % category_id)
		definition["label"] = filter["label"]
		definition["tooltip"] = "Show %s" % filter.get("tooltip", filter["label"])
		definition["group"] = &"shop-category"
		definition["toggle_mode"] = true
		definition["art_region"] = filter["region"]
		var button := ClassicBitmapButton.new()
		button.name = "ShopFilter_%s" % category_id
		button.configure(definition, 1)
		button.custom_minimum_size = FILTER_BUTTON_SIZE
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.button_group = _category_group
		button.button_pressed = category_id == _selected_category
		button.command_requested.connect(func(_command_id: StringName) -> void: _select_category(category_id))
		_category_buttons[category_id] = button
		row.add_child(button)


func _build_control_spine(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "ShopExchangeDivider"
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = FILTER_RAIL_WIDTH
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var spine := VBoxContainer.new()
	spine.name = "ShopControlSpine"
	spine.add_theme_constant_override("separation", 4)
	panel.add_child(spine)
	var filters := VBoxContainer.new()
	filters.name = "ShopCategoryFilters"
	filters.add_theme_constant_override("separation", 2)
	filters.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	spine.add_child(filters)
	for filter: Dictionary in STOCK_FILTERS:
		var category_id := StringName(filter["id"])
		var definition := ClassicUiAssetCatalog.definition(filter["asset"]).duplicate(true)
		definition["asset_id"] = filter["asset"]
		definition["id"] = StringName("shop.category.%s" % category_id)
		definition["label"] = filter["label"]
		definition["tooltip"] = "Show %s" % filter.get("tooltip", filter["label"])
		definition["group"] = &"shop-category"
		definition["toggle_mode"] = true
		definition["art_region"] = filter["region"]
		var button := ClassicBitmapButton.new()
		button.name = "ShopFilter_%s" % category_id
		button.configure(definition, 1)
		button.custom_minimum_size = FILTER_BUTTON_SIZE
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.button_group = _category_group
		button.button_pressed = category_id == _selected_category
		button.command_requested.connect(func(_command_id: StringName) -> void: _select_category(category_id))
		_category_buttons[category_id] = button
		filters.add_child(button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spine.add_child(spacer)


func _build_shopper_selector(duplicate_columns: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "ShopperPortraitSelector"
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if duplicate_columns:
		panel.custom_minimum_size.x = 76.0 if _compact else 96.0
		var pair := HBoxContainer.new()
		pair.name = "ShopPortraitMatrix"
		pair.alignment = BoxContainer.ALIGNMENT_CENTER
		pair.add_theme_constant_override("separation", 2)
		panel.add_child(pair)
		for side: String in ["Buyer", "Seller"]:
			var group := GridContainer.new()
			group.name = "Shop%sPortraits" % side
			group.columns = 2
			group.add_theme_constant_override("h_separation", 1)
			group.add_theme_constant_override("v_separation", 1)
			pair.add_child(group)
			for character: InteractionRequestValue.ServiceCharacter in _characters:
				group.add_child(_shopper_portrait(character, side))
		return panel
	var row := GridContainer.new()
	row.name = "ShopPortraitMatrix"
	row.columns = mini(3, _characters.size())
	row.add_theme_constant_override("h_separation", 1)
	row.add_theme_constant_override("v_separation", 1)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_child(row)
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		row.add_child(_shopper_portrait(character, "Shopper"))
	return panel


func _shopper_portrait(character: InteractionRequestValue.ServiceCharacter, side: String) -> Button:
	var button := Button.new()
	button.name = "Shop%s_%s" % [side, character.id]
	button.icon = _portrait_texture(character.portrait_id)
	button.expand_icon = true
	button.toggle_mode = true
	button.button_pressed = character.id == (_selected_character_id if side != "Seller" else _right_character_id)
	button.custom_minimum_size = (COMPACT_FOOTER_PORTRAIT_SIZE if _compact else FOOTER_PORTRAIT_SIZE) if side != "Shopper" else COMPACT_PORTRAIT_SIZE
	button.add_theme_constant_override("icon_max_width", int(button.custom_minimum_size.x))
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.clip_contents = true
	_apply_portrait_button_styles(button)
	button.tooltip_text = "%s: %s" % ["Left shopper" if side != "Seller" else "Right shopper", character.name]
	button.set_meta(&"character_id", character.id)
	button.set_meta(&"shop_side", side)
	button.pressed.connect((_select_right_character if side == "Seller" else _select_character).bind(character.id))
	_shopper_buttons[button.name] = button
	return button


func _apply_portrait_button_styles(button: Button) -> void:
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("15191b") if state != &"pressed" else Color("3b3420")
		style.border_color = GOLD if state in [&"hover", &"pressed", &"focus"] else Color("4d5559")
		style.set_border_width_all(1)
		style.content_margin_left = 0.0
		style.content_margin_top = 0.0
		style.content_margin_right = 0.0
		style.content_margin_bottom = 0.0
		button.add_theme_stylebox_override(state, style)


func _inventory_row(character: InteractionRequestValue.ServiceCharacter, item: InteractionRequestValue.InventoryItem, prefix: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var icon := CONTENT_ICON_SCRIPT.new() as Control
	icon.name = "%sIcon_%s" % [prefix, item.instance_id.replace(".", "_")]
	icon.configure(item.icon_resource_type, item.icon_id, _media, _ledger_row_height(), item.name)
	row.add_child(icon)
	var button := EXCHANGE_ITEM_BUTTON_SCRIPT.new()
	button.name = "%s_%s" % [prefix, item.instance_id.replace(".", "_")]
	button.text = "%s\n%s  •  sell %d gold" % [item.name, "Equipped" if item.equipped else "Carried", item.sell_price]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.custom_minimum_size.y = _ledger_row_height()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.theme_type_variation = &"ClassicItemLedgerButton"
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.button_group = _inventory_group
	button.button_pressed = _selected_item != null and _selected_item.instance_id == item.instance_id and _selected_item_owner_id == character.id
	button.pressed.connect(_select_item.bind(character.id, item.instance_id))
	button.configure_drag({"kind": &"shop-inventory-item", "sourceId": character.id, "instanceId": item.instance_id})
	row.add_child(button)
	_detail_popover.bind_hover(icon, _inventory_detail(item))
	_detail_popover.bind_hover(button, _inventory_detail(item))
	return row


func _update_shopper_buttons() -> void:
	for id: Variant in _shopper_buttons:
		var button := _shopper_buttons[id] as BaseButton
		var side := String(button.get_meta(&"shop_side", ""))
		var selected_id := _right_character_id if side == "Seller" else _selected_character_id
		button.set_pressed_no_signal(String(button.get_meta(&"character_id", "")) == selected_id)


func _refresh_shopper_facts() -> void:
	var left := _character_by_id(_selected_character_id)
	var right := _character_by_id(_right_character_id)
	if left != null:
		_left_load.text = "Load\n%d / %d\nItems %d" % [left.load, left.maximum_load, left.inventory.size()]
		_shopper_name.text = left.name
		_selected_portrait.texture = _portrait_texture(left.portrait_id)
	else:
		_left_load.text = "No shopper"
		_shopper_name.text = ""
		_selected_portrait.texture = null
	_right_load.text = ("Shop\nStock %d" if _compact else "Shop Keeper\nStock %d") % _stock.size() if right == null else "Load\n%d / %d\nItems %d" % [right.load, right.maximum_load, right.inventory.size()]


func _show_items() -> void:
	var character := _character_by_id(_selected_character_id)
	_selected_stock = null
	_selected_item = null
	_selected_item_owner_id = ""
	_refresh_inspector()
	_item_description.text = "%s carries %d item%s. Select a row in the left ledger to inspect or trade it." % [character.name, character.inventory.size(), "" if character.inventory.size() == 1 else "s"] if character != null else "No adventurer is selected."


func _show_money() -> void:
	_selected_stock = null
	_selected_item = null
	_selected_item_owner_id = ""
	_refresh_inspector()
	_item_description.text = "The party has %d gold available for this shop." % _body.party_gold


func _facts_text(facts: Array[InteractionRequestValue.ItemDetailFact], extra_label: String, extra_value: String) -> String:
	var lines: Array[String] = []
	for fact: InteractionRequestValue.ItemDetailFact in facts:
		lines.append("%s  %s" % [fact.label, fact.value])
	lines.append("%s  %s" % [extra_label, extra_value])
	return "  •  ".join(lines)


func _detail_facts(facts: Array[InteractionRequestValue.ItemDetailFact], suffix: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fact: InteractionRequestValue.ItemDetailFact in facts:
		result.append({"label": fact.label, "value": fact.value})
	result.append_array(suffix)
	return result


func _visible_stock() -> Array[InteractionRequestValue.ShopStock]:
	var result: Array[InteractionRequestValue.ShopStock] = []
	for entry: InteractionRequestValue.ShopStock in _stock:
		if entry.category.is_empty() or entry.category == _selected_category:
			result.append(entry)
	return result


func _portrait_texture(asset_id: String) -> Texture2D:
	if _media == null or asset_id.is_empty():
		return null
	return _media.image_texture(_media.asset_by_id(asset_id))


func _stock_detail(entry: InteractionRequestValue.ShopStock) -> Dictionary:
	return {"title": entry.name, "subtitle": entry.description, "facts": _detail_facts(entry.facts, [{"label": "Price", "value": "%d gold" % entry.buy_price}, {"label": "Quantity", "value": str(entry.quantity)}]), "restrictions": [entry.buy_reason] if not entry.buy_reason.is_empty() else [], "iconResourceType": entry.icon_resource_type, "iconId": entry.icon_id}


func _inventory_detail(item: InteractionRequestValue.InventoryItem) -> Dictionary:
	var facts: Array[Dictionary] = _detail_facts(item.facts, [{"label": "State", "value": "Equipped" if item.equipped else "Carried"}, {"label": "Knowledge", "value": "Identified" if item.identified else "Unidentified"}, {"label": "Sell", "value": "%d gold" % item.sell_price}])
	if item.charges != 0:
		facts.append({"label": "Charges", "value": "Unlimited" if item.charges < 0 else str(item.charges)})
	var restrictions: Array[String] = []
	if not item.sell_reason.is_empty(): restrictions.append(item.sell_reason)
	if not item.identify_reason.is_empty(): restrictions.append(item.identify_reason)
	return {"title": item.name, "subtitle": item.description, "facts": facts, "restrictions": restrictions, "iconResourceType": item.icon_resource_type, "iconId": item.icon_id}


func _exchange_pane(parent: HBoxContainer, pane_name: String, title: String, accepted_kind: StringName, target_id: String) -> VBoxContainer:
	var panel := EXCHANGE_LEDGER_SCRIPT.new()
	panel.name = pane_name
	panel.theme_type_variation = &"ClassicItemLedger"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.configure_drop(accepted_kind, target_id)
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	panel.add_child(content)
	var heading := _label(title, Color("151512"))
	heading.theme_type_variation = &"ClassicHeading"
	content.add_child(heading)
	return content


func _pane(parent: Container, pane_name: String, title: String, ratio: float) -> VBoxContainer:
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
	scroll.custom_minimum_size.y = _ledger_scroll_height()
	return scroll


func _ledger_row_height() -> float:
	return COMPACT_LEDGER_ROW_HEIGHT if _compact else WIDE_LEDGER_ROW_HEIGHT


func _route_button_size() -> Vector2:
	return COMPACT_ROUTE_BUTTON_SIZE if _compact else ROUTE_BUTTON_SIZE


func _ledger_scroll_height() -> float:
	var visible_rows := COMPACT_VISIBLE_ROWS if _compact else CLASSIC_VISIBLE_ROWS
	return visible_rows * _ledger_row_height() + (visible_rows - 1) * LEDGER_ROW_SEPARATION


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", color)
	return label


func _compact_fact(control_name: String, minimum_width: float = 78.0) -> Label:
	var label := _label("", CYAN)
	label.name = control_name
	label.custom_minimum_size.x = minimum_width
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _action_button(button_name: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.custom_minimum_size = Vector2(112.0, 38.0)
	button.pressed.connect(callback)
	return button
