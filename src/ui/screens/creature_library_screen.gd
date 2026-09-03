## Owns the stable list-and-detail layout shared by Allies and Bestiary screens.
class_name CreatureLibraryScreen
extends ScreenFrame

const BODY_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody"


func prepare_for_render(compact: bool) -> void:
	_clear_children(list_panel())
	_clear_children(detail_panel())
	var columns := columns_control()
	columns.vertical = compact
	list_panel().custom_minimum_size = Vector2(248.0, 150.0 if compact else 0.0)


func columns_control() -> BoxContainer:
	return get_node(BODY_PATH + "/CreatureColumns") as BoxContainer


func list_panel() -> PanelContainer:
	return get_node(BODY_PATH + "/CreatureColumns/CreatureListPanel") as PanelContainer


func detail_panel() -> PanelContainer:
	return get_node(BODY_PATH + "/CreatureColumns/CreatureDetailPanel") as PanelContainer


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
