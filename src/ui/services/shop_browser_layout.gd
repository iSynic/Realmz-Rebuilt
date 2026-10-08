## Retains the Shop's authored wide and compact browsers across profile changes.

class_name ShopBrowserLayout
extends RefCounted

var wide_browser: HBoxContainer
var compact_browser: PanelContainer
var active_browser: Control
var description_pane: PanelContainer
var stats_pane: PanelContainer
var description_label: Label
var stats_label: Label
var description_readout: RichTextLabel
var stats_readout: RichTextLabel
var _detail_strip: HBoxContainer
var _compact_detail_rows: VBoxContainer


func activate(owner: Control, compact: bool, party_gold: int, inflation_percent: int) -> Control:
	if wide_browser == null:
		wide_browser = owner.find_child("ShopExchangeLedgers", true, false) as HBoxContainer
		compact_browser = owner.find_child("ShopCompactBrowser", true, false) as PanelContainer
		_detail_strip = owner.find_child("ShopDetailStrip", true, false) as HBoxContainer
		_compact_detail_rows = compact_browser.find_child("ShopCompactDetailRows", true, false) as VBoxContainer
		description_pane = owner.find_child("ShopItemDescriptionPane", true, false) as PanelContainer
		stats_pane = owner.find_child("ShopItemStatsPane", true, false) as PanelContainer
		description_label = description_pane.find_child("ShopItemDescription", true, false) as Label
		stats_label = stats_pane.find_child("ShopItemStats", true, false) as Label
		description_readout = description_pane.find_child("ShopItemDescriptionReadout", true, false) as RichTextLabel
		stats_readout = stats_pane.find_child("ShopItemStatsReadout", true, false) as RichTextLabel
	var columns := owner.find_child("ShopColumns", true, false) as HBoxContainer
	if compact:
		compact_browser.visible = true
		(owner.find_child("ShopCompactWealthActions", true, false) as Control).visible = true
		(owner.find_child("ShopWealthPanel", true, false) as Control).visible = false
		(owner.find_child("ShopCompactWealthPanel", true, false) as Control).visible = true
		(owner.find_child("ShopFacts", true, false) as Label).text = "Prices %d%%" % inflation_percent
		(owner.get_node("ShopHeader/Title") as Label).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		wide_browser.visible = false
		if wide_browser.get_parent() == columns:
			columns.remove_child(wide_browser)
		if compact_browser.get_parent() == null:
			columns.add_child(compact_browser)
		active_browser = compact_browser
	else:
		wide_browser.visible = true
		compact_browser.visible = false
		(owner.find_child("ShopCompactWealthActions", true, false) as Control).visible = false
		(owner.find_child("ShopWealthPanel", true, false) as Control).visible = true
		(owner.find_child("ShopCompactWealthPanel", true, false) as Control).visible = false
		(owner.find_child("ShopFacts", true, false) as Label).text = "%d gold  •  prices %d%%" % [party_gold, inflation_percent]
		(owner.get_node("ShopHeader/Title") as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if wide_browser.get_parent() == null:
			columns.add_child(wide_browser)
			columns.move_child(wide_browser, 0)
		if compact_browser.get_parent() == columns:
			columns.remove_child(compact_browser)
		active_browser = wide_browser
	_set_detail_profile(compact)
	UiSizing.bind_added(active_browser.get_instance_id())
	return active_browser


func capture_state(owner: Control, compact: bool) -> Dictionary:
	if active_browser == null:
		return {}
	var inventory_scroll := active_browser.find_child("InventoryScroll", true, false) as ScrollContainer
	var stock_scroll := active_browser.find_child("ShopStockScroll", true, false) as ScrollContainer
	var focus := owner.get_viewport().gui_get_focus_owner() if owner.get_viewport() != null else null
	return {"tab": (active_browser.get_node("ShopBrowserTabs") as TabContainer).current_tab if compact else 0,
		"inventoryScroll": inventory_scroll.scroll_vertical if inventory_scroll != null else 0,
		"stockScroll": stock_scroll.scroll_vertical if stock_scroll != null else 0,
		"focusName": focus.name if focus != null and active_browser.is_ancestor_of(focus) else ""}


func restore_state(browser: Control, compact: bool, state: Dictionary) -> void:
	if browser == null or state.is_empty():
		return
	if compact:
		(browser.get_node("ShopBrowserTabs") as TabContainer).current_tab = int(state.get("tab", 0))
	for pair: Array in [["InventoryScroll", "inventoryScroll"], ["ShopStockScroll", "stockScroll"]]:
		var scroll := browser.find_child(pair[0], true, false) as ScrollContainer
		if scroll != null:
			scroll.set_deferred("scroll_vertical", int(state.get(pair[1], 0)))
	var focus_name := String(state.get("focusName", ""))
	var focus := browser.find_child(focus_name, true, false) as Control if not focus_name.is_empty() else null
	if focus != null:
		focus.call_deferred("grab_focus")


func apply_sizes(owner: Control, compact: bool, route_size: Vector2, left_load: Label, right_load: Label, buy: Button, sell: Button, identify: Button) -> void:
	var profile := UiSizing.profile_for(owner)
	var text_growth := profile.font_scale / profile.ui_scale if profile != null and profile.ui_scale > 0.0 else 1.0
	var done_size := route_size
	if compact and text_growth > 1.0:
		done_size = Vector2(maxf(done_size.x, 58.0), maxf(done_size.y, 50.0))
	var route_controls := owner.find_child("ShopRouteControls", true, false) as PanelContainer
	var route_actions := route_controls.get_node("Content") as GridContainer
	route_actions.columns = 2 if compact else 4
	var route_row_height := maxf(done_size.y, route_size.y)
	var compact_control_height := route_row_height * 2.0 + 14.0
	UiSizing.minimum_size(owner.find_child("ShopControlStrip", true, false) as Control, Vector2(0.0, maxf(68.0, compact_control_height if compact else done_size.y + 12.0)))
	for spec: Array in [["ShopLeftLoadPanel", 66.0, 86.0], ["ShopSelectedShopperPanel", 64.0, 84.0], ["ShopSelectedShopper", 56.0, 76.0], ["ShopTransactionContainer", 150.0, 174.0], ["ShopTransactionPanel", 142.0, 166.0], ["ShopRightLoadPanel", 58.0, 86.0]]:
		UiSizing.minimum_size(owner.find_child(spec[0], true, false) as Control, Vector2(spec[1] if compact else spec[2], 0.0))
	UiSizing.minimum_size(route_controls, Vector2((done_size.x * 2.0 + 14.0) if compact else 257.0, 0.0))
	UiSizing.minimum_size(owner.get_node("ShopLowerWorkspace/ShopControlStrip/ShopControls/ShopperPortraitSelector") as Control, Vector2(76.0 if compact else 96.0, 0.0))
	UiSizing.minimum_size(left_load, Vector2(62.0 if compact else 78.0, 0.0))
	UiSizing.minimum_size(right_load, Vector2(54.0 if compact else 78.0, 0.0))
	for button: Button in [buy, sell, identify]:
		UiSizing.minimum_size(button, Vector2(44.0, 22.0) if compact else Vector2(52.0, 24.0))
	UiSizing.minimum_size(owner.find_child("ShopDone", true, false) as Control, done_size)
	UiSizing.minimum_size(_detail_strip, Vector2(0.0, 82.0) if not compact else Vector2.ZERO)
	for pane: PanelContainer in [description_pane, stats_pane]:
		UiSizing.minimum_size(pane, Vector2(0.0, 64.0) if not compact else Vector2.ZERO)
	if compact:
		for pane: PanelContainer in [description_pane, stats_pane]:
			pane.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


func configure_route_button(button: ClassicBitmapButton, caption: String, asset_id: StringName, route_size: Vector2, callback: Callable, art_options: Dictionary = {}) -> void:
	var definition := {"id": StringName(button.name), "asset_id": asset_id, "tooltip": caption, "label": ""}
	definition.merge(art_options, true)
	button.configure(definition, 1)
	UiSizing.minimum_size(button, route_size)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.command_requested.connect(func(_command_id: StringName) -> void: callback.call())


func dispose_detached() -> void:
	for browser: Control in [wide_browser, compact_browser]:
		if browser != null and is_instance_valid(browser) and browser.get_parent() == null:
			browser.free()


func _set_detail_profile(compact: bool) -> void:
	var destination: BoxContainer = _compact_detail_rows if compact else _detail_strip
	for pane: PanelContainer in [description_pane, stats_pane]:
		if pane.get_parent() == destination:
			continue
		if pane.get_parent() != null:
			pane.get_parent().remove_child(pane)
		pane.owner = null
		destination.add_child(pane)
		if destination.owner != null:
			pane.owner = destination.owner
	_detail_strip.visible = not compact
