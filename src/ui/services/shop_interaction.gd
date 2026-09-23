## Presents the dynamic shop interaction without owning gameplay state.

class_name ShopInteraction
extends InteractionComponent

const GOLD := Color("e5c45c")
const CLASSIC_VISIBLE_ROWS := 9
const COMPACT_VISIBLE_ROWS := 5
const WIDE_LEDGER_ROW_HEIGHT := 34.0
const COMPACT_LEDGER_ROW_HEIGHT := 30.0
const LEDGER_ROW_SEPARATION := 2.0
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

@export var item_row_scene: PackedScene
@export var character_button_scene: PackedScene
@export var empty_label_scene: PackedScene
@export var inventory_workspace_scene: PackedScene
@export var money_workspace_scene: PackedScene

var _compact := false
var _media: ClassicMediaCatalog
var _game_view: GameView
var _body: ShopRequestBody
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
var _browser: Control
var _row_height: float
var _route_size: Vector2
var _scroll_height: float
var _inventory_controller: InventoryScreenController
var _inventory_workspace: VBoxContainer
var _money_controller: ServicesScreenController
var _money_workspace: VBoxContainer
var _money_workspace_open := false
var _inventory_focus := WorkspaceFocusController.new()
var _money_focus := WorkspaceFocusController.new()


func configure(media: ClassicMediaCatalog, game_view: GameView, compact: bool) -> void:
	_media = media
	_game_view = game_view
	_compact = compact


func capture_browser_state() -> Dictionary:
	if _body == null or _inventory_rows == null or _stock_rows == null:
		return {}
	return {"shopId": _body.shop_id, "leftId": _selected_character_id, "rightId": _right_character_id, "category": _selected_category,
		"tab": (_browser.get_node("ShopBrowserTabs") as TabContainer).current_tab if _compact else 0,
		"inventoryScroll": (_inventory_rows.get_parent() as ScrollContainer).scroll_vertical, "stockScroll": (_stock_rows.get_parent() as ScrollContainer).scroll_vertical,
		"itemOwnerId": _selected_item_owner_id, "instanceId": _selected_item.instance_id if _selected_item != null else "", "stockKey": _selected_stock.stock_key if _selected_stock != null else "", "moneyOpen": _money_workspace_open,
		"moneyCharacterId": _money_controller.selected_character_id() if _money_workspace_open and _money_controller != null else ""}


func restore_browser_state(state: Dictionary) -> void:
	if state.is_empty() or String(state.get("shopId", "")) != _body.shop_id:
		return
	_select_category(StringName(state.get("category", &"weapons")))
	if _character_by_id(String(state.get("leftId", ""))) != null:
		_select_character(String(state.leftId))
	if _character_by_id(String(state.get("rightId", ""))) != null:
		_select_right_character(String(state.rightId))
	if not String(state.get("instanceId", "")).is_empty():
		_select_item(String(state.itemOwnerId), String(state.instanceId))
	elif not String(state.get("stockKey", "")).is_empty():
		_select_stock(String(state.stockKey))
	if _compact:
		(_browser.get_node("ShopBrowserTabs") as TabContainer).current_tab = int(state.get("tab", 0))
	(_inventory_rows.get_parent() as ScrollContainer).set_deferred("scroll_vertical", int(state.get("inventoryScroll", 0)))
	(_stock_rows.get_parent() as ScrollContainer).set_deferred("scroll_vertical", int(state.get("stockScroll", 0)))
	if bool(state.get("moneyOpen", false)):
		_show_workspace(&"money", String(state.get("moneyCharacterId", "")))


func build(request: InteractionRequest) -> void:
	_body = request.body as ShopRequestBody
	if _body == null:
		add_hint("The shop request is malformed.")
		return
	_characters = _body.characters.duplicate()
	_stock = _body.stock.duplicate()
	_row_height = COMPACT_LEDGER_ROW_HEIGHT if _compact else WIDE_LEDGER_ROW_HEIGHT
	_route_size = COMPACT_ROUTE_BUTTON_SIZE if _compact else ROUTE_BUTTON_SIZE
	var visible_rows := COMPACT_VISIBLE_ROWS if _compact else CLASSIC_VISIBLE_ROWS
	_scroll_height = visible_rows * _row_height + (visible_rows - 1) * LEDGER_ROW_SEPARATION
	if not _characters.is_empty():
		_selected_character_id = _characters[0].id
	_detail_popover = get_node("ClassicItemDetailPopover") as ClassicItemDetailPopover
	_detail_popover.configure(_media, get_theme())
	%ShopFacts.text = "%d gold  •  prices %d%%" % [_body.party_gold, _body.inflation_percent]
	_select_profile_browser()
	_bind_ledgers()
	_bind_footer()
	_bind_category_filters()
	_populate_shopper_selectors()
	_refresh_inventory()
	_refresh_inspector()


func _select_profile_browser() -> void:
	var wide := %ShopExchangeLedgers as HBoxContainer
	var compact := %ShopCompactBrowser as PanelContainer
	if _compact:
		%ShopCompactWealthActions.visible = true
		%ShopWealthPanel.visible = false
		%ShopCompactWealthPanel.visible = true
		%ShopFacts.text = "Prices %d%%" % _body.inflation_percent
		(get_node("ShopHeader/Title") as Label).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		wide.get_parent().remove_child(wide)
		wide.free()
		compact.visible = true
		_browser = compact
	else:
		compact.get_parent().remove_child(compact)
		compact.free()
		_browser = wide


func _bind_ledgers() -> void:
	_stock_rows = _browser.find_child("ShopStockRows", true, false) as VBoxContainer
	_inventory_rows = _browser.find_child("InventoryRows", true, false) as VBoxContainer
	_stock_heading = _browser.find_child("ShopStockHeading", true, false) as Label
	var inventory_scroll := _browser.find_child("InventoryScroll", true, false) as ScrollContainer
	var stock_scroll := _browser.find_child("ShopStockScroll", true, false) as ScrollContainer
	inventory_scroll.custom_minimum_size.y = _scroll_height
	stock_scroll.custom_minimum_size.y = _scroll_height
	if not _compact:
		var pack_ledger := _browser.find_child("SelectedInventoryColumn", true, false) as ClassicExchangeLedger
		var stock_ledger := _browser.find_child("ShopStockColumn", true, false) as ClassicExchangeLedger
		pack_ledger.configure_drop(&"shop-stock-item", _selected_character_id)
		stock_ledger.configure_drop(&"shop-inventory-item", "shop")
		pack_ledger.item_dropped.connect(_drop_on_character)
		stock_ledger.item_dropped.connect(_drop_on_shop)
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
		if right_character.inventory.is_empty(): _stock_rows.add_child(_empty_label("%s carries no items." % right_character.name))
		return
	var visible := _visible_stock()
	if visible.is_empty():
		_stock_rows.add_child(_empty_label("No stock is available in this category."))
		return
	for entry: InteractionRequestValue.ShopStock in visible:
		var row := item_row_scene.instantiate() as HBoxContainer
		var icon := row.get_node("%ItemIcon") as ClassicContentIcon
		icon.name = "StockIcon_%s" % entry.stock_key.replace(":", "_").replace(".", "_")
		icon.configure(entry.icon_resource_type, entry.icon_id, _media, _row_height, entry.name)
		var button := row.get_node("%ItemButton") as ClassicExchangeItemButton
		button.name = "Stock_%s" % entry.stock_key.replace(":", "_").replace(".", "_")
		button.set_meta("operation", "shop-stock:%s" % entry.stock_key)
		button.text = "%s\n%d gold  •  %d left" % [entry.name, entry.buy_price, entry.quantity]
		button.custom_minimum_size.y = _row_height
		button.button_group = _stock_group
		button.button_pressed = _selected_stock != null and _selected_stock.stock_key == entry.stock_key
		button.pressed.connect(_select_stock.bind(entry.stock_key))
		button.focus_entered.connect(_select_stock.bind(entry.stock_key))
		button.configure_drag({"kind": &"shop-stock-item", "sourceId": "shop", "stockKey": entry.stock_key})
		_detail_popover.bind_hover(icon, _stock_detail(entry))
		_detail_popover.bind_hover(button, _stock_detail(entry))
		_stock_rows.add_child(row)


func _bind_footer() -> void:
	_left_load = %ShopLeftLoad as Label
	_right_load = %ShopRightLoad as Label
	_shopper_name = %ShopperName as Label
	_transaction_facts = %ShopTransactionFacts as Label
	_item_description = %ShopItemDescription as Label
	_item_stats = %ShopItemStats as Label
	_selected_portrait = %ShopSelectedPortrait as TextureRect
	_buy_button = %ShopBuy as Button
	_sell_button = %ShopSellSelected as Button
	_identify_button = %ShopIdentify as Button
	_buy_button.pressed.connect(_submit_buy)
	_sell_button.pressed.connect(_submit_sell)
	_identify_button.pressed.connect(_submit_identify)
	%ShopDone.pressed.connect(_submit_leave)
	var pool_availability: ActionAvailabilityView = _game_view.money_workspace.pool if _game_view != null and _game_view.money_workspace != null else null
	var share_availability: ActionAvailabilityView = _game_view.money_workspace.share if _game_view != null and _game_view.money_workspace != null else null
	var pool_button: Button = %ShopCompactPool if _compact else %ShopPool
	var share_button: Button = %ShopCompactShare if _compact else %ShopShare
	pool_button.disabled = pool_availability == null or not pool_availability.enabled
	share_button.disabled = share_availability == null or not share_availability.enabled
	pool_button.tooltip_text = "Party wealth is unavailable." if pool_availability == null else pool_availability.reason if not pool_availability.enabled else "Pool party wealth"
	share_button.tooltip_text = "Party wealth is unavailable." if share_availability == null else share_availability.reason if not share_availability.enabled else "Share pooled wealth"
	if not pool_button.disabled:
		pool_button.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.ShopBody.new(&"pool")))
	if not share_button.disabled:
		share_button.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.ShopBody.new(&"share")))
	_configure_route_button(%ShopKeeperRestore, "Shop Keeper", &"command.shop_original", func() -> void: _select_category(_selected_category), {"asset_path": "res://src/ui/shared/assets/ui/commands/shop.png"})
	_configure_route_button(%ShopItems, "Items", &"command.inventory", _show_workspace.bind(&"items"), {"art_region": [5, 2, 36, 34], "art_clear_regions": [[0, 4, 4, 8]]})
	_configure_route_button(%ShopMoney, "Money", &"command.money", _show_workspace.bind(&"money"), {"art_region": [5, 5, 35, 31], "art_clear_regions": [[0, 0, 8, 8]]})
	_apply_profile_sizes()
	_selection_summary = _item_description


func _configure_route_button(button: ClassicBitmapButton, caption: String, asset_id: StringName, callback: Callable, art_options: Dictionary = {}) -> void:
	var definition := {"id": StringName(button.name), "asset_id": asset_id, "tooltip": caption, "label": ""}
	definition.merge(art_options, true)
	button.configure(definition, 1)
	button.custom_minimum_size = _route_size
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.command_requested.connect(func(_command_id: StringName) -> void: callback.call())


func _apply_profile_sizes() -> void:
	find_child("ShopLeftLoadPanel", true, false).custom_minimum_size.x = 66.0 if _compact else 86.0
	find_child("ShopSelectedShopperPanel", true, false).custom_minimum_size.x = 64.0 if _compact else 84.0
	find_child("ShopSelectedShopper", true, false).custom_minimum_size.x = 56.0 if _compact else 76.0
	find_child("ShopTransactionContainer", true, false).custom_minimum_size.x = 150.0 if _compact else 174.0
	find_child("ShopTransactionPanel", true, false).custom_minimum_size.x = 142.0 if _compact else 166.0
	find_child("ShopRouteControls", true, false).custom_minimum_size.x = 190.0 if _compact else 257.0
	find_child("ShopRightLoadPanel", true, false).custom_minimum_size.x = 58.0 if _compact else 86.0
	get_node("ShopLowerWorkspace/ShopControlStrip/ShopControls/ShopperPortraitSelector").custom_minimum_size.x = 76.0 if _compact else 96.0
	_left_load.custom_minimum_size.x = 62.0 if _compact else 78.0
	_right_load.custom_minimum_size.x = 54.0 if _compact else 78.0
	for button: Button in [_buy_button, _sell_button, _identify_button]:
		button.custom_minimum_size = Vector2(44.0, 22.0) if _compact else Vector2(52.0, 24.0)
	%ShopDone.custom_minimum_size = _route_size


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
		_inventory_rows.add_child(_empty_label("No adventurer is selected."))
		return
	for item: InteractionRequestValue.InventoryItem in character.inventory:
		_inventory_rows.add_child(_inventory_row(character, item, "Inventory"))
	if character.inventory.is_empty():
		_inventory_rows.add_child(_empty_label("%s carries no items." % character.name))


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


func _bind_category_filters() -> void:
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
		var button := _browser.find_child("ShopFilter_%s" % category_id, true, false) as ClassicBitmapButton
		button.configure(definition, 1)
		button.custom_minimum_size = FILTER_BUTTON_SIZE
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.button_group = _category_group
		button.button_pressed = category_id == _selected_category
		button.command_requested.connect(func(_command_id: StringName) -> void: _select_category(category_id))
		_category_buttons[category_id] = button


func _populate_shopper_selectors() -> void:
	var buyer_grid := %ShopBuyerPortraits as GridContainer
	var seller_grid := %ShopSellerPortraits as GridContainer
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		buyer_grid.add_child(_shopper_portrait(character, "Buyer"))
		seller_grid.add_child(_shopper_portrait(character, "Seller"))
	if _compact:
		var compact_grid := _browser.find_child("ShopCompactPortraits", true, false) as GridContainer
		compact_grid.columns = mini(3, _characters.size())
		for character: InteractionRequestValue.ServiceCharacter in _characters:
			compact_grid.add_child(_shopper_portrait(character, "Shopper"))


func _shopper_portrait(character: InteractionRequestValue.ServiceCharacter, side: String) -> Button:
	var button := character_button_scene.instantiate() as Button
	button.name = "Shop%s_%s" % [side, character.id]
	button.icon = _portrait_texture(character.portrait_id)
	button.button_pressed = character.id == (_selected_character_id if side != "Seller" else _right_character_id)
	button.custom_minimum_size = (COMPACT_FOOTER_PORTRAIT_SIZE if _compact else FOOTER_PORTRAIT_SIZE) if side != "Shopper" else COMPACT_PORTRAIT_SIZE
	button.add_theme_constant_override("icon_max_width", int(button.custom_minimum_size.x))
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
	var row := item_row_scene.instantiate() as HBoxContainer
	var icon := row.get_node("%ItemIcon") as ClassicContentIcon
	icon.name = "%sIcon_%s" % [prefix, item.instance_id.replace(".", "_")]
	icon.configure(item.icon_resource_type, item.icon_id, _media, _row_height, item.name)
	var button := row.get_node("%ItemButton") as ClassicExchangeItemButton
	button.name = "%s_%s" % [prefix, item.instance_id.replace(".", "_")]
	button.set_meta("item_instance_id", item.instance_id)
	button.text = "%s\n%s  •  sell %d gold" % [item.name, "Equipped" if item.equipped else "Carried", item.sell_price]
	button.custom_minimum_size.y = _row_height
	button.button_group = _inventory_group
	button.button_pressed = _selected_item != null and _selected_item.instance_id == item.instance_id and _selected_item_owner_id == character.id
	button.pressed.connect(_select_item.bind(character.id, item.instance_id))
	button.focus_entered.connect(_select_item.bind(character.id, item.instance_id))
	button.configure_drag({"kind": &"shop-inventory-item", "sourceId": character.id, "instanceId": item.instance_id})
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
	var money: MoneyWorkspaceView = _game_view.money_workspace if _game_view != null else null
	var selected_money: MoneyCharacterView = money.character(_selected_character_id) if money != null else null
	%ShopCurrentGold.text = "Gold %d" % selected_money.gold if selected_money != null else "Gold —"
	%ShopPooledGold.text = "Pool %d" % money.pooled_gold if money != null else "Pool —"
	%ShopCompactWealth.text = "%s  •  %s" % [%ShopCurrentGold.text, %ShopPooledGold.text]
	if left != null:
		_left_load.text = "Load\n%d / %d\nItems %d" % [left.load, left.maximum_load, left.inventory.size()]
		_shopper_name.text = left.name
		_selected_portrait.texture = _portrait_texture(left.portrait_id)
	else:
		_left_load.text = "No shopper"
		_shopper_name.text = ""
		_selected_portrait.texture = null
	_right_load.text = ("Shop\nStock %d" if _compact else "Shop Keeper\nStock %d") % _stock.size() if right == null else "Load\n%d / %d\nItems %d" % [right.load, right.maximum_load, right.inventory.size()]


func _show_workspace(kind: StringName, money_character_id: String = "") -> void:
	var is_items := kind == &"items"
	var scene := inventory_workspace_scene if is_items else money_workspace_scene
	if _game_view == null or scene == null:
		presentation_status_requested.emit("The party %s workspace is unavailable." % ("Items" if is_items else "Money"), true)
		return
	if is_items:
		_inventory_controller = InventoryScreenController.new()
		_inventory_controller.set_layout_profile(UiLayoutProfile.COMPACT if _compact else UiLayoutProfile.WIDE)
		_inventory_workspace = scene.instantiate() as VBoxContainer
		_inventory_workspace.name = "ShopItemsWorkspace"
		_inventory_controller.refresh_requested.connect(_refresh_workspace.bind(kind))
		_inventory_controller.back_requested.connect(func() -> void:
			application_workspace_closed.emit()
			_inventory_controller = null
			_inventory_workspace = null
		)
		_refresh_workspace(kind)
		application_workspace_requested.emit(_inventory_workspace)
		if _inventory_workspace.is_inside_tree(): Callable(_inventory_focus, "focus_first").call_deferred(_inventory_workspace)
		return
	_money_controller = ServicesScreenController.new()
	_money_controller.set_layout_profile(UiLayoutProfile.COMPACT if _compact else UiLayoutProfile.WIDE)
	_money_controller.set_selected_character_id(money_character_id)
	_money_workspace = scene.instantiate() as VBoxContainer
	_money_workspace.name = "ShopMoneyWorkspace"
	_money_workspace_open = true
	_money_controller.refresh_requested.connect(_refresh_workspace.bind(kind))
	_money_controller.intent_submitted.connect(func(intent: PlayerIntent) -> void:
		var money := intent.payload as EconomyIntentPayloads.Money
		if intent.kind != PlayerIntent.Kind.MONEY_ACTION or money == null:
			return
		response_body_submitted.emit(InteractionResponse.ShopBody.new(money.action, money.character_id, "", "", money.denomination, money.amount))
	)
	_money_controller.back_requested.connect(func() -> void:
		_money_workspace_open = false
		application_workspace_closed.emit()
		_money_controller = null
		_money_workspace = null
	)
	_refresh_workspace(kind)
	application_workspace_requested.emit(_money_workspace)
	if _money_workspace.is_inside_tree(): Callable(_money_focus, "focus_first").call_deferred(_money_workspace)


func _refresh_workspace(kind: StringName) -> void:
	var is_items := kind == &"items"
	var workspace: VBoxContainer = _inventory_workspace if is_items else _money_workspace
	if workspace == null or not is_instance_valid(workspace): return
	var focus := _inventory_focus if is_items else _money_focus
	var route := &"shop-items" if is_items else &"shop-money"
	var mounted := workspace.is_inside_tree()
	if mounted: focus.store(workspace, workspace, route)
	if is_items: _inventory_controller.present_browse(workspace, _game_view, _media, 1.0, "Return to the Shop before changing carried items.")
	else: _money_controller.present_shop(workspace, _game_view, _media)
	focus.prepare(workspace, route)
	if mounted: Callable(focus, "restore").call_deferred(workspace, workspace, null, route, false, 0, 0)


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


func _empty_label(text: String) -> Label:
	var label := empty_label_scene.instantiate() as Label
	label.text = text
	return label
