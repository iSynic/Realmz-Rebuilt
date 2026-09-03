## Defines one editor-authored shell mode or mounted application workspace.
class_name UiRouteDefinition
extends Resource

enum Presentation {
	SHELL_MODE,
	WORKSPACE,
}

@export var route_id: StringName
@export var label: String
@export var shortcut: StringName
@export var primary: bool
@export_multiline var description: String
@export var presentation: Presentation = Presentation.WORKSPACE
@export var workspace_scene: PackedScene


func is_workspace() -> bool:
	return presentation == Presentation.WORKSPACE
