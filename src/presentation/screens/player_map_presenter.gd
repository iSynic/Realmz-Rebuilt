class_name PlayerMapPresenter
extends VBoxContainer


func present(view: PlayerMapView, media: PackageMediaCatalog) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	if view == null:
		return
	var title := Label.new()
	title.text = view.name
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("d5b45d"))
	add_child(title)
	if view.mode == PlayerMapDefinition.SCROLLING_TEXT:
		var text := RichTextLabel.new()
		text.name = "PlayerMapScrollingText"
		text.custom_minimum_size = Vector2(320, 320)
		text.fit_content = false
		text.bbcode_enabled = false
		var asset: PackageMediaAsset = media.asset_by_id(view.scrolling_text_asset_id) if media != null else null
		text.text = media.read_bytes(asset).get_string_from_utf8() if asset != null else "Scrolling map text is unavailable."
		add_child(text)
	else:
		var canvas := PlayerMapCanvas.new()
		canvas.name = "PlayerMapCanvas"
		canvas.present(view, media)
		add_child(canvas)
		if not view.note.is_empty():
			var note := Label.new()
			note.name = "PlayerMapNote"
			note.text = view.note
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			add_child(note)
