## Owns the stable, editor-visible regions of the ordinary Inventory screen.
class_name InventoryScreen
extends ScreenFrame

const BODY_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody"


func prepare_normal_layout(compact: bool) -> void:
	clear_rendered_content()
	var main_split := _main_split()
	main_split.visible = true
	item_inspector_panel().visible = true
	_alternate_content().visible = false
	main_split.custom_minimum_size.y = 300.0 if compact else 410.0
	main_split.size_flags_vertical = Control.SIZE_FILL if compact else Control.SIZE_EXPAND_FILL


func prepare_alternate_layout() -> VBoxContainer:
	clear_rendered_content()
	_main_split().visible = false
	item_inspector_panel().visible = false
	var alternate_content := _alternate_content()
	alternate_content.visible = true
	return alternate_content


func clear_rendered_content() -> void:
	item_browser_content().clear_dynamic_content()
	command_rail_content().clear_dynamic_content()
	item_inspector_content().clear_dynamic_content()
	_clear_children(_alternate_content())
	for child: Node in body_control().get_children():
		if child not in [_main_split(), item_inspector_panel(), _alternate_content()]:
			body_control().remove_child(child)
			child.queue_free()


func item_browser_panel() -> PanelContainer:
	return get_node(BODY_PATH + "/InventoryMainSplit/InventoryItemBrowser") as PanelContainer


func command_rail_panel() -> PanelContainer:
	return get_node(BODY_PATH + "/InventoryMainSplit/InventoryCharacterCommandRail") as PanelContainer


func item_inspector_panel() -> PanelContainer:
	return get_node(BODY_PATH + "/InventoryItemInspector") as PanelContainer


func item_browser_content() -> InventoryItemBrowser:
	return item_browser_panel().get_node("InventoryItemBrowserContent") as InventoryItemBrowser


func command_rail_content() -> InventoryCommandRail:
	return command_rail_panel().get_node("InventoryCommandRailContent") as InventoryCommandRail


func item_inspector_content() -> InventoryItemInspector:
	return item_inspector_panel().get_node("InventoryItemInspectorContent") as InventoryItemInspector


func _main_split() -> HBoxContainer:
	return get_node(BODY_PATH + "/InventoryMainSplit") as HBoxContainer


func _alternate_content() -> VBoxContainer:
	return get_node(BODY_PATH + "/InventoryAlternateContent") as VBoxContainer


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
