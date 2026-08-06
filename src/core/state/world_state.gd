class_name WorldState
extends RefCounted

var _terrain_overrides: Dictionary = {}
var _door_states: Dictionary = {}
var _discovered_secrets: Dictionary = {}
var _disabled_triggers: Dictionary = {}
var _visited_cells: Dictionary = {}
var _trigger_chances: Dictionary = {}
var _acquired_maps: Dictionary = {}
var _random_regions: Dictionary = {}


func terrain_for(map_id: String, cell: MapCell) -> String:
	return String(_terrain_overrides.get(_cell_key(map_id, cell.coordinate), cell.terrain_id))


func replace_terrain(map_id: String, coordinate: Vector2i, terrain_id: String) -> void:
	_terrain_overrides[_cell_key(map_id, coordinate)] = terrain_id


func open_door(door_id: String) -> void:
	if not door_id.is_empty():
		_door_states[door_id] = "open"


func door_is_open(door_id: String, initially_open: bool = false) -> bool:
	if door_id.is_empty():
		return true
	return _door_states.get(door_id, "open" if initially_open else "closed") == "open"


func discover_secret(secret_id: String) -> void:
	if not secret_id.is_empty():
		_discovered_secrets[secret_id] = true


func secret_is_discovered(secret_id: String, initially_discovered: bool = false) -> bool:
	return secret_id.is_empty() or initially_discovered or _discovered_secrets.has(secret_id)


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


func acquire_map(map_id: String) -> void:
	if not map_id.is_empty():
		_acquired_maps[map_id] = true


func has_map(map_id: String) -> bool:
	return _acquired_maps.has(map_id)


func set_random_region(region: RandomRegionState) -> void:
	if region != null and not region.id.is_empty():
		_random_regions[region.id] = region


func random_region(region: RandomEncounterRegion) -> RandomRegionState:
	if _random_regions.has(region.id):
		return _random_regions[region.id] as RandomRegionState
	return RandomRegionState.new(region.id, region.chance_ten_thousand, region.battle_minimum, region.battle_maximum, region.random_door_percents())


func mark_visited(map_id: String, coordinate: Vector2i) -> void:
	_visited_cells[_cell_key(map_id, coordinate)] = true


func was_visited(map_id: String, coordinate: Vector2i) -> bool:
	return _visited_cells.has(_cell_key(map_id, coordinate))


func to_data() -> Dictionary:
	var random_regions: Array[Dictionary] = []
	var random_region_ids: Array = _random_regions.keys()
	random_region_ids.sort()
	for region_id: Variant in random_region_ids:
		random_regions.append((_random_regions[region_id] as RandomRegionState).to_data())
	return {
		"terrainOverrides": _sorted_dictionary(_terrain_overrides),
		"doorStates": _sorted_dictionary(_door_states),
		"discoveredSecrets": _sorted_keys(_discovered_secrets),
		"disabledTriggers": _sorted_keys(_disabled_triggers),
		"visitedCells": _sorted_keys(_visited_cells),
		"triggerChances": _sorted_dictionary(_trigger_chances),
		"acquiredMaps": _sorted_keys(_acquired_maps),
		"randomRegions": random_regions,
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
	for key: Variant in data["doorStates"]:
		if not key is String or data["doorStates"][key] not in ["open", "closed"]:
			return null
		state._door_states[key] = data["doorStates"][key]
	if not _load_key_array(data["discoveredSecrets"], state._discovered_secrets) or not _load_key_array(data["disabledTriggers"], state._disabled_triggers) or not _load_key_array(data["visitedCells"], state._visited_cells):
		return null
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
			state._random_regions[region.id] = region
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
