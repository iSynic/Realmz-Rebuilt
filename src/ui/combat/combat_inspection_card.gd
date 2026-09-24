## Presents read-only combatant facts without replacing the active battle task.

class_name CombatInspectionCard
extends PanelContainer

const SECTIONS: Array[StringName] = [&"attacks", &"items", &"conditions"]

var _combatant: InteractionRequestValue.Combatant
var _section := 0
var _pinned := false
var _stage_rect := Rect2()
var _anchor := Vector2.ZERO
var _previous_focus: WeakRef


func _ready() -> void:
	for index: int in SECTIONS.size():
		(%Tabs.get_child(index) as Button).pressed.connect(func() -> void: _select_section(index))
	%Pin.pressed.connect(func() -> void: _set_pinned(true))
	%Close.pressed.connect(dismiss)
	minimum_size_changed.connect(func() -> void: _apply_layout.call_deferred())
	set_process(false)


func present(combatant: InteractionRequestValue.Combatant, pinned: bool) -> void:
	if visible and _pinned and not pinned:
		return
	var changed := _combatant == null or _combatant.id != combatant.id
	if visible and not changed and _pinned == pinned:
		return
	if not visible:
		_previous_focus = weakref(get_viewport().gui_get_focus_owner())
	if not visible or changed:
		_anchor = get_global_mouse_position()
	_combatant = combatant
	%CombatantName.text = combatant.name
	%AttackCount.text = "%s attacks per round" % combatant.attacks
	visible = true
	_set_pinned(pinned)
	_select_section(_section)
	set_process(true)
	_apply_layout()


func set_stage_rect(stage_rect: Rect2) -> void:
	_stage_rect = stage_rect
	_apply_layout()


func dismiss() -> bool:
	if not visible:
		return false
	visible = false
	_pinned = false
	set_process(false)
	var previous: Control = _previous_focus.get_ref() as Control if _previous_focus != null else null
	if is_instance_valid(previous) and previous.is_visible_in_tree():
		previous.grab_focus()
	return true


func handle_input(event: InputEvent) -> bool:
	if not visible:
		return false
	if event.is_action_pressed(&"realmz_back"):
		return dismiss()
	if _pinned and event is InputEventMouseButton and event.pressed and not (event.ctrl_pressed or event.meta_pressed) and not get_global_rect().has_point(event.position):
		return dismiss()
	if not _pinned or not event is InputEventKey or not event.is_pressed():
		return false
	var key := event as InputEventKey
	if key.keycode in [KEY_LEFT, KEY_RIGHT]:
		_select_section(posmod(_section + (-1 if key.keycode == KEY_LEFT else 1), SECTIONS.size()))
	elif key.keycode in [KEY_UP, KEY_DOWN]:
		%RecordScroll.scroll_vertical += -32 if key.keycode == KEY_UP else 32
	elif key.keycode == KEY_TAB:
		var controls: Array[Control] = [%Tabs.get_child(0), %Tabs.get_child(1), %Tabs.get_child(2), %Close]
		var index := controls.find(get_viewport().gui_get_focus_owner())
		controls[posmod(index + (-1 if key.shift_pressed else 1), controls.size())].grab_focus()
	elif key.keycode in [KEY_ENTER, KEY_SPACE]:
		var focused := get_viewport().gui_get_focus_owner() as Button
		if focused != null and is_ancestor_of(focused):
			focused.pressed.emit()
	return true


func handle_controller(action: StringName, direction: Vector2i, scroll: Vector2i) -> bool:
	if not visible or not _pinned:
		return false
	if action == &"realmz_controller_back" or action == &"realmz_controller_confirm":
		dismiss()
	elif direction.x != 0 or action in [&"realmz_controller_section_previous", &"realmz_controller_section_next"]:
		var delta := direction.x if direction.x != 0 else (-1 if action == &"realmz_controller_section_previous" else 1)
		_select_section(posmod(_section + delta, SECTIONS.size()))
	elif direction.y != 0 or scroll.y != 0:
		%RecordScroll.scroll_vertical += (direction.y + scroll.y) * 32
	return true


func _process(_delta: float) -> void:
	if not get_window().has_focus():
		dismiss()
	elif not _pinned and not Input.is_physical_key_pressed(KEY_CTRL) and not Input.is_physical_key_pressed(KEY_META):
		dismiss()


func _set_pinned(pinned: bool) -> void:
	_pinned = pinned
	%Pin.visible = not pinned
	%Hint.text = "Pinned • Esc to close" if pinned else "Hold Ctrl to inspect • click to pin"
	if pinned:
		%Close.grab_focus()


func _select_section(index: int) -> void:
	_section = index
	if _combatant == null:
		return
	for tab_index: int in SECTIONS.size():
		(%Tabs.get_child(tab_index) as Button).set_pressed_no_signal(tab_index == index)
	var rows: Array[String] = _combatant.attack_rows if index == 0 else (_combatant.items if index == 1 else _combatant.conditions)
	%Record.text = "\n\n".join(rows) if not rows.is_empty() else "None"
	%RecordScroll.scroll_vertical = 0


func _apply_layout() -> void:
	if not is_inside_tree() or not _stage_rect.has_area():
		return
	var bounds := _stage_rect.grow(-8.0)
	size = Vector2(minf(376.0, bounds.size.x), minf(320.0, bounds.size.y))
	var next := _anchor + Vector2(28.0, 20.0)
	if next.x + size.x > bounds.end.x:
		next.x = _anchor.x - size.x - 28.0
	position = Vector2(clampf(next.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - size.x)), clampf(next.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - size.y)))
