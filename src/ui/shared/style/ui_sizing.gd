## Applies resolved presentation metrics to retained, scene-authored controls.
class_name UiSizing
extends RefCounted

const PROFILE := &"ui_sizing_profile"
const BASELINE := &"ui_sizing_baseline"


static func apply(root: Control, profile: UiLayoutProfile) -> void:
	root.set_meta(PROFILE, profile)
	_apply_branch(root, profile)


static func apply_detached(root: Control, profile: UiLayoutProfile) -> void:
	if profile_for(root.get_parent()) == null:
		apply(root, profile)


static func profile_for(node: Node) -> UiLayoutProfile:
	var current := node
	while current != null:
		if current.has_meta(PROFILE):
			return current.get_meta(PROFILE) as UiLayoutProfile
		current = current.get_parent()
	return null


static func bind_added(instance_id: int) -> void:
	if not is_instance_id_valid(instance_id): return
	var node := instance_from_id(instance_id) as Node
	if node == null: return
	var profile := profile_for(node)
	if profile != null:
		_apply_branch(node, profile, true)


static func font_size(control: Control, key: StringName, baseline: int) -> void:
	var metrics := _baseline(control)
	(metrics["fonts"] as Dictionary)[key] = baseline
	var profile := profile_for(control)
	_set_font_size(control, key, maxi(1, roundi(baseline * (profile.font_scale if profile != null else 1.0))))


static func minimum_size(control: Control, baseline: Vector2) -> void:
	_baseline(control)["minimum"] = baseline
	var profile := profile_for(control)
	control.custom_minimum_size = baseline * (profile.ui_scale if profile != null else 1.0)


static func constant(control: Control, key: StringName, baseline: int) -> void:
	var metrics := _baseline(control)
	(metrics["constants"] as Dictionary)[key] = baseline
	var profile := profile_for(control)
	_set_constant(control, key, roundi(baseline * (profile.ui_scale if profile != null else 1.0)))


static func artwork(control: TextureRect, native: Texture2D) -> void:
	control.texture = native
	var profile := profile_for(control)
	if profile != null: _scale_artwork(control, _baseline(control), profile.bitmap_scale)


static func _apply_branch(node: Node, profile: UiLayoutProfile, added_only: bool = false) -> void:
	if node is Control:
		var control := node as Control
		if control.has_meta(PROFILE): control.set_meta(PROFILE, profile)
		var metrics := _baseline(control)
		var scale_key := Vector3(profile.ui_scale, profile.font_scale, profile.bitmap_scale)
		if not added_only or control is TextureRect or metrics.get("applied_profile") != scale_key:
			control.custom_minimum_size = Vector2(metrics["minimum"]) * profile.ui_scale
			if control is TextureRect:
				var image := control as TextureRect
				var authored: Vector2 = metrics["minimum"]
				if image.stretch_mode in [TextureRect.STRETCH_KEEP, TextureRect.STRETCH_KEEP_CENTERED, TextureRect.STRETCH_KEEP_ASPECT_CENTERED] and authored.x > 0.0 and authored.y > 0.0 and authored.x <= 96.0 and authored.y <= 96.0:
					control.custom_minimum_size = authored * profile.bitmap_scale
					_scale_artwork(image, metrics, profile.bitmap_scale)
			for key: StringName in metrics["fonts"]:
				_set_font_size(control, key, maxi(1, roundi(int(metrics["fonts"][key]) * profile.font_scale)))
			for key: StringName in metrics["constants"]:
				_set_constant(control, key, roundi(int(metrics["constants"][key]) * profile.ui_scale))
			for key: StringName in metrics["styles"]:
				if metrics.get("style_scale", 1.0) == profile.ui_scale and control.get_theme_stylebox(key) == metrics["applied_styles"].get(key): continue
				var style := (metrics["styles"][key] as StyleBox).duplicate() as StyleBox
				for side: String in ["left", "top", "right", "bottom"]:
					var margin := "content_margin_" + side
					if float(style.get(margin)) >= 0.0: style.set(margin, float(style.get(margin)) * profile.ui_scale)
				control.add_theme_stylebox_override(key, style)
				metrics["applied_styles"][key] = style
			metrics["style_scale"] = profile.ui_scale
			if metrics.has("offsets"):
				var offsets: Vector4 = metrics["offsets"]
				control.offset_left = offsets.x * profile.ui_scale
				control.offset_top = offsets.y * profile.ui_scale
				control.offset_right = offsets.z * profile.ui_scale
				control.offset_bottom = offsets.w * profile.ui_scale
			metrics["applied_profile"] = scale_key
	for child: Node in node.get_children():
		_apply_branch(child, profile, added_only)
	if node.has_method("apply_ui_sizing"):
		node.call("apply_ui_sizing", profile)


static func _set_font_size(control: Control, key: StringName, value: int) -> void:
	if not control.has_theme_font_size_override(key) or control.get_theme_font_size(key) != value:
		control.add_theme_font_size_override(key, value)


static func _set_constant(control: Control, key: StringName, value: int) -> void:
	if not control.has_theme_constant_override(key) or control.get_theme_constant(key) != value:
		control.add_theme_constant_override(key, value)


static func _scale_artwork(control: TextureRect, metrics: Dictionary, scale: int) -> void:
	if control.texture == null: return
	if control.texture != metrics.get("scaled_artwork"):
		metrics["native_artwork"] = control.texture
	var native := metrics["native_artwork"] as Texture2D
	control.custom_minimum_size = Vector2(metrics["minimum"]).max(native.get_size()) * scale
	if metrics.get("artwork_scale", 0) != scale or control.texture != metrics.get("scaled_artwork"):
		var cache: Dictionary = metrics.get("artwork_cache", {})
		var key := Vector2i(native.get_instance_id(), scale)
		if not cache.has(key):
			var source_image := native.get_image()
			if source_image == null or source_image.is_empty(): return
			var image := source_image.duplicate() as Image
			image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
			cache[key] = ImageTexture.create_from_image(image)
		metrics["artwork_cache"] = cache
		metrics["scaled_artwork"] = cache[key]
		metrics["artwork_scale"] = scale
	control.texture = metrics["scaled_artwork"] as Texture2D
	control.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED


static func _baseline(control: Control) -> Dictionary:
	if control.has_meta(BASELINE):
		return control.get_meta(BASELINE) as Dictionary
	var fonts: Dictionary = {}
	var constants: Dictionary = {}
	var styles: Dictionary = {}
	var applied_styles: Dictionary = {}
	for property: Dictionary in control.get_property_list():
		if not (int(property["usage"]) & PROPERTY_USAGE_STORAGE): continue
		var name := String(property["name"])
		if not name.begins_with("theme_override_"): continue
		if name.begins_with("theme_override_font_sizes/"):
			var key := StringName(name.get_slice("/", 1))
			if control.has_theme_font_size_override(key): fonts[key] = control.get(name)
		elif name.begins_with("theme_override_constants/"):
			var key := StringName(name.get_slice("/", 1))
			if control.has_theme_constant_override(key): constants[key] = control.get(name)
		elif name.begins_with("theme_override_styles/"):
			var key := StringName(name.get_slice("/", 1))
			if control.has_theme_stylebox_override(key):
				applied_styles[key] = control.get(name)
				styles[key] = (applied_styles[key] as StyleBox).duplicate()
	var result := {"minimum": control.custom_minimum_size, "fonts": fonts, "constants": constants, "styles": styles, "applied_styles": applied_styles}
	if control.owner != null and control.scene_file_path.is_empty() and control.get_parent() is Control and not control.get_parent() is Container:
		result["offsets"] = Vector4(control.offset_left, control.offset_top, control.offset_right, control.offset_bottom)
	control.set_meta(BASELINE, result)
	return result
