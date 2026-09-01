class_name PlayerMapParchmentMat
extends PanelContainer

const PARCHMENT_TEXTURE_PATH := "res://src/presentation/assets/ui/map-parchment-tile.png"
const BASE_MAP_SIZE := 320.0
const BORDER_RATIO := 0.125

var _style := StyleBoxTexture.new()


func _init() -> void:
	name = "PlayerMapParchmentMat"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style.texture = load(PARCHMENT_TEXTURE_PATH) as Texture2D
	_style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	_style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	add_theme_stylebox_override("panel", _style)
	set_map_zoom(1.0)


func set_map_zoom(zoom: float) -> void:
	var border := border_size(zoom)
	_style.content_margin_left = border
	_style.content_margin_top = border
	_style.content_margin_right = border
	_style.content_margin_bottom = border
	queue_sort()
	queue_redraw()


static func border_size(zoom: float) -> float:
	return roundf(BASE_MAP_SIZE * BORDER_RATIO * clampf(zoom, 1.0, 4.0))
