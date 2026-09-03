## Binds detached Classic spell selection chrome data to scene-owned controls.

class_name ClassicSpellSelectionChrome
extends RefCounted

const LEVEL_BUTTON_SCENE := preload("res://src/ui/classic_spell_level_button.tscn")
const LEVEL_HEADING_SCENE := preload("res://src/ui/classic_spell_level_heading.tscn")
const SPELL_BUTTON_SCENE := preload("res://src/ui/classic_spell_selection_button.tscn")

const LEVEL_COLORS: Array[Color] = [
	Color("f4df58"), Color("efcf45"), Color("eabb3e"), Color("e59d39"),
	Color("df7c36"), Color("d95e36"), Color("d34439"),
]


static func level_button(level: int, selected: bool, enabled: bool, action: Callable, unavailable_text: String) -> Button:
	var button := LEVEL_BUTTON_SCENE.instantiate() as Button
	button.name = "SpellLevel%d" % level
	button.text = "Level %d" % level
	button.button_pressed = selected
	button.disabled = not enabled
	button.tooltip_text = unavailable_text if button.disabled else "Show level %d spells" % level
	var color := LEVEL_COLORS[clampi(level, 1, 7) - 1]
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(color_name, color)
	button.add_theme_color_override(&"font_disabled_color", color.darkened(0.52))
	button.pressed.connect(action)
	return button


static func level_heading() -> TextureRect:
	var heading := LEVEL_HEADING_SCENE.instantiate() as TextureRect
	heading.texture = ClassicUiAssetCatalog.texture(&"spells.label.level")
	return heading


static func spell_button(node_name: String, text: String, selected: bool, enabled: bool, tooltip: String, action: Callable, icon: Texture2D = null) -> Button:
	var button := SPELL_BUTTON_SCENE.instantiate() as Button
	button.name = node_name
	button.text = text
	button.button_pressed = selected
	button.disabled = not enabled
	button.tooltip_text = tooltip
	if icon != null:
		button.icon = icon
	button.pressed.connect(action)
	return button


static func definition_button(node_name: String, text: String, selected: bool, enabled: bool, tooltip: String, action: Callable) -> Button:
	return spell_button(node_name, text, selected, enabled, tooltip, action)
