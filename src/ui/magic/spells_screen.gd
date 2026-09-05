## Owns the stable, editor-visible controls and content regions of the Spells screen.
class_name SpellsScreen
extends ScreenFrame

const WORKSPACE_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody/SpellsWorkspace"


func workspace() -> SpellsWorkspace:
	return get_node(WORKSPACE_PATH) as SpellsWorkspace
