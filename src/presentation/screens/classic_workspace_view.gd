class_name ClassicWorkspaceView
extends PanelContainer

@onready var scroll: ScrollContainer = %ScreenBodyScroll
@onready var body: VBoxContainer = %ScreenBody


func set_workspace_rect(workspace_rect: Rect2) -> void:
	position = workspace_rect.position + Vector2(8.0, 8.0)
	size = workspace_rect.size - Vector2(16.0, 16.0)
