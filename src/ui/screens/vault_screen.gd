## Owns the stable, editor-visible list, history, and inspection regions of Character Files.
class_name VaultScreen
extends ScreenFrame

const BODY_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody"

@export var character_sheet_scene: PackedScene


func prepare_list_layout() -> void:
	clear_rendered_content()
	header_area().visible = true
	list_area().visible = true
	history_area().visible = true
	inspection_area().visible = false


func prepare_inspection_layout() -> VBoxContainer:
	clear_rendered_content()
	header_area().visible = false
	list_area().visible = false
	history_area().visible = false
	var inspection := inspection_area()
	inspection.visible = true
	return inspection


func clear_rendered_content() -> void:
	_clear_children(header_area())
	_clear_children(list_area())
	_clear_children(history_area())
	_clear_children(inspection_area())
	for child: Node in body_control().get_children():
		if child not in [header_area(), list_area(), history_area(), inspection_area()]:
			body_control().remove_child(child)
			child.queue_free()


func header_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/VaultHeaderArea") as VBoxContainer


func list_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/VaultListArea") as VBoxContainer


func history_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/VaultHistoryArea") as VBoxContainer


func inspection_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/VaultInspectionArea") as VBoxContainer


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
