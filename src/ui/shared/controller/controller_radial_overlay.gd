## Presents a paged tap-and-confirm controller command radial.

class_name ControllerRadialOverlay
extends Control

## Reusable, presentation-only radial command chooser.
## Callers provide ordered ControllerRadialEntry values and consume command_selected.

signal command_selected(command_id: StringName)

const MAX_SECTORS_PER_PAGE := 8

@export var sector_radius: float = 174.0
@export var sector_gap: float = 0.035
@export var page_size: int = 8
@export var selected_color := Color("#c49c55")
@export var available_color := Color("#31485a")
@export var disabled_color := Color("#252f39")
@export var outline_color := Color("#a9bac0")

@onready var _page_indicator: Label = %PageIndicator
@onready var _title: Label = %Title
@onready var _selection_label: Label = %SelectionLabel
@onready var _reason_label: Label = %ReasonLabel

var _entries: Array[ControllerRadialEntry] = []
var _page: int = 0
var _selected_index: int = 0
var _open: bool = false


func _ready() -> void:
	visible = false
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_text()


func open(entries: Array[ControllerRadialEntry], initial_index: int = 0) -> void:
	_entries = entries.duplicate()
	_page = 0
	_selected_index = clampi(initial_index, 0, maxi(0, mini(_effective_page_size(), _entries.size()) - 1))
	_open = not _entries.is_empty()
	visible = _open
	if _open:
		grab_focus()
		_update_text()
		queue_redraw()


func set_title(value: String) -> void:
	if is_node_ready():
		_title.text = value


func close() -> void:
	_open = false
	visible = false
	queue_redraw()


func is_open() -> bool:
	return _open


func set_entries(entries: Array[ControllerRadialEntry]) -> void:
	_entries = entries.duplicate()
	_page = mini(_page, maxi(0, page_count() - 1))
	_selected_index = mini(_selected_index, maxi(0, current_page_entries().size() - 1))
	_update_text()
	queue_redraw()


func confirm_selected() -> void:
	if not _open:
		return
	var current := current_page_entries()
	if _selected_index < 0 or _selected_index >= current.size():
		return
	var entry := current[_selected_index]
	if not entry.enabled:
		_update_text()
		return
	command_selected.emit(entry.id)
	close()


func cancel() -> void:
	close()


func previous_page() -> void:
	if page_count() <= 1:
		return
	_page = posmod(_page - 1, page_count())
	_selected_index = mini(_selected_index, maxi(0, current_page_entries().size() - 1))
	_update_text()
	queue_redraw()


func next_page() -> void:
	if page_count() <= 1:
		return
	_page = (_page + 1) % page_count()
	_selected_index = mini(_selected_index, maxi(0, current_page_entries().size() - 1))
	_update_text()
	queue_redraw()


func move_direction(direction: Vector2) -> void:
	if not _open or direction.is_zero_approx():
		return
	var count := current_page_entries().size()
	if count == 0:
		return
	var requested_angle := atan2(direction.y, direction.x)
	var nearest_index := 0
	var nearest_distance := INF
	for index: int in count:
		var sector_angle := -PI * 0.5 + TAU * (float(index) + 0.5) / float(count)
		var distance := absf(wrapf(requested_angle - sector_angle, -PI, PI))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	_selected_index = nearest_index
	_update_text()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_UP: move_direction(Vector2.UP)
			KEY_DOWN: move_direction(Vector2.DOWN)
			KEY_LEFT: move_direction(Vector2.LEFT)
			KEY_RIGHT: move_direction(Vector2.RIGHT)
			KEY_PAGEUP: previous_page()
			KEY_PAGEDOWN: next_page()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: confirm_selected()
			KEY_ESCAPE: cancel()
			_: return
		get_viewport().set_input_as_handled()
		return


func _draw() -> void:
	if not _open:
		return
	var center := size * 0.5
	var current := current_page_entries()
	var count := current.size()
	if count == 0:
		return
	var radius := minf(sector_radius, minf(size.x, size.y) * 0.29)
	for index: int in count:
		var start := -PI * 0.5 + TAU * float(index) / float(count) + sector_gap
		var end := -PI * 0.5 + TAU * float(index + 1) / float(count) - sector_gap
		var color := disabled_color if not current[index].enabled else available_color
		if index == _selected_index:
			color = selected_color if current[index].enabled else selected_color.darkened(0.35)
		draw_colored_polygon(_sector(center, radius, start, end), color)
		draw_polyline(_sector(center, radius, start, end), outline_color, 2.0, true)
		var midpoint := (start + end) * 0.5
		var label_position := center + Vector2(cos(midpoint), sin(midpoint)) * radius * 0.64
		var font := ThemeDB.fallback_font
		var text := current[index].label
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string(font, label_position - Vector2(text_size.x * 0.5, -6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func _sector(center: Vector2, radius: float, start: float, end: float) -> PackedVector2Array:
	var points := PackedVector2Array([center])
	var segments := 12
	for step: int in range(segments + 1):
		var angle := lerpf(start, end, float(step) / float(segments))
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func current_page_entries() -> Array[ControllerRadialEntry]:
	var result: Array[ControllerRadialEntry] = []
	var first := _page * _effective_page_size()
	var last := mini(first + _effective_page_size(), _entries.size())
	for index: int in range(first, last):
		result.append(_entries[index])
	return result


func page_count() -> int:
	return maxi(1, ceili(float(_entries.size()) / float(_effective_page_size())))


func _effective_page_size() -> int:
	return clampi(page_size, 1, MAX_SECTORS_PER_PAGE)


func _update_text() -> void:
	if not is_node_ready():
		return
	var current := current_page_entries()
	_page_indicator.text = "Page %d / %d" % [_page + 1, page_count()]
	if current.is_empty():
		_selection_label.text = "No commands"
		_reason_label.text = ""
		return
	var entry := current[clampi(_selected_index, 0, current.size() - 1)]
	_selection_label.text = entry.label
	_reason_label.text = "Unavailable: %s" % entry.disabled_reason if not entry.enabled and not entry.disabled_reason.is_empty() else ("Unavailable" if not entry.enabled else "")
