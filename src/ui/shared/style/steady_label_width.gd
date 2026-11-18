## Keeps a label as wide as the longest number it may show, so ticking digits do not push its neighbours.

class_name SteadyLabelWidth
extends RefCounted


## Sets the text and reserves the width of `widest`, a sample of the longest text, measured with
## every digit as wide as the font's widest digit. Empty text reserves nothing.
static func apply(label: Label, text: String, widest: String) -> void:
	label.text = text
	if text.is_empty():
		label.custom_minimum_size.x = 0.0
		return
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	var digit_width := 0.0
	for digit: int in 10:
		digit_width = maxf(digit_width, font.get_string_size(str(digit), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var digits := 0
	var lettering := ""
	for index: int in widest.length():
		if widest[index].is_valid_int():
			digits += 1
		else:
			lettering += widest[index]
	label.custom_minimum_size.x = ceilf(font.get_string_size(lettering, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + digits * digit_width)
