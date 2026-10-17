## Owns the transient options for one retained HUD panel.
class_name HudPanelMenu
extends Control

signal arrange_requested

var _panel: HudPanel
var _restore_focus: WeakRef
var _buttons: Array[Button] = []


func _ready() -> void:
	_buttons = [$Menu/Actions/Open, $Menu/Actions/KeepVisible, $Menu/Actions/Hide, $Menu/Actions/Arrange, $Menu/Actions/Back]
	_buttons[0].pressed.connect(_open_content)
	_buttons[1].toggled.connect(_pin)
	_buttons[2].pressed.connect(_hide_panel)
	_buttons[3].pressed.connect(_arrange)
	_buttons[4].pressed.connect(close)
	gui_input.connect(_outside_input)
	resized.connect(_clamp_menu)


func open(panel: HudPanel, location: Vector2, can_arrange: bool) -> void:
	close()
	_panel = panel
	_panel.menu_hold = true
	var focused := get_viewport().gui_get_focus_owner()
	_restore_focus = weakref(focused) if focused != null else null
	_buttons[1].set_pressed_no_signal(panel.is_pinned())
	_buttons[1].text = "✓ Keep visible" if panel.is_pinned() else "Keep visible"
	_buttons[2].disabled = panel.is_required()
	_buttons[2].tooltip_text = "Finish the current choice before hiding this panel." if panel.is_required() else ""
	_buttons[3].disabled = not can_arrange
	_buttons[3].tooltip_text = "Finish the current choice before arranging panels." if not can_arrange else ""
	show()
	$Menu.reset_size()
	$Menu.position = location
	_clamp_menu()
	_buttons[0].grab_focus()


func close() -> void:
	if not visible: return
	hide()
	if is_instance_valid(_panel): _panel.menu_hold = false
	var previous := _restore_focus.get_ref() as Control if _restore_focus != null else null
	if is_instance_valid(previous) and previous.is_visible_in_tree(): previous.grab_focus()
	else:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and is_ancestor_of(focused): focused.release_focus()
	_restore_focus = null


func handle_input(event: InputEvent) -> bool:
	if not visible: return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed(&"realmz_back"): close()
		elif event.keycode in [KEY_UP, KEY_DOWN, KEY_TAB]: _move(-1 if event.keycode == KEY_UP or event.shift_pressed else 1)
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]: _confirm()
		get_viewport().set_input_as_handled()
	return true


func handle_controller(action: StringName, pressed: bool, direction: Vector2i) -> bool:
	if not visible: return false
	if not pressed: return true
	if action == &"realmz_controller_back": close()
	elif action == &"realmz_controller_confirm": _confirm()
	elif direction != Vector2i.ZERO: _move(1 if direction.y > 0 or direction.x > 0 else -1)
	return true


func _move(delta: int) -> void:
	var index := _buttons.find(get_viewport().gui_get_focus_owner())
	for offset: int in range(1, _buttons.size() + 1):
		var button := _buttons[posmod(index + offset * delta, _buttons.size())]
		if not button.disabled:
			button.grab_focus()
			return


func _confirm() -> void:
	var button := get_viewport().gui_get_focus_owner() as Button
	if button == null or not _buttons.has(button) or button.disabled: return
	if button.toggle_mode: button.button_pressed = not button.button_pressed
	else: button.pressed.emit()


func _outside_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
		accept_event()


func _open_content() -> void:
	close()
	_panel.focus_content()


func _pin(value: bool) -> void:
	_panel.set_pinned(value)
	_buttons[1].set_pressed_no_signal(_panel.is_pinned())
	_buttons[1].text = "✓ Keep visible" if _panel.is_pinned() else "Keep visible"


func _clamp_menu() -> void:
	if not is_node_ready() or not visible: return
	$Menu.position = $Menu.position.clamp(Vector2(8, 8), (size - $Menu.size - Vector2(8, 8)).max(Vector2(8, 8)))


func _hide_panel() -> void:
	close()
	_panel.collapse()


func _arrange() -> void:
	close()
	arrange_requested.emit()
