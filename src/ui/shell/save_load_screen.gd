## Centers the Save & Load workspace over the retained adventure stage.
class_name SaveLoadScreen
extends SystemScreen


func set_workspace_rect(workspace_rect: Rect2) -> void:
	var modal_size := Vector2(minf(1016.0, workspace_rect.size.x - 32.0), minf(586.0, workspace_rect.size.y - 20.0))
	position = workspace_rect.position + (workspace_rect.size - modal_size) * 0.5
	size = modal_size
	_update_back_visibility()
