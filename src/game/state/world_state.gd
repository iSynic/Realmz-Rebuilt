class_name WorldState
extends RefCounted

var _terrain_overrides: Dictionary = {}
var _boat_presence_overrides: Dictionary = {}
var _door_states: Dictionary = {}
var _discovered_secrets: Dictionary = {}
var _disabled_triggers: Dictionary = {}
var _visited_cells: Dictionary = {}
var _seen_cells: Dictionary = {}
var _trigger_chances: Dictionary = {}
var _acquired_maps: Dictionary = {}
var _random_regions: Dictionary = {}
var _has_random_region_bounds_override: bool = false
var _random_region_bounds_revision: int = 0
var _map_darkness: Dictionary = {}
var _map_landlooks: Dictionary = {}
var _location_notes: Dictionary = {}
var _topology_revision: int = 0
var _exploration_revision: int = 0


func terrain_for(map_id: String, cell: MapCell) -> String:
	return String(_terrain_overrides.get(_cell_key(map_id, cell.coordinate), cell.terrain_id))


func replace_terrain(map_id: String, coordinate: Vector2i, terrain_id: String) -> void:
	var key := _cell_key(map_id, coordinate)
	if String(_terrain_overrides.get(key, "")) != terrain_id:
		_terrain_overrides[key] = terrain_id
		_topology_revision += 1


func has_terrain_override(map_id: String, coordinate: Vector2i) -> bool:
	return _terrain_overrides.has(_cell_key(map_id, coordinate))


func classic_tile_for(map_id: String, cell: MapCell) -> int:
	var terrain_id := terrain_for(map_id, cell)
	var prefix := "classic.terrain."
	if terrain_id.begins_with(prefix):
		var value := terrain_id.trim_prefix(prefix)
		if value.is_valid_int():
			return int(value)
	return cell.render_tile


static func normalized_classic_land_tile(raw_tile: int) -> int:
	var magnitude := -raw_tile if raw_tile < 0 else raw_tile & ~0x6000
	while magnitude > 999:
		magnitude -= 1000
	return magnitude


static func classic_special_land_overlay(raw_tile: int) -> String:
	if raw_tile >= 0:
		var positive_resource_id := normalized_classic_land_tile(raw_tile)
		return "realmz-land-cicn-%d" % positive_resource_id if positive_resource_id > 200 else ""
	if raw_tile < -3999:
		return ""
	var resource_id := raw_tile
	for index: int in 3:
		if resource_id >= -999:
			break
		resource_id += 1000
	return "realmz-special-land-neg-%d" % absi(resource_id)


func set_boat_present(map_id: String, coordinate: Vector2i, present: bool) -> void:
	var key := _cell_key(map_id, coordinate)
	if not _boat_presence_overrides.has(key) or bool(_boat_presence_overrides[key]) != present:
		_boat_presence_overrides[key] = present
		_topology_revision += 1


func boat_presence_state(map_id: String, coordinate: Vector2i) -> int:
	var key := _cell_key(map_id, coordinate)
	if not _boat_presence_overrides.has(key):
		return -1
	return 1 if bool(_boat_presence_overrides[key]) else 0


func boat_presence_overrides() -> Dictionary:
	return _boat_presence_overrides.duplicate()


func open_door(door_id: String) -> void:
	if not door_id.is_empty() and not door_is_open(door_id):
		_door_states[door_id] = "open"
		_topology_revision += 1


func door_is_open(door_id: String, initially_open: bool = false) -> bool:
	if door_id.is_empty():
		return true
	return _door_states.get(door_id, "open" if initially_open else "closed") == "open"


func discover_secret(secret_id: String) -> void:
	if not secret_id.is_empty() and not _discovered_secrets.has(secret_id):
		_discovered_secrets[secret_id] = true
		_topology_revision += 1


func secret_is_discovered(secret_id: String, initially_discovered: bool = false) -> bool:
	return secret_id.is_empty() or initially_discovered or _discovered_secrets.has(secret_id)


func topology_revision() -> int:
	return _topology_revision


func exploration_revision() -> int:
	return _exploration_revision


func disable_trigger(trigger_id: String) -> void:
	_disabled_triggers[trigger_id] = true


func trigger_is_disabled(trigger_id: String) -> bool:
	return _disabled_triggers.has(trigger_id)


func set_trigger_chance(trigger_id: String, percent: int) -> void:
	if trigger_id.is_empty():
		return
	_trigger_chances[trigger_id] = clampi(percent, -1, 100)
	if percent < 0:
		disable_trigger(trigger_id)


func trigger_chance(trigger_id: String, authored_percent: int) -> int:
	return int(_trigger_chances.get(trigger_id, authored_percent))


func trigger_chance_is_overridden(trigger_id: String) -> bool:
	return _trigger_chances.has(trigger_id)


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


func set_random_region(region: RandomRegionState) -> void:
	if region != null and not region.id.is_empty():
		var previous := _random_regions.get(region.id) as RandomRegionState
		if previous == null and region.bounds_overridden or previous != null and (previous.bounds_overridden != region.bounds_overridden or region.bounds_overridden and previous.bounds_edges() != region.bounds_edges()):
			_random_region_bounds_revision += 1
		_random_regions[region.id] = region
		_has_random_region_bounds_override = false
		for value: RandomRegionState in _random_regions.values():
			if value.bounds_overridden:
				_has_random_region_bounds_override = true
				break


func random_region(region: RandomEncounterRegion) -> RandomRegionState:
	if _random_regions.has(region.id):
		return _random_regions[region.id] as RandomRegionState
	return RandomRegionState.new(region.id, region.chance_ten_thousand, region.battle_minimum, region.battle_maximum, region.random_door_percents(), region.bounds)


func random_region_ids_at(map: MapDefinition, coordinate: Vector2i) -> Array[String]:
	if map == null or map.topology.cell_at(coordinate) == null:
		return []
	var authored_ids := map.topology.cell_at(coordinate).random_rect_ids()
	var result: Array[String] = []
	for region: RandomEncounterRegion in map.random_regions():
		var effective := random_region(region)
		if effective.contains(region.bounds, coordinate) if effective.bounds_overridden else authored_ids.has(region.id):
			result.append(region.id)
	return result


func has_random_region_at(map: MapDefinition, coordinate: Vector2i) -> bool:
	if map == null:
		return false
	var cell := map.topology.cell_at(coordinate)
	if cell == null:
		return false
	var authored_ids := cell.random_rect_ids()
	if not _has_random_region_bounds_override:
		return not authored_ids.is_empty()
	for region: RandomEncounterRegion in map.random_regions():
		var effective := random_region(region)
		if effective.contains(region.bounds, coordinate) if effective.bounds_overridden else authored_ids.has(region.id):
			return true
	return false


func random_region_bounds_revision() -> int:
	return _random_region_bounds_revision


func set_map_darkness(map_id: String, dark: bool) -> void:
	if not map_id.is_empty():
		_map_darkness[map_id] = dark


func map_is_dark(map: MapDefinition) -> bool:
	return false if map == null else bool(_map_darkness.get(map.id, map.dark))


func set_map_landlook(map_id: String, landlook: int) -> void:
	if not map_id.is_empty() and (not _map_landlooks.has(map_id) or int(_map_landlooks[map_id]) != landlook):
		_map_landlooks[map_id] = landlook
		_topology_revision += 1


func map_landlook(map: MapDefinition) -> int:
	return -1 if map == null else int(_map_landlooks.get(map.id, map.landlook))


func map_landlook_for(map_id: String, authored_landlook: int) -> int:
	return int(_map_landlooks.get(map_id, authored_landlook))


func mark_visited(map_id: String, coordinate: Vector2i) -> void:
	var key := _cell_key(map_id, coordinate)
	if not _visited_cells.has(key) or not _seen_cells.has(key):
		_visited_cells[key] = true
		_seen_cells[key] = true
		_exploration_revision += 1


func was_visited(map_id: String, coordinate: Vector2i) -> bool:
	return _visited_cells.has(_cell_key(map_id, coordinate))


func visited_coordinates(map_id: String) -> Array[Vector2i]:
	return _coordinates_for(map_id, _visited_cells)


func mark_seen(map_id: String, coordinate: Vector2i) -> void:
	var key := _cell_key(map_id, coordinate)
	if not _seen_cells.has(key):
		_seen_cells[key] = true
		_exploration_revision += 1


func mark_seen_many(map_id: String, coordinates: Array[Vector2i]) -> void:
	for coordinate: Vector2i in coordinates:
		mark_seen(map_id, coordinate)


func was_seen(map_id: String, coordinate: Vector2i) -> bool:
	return _seen_cells.has(_cell_key(map_id, coordinate))


func seen_coordinates(map_id: String) -> Array[Vector2i]:
	return _coordinates_for(map_id, _seen_cells)


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


func to_data() -> Dictionary:
	var random_regions: Array[Dictionary] = []
	var random_region_ids: Array = _random_regions.keys()
	random_region_ids.sort()
	for region_id: Variant in random_region_ids:
		random_regions.append((_random_regions[region_id] as RandomRegionState).to_data())
	var location_notes_data: Array[Dictionary] = []
	for note: LocationNoteState in location_notes():
		location_notes_data.append(note.to_data())
	return {
		"terrainOverrides": _sorted_dictionary(_terrain_overrides),
		"boatPresenceOverrides": _sorted_dictionary(_boat_presence_overrides),
		"doorStates": _sorted_dictionary(_door_states),
		"discoveredSecrets": _sorted_keys(_discovered_secrets),
		"disabledTriggers": _sorted_keys(_disabled_triggers),
		"visitedCells": _sorted_keys(_visited_cells),
		"seenCells": _sorted_keys(_seen_cells),
		"triggerChances": _sorted_dictionary(_trigger_chances),
		"acquiredMaps": _sorted_keys(_acquired_maps),
		"randomRegions": random_regions,
		"mapDarkness": _sorted_dictionary(_map_darkness),
		"mapLandlooks": _sorted_dictionary(_map_landlooks),
		"locationNotes": location_notes_data,
	}


static func from_data(data: Variant) -> WorldState:
	if not data is Dictionary:
		return null
	for field: String in ["terrainOverrides", "doorStates", "discoveredSecrets", "disabledTriggers", "visitedCells"]:
		if not data.has(field):
			return null
	if not data["terrainOverrides"] is Dictionary or not data["doorStates"] is Dictionary:
		return null
	var state := WorldState.new()
	for key: Variant in data["terrainOverrides"]:
		if not key is String or not data["terrainOverrides"][key] is String:
			return null
		state._terrain_overrides[key] = data["terrainOverrides"][key]
	if data.has("boatPresenceOverrides"):
		if not data["boatPresenceOverrides"] is Dictionary:
			return null
		for key: Variant in data["boatPresenceOverrides"]:
			if not key is String or key.is_empty() or not data["boatPresenceOverrides"][key] is bool:
				return null
			state._boat_presence_overrides[key] = data["boatPresenceOverrides"][key]
	for key: Variant in data["doorStates"]:
		if not key is String or data["doorStates"][key] not in ["open", "closed"]:
			return null
		state._door_states[key] = data["doorStates"][key]
	if not _load_key_array(data["discoveredSecrets"], state._discovered_secrets) or not _load_key_array(data["disabledTriggers"], state._disabled_triggers) or not _load_key_array(data["visitedCells"], state._visited_cells):
		return null
	if data.has("seenCells"):
		if not _load_key_array(data["seenCells"], state._seen_cells):
			return null
	else:
		state._seen_cells = state._visited_cells.duplicate()
	for key: Variant in state._visited_cells:
		state._seen_cells[key] = true
	if data.has("triggerChances"):
		if not data["triggerChances"] is Dictionary:
			return null
		for key: Variant in data["triggerChances"]:
			var percent := _integer(data["triggerChances"][key])
			if not key is String or key.is_empty() or percent < -1 or percent > 100:
				return null
			state._trigger_chances[key] = percent
	if data.has("acquiredMaps") and not _load_key_array(data["acquiredMaps"], state._acquired_maps):
		return null
	if data.has("randomRegions"):
		if not data["randomRegions"] is Array:
			return null
		for entry: Variant in data["randomRegions"]:
			var region := RandomRegionState.from_data(entry)
			if region == null or state._random_regions.has(region.id):
				return null
			state.set_random_region(region)
	if data.has("mapDarkness"):
		if not data["mapDarkness"] is Dictionary:
			return null
		for key: Variant in data["mapDarkness"]:
			if not key is String or key.is_empty() or not data["mapDarkness"][key] is bool:
				return null
			state._map_darkness[key] = data["mapDarkness"][key]
	if data.has("mapLandlooks"):
		if not data["mapLandlooks"] is Dictionary:
			return null
		for key: Variant in data["mapLandlooks"]:
			var landlook := _signed_integer(data["mapLandlooks"][key])
			if not key is String or key.is_empty() or landlook < -128 or landlook > 127:
				return null
			state._map_landlooks[key] = landlook
	if data.has("locationNotes"):
		if not data["locationNotes"] is Array:
			return null
		for entry: Variant in data["locationNotes"]:
			var note := LocationNoteState.from_data(entry)
			if note == null or state._location_notes.has(note.id()):
				return null
			state._location_notes[note.id()] = note
	return state


static func _load_key_array(value: Variant, target: Dictionary) -> bool:
	if not value is Array:
		return false
	for key: Variant in value:
		if not key is String or key.is_empty() or target.has(key):
			return false
		target[key] = true
	return true


static func _sorted_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = source.keys()
	keys.sort()
	for key: Variant in keys:
		result[key] = source[key]
	return result


static func _sorted_keys(source: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in source.keys():
		keys.append(String(key))
	keys.sort()
	return keys


static func _cell_key(map_id: String, coordinate: Vector2i) -> String:
	return "%s:%d,%d" % [map_id, coordinate.x, coordinate.y]


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
