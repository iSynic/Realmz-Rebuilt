## Binds one authored menu action and its pointer/controller focus marker.
class_name MainMenuAction
extends Button

@onready var _marker: ColorRect = %FocusMarker
var _ui_scale := 1.0
var _marker_scale := 1


func _ready() -> void:
	mouse_entered.connect(grab_focus)
	focus_entered.connect(_update_marker)
	focus_exited.connect(_update_marker)
	resized.connect(_update_marker)
	_update_marker()


func apply_ui_sizing(profile: UiLayoutProfile) -> void:
	_ui_scale = profile.ui_scale
	_marker_scale = profile.bitmap_scale
	if is_node_ready(): _update_marker()


func _update_marker() -> void:
	_marker.size = Vector2.ONE * 5.0 * _marker_scale
	_marker.position = Vector2(18.0 * _ui_scale, (size.y - _marker.size.y) * 0.5)
	_marker.color = Color("152131") if has_focus() else Color("6d818f")
