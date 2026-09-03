class_name WorldDefinition
extends RefCounted

var _maps_by_id: Dictionary = {}
var _transitions_by_source: Dictionary = {}
var _battle_terrain_sets: Dictionary = {}
var _battle_terrain_sets_by_landlook: Dictionary = {}
var _player_maps_by_id: Dictionary = {}
var _player_maps_by_classic_id: Dictionary = {}


func _init(world_maps: Array[MapDefinition], transitions: Array[MapTransition] = [], battle_terrain_sets: Array[BattleTerrainSetDefinition] = [], player_map_definitions: Array[PlayerMapDefinition] = []) -> void:
	for map_definition: MapDefinition in world_maps:
		_maps_by_id[map_definition.id] = map_definition
	for transition: MapTransition in transitions:
		_transitions_by_source[_transition_key(transition.source_map_id, transition.source_edge)] = transition
	for terrain_set: BattleTerrainSetDefinition in battle_terrain_sets:
		_battle_terrain_sets[terrain_set.id] = terrain_set
		if terrain_set.landlook >= 0:
			_battle_terrain_sets_by_landlook[terrain_set.landlook] = terrain_set
	for player_map: PlayerMapDefinition in player_map_definitions:
		_player_maps_by_id[player_map.id] = player_map
		_player_maps_by_classic_id[player_map.classic_id] = player_map


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


func battle_terrain_set_by_landlook(landlook: int) -> BattleTerrainSetDefinition:
	return _battle_terrain_sets_by_landlook.get(landlook) as BattleTerrainSetDefinition


func battle_terrain_set_for_map(map: MapDefinition, world_state: WorldState) -> BattleTerrainSetDefinition:
	if map == null:
		return null
	if map.level_type == &"land":
		var landlook := map.landlook if world_state == null else world_state.map_landlook(map)
		return _battle_terrain_sets_by_landlook.get(landlook) as BattleTerrainSetDefinition
	return battle_terrain_set_by_id(map.battle_terrain_set_id)


func player_map_by_id(definition_id: String) -> PlayerMapDefinition:
	return _player_maps_by_id.get(definition_id) as PlayerMapDefinition


func player_map_by_classic_id(classic_id: int) -> PlayerMapDefinition:
	return _player_maps_by_classic_id.get(classic_id) as PlayerMapDefinition


func player_maps() -> Array[PlayerMapDefinition]:
	var result: Array[PlayerMapDefinition] = []
	for value: Variant in _player_maps_by_classic_id.values():
		result.append(value as PlayerMapDefinition)
	result.sort_custom(func(left: PlayerMapDefinition, right: PlayerMapDefinition) -> bool: return left.classic_id < right.classic_id)
	return result


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


func probe_movement(map_id: String, origin: Vector2i, direction: Vector2i, world_state: WorldState, party_in_boat: bool = false) -> WorldMovementResult:
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
	var topology_result := TopologyMoveResult.permitted(target_map.topology.effective_cell_at(target_coordinate, world_state)) if transition != null else target_map.topology.probe_movement(target_coordinate, direction, world_state, source_map.level_type, party_in_boat)
	if topology_result.target_cell == null:
		return WorldMovementResult.blocked(&"outside_map", source_map, target_map, target_coordinate, topology_result, transition)
	if not topology_result.allowed:
		return WorldMovementResult.blocked(topology_result.reason, source_map, target_map, target_coordinate, topology_result, transition)
	return WorldMovementResult.permitted(source_map, target_map, target_coordinate, transition, topology_result)


static func _transition_key(map_id: String, edge: StringName) -> String:
	return "%s:%s" % [map_id, String(edge)]
