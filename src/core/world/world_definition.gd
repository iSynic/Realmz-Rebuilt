class_name WorldDefinition
extends RefCounted

var _maps_by_id: Dictionary = {}


func _init(maps: Array[MapDefinition]) -> void:
	for map: MapDefinition in maps:
		_maps_by_id[map.id] = map


func map_by_id(map_id: String) -> MapDefinition:
	return _maps_by_id.get(map_id) as MapDefinition


func map_ids() -> Array[String]:
	var ids: Array[String] = []
	for map_id: Variant in _maps_by_id.keys():
		ids.append(String(map_id))
	ids.sort()
	return ids
