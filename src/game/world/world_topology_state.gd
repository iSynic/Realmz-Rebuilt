## Stores mutable map topology and appearance overlays for one playthrough.

class_name WorldTopologyState
extends RefCounted

var _terrain_overrides: Dictionary = {}
var _boat_presence_overrides: Dictionary = {}
var _door_states: Dictionary = {}
var _discovered_secrets: Dictionary = {}
var _map_darkness: Dictionary = {}
var _map_landlooks: Dictionary = {}
var _revision: int = 0


func terrain_for(map_id: String, cell: MapCell) -> String:
	return String(_terrain_overrides.get(_cell_key(map_id, cell.coordinate), cell.terrain_id))


func replace_terrain(map_id: String, coordinate: Vector2i, terrain_id: String) -> void:
	var key := _cell_key(map_id, coordinate)
	if String(_terrain_overrides.get(key, "")) != terrain_id:
		_terrain_overrides[key] = terrain_id
		_revision += 1


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


func set_boat_present(map_id: String, coordinate: Vector2i, present: bool) -> void:
	var key := _cell_key(map_id, coordinate)
	if not _boat_presence_overrides.has(key) or bool(_boat_presence_overrides[key]) != present:
		_boat_presence_overrides[key] = present
		_revision += 1


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
		_revision += 1


func door_is_open(door_id: String, initially_open: bool = false) -> bool:
	if door_id.is_empty():
		return true
	return _door_states.get(door_id, "open" if initially_open else "closed") == "open"


func discover_secret(secret_id: String) -> void:
	if not secret_id.is_empty() and not _discovered_secrets.has(secret_id):
		_discovered_secrets[secret_id] = true
		_revision += 1


func secret_is_discovered(secret_id: String, initially_discovered: bool = false) -> bool:
	return secret_id.is_empty() or initially_discovered or _discovered_secrets.has(secret_id)


func revision() -> int:
	return _revision


func set_map_darkness(map_id: String, dark: bool) -> void:
	if not map_id.is_empty():
		_map_darkness[map_id] = dark


func map_is_dark(map: MapDefinition) -> bool:
	return false if map == null else bool(_map_darkness.get(map.id, map.dark))


func set_map_landlook(map_id: String, landlook: int) -> void:
	if not map_id.is_empty() and (not _map_landlooks.has(map_id) or int(_map_landlooks[map_id]) != landlook):
		_map_landlooks[map_id] = landlook
		_revision += 1


func map_landlook(map: MapDefinition) -> int:
	return -1 if map == null else int(_map_landlooks.get(map.id, map.landlook))


func map_landlook_for(map_id: String, authored_landlook: int) -> int:
	return int(_map_landlooks.get(map_id, authored_landlook))


func to_data() -> Dictionary:
	return {
		"terrainOverrides": _sorted_dictionary(_terrain_overrides),
		"boatPresenceOverrides": _sorted_dictionary(_boat_presence_overrides),
		"doorStates": _sorted_dictionary(_door_states),
		"discoveredSecrets": _sorted_keys(_discovered_secrets),
		"mapDarkness": _sorted_dictionary(_map_darkness),
		"mapLandlooks": _sorted_dictionary(_map_landlooks),
	}


static func from_data(data: Dictionary) -> WorldTopologyState:
	if not data.has("terrainOverrides") or not data["terrainOverrides"] is Dictionary:
		return null
	if not data.has("doorStates") or not data["doorStates"] is Dictionary:
		return null
	if not data.has("discoveredSecrets"):
		return null
	var state := WorldTopologyState.new()
	for key: Variant in data["terrainOverrides"]:
		if not key is String or not data["terrainOverrides"][key] is String:
			return null
		state._terrain_overrides[key] = data["terrainOverrides"][key]
	if not _load_boat_presence(data, state) or not _load_doors_and_secrets(data, state):
		return null
	if not _load_map_appearance(data, state):
		return null
	return state


static func _load_boat_presence(data: Dictionary, state: WorldTopologyState) -> bool:
	if not data.has("boatPresenceOverrides"):
		return true
	if not data["boatPresenceOverrides"] is Dictionary:
		return false
	for key: Variant in data["boatPresenceOverrides"]:
		if not key is String or key.is_empty() or not data["boatPresenceOverrides"][key] is bool:
			return false
		state._boat_presence_overrides[key] = data["boatPresenceOverrides"][key]
	return true


static func _load_doors_and_secrets(data: Dictionary, state: WorldTopologyState) -> bool:
	for key: Variant in data["doorStates"]:
		if not key is String or data["doorStates"][key] not in ["open", "closed"]:
			return false
		state._door_states[key] = data["doorStates"][key]
	return _load_key_array(data["discoveredSecrets"], state._discovered_secrets)


static func _load_map_appearance(data: Dictionary, state: WorldTopologyState) -> bool:
	if data.has("mapDarkness"):
		if not data["mapDarkness"] is Dictionary:
			return false
		for key: Variant in data["mapDarkness"]:
			if not key is String or key.is_empty() or not data["mapDarkness"][key] is bool:
				return false
			state._map_darkness[key] = data["mapDarkness"][key]
	if data.has("mapLandlooks"):
		if not data["mapLandlooks"] is Dictionary:
			return false
		for key: Variant in data["mapLandlooks"]:
			var landlook := _signed_integer(data["mapLandlooks"][key])
			if not key is String or key.is_empty() or landlook < -128 or landlook > 127:
				return false
			state._map_landlooks[key] = landlook
	return true


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


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
