## Formats physical-position and remapped controller bindings for live prompts.
class_name ControllerBindingLabels
extends RefCounted


static func action(preferences: ControllerPreferences, action_id: StringName, family: String, fallback: String) -> String:
	if preferences == null: return fallback
	for binding: Dictionary in preferences.bindings:
		if StringName(binding.get("action", "")) != action_id: continue
		if binding.get("kind") == ControllerPreferences.BINDING_AXIS:
			return "Axis %d%s" % [int(binding.get("code", -1)), "+" if int(binding.get("direction", 0)) > 0 else "−"]
		return button(int(binding.get("code", -1)), family)
	return "Unbound"


static func button(code: int, family: String) -> String:
	if code == JOY_BUTTON_A: return face(&"south", family)
	if code == JOY_BUTTON_B: return face(&"east", family)
	if code == JOY_BUTTON_X: return face(&"west", family)
	if code == JOY_BUTTON_Y: return face(&"north", family)
	if code == JOY_BUTTON_LEFT_SHOULDER: return "L1" if family == ControllerPreferences.PROMPT_PLAYSTATION else "LB"
	if code == JOY_BUTTON_RIGHT_SHOULDER: return "R1" if family == ControllerPreferences.PROMPT_PLAYSTATION else "RB"
	if code == JOY_BUTTON_BACK: return "Create" if family == ControllerPreferences.PROMPT_PLAYSTATION else "Minus" if family == ControllerPreferences.PROMPT_SWITCH else "View"
	if code == JOY_BUTTON_START: return "Options" if family == ControllerPreferences.PROMPT_PLAYSTATION else "Plus" if family == ControllerPreferences.PROMPT_SWITCH else "Menu"
	return "Button %d" % code


static func face(position: StringName, family: String) -> String:
	match family:
		ControllerPreferences.PROMPT_PLAYSTATION:
			return {&"south": "Cross", &"east": "Circle", &"west": "Square", &"north": "Triangle"}.get(position, "Button")
		ControllerPreferences.PROMPT_SWITCH:
			return {&"south": "B", &"east": "A", &"west": "Y", &"north": "X"}.get(position, "Button")
		ControllerPreferences.PROMPT_XBOX:
			return {&"south": "A", &"east": "B", &"west": "X", &"north": "Y"}.get(position, "Button")
	return {&"south": "South", &"east": "East", &"west": "West", &"north": "North"}.get(position, "Button")
