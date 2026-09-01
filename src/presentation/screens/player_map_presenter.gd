class_name PlayerMapPresenter
extends VBoxContainer

var _canvas: PlayerMapCanvas


func present(view: PlayerMapView, media: ClassicMediaCatalog) -> void:
	_canvas = null
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	if view == null:
		return
	if view.mode == PlayerMapDefinition.SCROLLING_TEXT:
		var text := RichTextLabel.new()
		text.name = "PlayerMapScrollingText"
		text.custom_minimum_size = Vector2(320, 320)
		text.fit_content = false
		text.bbcode_enabled = false
		var asset: MediaAsset = media.asset_by_id(view.scrolling_text_asset_id) if media != null else null
		text.text = media.read_bytes(asset).get_string_from_utf8() if asset != null else "Scrolling map text is unavailable."
		add_child(text)
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
