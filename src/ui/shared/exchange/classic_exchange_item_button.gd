## Presents the dynamic Classic exchange item button interaction without owning gameplay state.

class_name ClassicExchangeItemButton
extends Button

const DRAG_PREVIEW_SCENE_PATH := "res://src/ui/shared/exchange/classic_exchange_drag_preview.tscn"

var drag_payload: Dictionary = {}


func configure_drag(payload: Dictionary) -> void:
	drag_payload = payload.duplicate(true)
	mouse_default_cursor_shape = Control.CURSOR_DRAG if not disabled else Control.CURSOR_FORBIDDEN


func _get_drag_data(_position: Vector2) -> Variant:
	return create_drag_data(_position)


func create_drag_data(_position: Vector2) -> Variant:
	if disabled or drag_payload.is_empty():
		return null
	# The dragged item is a half-transparent copy of its whole row, held where it was grabbed.
	var preview := (load(DRAG_PREVIEW_SCENE_PATH) as PackedScene).instantiate() as Label
	var row := get_parent() as Control
	if row == null:
		preview.text = text.get_slice("\n", 0)
	else:
		var card := row.duplicate(0) as Control
		card.size = row.size
		card.position = -(position + _position)
		card.modulate.a = 0.5
		preview.add_child(card)
	# Above the service panels, which sit on a raised layer and would otherwise cover it.
	preview.z_index = 4000
	set_drag_preview(preview)
	return drag_payload.duplicate(true)
