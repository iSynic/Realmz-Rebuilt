## Presents compact physical-position controller prompts above the application edge.

class_name ControllerPromptStrip
extends PanelContainer

@onready var _prompt: Label = %PromptText
@onready var _detail: Label = %PromptDetail

var _family: String = ControllerPreferences.PROMPT_GENERIC


func present(family: String, context_detail: String = "") -> void:
	_family = family
	visible = true
	_prompt.text = "%s Confirm   %s Back   %s Actions   %s Workspaces   ☰ System" % [_face(&"south"), _face(&"east"), _face(&"west"), _face(&"north")]
	_detail.text = context_detail
	_detail.visible = not context_detail.is_empty()


func hide_prompts() -> void:
	visible = false


func set_detail(value: String) -> void:
	_detail.text = value
	_detail.visible = not value.is_empty()


func _face(position: StringName) -> String:
	match _family:
		ControllerPreferences.PROMPT_PLAYSTATION:
			return {&"south": "Cross", &"east": "Circle", &"west": "Square", &"north": "Triangle"}.get(position, "Button")
		ControllerPreferences.PROMPT_SWITCH:
			return {&"south": "B", &"east": "A", &"west": "Y", &"north": "X"}.get(position, "Button")
		ControllerPreferences.PROMPT_XBOX:
			return {&"south": "A", &"east": "B", &"west": "X", &"north": "Y"}.get(position, "Button")
	return {&"south": "South", &"east": "East", &"west": "West", &"north": "North"}.get(position, "Button")
