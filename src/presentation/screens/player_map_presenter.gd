class_name PlayerMapPresenter
extends VBoxContainer

signal scrolling_text_finished

const ClassicScrollingTextSurfaceType := preload("res://src/presentation/screens/classic_scrolling_text_surface.gd")

var _canvas: PlayerMapCanvas


func present(view: PlayerMapView, media: ClassicMediaCatalog) -> void:
	_canvas = null
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	if view == null:
		return
	if view.mode == PlayerMapDefinition.SCROLLING_TEXT:
		var surface := ClassicScrollingTextSurfaceType.new() as ClassicScrollingTextSurface
		surface.custom_minimum_size = Vector2(320, 320)
		surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
		surface.configure(media, &"PlayerMapScrollingText")
		surface.double_click_requested.connect(func() -> void: scrolling_text_finished.emit())
		var asset: MediaAsset = media.asset_by_id(view.scrolling_text_asset_id) if media != null else null
		surface.present_asset(asset, "Scrolling map text is unavailable.")
		add_child(surface)
	else:
		var canvas := PlayerMapCanvas.new()
		canvas.name = "PlayerMapCanvas"
		canvas.present(view, media)
		_canvas = canvas
		add_child(canvas)


func set_map_zoom(zoom: float) -> void:
	if _canvas != null:
		_canvas.set_zoom(zoom)


func map_zoom() -> float:
	return _canvas.zoom() if _canvas != null else 1.0
