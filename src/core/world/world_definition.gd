class_name WorldDefinition
extends RefCounted

var _maps_by_id: Dictionary = {}
var _transitions_by_source: Dictionary = {}


func _init(world_maps: Array[MapDefinition], transitions: Array[MapTransition] = []) -> void:
	for map_definition: MapDefinition in world_maps:
		_maps_by_id[map_definition.id] = map_definition
	for transition: MapTransition in transitions:
		_transitions_by_source[_transition_key(transition.source_map_id, transition.source_edge)] = transition


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
		_:
			return Vector2i(-1, -1)


static func _transition_key(map_id: String, edge: StringName) -> String:
	return "%s:%s" % [map_id, String(edge)]
