## Stores mutable exploration memory, acquired maps, and player location notes.

class_name WorldExplorationState
extends RefCounted

var _visited_cells: Dictionary = {}
var _seen_cells: Dictionary = {}
var _acquired_maps: Dictionary = {}
var _location_notes: Dictionary = {}
var _revision: int = 0


func revision() -> int:
	return _revision


func acquire_map(map_id: String) -> void:
	if not map_id.is_empty():
		_acquired_maps[map_id] = true


func has_map(map_id: String) -> bool:
	return _acquired_maps.has(map_id)


func acquired_map_ids() -> Array[String]:
	var result: Array[String] = []
	for map_id: Variant in _acquired_maps.keys():
		if map_id is String:
			result.append(map_id)
	result.sort()
	return result


func upsert_location_note(note: LocationNoteState) -> bool:
	if note == null or not note.is_structurally_valid():
		return false
	for current: LocationNoteState in location_notes_for_kind(note.map_kind):
		if current.record_ordinal == note.record_ordinal and current.id() != note.id():
			return false
	_location_notes[note.id()] = note
	return true


func remove_location_note(map_id: String, coordinate: Vector2i) -> bool:
	return _location_notes.erase(LocationNoteState.key_for(map_id, coordinate))


func location_note_at(map_id: String, coordinate: Vector2i) -> LocationNoteState:
	return _location_notes.get(LocationNoteState.key_for(map_id, coordinate)) as LocationNoteState


func location_notes() -> Array[LocationNoteState]:
	var result: Array[LocationNoteState] = []
	for value: Variant in _location_notes.values():
		result.append(value as LocationNoteState)
	result.sort_custom(func(left: LocationNoteState, right: LocationNoteState) -> bool:
		return String(left.map_kind) < String(right.map_kind) or left.map_kind == right.map_kind and left.record_ordinal < right.record_ordinal
	)
	return result


func location_notes_for_kind(map_kind: StringName) -> Array[LocationNoteState]:
	var result: Array[LocationNoteState] = []
	for note: LocationNoteState in location_notes():
		if note.map_kind == map_kind:
			result.append(note)
	return result


func next_location_note_ordinal(map_kind: StringName) -> int:
	var used: Dictionary = {}
	for note: LocationNoteState in location_notes_for_kind(map_kind):
		used[note.record_ordinal] = true
	for ordinal: int in LocationNoteState.MAX_NOTES_PER_MAP_KIND:
		if not used.has(ordinal):
			return ordinal
	return -1


func mark_visited(map_id: String, coordinate: Vector2i) -> void:
	var key := _cell_key(map_id, coordinate)
	if not _visited_cells.has(key) or not _seen_cells.has(key):
		_visited_cells[key] = true
		_seen_cells[key] = true
		_revision += 1


func was_visited(map_id: String, coordinate: Vector2i) -> bool:
	return _visited_cells.has(_cell_key(map_id, coordinate))


func visited_coordinates(map_id: String) -> Array[Vector2i]:
	return _coordinates_for(map_id, _visited_cells)


func mark_seen(map_id: String, coordinate: Vector2i) -> void:
	var key := _cell_key(map_id, coordinate)
	if not _seen_cells.has(key):
		_seen_cells[key] = true
		_revision += 1


func mark_seen_many(map_id: String, coordinates: Array[Vector2i]) -> void:
	for coordinate: Vector2i in coordinates:
		mark_seen(map_id, coordinate)


func was_seen(map_id: String, coordinate: Vector2i) -> bool:
	return _seen_cells.has(_cell_key(map_id, coordinate))


func seen_coordinates(map_id: String) -> Array[Vector2i]:
	return _coordinates_for(map_id, _seen_cells)


func to_data() -> Dictionary:
	var location_notes_data: Array[Dictionary] = []
	for note: LocationNoteState in location_notes():
		location_notes_data.append(note.to_data())
	return {
		"visitedCells": _sorted_keys(_visited_cells),
		"seenCells": _sorted_keys(_seen_cells),
		"acquiredMaps": _sorted_keys(_acquired_maps),
		"locationNotes": location_notes_data,
	}


static func from_data(data: Dictionary) -> WorldExplorationState:
	if not data.has("visitedCells"):
		return null
	var state := WorldExplorationState.new()
	if not _load_key_array(data["visitedCells"], state._visited_cells):
		return null
	if data.has("seenCells"):
		if not _load_key_array(data["seenCells"], state._seen_cells):
			return null
	else:
		state._seen_cells = state._visited_cells.duplicate()
	for key: Variant in state._visited_cells:
		state._seen_cells[key] = true
	if data.has("acquiredMaps") and not _load_key_array(data["acquiredMaps"], state._acquired_maps):
		return null
	if not _load_location_notes(data, state):
		return null
	return state


static func _load_location_notes(data: Dictionary, state: WorldExplorationState) -> bool:
	if not data.has("locationNotes"):
		return true
	if not data["locationNotes"] is Array:
		return false
	for entry: Variant in data["locationNotes"]:
		var note := LocationNoteState.from_data(entry)
		if note == null or state._location_notes.has(note.id()):
			return false
		state._location_notes[note.id()] = note
	return true


func _coordinates_for(map_id: String, source: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var prefix := "%s:" % map_id
	for key_value: Variant in source.keys():
		var key := String(key_value)
		if not key.begins_with(prefix):
			continue
		var components := key.trim_prefix(prefix).split(",", false, 1)
		if components.size() != 2 or not components[0].is_valid_int() or not components[1].is_valid_int():
			continue
		result.append(Vector2i(int(components[0]), int(components[1])))
	result.sort_custom(func(left: Vector2i, right: Vector2i) -> bool: return left.y < right.y or left.y == right.y and left.x < right.x)
	return result


static func _load_key_array(value: Variant, target: Dictionary) -> bool:
	if not value is Array:
		return false
	for key: Variant in value:
		if not key is String or key.is_empty() or target.has(key):
			return false
		target[key] = true
	return true


static func _sorted_keys(source: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in source.keys():
		keys.append(String(key))
	keys.sort()
	return keys


static func _cell_key(map_id: String, coordinate: Vector2i) -> String:
	return "%s:%d,%d" % [map_id, coordinate.x, coordinate.y]
