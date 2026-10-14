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
	var confirm := ControllerBindingLabels.action(preferences, &"realmz_controller_confirm", _family, ControllerBindingLabels.face(&"south", _family))
	var back := ControllerBindingLabels.action(preferences, &"realmz_controller_back", _family, ControllerBindingLabels.face(&"east", _family))
	var previous := ControllerBindingLabels.action(preferences, &"realmz_controller_section_previous", _family, "LB")
	var next := ControllerBindingLabels.action(preferences, &"realmz_controller_section_next", _family, "RB")
	match context:
		&"spellbook": _prompt.text = "D-pad Navigate   %s Select   %s Back   %s / %s Spell Level" % [confirm, back, previous, next]
		&"top_menu": _prompt.text = "D-pad Navigate   %s Open / Select   %s Back" % [confirm, back]
		&"system": _prompt.text = "D-pad Navigate   %s Select   %s Back   %s / %s Sections" % [confirm, back, previous, next]
		_: _prompt.text = "Direction highlights   %s Select   %s Back   %s / %s Page" % [confirm, back, previous, next]
	_detail.text = ""
	_detail.visible = false
	_hide_timer.start(3.0)


func present_spellbook(preferences: ControllerPreferences, levels: bool = true) -> void:
	present(_family, &"spellbook" if levels else &"system", preferences)


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
