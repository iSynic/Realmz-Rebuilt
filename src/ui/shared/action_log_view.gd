## Presents a selectable, copyable, bounded record of readable game actions.

class_name ActionLogView
extends Control


signal close_requested
signal clear_requested

var _log: RichTextLabel
var _count: Label
var _title: Label
var _clear: Button
var _actions: Array[Button] = []
var _lines: Array[String] = []
var _actor: OptionButton
var _movement: CheckButton

## Reading choices kept for the session: the log's text size before interface scaling,
## and whether movement lines are shown.
static var text_size := 18
static var show_movement := true


func _ready() -> void:
	var readable_font := load(ClassicTypography.READABLE_UI_PATH) as Font
	_title = %Title
	_title.add_theme_font_override("font", readable_font)
	_count = %Count
	_count.add_theme_font_override("font", readable_font)
	for button: Button in [%Clear, %CopyAll, %Close]:
		button.add_theme_font_override("font", readable_font)
		_actions.append(button)
	_clear = %Clear
	_clear.pressed.connect(func() -> void:
		if _clear.visible:
			clear_requested.emit()
	)
	(%CopyAll as Button).pressed.connect(_copy_all)
	(%Close as Button).pressed.connect(func() -> void: close_requested.emit())
	_log = %GameActionLog
	_log.add_theme_font_override("normal_font", readable_font)
	_actor = %Actor
	_actor.item_selected.connect(func(_index: int) -> void: _render())
	_movement = %Movement
	_movement.button_pressed = show_movement
	_movement.toggled.connect(func(shown: bool) -> void:
		show_movement = shown
		_render()
	)
	for step: Array in [[%Smaller, -2], [%Larger, 2]]:
		(step[0] as Button).pressed.connect(func() -> void:
			text_size = clampi(text_size + int(step[1]), 12, 32)
			_render()
		)
	for control: Control in [_actor, _movement, %Smaller, %Larger]:
		control.add_theme_font_override("font", readable_font)
	_actions.append_array([_movement, %Smaller as Button, %Larger as Button])


func present(lines: Array[String], title: String = "Game-action console", allow_clear: bool = true) -> void:
	var parent := get_parent()
	if parent != null:
		parent.move_child(self, parent.get_child_count() - 1)
	_title.text = title
	_clear.visible = allow_clear
	# A readable column in the middle of the window, as wide as the interface scale allows.
	var profile := UiSizing.profile_for(self)
	var half := minf(440.0 * (profile.ui_scale if profile != null else 1.0), size.x * 0.5 - 24.0)
	($Panel as Control).offset_left = -half
	($Panel as Control).offset_right = half
	set_lines(lines)
	# The log wears the menu dialog's surface and the interface theme's frame.
	UiThemeService.frame_for($Panel as Control, true)
	show()
	_focus_first_action()


func set_lines(lines: Array[String]) -> void:
	_lines = lines.duplicate()
	var chosen := _actor.get_item_text(_actor.selected) if _actor.selected > 0 else ""
	_actor.clear()
	_actor.add_item("Everyone")
	for name: String in ActionLogFormat.actors(_lines):
		_actor.add_item(name)
		if name == chosen: _actor.select(_actor.item_count - 1)
	_actor.visible = _actor.item_count > 2
	_movement.visible = _lines.any(func(line: String) -> bool: return line.ends_with(ActionLogFormat.MOVE_SUFFIX))
	_render()


## Lays the filtered lines out at the chosen text size and follows the newest line.
func _render() -> void:
	var shown := ActionLogFormat.filtered(_lines, not show_movement, _actor.get_item_text(_actor.selected) if _actor.selected > 0 else "")
	var palette := UiThemeService.current()
	UiSizing.font_size(_log, &"normal_font_size", text_size)
	_log.text = ActionLogFormat.markup(shown, palette.colors[&"accent"], palette.colors[&"muted"], _log.get_theme_font_size(&"normal_font_size") + 3) if not shown.is_empty() else "No committed game actions recorded yet." if _lines.is_empty() else "Nothing matches this filter."
	_count.text = "%d lines" % _lines.size() if shown.size() == _lines.size() else "%d of %d lines" % [shown.size(), _lines.size()]
	if not shown.is_empty():
		_log.scroll_to_line.call_deferred(maxi(0, _log.get_line_count() - 1))


func close_console() -> void:
	hide()
	if is_inside_tree():
		release_focus()


func handle_input(event: InputEvent) -> bool:
	if not visible:
		return false
	if event.is_action_pressed(&"realmz_back"):
		close_requested.emit()
		return true
	var key := event as InputEventKey
	if key == null:
		return event is InputEventAction
	if key.pressed:
		match key.keycode:
			KEY_UP, KEY_DOWN:
				handle_controller(&"", Vector2i.UP if key.keycode == KEY_UP else Vector2i.DOWN)
			KEY_PAGEUP, KEY_PAGEDOWN:
				var bar := _log.get_v_scroll_bar()
				bar.value += (-1.0 if key.keycode == KEY_PAGEUP else 1.0) * maxf(32.0, bar.page)
			KEY_HOME: _log.get_v_scroll_bar().value = 0.0
			KEY_END: _log.get_v_scroll_bar().value = _log.get_v_scroll_bar().max_value
			KEY_LEFT, KEY_RIGHT, KEY_TAB:
				_move_action_focus(-1 if key.keycode == KEY_LEFT or key.shift_pressed else 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if not key.echo: handle_controller(&"realmz_controller_confirm", Vector2i.ZERO)
	return true


func handle_controller(action_id: StringName, direction: Vector2i) -> bool:
	if not visible:
		return false
	if action_id == &"realmz_controller_back":
		close_requested.emit()
		return true
	if action_id == &"realmz_controller_confirm":
		var focused := get_viewport().gui_get_focus_owner()
		if focused is Button and not (focused as Button).disabled:
			if (focused as Button).toggle_mode: (focused as Button).button_pressed = not (focused as Button).button_pressed
			else: (focused as Button).pressed.emit()
		return true
	if direction.x != 0:
		_move_action_focus(direction.x)
		return true
	if direction.y != 0:
		var bar := _log.get_v_scroll_bar()
		bar.value = clampf(bar.value + direction.y * 32.0, bar.min_value, bar.max_value)
		return true
	return true


func _focus_first_action() -> void:
	for button: Button in _actions:
		if button.visible and not button.disabled:
			button.grab_focus()
			return


func _move_action_focus(delta: int) -> void:
	var available: Array[Button] = []
	for button: Button in _actions:
		if button.visible and not button.disabled:
			available.append(button)
	if available.is_empty():
		return
	var current := get_viewport().gui_get_focus_owner()
	var index := available.find(current)
	available[wrapi((index if index >= 0 else -1) + (1 if delta > 0 else -1), 0, available.size())].grab_focus()


func _copy_all() -> void:
	DisplayServer.clipboard_set(_log.get_parsed_text())
