class_name WorldDefinition
extends RefCounted

var _maps_by_id: Dictionary = {}
var _transitions_by_source: Dictionary = {}
var _battle_terrain_sets: Dictionary = {}


func _init(world_maps: Array[MapDefinition], transitions: Array[MapTransition] = [], battle_terrain_sets: Array[BattleTerrainSetDefinition] = []) -> void:
	for map_definition: MapDefinition in world_maps:
		_maps_by_id[map_definition.id] = map_definition
	for transition: MapTransition in transitions:
		_transitions_by_source[_transition_key(transition.source_map_id, transition.source_edge)] = transition
	for terrain_set: BattleTerrainSetDefinition in battle_terrain_sets:
		_battle_terrain_sets[terrain_set.id] = terrain_set


func map_by_id(map_id: String) -> MapDefinition:
	return _maps_by_id.get(map_id) as MapDefinition


func map_ids() -> Array[String]:
	var ids: Array[String] = []
	for map_id: Variant in _maps_by_id.keys():
		ids.append(String(map_id))
	ids.sort()
	return ids


func map_by_type_and_index(level_type: StringName, level_index: int) -> MapDefinition:
	for value: Variant in _maps_by_id.values():
		var map := value as MapDefinition
		if map.level_type == level_type and map.level_index == level_index:
			return map
	return null


func battle_terrain_set_by_id(definition_id: String) -> BattleTerrainSetDefinition:
	return _battle_terrain_sets.get(definition_id) as BattleTerrainSetDefinition


func transition_from(map_id: String, edge: StringName) -> MapTransition:
	return _transitions_by_source.get(_transition_key(map_id, edge)) as MapTransition


func transition_target_coordinate(transition: MapTransition, source_coordinate: Vector2i) -> Vector2i:
	var target_map := map_by_id(transition.target_map_id)
	if target_map == null:
		return Vector2i(-1, -1)
	match transition.target_edge:
		&"north":
			return Vector2i(clampi(source_coordinate.x, 0, target_map.topology.width - 1), 0)
		&"east":
			return Vector2i(target_map.topology.width - 1, clampi(source_coordinate.y, 0, target_map.topology.height - 1))
		&"south":
			return Vector2i(clampi(source_coordinate.x, 0, target_map.topology.width - 1), target_map.topology.height - 1)
		&"west":
			return Vector2i(0, clampi(source_coordinate.y, 0, target_map.topology.height - 1))
		&"northwest":
			return Vector2i.ZERO
		&"northeast":
			return Vector2i(target_map.topology.width - 1, 0)
		&"southeast":
			return Vector2i(target_map.topology.width - 1, target_map.topology.height - 1)
		&"southwest":
			return Vector2i(0, target_map.topology.height - 1)
		_:
			return Vector2i(-1, -1)


func probe_movement(map_id: String, origin: Vector2i, direction: Vector2i, world_state: WorldState) -> WorldMovementResult:
	var source_map := map_by_id(map_id)
	if source_map == null:
		return WorldMovementResult.blocked(&"outside_map")
	if source_map.level_type == &"land":
		if not MapTopology.is_cardinal_direction(direction) and not MapTopology.is_diagonal_direction(direction):
			return WorldMovementResult.blocked(&"invalid_direction", source_map)
	elif not MapTopology.is_cardinal_direction(direction):
		return WorldMovementResult.blocked(&"invalid_direction", source_map)
	var target_map := source_map
	var target_coordinate := origin + direction
	var transition: MapTransition = null
	if not source_map.topology.contains(target_coordinate):
		var crossing := Vector2i(
			-1 if target_coordinate.x < 0 else (1 if target_coordinate.x >= source_map.topology.width else 0),
			-1 if target_coordinate.y < 0 else (1 if target_coordinate.y >= source_map.topology.height else 0)
		)
		transition = transition_from(source_map.id, MapTopology.direction_name(crossing))
		if transition == null:
			return WorldMovementResult.blocked(&"map_boundary", source_map)
		target_map = map_by_id(transition.target_map_id)
		if target_map == null:
			return WorldMovementResult.blocked(&"outside_map", source_map)
		target_coordinate = transition_target_coordinate(transition, target_coordinate)
	var topology_result := target_map.topology.probe_movement(target_coordinate, direction, world_state, source_map.level_type)
	if not topology_result.allowed:
		return WorldMovementResult.blocked(topology_result.reason, source_map, target_map, target_coordinate, topology_result)
	return WorldMovementResult.permitted(source_map, target_map, target_coordinate, transition, topology_result)


static func _transition_key(map_id: String, edge: StringName) -> String:
	return "%s:%s" % [map_id, String(edge)]
