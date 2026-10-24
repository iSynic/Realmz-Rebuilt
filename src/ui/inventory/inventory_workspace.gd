## Owns the reusable, editor-authored Inventory and Trade workspace regions.
class_name InventoryWorkspace
extends VBoxContainer

var _authored_split_minimum := Vector2.ZERO
var _authored_browser_minimum := Vector2.ZERO
var _authored_rail_minimum := Vector2.ZERO
var _authored_inspector_minimum := Vector2.ZERO

func _ready() -> void:
	_authored_split_minimum = main_split().custom_minimum_size
	_authored_browser_minimum = item_browser_panel().custom_minimum_size
	_authored_rail_minimum = command_rail_panel().custom_minimum_size
	_authored_inspector_minimum = item_inspector_panel().custom_minimum_size
	command_rail_content().set_item_actions(item_inspector_content().item_actions())


func prepare_normal_layout(compact: bool, encounter: bool = false) -> void:
	UiSizing.constant(self, &"separation", 6 if compact else 8)
	clear_rendered_content()
	var split := main_split()
	split.visible = true
	item_inspector_panel().visible = true
	alternate_content().visible = false
	trade_workspace().visible = false
	split.vertical = false
	split.size_flags_vertical = Control.SIZE_FILL if encounter else Control.SIZE_EXPAND_FILL
	if compact:
		UiSizing.minimum_size(split, Vector2(0.0, 282.0))
		UiSizing.minimum_size(item_browser_panel(), Vector2(390.0, 282.0))
		UiSizing.minimum_size(command_rail_panel(), Vector2(285.0, 282.0))
		UiSizing.minimum_size(item_inspector_panel(), Vector2(0.0, 190.0 if encounter else 130.0))
	else:
		main_split().custom_minimum_size = _authored_split_minimum
		item_browser_panel().custom_minimum_size = _authored_browser_minimum
		command_rail_panel().custom_minimum_size = _authored_rail_minimum
		item_inspector_panel().custom_minimum_size = _authored_inspector_minimum
	item_inspector_panel().size_flags_vertical = Control.SIZE_EXPAND_FILL if compact and encounter else Control.SIZE_FILL
	command_rail_content().set_item_actions(item_inspector_content().item_actions())


func prepare_alternate_layout() -> VBoxContainer:
	clear_rendered_content()
	main_split().visible = false
	item_inspector_panel().visible = false
	var alternate := alternate_content()
	alternate.visible = true
	empty_state().visible = false
	trade_workspace().visible = false
	return alternate


func prepare_trade_layout() -> InventoryTradeWorkspace:
	prepare_alternate_layout()
	alternate_content().visible = false
	var trade := trade_workspace()
	trade.visible = true
	return trade


func clear_rendered_content() -> void:
	item_browser_content().clear_dynamic_content()
	command_rail_content().clear_dynamic_content()
	item_inspector_content().clear_dynamic_content()
	empty_state().visible = false
	trade_workspace().visible = false
	for child: Node in alternate_content().get_children():
		if child != empty_state():
			alternate_content().remove_child(child)
			child.queue_free()
	item_detail_popover().clear_hover()
	for child: Node in get_children():
		if child not in [main_split(), item_inspector_panel(), alternate_content(), item_detail_popover(), trade_workspace()]:
			remove_child(child)
			child.queue_free()


func item_detail_popover() -> ClassicItemDetailPopover:
	return get_node("InventoryItemDetailPopover") as ClassicItemDetailPopover


func main_split() -> BoxContainer:
	return get_node("InventoryMainSplit") as BoxContainer


func item_browser_panel() -> PanelContainer:
	return get_node("InventoryMainSplit/InventoryItemBrowser") as PanelContainer


func command_rail_panel() -> PanelContainer:
	return get_node("InventoryMainSplit/InventoryCharacterCommandRail") as PanelContainer


func item_inspector_panel() -> PanelContainer:
	return get_node("InventoryItemInspector") as PanelContainer


func item_browser_content() -> InventoryItemBrowser:
	return item_browser_panel().get_node("InventoryItemBrowserContent") as InventoryItemBrowser


func command_rail_content() -> InventoryCommandRail:
	return command_rail_panel().get_node("InventoryCommandRailContent") as InventoryCommandRail


func item_inspector_content() -> InventoryItemInspector:
	return item_inspector_panel().get_node("InventoryItemInspectorContent") as InventoryItemInspector


func alternate_content() -> VBoxContainer:
	return get_node("InventoryAlternateContent") as VBoxContainer


func empty_state() -> InventoryEmptyState:
	return get_node("InventoryAlternateContent/InventoryEmptyState") as InventoryEmptyState


func trade_workspace() -> InventoryTradeWorkspace:
	return get_node("InventoryTradeWorkspace") as InventoryTradeWorkspace
