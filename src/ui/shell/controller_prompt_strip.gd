## Presents compact physical-position controller prompts above the application edge.

class_name ControllerPromptStrip
extends PanelContainer

@onready var _prompt: Label = %PromptText
@onready var _detail: Label = %PromptDetail

var _family: String = ControllerPreferences.PROMPT_GENERIC
var _hide_timer: Timer
var _fade: Tween


func _ready() -> void:
	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.timeout.connect(_fade_out)
	add_child(_hide_timer)


func present(family: String, context: StringName = &"", preferences: ControllerPreferences = null) -> void:
	_family = family
	if _fade != null:
		_fade.kill()
	modulate.a = 1.0
	visible = true
	var confirm := _binding_label(preferences, &"realmz_controller_confirm", _face(&"south"))
	var back := _binding_label(preferences, &"realmz_controller_back", _face(&"east"))
	var previous := _binding_label(preferences, &"realmz_controller_section_previous", "LB")
	var next := _binding_label(preferences, &"realmz_controller_section_next", "RB")
	match context:
		&"top_menu": _prompt.text = "D-pad Navigate   %s Open / Select   %s Back" % [confirm, back]
		&"system": _prompt.text = "D-pad Navigate   %s Select   %s Back   %s / %s Sections" % [confirm, back, previous, next]
		_: _prompt.text = "Direction highlights   %s Select   %s Back   %s / %s Page" % [confirm, back, previous, next]
	_detail.text = ""
	_detail.visible = false
	_hide_timer.start(3.0)


func hide_prompts() -> void:
	visible = false


func set_detail(value: String) -> void:
	if value.is_empty():
		return
	if _fade != null:
		_fade.kill()
	modulate.a = 1.0
	visible = true
	_detail.text = value
	_detail.visible = true
	_hide_timer.start(3.0)


func _fade_out() -> void:
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, 0.35)
	_fade.tween_callback(hide_prompts)


func _binding_label(preferences: ControllerPreferences, action_id: StringName, fallback: String) -> String:
	if preferences == null:
		return fallback
	for binding: Dictionary in preferences.bindings:
		if StringName(binding.get("action", "")) != action_id:
			continue
		if binding.get("kind") == ControllerPreferences.BINDING_AXIS:
			return "Axis %d%s" % [int(binding.get("code", -1)), "+" if int(binding.get("direction", 0)) > 0 else "−"]
		return _button_label(int(binding.get("code", -1)))
	return "Unbound"


func _button_label(code: int) -> String:
	if code == JOY_BUTTON_A: return _face(&"south")
	if code == JOY_BUTTON_B: return _face(&"east")
	if code == JOY_BUTTON_X: return _face(&"west")
	if code == JOY_BUTTON_Y: return _face(&"north")
	if code == JOY_BUTTON_LEFT_SHOULDER: return "L1" if _family == ControllerPreferences.PROMPT_PLAYSTATION else "LB"
	if code == JOY_BUTTON_RIGHT_SHOULDER: return "R1" if _family == ControllerPreferences.PROMPT_PLAYSTATION else "RB"
	if code == JOY_BUTTON_BACK: return "Create" if _family == ControllerPreferences.PROMPT_PLAYSTATION else "Minus" if _family == ControllerPreferences.PROMPT_SWITCH else "View"
	if code == JOY_BUTTON_START: return "Options" if _family == ControllerPreferences.PROMPT_PLAYSTATION else "Plus" if _family == ControllerPreferences.PROMPT_SWITCH else "Menu"
	return "Button %d" % code


func _face(position: StringName) -> String:
	match _family:
		ControllerPreferences.PROMPT_PLAYSTATION:
			return {&"south": "Cross", &"east": "Circle", &"west": "Square", &"north": "Triangle"}.get(position, "Button")
		ControllerPreferences.PROMPT_SWITCH:
			return {&"south": "B", &"east": "A", &"west": "Y", &"north": "X"}.get(position, "Button")
		ControllerPreferences.PROMPT_XBOX:
			return {&"south": "A", &"east": "B", &"west": "X", &"north": "Y"}.get(position, "Button")
	return {&"south": "South", &"east": "East", &"west": "West", &"north": "North"}.get(position, "Button")
