## Owns the complete, editor-visible Maps / Notes route composition.
class_name JournalScreen
extends ScreenFrame

const BODY_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody"


func _enter_tree() -> void:
	var back := get_node("WorkspaceColumn/WorkspaceHeader/RouteBackAction") as Button
	back.owner = null
	back.reparent(get_node("WorkspaceColumn/JournalFooter/BackHost"))
	back.owner = self
	UiSizing.minimum_size(back, Vector2(142.0, 34.0))
	workspace().get_node("MapsNotesSummary").visible = false


func workspace() -> MapsNotesWorkspace:
	return get_node(BODY_PATH + "/MapsNotesWorkspace") as MapsNotesWorkspace


func count_label() -> Label:
	return get_node("WorkspaceColumn/WorkspaceHeader/JournalCount") as Label


func prepare_for_render(compact: bool = false) -> void:
	workspace().visible = true
	workspace().prepare(compact)
	_alternate_content().visible = false


func prepare_alternate_layout() -> VBoxContainer:
	workspace().visible = false
	var alternate_content := _alternate_content()
	_clear_children(alternate_content)
	alternate_content.visible = true
	return alternate_content


func _alternate_content() -> VBoxContainer:
	return get_node(BODY_PATH + "/JournalAlternateContent") as VBoxContainer


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
