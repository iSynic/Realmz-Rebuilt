class_name ClassicSpellSelectionChrome
extends RefCounted


static func level_button(level: int, selected: bool, enabled: bool, action: Callable, unavailable_text: String) -> Button:
	var button := Button.new()
	button.name = "SpellLevel%d" % level
	button.text = str(level)
	button.toggle_mode = true
	button.button_pressed = selected
	button.disabled = not enabled
	button.custom_minimum_size.y = 31.0
	button.tooltip_text = unavailable_text if button.disabled else "Show level %d spells" % level
	button.pressed.connect(action)
	return button


static func spell_button(node_name: String, text: String, selected: bool, enabled: bool, tooltip: String, action: Callable, icon: Texture2D = null) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggle_mode = true
	button.button_pressed = selected
	button.disabled = not enabled
	button.custom_minimum_size.y = 38.0
	button.tooltip_text = tooltip
	if icon != null:
		button.icon = icon
	button.pressed.connect(action)
	return button
