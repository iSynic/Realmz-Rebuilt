## Owns the reusable, editor-authored Inventory and Trade workspace regions.
class_name InventoryWorkspace
extends VBoxContainer

@export var empty_state_scene: PackedScene
@export var trade_workspace_scene: PackedScene


func prepare_normal_layout(compact: bool) -> void:
	clear_rendered_content()
	var split := main_split()
	split.visible = true
	item_inspector_panel().visible = true
	alternate_content().visible = false
	split.vertical = false
	split.custom_minimum_size.y = 300.0 if compact else 410.0
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_browser_panel().custom_minimum_size = Vector2(390.0 if compact else 620.0, 300.0 if compact else 330.0)
	command_rail_panel().custom_minimum_size = Vector2(285.0, 300.0 if compact else 330.0)
	item_inspector_panel().custom_minimum_size.y = 130.0 if compact else 150.0


func prepare_alternate_layout() -> VBoxContainer:
	clear_rendered_content()
	main_split().visible = false
	item_inspector_panel().visible = false
	var alternate := alternate_content()
	alternate.visible = true
	return alternate


func clear_rendered_content() -> void:
	item_browser_content().clear_dynamic_content()
	command_rail_content().clear_dynamic_content()
	item_inspector_content().clear_dynamic_content()
	_clear_children(alternate_content())
	for child: Node in get_children():
		if child not in [main_split(), item_inspector_panel(), alternate_content()]:
			remove_child(child)
			child.queue_free()


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


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
