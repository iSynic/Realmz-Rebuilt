## Owns the stable list-and-detail layout shared by Allies and Bestiary screens.
class_name CreatureLibraryScreen
extends ScreenFrame

const BODY_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody"

@export var creature_row_scene: PackedScene


func prepare_for_render(compact: bool) -> void:
	_clear_children(list_rows())
	var columns := columns_control()
	columns.vertical = compact
	list_panel().custom_minimum_size = Vector2(248.0, 150.0 if compact else 0.0)
	state_cards().vertical = compact
	detail_record().visible = false
	empty_state().visible = false


func columns_control() -> BoxContainer:
	return get_node(BODY_PATH + "/CreatureColumns") as BoxContainer


func list_panel() -> PanelContainer:
	return get_node(BODY_PATH + "/CreatureColumns/CreatureListPanel") as PanelContainer


func detail_panel() -> PanelContainer:
	return get_node(BODY_PATH + "/CreatureColumns/CreatureDetailPanel") as PanelContainer


func list_title() -> Label:
	return get_node(BODY_PATH + "/CreatureColumns/CreatureListPanel/ListContent/CreatureListTitle") as Label


func list_rows() -> VBoxContainer:
	return get_node(BODY_PATH + "/CreatureColumns/CreatureListPanel/ListContent/CreatureListScroll/CreatureListRows") as VBoxContainer


func detail_record() -> VBoxContainer:
	return get_node(BODY_PATH + "/CreatureColumns/CreatureDetailPanel/DetailContent/CreatureRecord") as VBoxContainer


func empty_state() -> VBoxContainer:
	return get_node(BODY_PATH + "/CreatureColumns/CreatureDetailPanel/DetailContent/CreatureEmptyState") as VBoxContainer


func facts() -> GridContainer:
	return get_node(BODY_PATH + "/CreatureColumns/CreatureDetailPanel/DetailContent/CreatureRecord/CreatureFacts") as GridContainer


func state_cards() -> BoxContainer:
	return get_node(BODY_PATH + "/CreatureColumns/CreatureDetailPanel/DetailContent/CreatureRecord/CreatureStateCards") as BoxContainer


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
