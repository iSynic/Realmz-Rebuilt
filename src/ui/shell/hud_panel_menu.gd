## Owns the transient options for one retained HUD panel.
class_name HudPanelMenu
extends Control

signal arrange_requested
## The player asked to move the command button the menu was opened on to the other bar.
signal move_requested
## The player asked to move that button one place earlier (-1) or later (1) in its bar.
signal shift_requested(direction: int)
## The player asked for the panel one step larger (1) or smaller (-1).
signal scale_requested(direction: int)
## The menu was opened for a panel-less surface (the effects bar) and its pin was toggled.
signal surface_keep_visible_changed(keep_visible: bool)

var _panel: HudPanel
var _restore_focus: WeakRef
var _buttons: Array[Button] = []


func _ready() -> void:
	_buttons = [$Menu/Actions/Open, $Menu/Actions/KeepVisible, $Menu/Actions/Hide, $Menu/Actions/Arrange, $Menu/Actions/Back, $Menu/Actions/Move, $Menu/Actions/Earlier, $Menu/Actions/Later, $Menu/Actions/Larger, $Menu/Actions/Smaller]
	_buttons[8].pressed.connect(func() -> void: scale_requested.emit(1))
	_buttons[9].pressed.connect(func() -> void: scale_requested.emit(-1))
	for step: int in [-1, 1]:
		_buttons[6 if step < 0 else 7].pressed.connect(func() -> void:
			close()
			shift_requested.emit(step))
	_buttons[5].pressed.connect(func() -> void:
		close()
		move_requested.emit())
	_buttons[0].pressed.connect(_open_content)
	_buttons[1].toggled.connect(_pin)
	_buttons[2].pressed.connect(_hide_panel)
	_buttons[3].pressed.connect(_arrange)
	_buttons[4].pressed.connect(close)
	gui_input.connect(_outside_input)
	resized.connect(_clamp_menu)


## `move_label` names the move offered for a command button under the pointer; empty hides it.
func open(panel: HudPanel, location: Vector2, can_arrange: bool, move_label: String = "") -> void:
	close()
	for index: int in [5, 6, 7]: _buttons[index].visible = not move_label.is_empty()
	_buttons[5].text = move_label
	_panel = panel
	_panel.menu_hold = true
	var focused := get_viewport().gui_get_focus_owner()
	_restore_focus = weakref(focused) if focused != null else null
	_buttons[0].visible = true
	_buttons[2].visible = true
	_buttons[8].visible = true
	_buttons[9].visible = true
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


## Opens the menu for a surface that is not a HUD panel: only its pin and Arrange apply.
func open_surface(keep_visible: bool, location: Vector2, can_arrange: bool) -> void:
	close()
	_panel = null
	for index: int in [5, 6, 7]: _buttons[index].visible = false
	var focused := get_viewport().gui_get_focus_owner()
	_restore_focus = weakref(focused) if focused != null else null
	_buttons[0].visible = false
	_buttons[2].visible = false
	_buttons[8].visible = false
	_buttons[9].visible = false
	_buttons[1].set_pressed_no_signal(keep_visible)
	_buttons[1].text = "✓ Keep visible" if keep_visible else "Keep visible"
	_buttons[3].disabled = not can_arrange
	show()
	$Menu.reset_size()
	$Menu.position = location
	_clamp_menu()
	_buttons[1].grab_focus()


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
		if not button.disabled and button.visible:
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
	if _panel == null:
		_buttons[1].text = "✓ Keep visible" if value else "Keep visible"
		surface_keep_visible_changed.emit(value)
		return
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
