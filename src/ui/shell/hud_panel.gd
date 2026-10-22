## Binds presentation preferences and transient reveal state to one authored HUD panel.
class_name HudPanel
extends Control

signal pin_changed(pinned: bool)
signal collapsed
signal open_changed(open: bool)
signal options_requested(location: Vector2)

const HOVER_DWELL_MS := 350
const INTERACTION_GRACE_MS := 450
const TRANSITION_SECONDS := 0.12
const TAB_IDLE_COLOR := Color(0.42, 0.47, 0.48, 0.72)
const TAB_HOVER_COLOR := Color(0.76, 0.68, 0.48, 0.72)
const TAB_PRESSED_COLOR := Color(0.94, 0.82, 0.52, 0.9)

@onready var _surface: PanelContainer = $Surface
@onready var _content: MarginContainer = $Surface/Column/Body/Content
@onready var _handle: Button = $Handle
@onready var _tab_shape: Polygon2D = $Handle/TabShape

var _auto_hide := false
var _reveal_on_hover := true
var _reduced_motion := false
var _required := false
var _open := true
var _manually_collapsed := false
var _reveal_deadline_ms := 0
var _handle_hover_started_ms := -1
var _pointer_press_hold := false
var _last_process_ms := 0
var _background_opacity := 0.9
var _panel_title := "Party"
var _transition: Tween
var menu_hold := false
var companion_surface: Control
var _retain_content_focus := false


func _ready() -> void:
	set_process(true)
	_handle.pressed.connect(_on_handle_pressed)
	_handle.button_down.connect(_on_handle_button_down)
	_handle.button_up.connect(_on_handle_button_up)
	_handle.mouse_entered.connect(_on_handle_mouse_entered)
	_handle.mouse_exited.connect(_on_handle_mouse_exited)
	_sync_controls()
	_apply_background_opacity()
	_set_open(not _auto_hide or _required, true)


## Applies one panel's saved presentation choices without taking ownership of them.
func configure(title: String, preferences: HudPanelPreferences, reduced_motion: bool) -> void:
	if preferences == null:
		return
	var visibility_changed := _auto_hide != preferences.auto_hide
	var next_opacity := clampf(preferences.background_opacity, 0.4, 1.0)
	var opacity_changed := not is_equal_approx(_background_opacity, next_opacity)
	var motion_changed_to_reduced := not _reduced_motion and reduced_motion
	_auto_hide = preferences.auto_hide
	_reveal_on_hover = preferences.reveal_on_hover
	_reduced_motion = reduced_motion
	_background_opacity = next_opacity
	_panel_title = title
	if is_node_ready():
		_sync_controls()
		if opacity_changed:
			_apply_background_opacity()
		if motion_changed_to_reduced:
			_set_open(_open, true)
		if visibility_changed:
			if _auto_hide:
				if _open and not _required and not _manually_collapsed:
					_reveal_deadline_ms = maxi(_reveal_deadline_ms,
						Time.get_ticks_msec() + INTERACTION_GRACE_MS)
			else:
				_manually_collapsed = false
				_reveal_deadline_ms = 0
				_set_open(true)


## Extends the current presentation reveal; repeated changes coalesce to one deadline.
func reveal(seconds: float = 5.0) -> void:
	_manually_collapsed = false
	_set_open(true)
	if _auto_hide and not _is_pinned() and not _required:
		var duration_ms := maxi(0, roundi(seconds * 1000.0))
		var next_deadline := Time.get_ticks_msec() + duration_ms
		_reveal_deadline_ms = maxi(_reveal_deadline_ms, next_deadline)
	else:
		_reveal_deadline_ms = 0


## Keeps mandatory task controls visible until their owning request resolves.
func set_required(required: bool) -> void:
	if required == _required:
		return
	_required = required
	_sync_controls()
	if required:
		_manually_collapsed = false
		_reveal_deadline_ms = 0
		_set_open(true)
	elif _auto_hide and not _is_pinned():
		_reveal_deadline_ms = maxi(_reveal_deadline_ms,
			Time.get_ticks_msec() + INTERACTION_GRACE_MS)


## The coordinator owns this panel's rectangle; child layout remains scene-authored.
func set_panel_rect(rect: Rect2) -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = rect.position
	size = Vector2(maxf(0.0, rect.size.x), maxf(0.0, rect.size.y))


func content_host() -> Control:
	return _content


func is_open() -> bool:
	return _open


func reveal_handle_contains_point(point: Vector2) -> bool:
	return _handle.is_visible_in_tree() and _handle.get_global_rect().has_point(point)


func is_required() -> bool:
	return _required


func is_pinned() -> bool:
	return not _auto_hide


func focus_content() -> void:
	_retain_content_focus = true
	reveal()
	for node: Node in _content.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.focus_mode == Control.FOCUS_ALL and not (control is BaseButton and control.disabled):
			control.grab_focus()
			return


## Releases focus from descendants before an owner hides or replaces this panel.
func release_panel_focus() -> void:
	_retain_content_focus = false
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()


func owns_content_focus() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return _retain_content_focus and focused != null and is_ancestor_of(focused)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		release_panel_focus()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_retain_content_focus = true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			var held_panel_press := _pointer_press_hold
			_pointer_press_hold = false
			if held_panel_press and _open and _auto_hide and not _required and not _is_pinned():
				_reveal_deadline_ms = maxi(_reveal_deadline_ms,
					Time.get_ticks_msec() + INTERACTION_GRACE_MS)
			return
		if not is_inside_tree() or not is_visible_in_tree() or not _open:
			_pointer_press_hold = false
			return
		var surface_local_position: Vector2 = _surface.get_global_transform_with_canvas().affine_inverse() * event.position
		_pointer_press_hold = Rect2(Vector2.ZERO, _surface.size).has_point(surface_local_position)


func request_options_at(location: Vector2) -> bool:
	if not is_visible_in_tree(): return false
	var target: Control = _surface if _open else _handle
	if not target.get_global_rect().has_point(location): return false
	options_requested.emit(location)
	return true


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if not is_inside_tree() or not is_visible_in_tree():
		if _last_process_ms > 0 and _reveal_deadline_ms > 0:
			_reveal_deadline_ms += now - _last_process_ms
		_handle_hover_started_ms = -1
		_pointer_press_hold = false
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and is_instance_valid(_surface) and _surface.is_ancestor_of(focused):
			focused.release_focus()
		_last_process_ms = now
		return
	_last_process_ms = now
	if _open and (menu_hold or _has_pointer_or_focus_hold()):
		if _reveal_deadline_ms > 0:
			_reveal_deadline_ms = maxi(_reveal_deadline_ms, now + INTERACTION_GRACE_MS)

	if _reveal_on_hover and not _open and _handle_hover_started_ms >= 0:
		if now - _handle_hover_started_ms >= HOVER_DWELL_MS:
			reveal()
			_handle_hover_started_ms = -1

	if not _auto_hide or _is_pinned() or _required or not _open or _manually_collapsed:
		return
	if _reveal_deadline_ms > 0 and now >= _reveal_deadline_ms:
		_set_open(false)
		_reveal_deadline_ms = 0


func _has_pointer_or_focus_hold() -> bool:
	if not is_instance_valid(_surface) or not _surface.visible:
		return false
	var pointer := get_global_mouse_position()
	if companion_surface != null and companion_surface.is_visible_in_tree() and companion_surface.get_global_rect().has_point(pointer):
		return true
	if _surface.get_global_rect().has_point(pointer):
		return true
	if _pointer_press_hold:
		return true
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and (hovered == _surface or _surface.is_ancestor_of(hovered)):
		return true
	return owns_content_focus()


func _apply_background_opacity() -> void:
	if not is_instance_valid(_surface):
		return
	_surface.self_modulate = Color(1.0, 1.0, 1.0, _background_opacity)


func _sync_controls() -> void:
	if not is_instance_valid(_handle): return
	_handle.tooltip_text = "Open %s panel" % _panel_title
	_handle.accessibility_name = "%s panel" % _panel_title


func _is_pinned() -> bool:
	return not _auto_hide


func _set_open(open: bool, immediate: bool = false) -> void:
	if not is_instance_valid(_surface) or not is_instance_valid(_handle):
		return
	if open == _open and not immediate:
		return
	_open = open
	open_changed.emit(open)
	if _transition != null and _transition.is_running():
		_transition.kill()
		_transition = null
	if open:
		_surface.visible = true
		_surface.mouse_filter = Control.MOUSE_FILTER_STOP
		_handle.visible = false
		if immediate or _reduced_motion or not is_inside_tree():
			_apply_background_opacity()
			return
		_surface.self_modulate.a = 0.0
		_transition = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_transition.tween_property(_surface, "self_modulate:a", _background_opacity, TRANSITION_SECONDS)
		return

	_handle.visible = true
	_surface.visible = false
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_background_opacity()


func set_pinned(pinned: bool) -> void:
	_auto_hide = not pinned
	_manually_collapsed = false
	if pinned:
		_reveal_deadline_ms = 0
		_set_open(true)
	else:
		_reveal_deadline_ms = Time.get_ticks_msec() + INTERACTION_GRACE_MS
		_set_open(true)
	pin_changed.emit(pinned)


func collapse() -> void:
	if _required:
		return
	_manually_collapsed = true
	_reveal_deadline_ms = 0
	release_panel_focus()
	_set_open(false)
	collapsed.emit()


func _on_handle_pressed() -> void:
	reveal()


func _on_handle_mouse_entered() -> void:
	_handle_hover_started_ms = Time.get_ticks_msec()
	_tab_shape.color = TAB_HOVER_COLOR


func _on_handle_mouse_exited() -> void:
	_handle_hover_started_ms = -1
	_tab_shape.color = TAB_IDLE_COLOR


func _on_handle_button_down() -> void:
	_tab_shape.color = TAB_PRESSED_COLOR


func _on_handle_button_up() -> void:
	_tab_shape.color = TAB_HOVER_COLOR if _handle.is_hovered() else TAB_IDLE_COLOR
