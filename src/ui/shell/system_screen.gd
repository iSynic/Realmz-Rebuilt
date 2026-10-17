## Owns the complete, editor-visible Preferences and Game route composition.
class_name SystemScreen
extends ScreenFrame

const BODY_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody"


func set_workspace_rect(workspace_rect: Rect2) -> void:
	super.set_workspace_rect(workspace_rect)
	if route_id != &"system":
		return
	var profile := UiSizing.profile_for(self)
	var compact := profile != null and profile.id == UiLayoutProfile.COMPACT
	var inset := Vector2(8, 8) if compact else Vector2(64, 36)
	position = workspace_rect.position + inset
	size = workspace_rect.size - inset * 2
	(get_node("WorkspaceColumn/WorkspaceHeader") as BoxContainer).vertical = false
	(get_node("WorkspaceColumn/WorkspaceHeader/ScreenDescription") as Label).hide()
	(get_node("WorkspaceColumn/WorkspaceHeader/ScreenTitle") as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_mode_title(save_mode: bool) -> void:
	(get_node("WorkspaceColumn/WorkspaceHeader/ScreenTitle") as Label).text = "Save & Load" if save_mode else "Settings"
	(get_node("WorkspaceColumn/WorkspaceHeader/ScreenDescription") as Label).text = "Ten scenario slots. Quick Save overwrites the active slot." if save_mode else ""


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
