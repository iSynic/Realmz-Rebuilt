class_name ShopInteraction
extends InteractionComponent

const GOLD := Color("e5c45c")
const CYAN := Color("8fcfd1")
const MUTED := Color("aeb6ba")
const CONTENT_ICON_SCRIPT := preload("res://src/presentation/classic_content_icon.gd")
const EXCHANGE_ITEM_BUTTON_SCRIPT := preload("res://src/presentation/interaction_components/classic_exchange_item_button.gd")
const EXCHANGE_LEDGER_SCRIPT := preload("res://src/presentation/interaction_components/classic_exchange_ledger.gd")
const STOCK_FILTERS: Array[Dictionary] = [
	{"id": &"weapons", "asset": &"inventory.category.weapons", "label": "Weapons"},
	{"id": &"armor", "asset": &"inventory.category.armor", "label": "Armor"},
	{"id": &"limb_armor", "asset": &"inventory.category.limb_armor", "label": "Armor", "tooltip": "Limb Armor", "region": [0, 0, 50, 50]},
	{"id": &"magic", "asset": &"inventory.category.magic", "label": "Magic"},
	{"id": &"supplies", "asset": &"inventory.category.supplies", "label": "Supplies"},
]

var _compact := false
var _media: ClassicMediaCatalog
var _body: InteractionRequest.ShopRequestBody
var _characters: Array[InteractionRequestValue.ServiceCharacter] = []
var _stock: Array[InteractionRequestValue.ShopStock] = []
var _selected_character_id: String
var _selected_stock: InteractionRequestValue.ShopStock
var _selected_item: InteractionRequestValue.InventoryItem
var _selected_category: StringName = &"weapons"
var _stock_rows: VBoxContainer
var _inventory_rows: VBoxContainer
var _selection_summary: Label
var _buy_button: Button
var _sell_button: Button
var _identify_button: Button
var _stock_group := ButtonGroup.new()
var _inventory_group := ButtonGroup.new()
var _category_group := ButtonGroup.new()
var _category_buttons: Dictionary = {}
var _shopper_buttons: Dictionary = {}


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
	custom_minimum_size = Vector2(0.0, 500.0) if _compact else Vector2.ZERO
	add_theme_constant_override("separation", 6)
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
	_stock_rows.add_theme_constant_override("separation", 3)
	scroll.add_child(_stock_rows)
	_refresh_stock()


func _refresh_stock() -> void:
	if _stock_rows == null:
		return
	for child: Node in _stock_rows.get_children():
		_stock_rows.remove_child(child)
		child.free()
	var visible := _visible_stock()
	if visible.is_empty():
		_stock_rows.add_child(_label("No stock is available in this category.", MUTED))
		return
	for entry: InteractionRequestValue.ShopStock in visible:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var icon := CONTENT_ICON_SCRIPT.new() as Control
		icon.name = "StockIcon_%s" % entry.stock_key.replace(":", "_").replace(".", "_")
		icon.configure(entry.icon_resource_type, entry.icon_id, _media, 46.0, entry.name)
		row.add_child(icon)
		var button := EXCHANGE_ITEM_BUTTON_SCRIPT.new()
		button.name = "Stock_%s" % entry.stock_key.replace(":", "_").replace(".", "_")
		button.text = "%s\n%d gold  •  %d left" % [entry.name, entry.buy_price, entry.quantity]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.custom_minimum_size.y = 46.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = &"ClassicItemLedgerButton"
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.button_group = _stock_group
		button.button_pressed = _selected_stock != null and _selected_stock.stock_key == entry.stock_key
		button.pressed.connect(_select_stock.bind(entry.stock_key))
		button.configure_drag({"kind": &"shop-stock-item", "sourceId": "shop", "stockKey": entry.stock_key})
		row.add_child(button)
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
	_inventory_rows.add_theme_constant_override("separation", 3)
	scroll.add_child(_inventory_rows)
	_refresh_inventory()


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
	_selection_summary = _label("Choose stock or a carried item.", MUTED)
	_selection_summary.name = "ShopSelectionSummary"
	_selection_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_selection_summary.clip_text = true
	footer.add_child(_selection_summary)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 6.0
	footer.add_child(spacer)
	var leave := _action_button("ShopLeave", "Leave Shop", _submit_leave)
	leave.custom_minimum_size.x = 150.0
	footer.add_child(leave)


func _select_character(character_id: String) -> void:
	_selected_character_id = character_id
	_selected_stock = null
	_selected_item = null
	for id: Variant in _shopper_buttons:
		var button := _shopper_buttons[id] as BaseButton
		button.set_pressed_no_signal(String(button.get_meta(&"character_id", "")) == character_id)
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


func _select_category(category: StringName) -> void:
	_selected_category = category
	_selected_stock = null
	_selected_item = null
	for id: Variant in _category_buttons:
		(_category_buttons[id] as BaseButton).set_pressed_no_signal(StringName(id) == category)
	_refresh_stock()
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
		var button := EXCHANGE_ITEM_BUTTON_SCRIPT.new()
		button.name = "Inventory_%s" % item.instance_id.replace(".", "_")
		button.text = "%s\n%s  •  sell %d gold" % [item.name, "Equipped" if item.equipped else "Carried", item.sell_price]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.custom_minimum_size.y = 46.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = &"ClassicItemLedgerButton"
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.button_group = _inventory_group
		button.pressed.connect(_select_item.bind(character.id, item.instance_id))
		button.configure_drag({"kind": &"shop-inventory-item", "sourceId": character.id, "instanceId": item.instance_id})
		row.add_child(button)
		_inventory_rows.add_child(row)
	if character.inventory.is_empty():
		_inventory_rows.add_child(_label("%s carries no items." % character.name, MUTED))


func _refresh_inspector() -> void:
	if _selection_summary == null:
		return
	_buy_button.disabled = _selected_stock == null or _selected_character_id.is_empty() or not _selected_stock.can_buy
	_sell_button.disabled = _selected_item == null or not _selected_item.can_sell
	_identify_button.disabled = _selected_item == null or not _selected_item.can_identify
	_buy_button.tooltip_text = "Select shop stock." if _selected_stock == null else "No shopper is available." if _selected_character_id.is_empty() else _selected_stock.buy_reason if not _selected_stock.can_buy else ""
	_sell_button.tooltip_text = "Select a carried item." if _selected_item == null else _selected_item.sell_reason if not _selected_item.can_sell else ""
	_identify_button.tooltip_text = "Select a carried item." if _selected_item == null else _selected_item.identify_reason if not _selected_item.can_identify else ""
	if _selected_stock != null:
		_selection_summary.text = "%s  •  Buy %d gold  •  %d left" % [_selected_stock.name, _selected_stock.buy_price, _selected_stock.quantity]
		_selection_summary.tooltip_text = _selected_stock.buy_reason
	elif _selected_item != null:
		var state := "Equipped" if _selected_item.equipped else "Carried"
		var knowledge := "Identified" if _selected_item.identified else "Unidentified"
		_selection_summary.text = "%s  •  %s  •  %s  •  Sell %d gold" % [_selected_item.name, state, knowledge, _selected_item.sell_price]
		_selection_summary.tooltip_text = _selected_item.sell_reason if not _selected_item.can_sell else _selected_item.identify_reason if not _selected_item.can_identify else ""
	else:
		_selection_summary.text = "Choose stock or a carried item."
		_selection_summary.tooltip_text = ""


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
		if filter.has("region"):
			definition["art_region"] = filter["region"]
		else:
			definition["art_clear_regions"] = [[0, 34, 50, 16]]
		var button := ClassicBitmapButton.new()
		button.name = "ShopFilter_%s" % category_id
		button.configure(definition, 1)
		button.custom_minimum_size.y = 58.0
		button.button_group = _category_group
		button.button_pressed = category_id == _selected_category
		button.command_requested.connect(func(_command_id: StringName) -> void: _select_category(category_id))
		_category_buttons[category_id] = button
		row.add_child(button)


func _build_control_spine(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "ShopExchangeDivider"
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = 170.0
	parent.add_child(panel)
	var spine := VBoxContainer.new()
	spine.name = "ShopControlSpine"
	spine.add_theme_constant_override("separation", 4)
	panel.add_child(spine)
	var filters := VBoxContainer.new()
	filters.name = "ShopCategoryFilters"
	filters.add_theme_constant_override("separation", 2)
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
		if filter.has("region"):
			definition["art_region"] = filter["region"]
		else:
			definition["art_clear_regions"] = [[0, 34, 50, 16]]
		var button := ClassicBitmapButton.new()
		button.name = "ShopFilter_%s" % category_id
		button.configure(definition, 1)
		button.button_group = _category_group
		button.button_pressed = category_id == _selected_category
		button.command_requested.connect(func(_command_id: StringName) -> void: _select_category(category_id))
		_category_buttons[category_id] = button
		filters.add_child(button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spine.add_child(spacer)
	spine.add_child(_build_shopper_selector(true))


func _build_shopper_selector(duplicate_columns: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "ShopperPortraitSelector"
	panel.theme_type_variation = &"ClassicInset"
	if duplicate_columns:
		var pair := HBoxContainer.new()
		pair.name = "ShopPortraitMatrix"
		pair.add_theme_constant_override("separation", 4)
		panel.add_child(pair)
		for side: String in ["Buyer", "Seller"]:
			var group := GridContainer.new()
			group.name = "Shop%sPortraits" % side
			group.columns = 2
			group.add_theme_constant_override("h_separation", 2)
			group.add_theme_constant_override("v_separation", 2)
			pair.add_child(group)
			for character: InteractionRequestValue.ServiceCharacter in _characters:
				group.add_child(_shopper_portrait(character, side))
		return panel
	var row := GridContainer.new()
	row.name = "ShopPortraitMatrix"
	row.columns = mini(3, _characters.size())
	row.add_theme_constant_override("h_separation", 3)
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
	button.button_pressed = character.id == _selected_character_id
	button.custom_minimum_size = Vector2(34.0, 30.0) if side != "Shopper" else Vector2(52.0, 42.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = "%s: %s using party funds" % [side, character.name]
	button.set_meta(&"character_id", character.id)
	button.pressed.connect(_select_character.bind(character.id))
	_shopper_buttons[button.name] = button
	return button


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
