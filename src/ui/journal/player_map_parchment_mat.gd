## Frames the acquired map in the menu chrome: a thin inset border that hugs the map at every
## zoom. It replaced a tiled parchment mat, whose name the node and class still carry.

class_name PlayerMapParchmentMat
extends PanelContainer


func _init() -> void:
	name = "PlayerMapParchmentMat"
	theme_type_variation = &"ClassicInset"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


## The frame no longer grows with the map; the map canvas alone follows the zoom.
func set_map_zoom(_zoom: float) -> void:
	queue_sort()
