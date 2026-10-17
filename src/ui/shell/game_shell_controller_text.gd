## Adapts controller editing actions to the retained on-screen keyboard.
class_name GameShellControllerText
extends RefCounted

var _shell: Variant

func _init(shell: Variant) -> void:
	_shell = shell

func is_open() -> bool: return _shell._controller_keyboard.is_open()


func open(focus_scope: Node = null) -> bool:
	var focused: Control = (focus_scope if focus_scope != null else _shell).get_viewport().gui_get_focus_owner()
	return _shell._controller_keyboard.open_for(focused) if focused is LineEdit or focused is TextEdit else false


func move(direction: Vector2i) -> void: _shell._controller_keyboard.move_direction(Vector2(direction))


func confirm() -> void: _shell._controller_keyboard.confirm_focused()


func cancel() -> void: _shell._controller_keyboard.cancel()


func page(delta: int) -> void:
	if delta < 0: _shell._controller_keyboard.previous_page()
	else: _shell._controller_keyboard.next_page()


func edit(action_id: StringName) -> void:
	match action_id:
		&"realmz_controller_action_radial": _shell._controller_keyboard.backspace()
		&"realmz_controller_workspace_radial": _shell._controller_keyboard.next_page()
		&"realmz_controller_character_previous": _shell._controller_keyboard.caret_left()
		&"realmz_controller_character_next": _shell._controller_keyboard.caret_right()
