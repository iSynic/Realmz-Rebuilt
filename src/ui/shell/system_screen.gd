## Owns the complete, editor-visible Preferences and Game route composition.
class_name SystemScreen
extends ScreenFrame

const BODY_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody"


func workspace() -> SystemWorkspace:
	return get_node(BODY_PATH + "/SystemWorkspace") as SystemWorkspace


func prepare_for_render(compact: bool = false) -> void:
	workspace().visible = true
	workspace().prepare(compact)
	_alternate_content().visible = false


func prepare_alternate_layout() -> VBoxContainer:
	workspace().visible = false
	var alternate := _alternate_content()
	_clear(alternate)
	alternate.visible = true
	return alternate


func _alternate_content() -> VBoxContainer:
	return get_node(BODY_PATH + "/SystemAlternateContent") as VBoxContainer


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
