@tool
## Adds disposable representative content to the scene being edited.
extends RefCounted

var _sample_nodes: Array[Node] = []
var _sample_values: Array[Dictionary] = []


func populate_snapshot(edited: Node, records: Array) -> void:
	clear()
	if edited == null:
		return
	if edited is Control and (edited as Control).theme == null:
		var project_theme := load(String(ProjectSettings.get_setting("gui/theme/custom", ""))) as Theme
		if project_theme != null:
			_sample_property(edited, &"theme", project_theme)
	var geometry: Array[Dictionary] = []
	for value: Variant in records:
		var record := Dictionary(value)
		var path := String(record.get("path", ""))
		var target := edited if path == "." else edited.get_node_or_null(NodePath(path))
		if target == null and record.has("sampleScene"):
			var parent_path := path.get_base_dir()
			var parent := edited if parent_path.is_empty() or parent_path == "." else edited.get_node_or_null(NodePath(parent_path))
			var scene := load(String(record["sampleScene"])) as PackedScene
			if parent is Container and scene != null:
				target = scene.instantiate()
				target.name = path.get_file()
				parent.add_child(target)
				target.owner = null
				_sample_nodes.append(target)
		if target == null:
			continue
		for property: String in Dictionary(record.get("properties", {})):
			var encoded := String(record["properties"][property])
			var sample: Variant = _load_sample_resource(encoded.trim_prefix("resource:")) if encoded.begins_with("resource:") else str_to_var(encoded)
			if property in ["position", "size"]:
				geometry.append({"node": target, "property": StringName(property), "value": sample})
			else:
				_sample_property(target, StringName(property), sample)
		if record.has("editorIcon"):
			_add_editor_icon(target, String(record["editorIcon"]))
	for entry: Dictionary in geometry:
		_sample_property(entry["node"] as Node, entry["property"], entry["value"])


func _add_editor_icon(target: Node, resource_path: String) -> void:
	var stage := target.get_node_or_null("CommandMargin/CommandContent/IconStage") as Control
	var texture := _load_sample_resource(resource_path) as Texture2D
	if stage == null or texture == null:
		return
	var icon := TextureRect.new()
	icon.name = "__BuilderSampleIcon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = texture
	stage.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.owner = null
	_sample_nodes.append(icon)


func _load_sample_resource(resource_path: String) -> Resource:
	if resource_path.begins_with("res://addons/realmz_builder/editor_sample_media/") and resource_path.ends_with(".png"):
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(resource_path)) == OK:
			return ImageTexture.create_from_image(image)
		return null
	return load(resource_path)


func clear() -> void:
	for sample: Node in _sample_nodes:
		if is_instance_valid(sample) and sample.get_parent() != null:
			sample.get_parent().remove_child(sample)
			sample.queue_free()
	_sample_nodes.clear()
	for entry: Dictionary in _sample_values:
		var node: Variant = entry["node"]
		if is_instance_valid(node) and node is Node and node.get(entry["property"]) == entry["sample"]:
			node.set(entry["property"], entry["original"])
			if node is ClassicBitmapButton or node is ClassicSearchCommandButton or node is ClassicTorchCommandButton:
				(node as Control).queue_redraw()
	_sample_values.clear()


func _sample_property(target: Node, property: StringName, sample: Variant) -> void:
	if property == &"size" and target is Control and sample is Vector2:
		var control := target as Control
		if not is_equal_approx(control.anchor_left, control.anchor_right) or not is_equal_approx(control.anchor_top, control.anchor_bottom):
			var difference: Vector2 = sample - control.size
			if not is_zero_approx(difference.x):
				_sample_property(control, &"offset_right", control.offset_right + difference.x)
			if not is_zero_approx(difference.y):
				_sample_property(control, &"offset_bottom", control.offset_bottom + difference.y)
			return
	var before: Variant = target.get(property)
	if before == sample or sample == null:
		return
	if before is Array or before is Dictionary: before = before.duplicate(true)
	if sample is Array or sample is Dictionary: sample = sample.duplicate(true)
	target.set(property, sample)
	_sample_values.append({"node": target, "property": property, "original": before, "sample": target.get(property)})
