## Owns the stable, editor-visible tabs and content regions of Maps / Notes.
class_name JournalScreen
extends ScreenFrame

const BODY_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody"


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
	_clear_children(places_area())
	_clear_children(maps_area())
	_clear_children(journal_area())
	_clear_children(_alternate_content())
	for child: Node in body_control().get_children():
		if child not in [summary_area(), tabs(), _alternate_content()]:
			body_control().remove_child(child)
			child.queue_free()


func summary_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/MapsNotesSummary") as VBoxContainer


func tabs() -> TabContainer:
	return get_node(BODY_PATH + "/MapsNotesTabs") as TabContainer


func places_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/MapsNotesTabs/Places") as VBoxContainer


func maps_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/MapsNotesTabs/Maps") as VBoxContainer


func journal_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/MapsNotesTabs/Journal") as VBoxContainer


func _alternate_content() -> VBoxContainer:
	return get_node(BODY_PATH + "/JournalAlternateContent") as VBoxContainer


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
