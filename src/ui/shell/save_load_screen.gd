## Centers the Save & Load workspace over the retained adventure stage.
class_name SaveLoadScreen
extends SystemScreen

@export var preferred_size := Vector2(1016.0, 586.0)
@export var window_fraction := Vector2(0.9, 0.9)


func set_workspace_rect(workspace_rect: Rect2) -> void:
	var profile := UiSizing.profile_for(self)
	var interface_scale := profile.ui_scale if profile != null else 1.0
	var preferred := preferred_size * interface_scale
	var desired := workspace_rect.size * window_fraction
	var available := workspace_rect.size - Vector2(32.0, 20.0) * interface_scale
	var modal_size := Vector2(minf(maxf(preferred.x, desired.x), available.x), minf(maxf(preferred.y, desired.y), available.y))
	position = workspace_rect.position + (workspace_rect.size - modal_size) * 0.5
	size = modal_size
	_update_back_visibility()
