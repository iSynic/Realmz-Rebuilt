class_name ClassicSpellSelectionChrome
extends RefCounted

const LEVEL_COLORS: Array[Color] = [
	Color("f4df58"), Color("efcf45"), Color("eabb3e"), Color("e59d39"),
	Color("df7c36"), Color("d95e36"), Color("d34439"),
]


static func level_button(level: int, selected: bool, enabled: bool, action: Callable, unavailable_text: String) -> Button:
	var button := Button.new()
	button.name = "SpellLevel%d" % level
	button.text = "Level %d" % level
	button.theme_type_variation = &"ClassicChoiceButton"
	button.toggle_mode = true
	button.button_pressed = selected
	button.disabled = not enabled
	button.custom_minimum_size = Vector2(68.0, 31.0)
	button.tooltip_text = unavailable_text if button.disabled else "Show level %d spells" % level
	var color := LEVEL_COLORS[clampi(level, 1, 7) - 1]
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(color_name, color)
	button.add_theme_color_override(&"font_disabled_color", color.darkened(0.52))
	button.pressed.connect(action)
	return button


static func level_heading() -> TextureRect:
	var heading := TextureRect.new()
	heading.name = "SpellLevelHeading"
	heading.texture = ClassicUiAssetCatalog.texture(&"spells.label.level")
	heading.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	heading.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heading.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heading.custom_minimum_size = Vector2(73.0, 18.0)
	return heading


static func spell_button(node_name: String, text: String, selected: bool, enabled: bool, tooltip: String, action: Callable, icon: Texture2D = null) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggle_mode = true
	button.button_pressed = selected
	button.disabled = not enabled
	button.custom_minimum_size.y = 30.0
	button.tooltip_text = tooltip
	if icon != null:
		button.icon = icon
	button.pressed.connect(action)
	return button


static func definition_button(node_name: String, text: String, selected: bool, enabled: bool, tooltip: String, action: Callable) -> Button:
	return spell_button(node_name, text, selected, enabled, tooltip, action)
