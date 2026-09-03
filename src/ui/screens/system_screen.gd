## Owns the stable, editor-visible tabs and content regions of Preferences and Game.
class_name SystemScreen
extends ScreenFrame

const BODY_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody"
const TAB_PATH := BODY_PATH + "/SystemWorkspaceTabs"


func prepare_for_render() -> void:
	clear_rendered_content()
	summary_area().visible = true
	tabs().visible = true
	_alternate_content().visible = false


func prepare_alternate_layout() -> VBoxContainer:
	clear_rendered_content()
	summary_area().visible = false
	tabs().visible = false
	var alternate_content := _alternate_content()
	alternate_content.visible = true
	return alternate_content


func clear_rendered_content() -> void:
	_clear_children(summary_area())
	for tab: VBoxContainer in tab_areas():
		_clear_children(tab)
	_clear_children(_alternate_content())
	for child: Node in body_control().get_children():
		if child not in [summary_area(), tabs(), _alternate_content()]:
			body_control().remove_child(child)
			child.queue_free()


func summary_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/SystemSummary") as VBoxContainer


func tabs() -> TabContainer:
	return get_node(TAB_PATH) as TabContainer


func tab_area(tab_name: String) -> VBoxContainer:
	return get_node(TAB_PATH + "/" + tab_name) as VBoxContainer


func tab_areas() -> Array[VBoxContainer]:
	var result: Array[VBoxContainer] = []
	for child: Node in tabs().get_children():
		if child is VBoxContainer:
			result.append(child as VBoxContainer)
	return result


func _alternate_content() -> VBoxContainer:
	return get_node(BODY_PATH + "/SystemAlternateContent") as VBoxContainer


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
