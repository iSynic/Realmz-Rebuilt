## Owns the stable, editor-visible regions of the ordinary Inventory screen.
class_name InventoryScreen
extends ScreenFrame

const WORKSPACE_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody/InventoryWorkspace"


func prepare_normal_layout(compact: bool) -> void:
	workspace().prepare_normal_layout(compact)


func prepare_alternate_layout() -> VBoxContainer:
	return workspace().prepare_alternate_layout()


func clear_rendered_content() -> void:
	workspace().clear_rendered_content()


func workspace() -> InventoryWorkspace:
	return get_node(WORKSPACE_PATH) as InventoryWorkspace


func item_browser_panel() -> PanelContainer:
	return workspace().item_browser_panel()


func command_rail_panel() -> PanelContainer:
	return workspace().command_rail_panel()


func item_inspector_panel() -> PanelContainer:
	return workspace().item_inspector_panel()


func item_browser_content() -> InventoryItemBrowser:
	return workspace().item_browser_content()


func command_rail_content() -> InventoryCommandRail:
	return workspace().command_rail_content()


func item_inspector_content() -> InventoryItemInspector:
	return workspace().item_inspector_content()
