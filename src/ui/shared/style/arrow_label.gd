## Shows "before → after" text with the arrow drawn larger than the words around it.
## The interface font's arrow is narrow and low, so at small sizes it reads as a dot.

class_name ArrowLabel
extends HBoxContainer

const ARROW := "→"
const PART_SCENE := "res://src/ui/shared/style/arrow_label_part.tscn"

var _variation: StringName = &""


## Lays out `text`, splitting on " → "; `font_size` and `variation` style the words.
## `fit_width` lets the last part shorten with an ellipsis when the row is narrow.
func set_arrow_text(text: String, font_size: int, variation: StringName, fit_width: bool = false) -> void:
	_variation = variation
	add_theme_constant_override(&"separation", 4)
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var parts := text.split(" %s " % ARROW)
	for index: int in parts.size():
		if index > 0:
			add_child(_label(ARROW, roundi(font_size * 1.5), false))
		add_child(_label(parts[index], font_size, fit_width and index == parts.size() - 1))
	tooltip_text = text
	for child: Node in get_children():
		(child as Control).tooltip_text = text


func _label(text: String, size: int, shrinks: bool) -> Label:
	var label := (load(PART_SCENE) as PackedScene).instantiate() as Label
	label.text = text
	label.theme_type_variation = _variation
	label.add_theme_font_size_override(&"font_size", size)
	if shrinks:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.clip_text = true
	return label
