## Binds detached Classic spell selection chrome data to scene-owned controls.

class_name ClassicSpellSelectionChrome
extends RefCounted

const SPELL_BUTTON_SCENE_PATH := "res://src/ui/magic/classic_spell_selection_button.tscn"

static func bind_level_button(button: Button, level: int, selected: bool, enabled: bool, action: Callable, unavailable_text: String) -> void:
	button.name = "SpellLevel%d" % level
	button.text = "Level %d" % level
	button.button_pressed = selected
	button.disabled = not enabled
	button.tooltip_text = unavailable_text if button.disabled else "Show level %d spells" % level
	_clear_pressed_connections(button)
	button.pressed.connect(action)


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
