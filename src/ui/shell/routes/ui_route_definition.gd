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
@export_file("*.tscn") var workspace_scene_path: String


func is_workspace() -> bool:
	return presentation == Presentation.WORKSPACE


func has_workspace_scene() -> bool:
	return not workspace_scene_path.is_empty()


func load_workspace_scene() -> PackedScene:
	return load(workspace_scene_path) as PackedScene if has_workspace_scene() else null
