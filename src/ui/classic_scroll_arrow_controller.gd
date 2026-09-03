class_name ClassicScrollArrowController
extends RefCounted


static func configure_descendants(root: Node, step: float, initial_delay: float, repeat_interval: float) -> void:
	if root is ScrollContainer:
		bind(root as ScrollContainer, step, initial_delay, repeat_interval)
	for child: Node in root.get_children():
		configure_descendants(child, step, initial_delay, repeat_interval)


static func bind(scroll: ScrollContainer, step: float, initial_delay: float, repeat_interval: float) -> void:
	if scroll == null:
		return
	configure(scroll, step)
	_bind_bar(scroll.get_v_scroll_bar(), true, step, initial_delay, repeat_interval)
	_bind_bar(scroll.get_h_scroll_bar(), false, step, initial_delay, repeat_interval)


static func configure(scroll: ScrollContainer, step: float) -> void:
	if scroll == null:
		return
	scroll.scroll_vertical_custom_step = step
	scroll.scroll_horizontal_custom_step = step


static func arrow_direction(bar: ScrollBar, position: Vector2, vertical: bool) -> int:
	if bar == null:
		return 0
	var arrow_extent := bar.size.x if vertical else bar.size.y
	var axis_position := position.y if vertical else position.x
	var axis_size := bar.size.y if vertical else bar.size.x
	if arrow_extent <= 0.0 or axis_size < arrow_extent * 2.0:
		return 0
	if axis_position >= 0.0 and axis_position < arrow_extent:
		return -1
	if axis_position >= axis_size - arrow_extent and axis_position <= axis_size:
		return 1
	return 0


static func _bind_bar(bar: ScrollBar, vertical: bool, step: float, initial_delay: float, repeat_interval: float) -> void:
	if bar == null or bar.has_meta(&"realmz_scroll_repeat"):
		return
	bar.set_meta(&"realmz_scroll_repeat", true)
	bar.set_meta(&"realmz_scroll_direction", 0)
	var timer := Timer.new()
	timer.name = "ClassicArrowRepeat"
	timer.one_shot = true
	bar.add_child(timer)
	timer.timeout.connect(_on_repeat.bind(bar, timer, step, repeat_interval))
	bar.gui_input.connect(_on_gui_input.bind(bar, vertical, timer, step, initial_delay, repeat_interval))


static func _on_gui_input(event: InputEvent, bar: ScrollBar, vertical: bool, timer: Timer, step: float, initial_delay: float, repeat_interval: float) -> void:
	if not event is InputEventMouseButton or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.pressed:
		var direction := arrow_direction(bar, mouse_event.position, vertical)
		if direction == 0:
			return
		bar.set_meta(&"realmz_scroll_direction", direction)
		timer.start(initial_delay)
		return
	bar.set_meta(&"realmz_scroll_direction", 0)
	timer.stop()


static func _on_repeat(bar: ScrollBar, timer: Timer, step: float, repeat_interval: float) -> void:
	var direction := int(bar.get_meta(&"realmz_scroll_direction", 0))
	if direction == 0 or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		bar.set_meta(&"realmz_scroll_direction", 0)
		return
	_step(bar, direction, step)
	timer.start(repeat_interval)


static func _step(bar: ScrollBar, direction: int, default_step: float) -> void:
	var increment := bar.custom_step if bar.custom_step > 0.0 else default_step
	bar.value += float(direction) * increment
