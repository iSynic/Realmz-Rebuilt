## Binds detached Classic spell selection chrome data to scene-owned controls.

class_name ClassicSpellSelectionChrome
extends RefCounted

const LEVEL_BUTTON_SCENE_PATH := "res://src/ui/magic/classic_spell_level_button.tscn"
const LEVEL_HEADING_SCENE_PATH := "res://src/ui/magic/classic_spell_level_heading.tscn"
const SPELL_BUTTON_SCENE_PATH := "res://src/ui/magic/classic_spell_selection_button.tscn"

const LEVEL_COLORS: Array[Color] = [
	Color("f4df58"), Color("efcf45"), Color("eabb3e"), Color("e59d39"),
	Color("df7c36"), Color("d95e36"), Color("d34439"),
]


static func level_button(level: int, selected: bool, enabled: bool, action: Callable, unavailable_text: String) -> Button:
	var button := (load(LEVEL_BUTTON_SCENE_PATH) as PackedScene).instantiate() as Button
	bind_level_button(button, level, selected, enabled, action, unavailable_text)
	return button


static func bind_level_button(button: Button, level: int, selected: bool, enabled: bool, action: Callable, unavailable_text: String) -> void:
	button.name = "SpellLevel%d" % level
	button.text = "Level %d" % level
	button.button_pressed = selected
	button.disabled = not enabled
	button.tooltip_text = unavailable_text if button.disabled else "Show level %d spells" % level
	var color := LEVEL_COLORS[clampi(level, 1, 7) - 1]
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(color_name, color)
	button.add_theme_color_override(&"font_disabled_color", color.darkened(0.52))
	_clear_pressed_connections(button)
	button.pressed.connect(action)


static func level_heading() -> TextureRect:
	var heading := (load(LEVEL_HEADING_SCENE_PATH) as PackedScene).instantiate() as TextureRect
	heading.texture = ClassicUiAssetCatalog.texture(&"spells.label.level")
	return heading


static func spell_button(node_name: String, text: String, selected: bool, enabled: bool, tooltip: String, action: Callable, icon: Texture2D = null) -> Button:
	var button := (load(SPELL_BUTTON_SCENE_PATH) as PackedScene).instantiate() as Button
	bind_spell_button(button, node_name, text, selected, enabled, tooltip, action, icon)
	return button


static func bind_spell_button(button: Button, node_name: String, text: String, selected: bool, enabled: bool, tooltip: String, action: Callable, icon: Texture2D = null) -> void:
	button.name = node_name
	button.text = text
	button.button_pressed = selected
	button.disabled = not enabled
	button.tooltip_text = tooltip
	if icon != null:
		button.icon = icon
	_clear_pressed_connections(button)
	button.pressed.connect(action)


static func definition_button(node_name: String, text: String, selected: bool, enabled: bool, tooltip: String, action: Callable) -> Button:
	return spell_button(node_name, text, selected, enabled, tooltip, action)


static func _clear_pressed_connections(button: Button) -> void:
	for connection: Dictionary in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"] as Callable)
