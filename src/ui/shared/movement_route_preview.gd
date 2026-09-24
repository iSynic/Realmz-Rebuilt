## Presents transient destination selection and request-owned movement routes.
class_name MovementRoutePreview
extends Control

signal destination_selected(coordinate: Vector2i)
signal destination_hovered(coordinate: Vector2i)
signal mode_changed(enabled: bool)

var enabled := false
var latched := false
var available := false
var reachable: Array[Vector2i] = []
var route: Array[Vector2i] = []
var destination := Vector2i(-1, -1)
var camera := Vector2i.ZERO
var cells := Vector2i.ZERO
var draw_origin := Vector2.ZERO
var cell_size := 32.0

func configure_geometry(origin: Vector2, top_left: Vector2i, visible_cells: Vector2i, tile_size: float) -> void:
	draw_origin = origin
	camera = top_left
	cells = visible_cells
	cell_size = tile_size
	queue_redraw()

func set_available(value: bool, shift_held: bool, always_enabled: bool = false) -> void:
	available = value
	enabled = available and (latched or shift_held or always_enabled)
	if not available:
		latched = false
	%RouteHint.visible = enabled or not route.is_empty()
	queue_redraw()

func clear() -> void:
	route.clear()
	reachable.clear()
	destination = Vector2i(-1, -1)
	latched = false
	enabled = false
	%RouteHint.text = ""
	queue_redraw()

func toggle() -> void:
	latched = not latched
	mode_changed.emit(latched)

func show_preview(path: Array[Vector2i], message: String, affordable: Array[Vector2i] = []) -> void:
	route = path.duplicate()
	reachable = affordable.duplicate()
	%RouteHint.text = message
	%RouteHint.visible = enabled or not route.is_empty()
	queue_redraw()

func handle_pointer(event: InputEvent) -> bool:
	if not available or not event is InputEventMouse:
		return false
	var mouse := event as InputEventMouse
	if mouse.ctrl_pressed or mouse.meta_pressed:
		return false
	var direct_move: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT
	if not enabled and not direct_move:
		return false
	var offset := mouse.position - draw_origin
	var local_cell := Vector2i(floori(offset.x / cell_size), floori(offset.y / cell_size))
	var coordinate := camera + local_cell if Rect2i(Vector2i.ZERO, cells).has_point(local_cell) else Vector2i(-1, -1)
	if coordinate != destination:
		destination = coordinate
		destination_hovered.emit(coordinate)
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] and button.pressed:
			destination_selected.emit(coordinate)
	return true

func move_focus(direction: Vector2i, origin: Vector2i) -> void:
	if destination.x < 0: destination = origin
	destination += direction
	destination = destination.clamp(camera, camera + cells - Vector2i.ONE)
	destination_hovered.emit(destination)

func _draw() -> void:
	if not enabled and route.is_empty(): return
	var bounds := Rect2i(camera, cells)
	for coordinate: Vector2i in reachable:
		if bounds.has_point(coordinate):
			draw_rect(Rect2(draw_origin + Vector2(coordinate - camera) * cell_size, Vector2.ONE * cell_size).grow(-2), Color(0.25, 0.8, 0.85, 0.22))
	for coordinate: Vector2i in route:
		if bounds.has_point(coordinate):
			draw_rect(Rect2(draw_origin + Vector2(coordinate - camera) * cell_size, Vector2.ONE * cell_size).grow(-5), Color(0.96, 0.78, 0.3, 0.65))
	if bounds.has_point(destination):
		draw_rect(Rect2(draw_origin + Vector2(destination - camera) * cell_size, Vector2.ONE * cell_size).grow(-1), Color(0.98, 0.85, 0.4), false, 2)
