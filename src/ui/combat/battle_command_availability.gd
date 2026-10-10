## Temporarily disables gameplay commands while retaining their supplied reasons.
class_name BattleCommandAvailability
extends RefCounted

var _buttons: Array[Button] = []
var _previous: Dictionary = {}
var pending := false


func register_button(button: Button) -> void:
	_buttons.append(button)


func clear() -> void:
	set_pending(false)
	_buttons.clear()


func set_pending(value: bool) -> void:
	pending = value
	for button: Button in _buttons:
		if not is_instance_valid(button): continue
		if pending and not _previous.has(button):
			_previous[button] = [button.disabled, button.tooltip_text]
			button.disabled = true
			button.tooltip_text = "Waiting for combat resolution."
		elif not pending and _previous.has(button):
			button.disabled = _previous[button][0]
			button.tooltip_text = _previous[button][1]
	if not pending: _previous.clear()
