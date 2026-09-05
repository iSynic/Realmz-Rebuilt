## Stores mutable placed-trigger and random-encounter state for one playthrough.

class_name WorldTriggerState
extends RefCounted

var _disabled_triggers: Dictionary = {}
var _trigger_chances: Dictionary = {}
var _random_regions: Dictionary = {}
var _has_random_region_bounds_override: bool = false
var _random_region_bounds_revision: int = 0


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


func set_random_region(region: RandomRegionState) -> void:
	if region == null or region.id.is_empty():
		return
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


func to_data() -> Dictionary:
	var random_regions: Array[Dictionary] = []
	var random_region_ids: Array = _random_regions.keys()
	random_region_ids.sort()
	for region_id: Variant in random_region_ids:
		random_regions.append((_random_regions[region_id] as RandomRegionState).to_data())
	return {
		"disabledTriggers": _sorted_keys(_disabled_triggers),
		"triggerChances": _sorted_dictionary(_trigger_chances),
		"randomRegions": random_regions,
	}


static func from_data(data: Dictionary) -> WorldTriggerState:
	if not data.has("disabledTriggers"):
		return null
	var state := WorldTriggerState.new()
	if not _load_key_array(data["disabledTriggers"], state._disabled_triggers):
		return null
	if not _load_trigger_chances(data, state) or not _load_random_regions(data, state):
		return null
	return state


static func _load_trigger_chances(data: Dictionary, state: WorldTriggerState) -> bool:
	if not data.has("triggerChances"):
		return true
	if not data["triggerChances"] is Dictionary:
		return false
	for key: Variant in data["triggerChances"]:
		var percent := _integer(data["triggerChances"][key])
		if not key is String or key.is_empty() or percent < -1 or percent > 100:
			return false
		state._trigger_chances[key] = percent
	return true


static func _load_random_regions(data: Dictionary, state: WorldTriggerState) -> bool:
	if not data.has("randomRegions"):
		return true
	if not data["randomRegions"] is Array:
		return false
	for entry: Variant in data["randomRegions"]:
		var region := RandomRegionState.from_data(entry)
		if region == null or state._random_regions.has(region.id):
			return false
		state.set_random_region(region)
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


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
