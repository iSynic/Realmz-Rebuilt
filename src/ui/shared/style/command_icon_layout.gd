## Sizes the existing command scene for a caption-free modular icon slot.
class_name CommandIconLayout
extends RefCounted


static func apply(button: BaseButton, native_size: Vector2, art_scale: int, padding: int) -> void:
	var modular := art_scale > 0
	var margin := button.get_node("CommandMargin") as MarginContainer
	var stage := button.get_node("CommandMargin/CommandContent/IconStage") as Control
	var caption := button.get_node("CommandMargin/CommandContent/CaptionBand") as Control
	caption.visible = not modular
	var keys: Array[StringName] = [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]
	for index: int in keys.size():
		if modular:
			margin.add_theme_constant_override(keys[index], padding)
		else:
			UiSizing.constant(margin, keys[index], [4, 3, 4, 5][index])
	if modular:
		stage.custom_minimum_size = native_size * art_scale
		button.custom_minimum_size = stage.custom_minimum_size + Vector2.ONE * padding * 2
	button.update_minimum_size()
	button.queue_redraw()
