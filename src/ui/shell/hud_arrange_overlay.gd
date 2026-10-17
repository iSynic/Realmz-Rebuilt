## Edits panel placement in a local draft while the adventure remains paused.
class_name HudArrangeOverlay
extends Control

var _shell_ref: WeakRef
var _draft: HudPreferences
var _frames: Array[Control] = []
var _selected := 0
var _dragging := false
var _resizing := false
var _size_origin := Vector2.ZERO
var _binding_controls := false
var _drag_origin := Vector2.ZERO
var _panel_origin := Vector2.ZERO
var _restore_focus: WeakRef
var _backdrop_visible := false


func _ready() -> void:
	_frames = [$Roster, $Narration, $World, $Party, $Effects]
	for index: int in _frames.size():
		(_frames[index].get_node("Content/Title") as Control).hide()
		_frames[index].gui_input.connect(_frame_input.bind(index))
		_frames[index].focus_entered.connect(_select.bind(index))
	$Toolbar/Content/Actions/CancelButton.pressed.connect(cancel)
	$Toolbar/Content/Actions/UseButton.pressed.connect(_use_positions)
	$Toolbar/Content/Actions/ResetButton.pressed.connect(_reset_positions)
	$Toolbar/Content/PanelSelector.item_selected.connect(func(index: int) -> void: _frames[index].grab_focus())
	$Toolbar/Content/PanelSelector.get_popup().exclusive = false
	for index: int in 2: _frames[index].get_node("Content/ResizeHandle").gui_input.connect(_resize_input.bind(index))
	%PanelWidth.value_changed.connect(_on_size_changed)
	%PanelHeight.value_changed.connect(_on_size_changed)
	%Orientation.item_selected.connect(_on_orientation_selected)
	%Orientation.get_popup().exclusive = false


func open(shell: GameShell) -> void:
	if visible: return
	_shell_ref = weakref(shell)
	_draft = shell.navigator.content_presenter.system_preferences.draft_settings().hud.duplicate_value()
	if not _draft.modular: return
	var focused := get_viewport().gui_get_focus_owner()
	_restore_focus = weakref(focused) if focused != null else null
	shell.navigator.hide()
	var backdrop := shell.get_node("PauseBackdrop") as Control
	_backdrop_visible = backdrop.visible
	backdrop.hide()
	shell.hud.begin_arrangement(_draft)
	show()
	_sync_frames()
	_frames[0].grab_focus()


func cancel() -> void:
	if not visible: return
	_close()


func _use_positions() -> void:
	var shell := _shell_ref.get_ref() as GameShell
	shell.navigator.content_presenter.system_preferences.stage_setting(&"hud", _draft)
	_close()


func _close() -> void:
	var shell := _shell_ref.get_ref() as GameShell
	hide()
	_dragging = false
	_resizing = false
	shell.navigator.show()
	(shell.get_node("PauseBackdrop") as Control).visible = _backdrop_visible
	shell.hud.end_arrangement()
	var previous := _restore_focus.get_ref() as Control if _restore_focus != null else null
	if previous != null and previous.is_visible_in_tree(): previous.grab_focus()
	_restore_focus = null
	_draft = null


func _process(_delta: float) -> void:
	if visible: _sync_frames()


func _sync_frames() -> void:
	var shell := _shell_ref.get_ref() as GameShell
	if shell == null: return
	var rectangles := shell.hud.panel_rectangles()
	for index: int in _frames.size():
		_frames[index].position = rectangles[index].position
		_frames[index].size = rectangles[index].size
	_sync_editors()
	var toolbar := $Toolbar as Control
	var desired_width := minf(size.x - 24.0, 720.0)
	var minimum := toolbar.get_combined_minimum_size()
	var bounds := Vector2(maxf(desired_width, minimum.x), minimum.y)
	var bottom := Rect2(Vector2((size.x - bounds.x) * 0.5, size.y - bounds.y - 12.0), bounds)
	var top := Rect2(Vector2(bottom.position.x, 12.0), bounds)
	var location := top.position if _covered_targets(top) < _covered_targets(bottom) else bottom.position
	if not toolbar.size.is_equal_approx(bounds): toolbar.size = bounds
	if not toolbar.position.is_equal_approx(location): toolbar.position = location


func _covered_targets(toolbar: Rect2) -> int:
	var score := 0
	for index: int in _frames.size():
		var rectangle := Rect2(_frames[index].position, _frames[index].size)
		if index == _selected:
			if toolbar.intersects(rectangle): score += 100
			if index < 2 and toolbar.intersects(Rect2(rectangle.end - Vector2(24, 24), Vector2(24, 24))): score += 1000
		elif toolbar.encloses(rectangle): score += 1
	return score


func _select(index: int) -> void:
	if index != _selected:
		_resizing = false
		_dragging = false
	_selected = index
	move_child(_frames[index], get_child_count() - 1)
	move_child($Toolbar, get_child_count() - 1)
	$Toolbar/Content/PanelSelector.select(index)
	for candidate: int in _frames.size():
		var frame := _frames[candidate] as PanelContainer
		frame.z_index = 1 if candidate == index else 0
		var style := frame.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		style.border_color = Color("e2c36e") if candidate == index else Color(0.72, 0.78, 0.8, 0.4)
		style.set_border_width_all(2 if candidate == index else 1)
		frame.add_theme_stylebox_override("panel", style)
		(frame.get_node("Content/MoveGlyph") as Control).visible = candidate == index
		if candidate < 2: frame.get_node("Content/ResizeHandle").visible = candidate == index


func _frame_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_select(index)
		_frames[index].grab_focus()
		_dragging = event.pressed
		_drag_origin = get_global_mouse_position()
		_panel_origin = _frames[index].position
		accept_event()
	elif event is InputEventMouseMotion and _dragging and index == _selected:
		_move_to(_panel_origin + get_global_mouse_position() - _drag_origin)
		accept_event()


func _move_to(location: Vector2) -> void:
	var shell := _shell_ref.get_ref() as GameShell
	var area := shell.hud.placement_area()
	var available := (area.size - shell.hud.panel_rectangles()[_selected].size).max(Vector2.ZERO)
	var local := (location - area.position).clamp(Vector2.ZERO, available)
	var normalized := Vector2(local.x / available.x if available.x > 0 else 0.0, local.y / available.y if available.y > 0 else 0.0)
	if _selected == 4:
		_draft.effects_custom_position = true
		_draft.effects_position = normalized
	else:
		var preference := _draft.panels[_selected]
		preference.custom_position = true
		preference.position = normalized
	shell.hud.update_arrangement(_draft)
	_sync_frames()


func _sync_editors() -> void:
	if _draft == null: return
	%SizeControls.visible = _selected < 2
	%OrientationControls.visible = _selected >= 2
	$Toolbar/Content/Help.text = "Drag to move or resize the corner. Confirm edits size; confirm again for actions." if _selected < 2 else "Drag or use directions to move. Shoulders select a panel."
	_binding_controls = true
	if _selected < 2:
		var shell := _shell_ref.get_ref() as GameShell
		var minimum := shell.hud.minimum_panel_size(_selected)
		var maximum := shell.hud.placement_area().size
		for axis: int in 2:
			var control := %PanelWidth if axis == 0 else %PanelHeight
			control.min_value = ceilf(minimum[axis])
			control.max_value = floorf(maximum[axis])
			if not control.get_line_edit().has_focus(): control.set_value_no_signal(roundf(_frames[_selected].size[axis]))
	else:
		%Orientation.select(HudPreferences.ORIENTATIONS.find(_draft.strip_orientations[_selected - 2]))
	_binding_controls = false


func _resize_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_frames[index].grab_focus()
		_resizing = event.pressed
		_drag_origin = get_global_mouse_position()
		_size_origin = _frames[index].size
		_frames[index].get_node("Content/ResizeHandle").accept_event()
	elif event is InputEventMouseMotion and _resizing and index == _selected:
		_resize_to(_size_origin + get_global_mouse_position() - _drag_origin)
		_frames[index].get_node("Content/ResizeHandle").accept_event()


func _resize_to(dimensions: Vector2) -> void:
	var shell := _shell_ref.get_ref() as GameShell
	var area := shell.hud.placement_area()
	var origin := _frames[_selected].position
	var preference := _draft.panels[_selected]
	preference.custom_size = true
	preference.size_fraction = dimensions.clamp(shell.hud.minimum_panel_size(_selected), area.size) / area.size
	shell.hud.update_arrangement(_draft)
	_move_to(origin)


func _on_size_changed(_value: float) -> void:
	if not _binding_controls and _selected < 2:
		_resize_to(Vector2(%PanelWidth.value, %PanelHeight.value))


func _on_orientation_selected(index: int) -> void:
	if _binding_controls or _selected < 2: return
	var origin := _frames[_selected].position
	_draft.strip_orientations[_selected - 2] = HudPreferences.ORIENTATIONS[index]
	(_shell_ref.get_ref() as GameShell).hud.update_arrangement(_draft)
	_move_to(origin)


func _focus_editor() -> void:
	if _selected < 2: %PanelWidth.get_line_edit().grab_focus()
	else: %Orientation.grab_focus()


func _edit_size_direction(direction: Vector2i) -> bool:
	for control: SpinBox in [%PanelWidth, %PanelHeight]:
		if control.get_line_edit().has_focus():
			if direction.y != 0: control.value -= direction.y * 8.0
			else: (%PanelHeight if control == %PanelWidth else %PanelWidth).get_line_edit().grab_focus()
			return true
	return false


func _reset_positions() -> void:
	for panel: HudPanelPreferences in _draft.panels:
		panel.custom_position = false
		panel.custom_size = false
	_draft.strip_orientations.assign(["auto", "auto", "auto"])
	_draft.effects_custom_position = false
	(_shell_ref.get_ref() as GameShell).hud.update_arrangement(_draft)
	_sync_frames()


func handle_controller(action: StringName, pressed: bool, direction: Vector2i) -> bool:
	if not visible: return false
	if not pressed: return true
	if action == &"realmz_controller_confirm":
		for control: SpinBox in [%PanelWidth, %PanelHeight]:
			if control.get_line_edit().has_focus():
				control.apply()
				$Toolbar/Content/Actions/UseButton.grab_focus()
				return true
	if action == &"realmz_controller_back": cancel()
	elif action == &"realmz_controller_confirm" and get_viewport().gui_get_focus_owner() in _frames:
		_focus_editor()
	elif direction != Vector2i.ZERO:
		if _edit_size_direction(direction): return true
		var focused := get_viewport().gui_get_focus_owner()
		if focused in _frames: _move_to(_frames[_selected].position + Vector2(direction) * 8.0)
		else: return false
	elif action == &"realmz_controller_section_next": _frames[(_selected + 1) % _frames.size()].grab_focus()
	elif action == &"realmz_controller_section_previous": _frames[posmod(_selected - 1, _frames.size())].grab_focus()
	else: return false
	return true


func handle_input(event: InputEvent) -> bool:
	if not visible: return false
	if event.is_action_pressed(&"realmz_back"):
		cancel()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and get_viewport().gui_get_focus_owner() in _frames:
		if event.is_action_pressed(&"ui_accept"):
			_focus_editor()
			get_viewport().set_input_as_handled()
			return true
		var directions := {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}
		if directions.has(event.keycode):
			_move_to(_frames[_selected].position + directions[event.keycode] * (1.0 if event.shift_pressed else 8.0))
			get_viewport().set_input_as_handled()
	return true
