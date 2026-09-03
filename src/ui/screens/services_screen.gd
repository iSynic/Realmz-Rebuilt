## Owns the complete, editor-visible Party Wealth route composition.
class_name ServicesScreen
extends ScreenFrame

const WORKSPACE_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody/ServicesWorkspace"


func prepare_for_render(compact: bool) -> void:
	workspace().prepare(compact)


func workspace() -> ServicesWorkspace:
	return get_node(WORKSPACE_PATH) as ServicesWorkspace
