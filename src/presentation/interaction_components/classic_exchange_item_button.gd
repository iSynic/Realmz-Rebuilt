class_name ClassicExchangeItemButton
extends Button

var drag_payload: Dictionary = {}


func configure_drag(payload: Dictionary) -> void:
	drag_payload = payload.duplicate(true)
	mouse_default_cursor_shape = Control.CURSOR_DRAG if not disabled else Control.CURSOR_FORBIDDEN


func _get_drag_data(_position: Vector2) -> Variant:
	if disabled or drag_payload.is_empty():
		return null
	var preview := Label.new()
	preview.text = text.get_slice("\n", 0)
	preview.add_theme_constant_override("outline_size", 4)
	preview.add_theme_color_override("font_outline_color", Color("111315"))
	set_drag_preview(preview)
	return drag_payload.duplicate(true)
