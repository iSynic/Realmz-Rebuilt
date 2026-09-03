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
	_clear_children(item_browser_panel())
	_clear_children(command_rail_panel())
	_clear_children(item_inspector_panel())
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


func _main_split() -> HBoxContainer:
	return get_node(BODY_PATH + "/InventoryMainSplit") as HBoxContainer


func _alternate_content() -> VBoxContainer:
	return get_node(BODY_PATH + "/InventoryAlternateContent") as VBoxContainer


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
