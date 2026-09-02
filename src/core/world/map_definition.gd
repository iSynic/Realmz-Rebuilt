class_name MapDefinition
extends RefCounted

var id: String
var name: String
var level_type: StringName
var level_index: int
var topology: MapTopology
var dark: bool
var uses_los: bool
var landlook: int
var base_scale: int
var battle_terrain_set_id: String
var _random_regions: Dictionary = {}


func _init(map_id: String, map_name: String, type: StringName, index: int, map_topology: MapTopology, is_dark: bool = false, line_of_sight_enabled: bool = false, landlook_id: int = -1, map_random_regions: Array[RandomEncounterRegion] = [], terrain_set_id: String = "", map_base_scale: int = -1) -> void:
	id = map_id
	name = map_name
	level_type = type
	level_index = index
	topology = map_topology
	dark = is_dark
	uses_los = line_of_sight_enabled
	landlook = landlook_id
	base_scale = map_base_scale
	battle_terrain_set_id = terrain_set_id
	for region: RandomEncounterRegion in map_random_regions:
		_random_regions[region.id] = region


func random_region_by_id(region_id: String) -> RandomEncounterRegion:
	return _random_regions.get(region_id) as RandomEncounterRegion


func random_regions() -> Array[RandomEncounterRegion]:
	var regions: Array[RandomEncounterRegion] = []
	for region: Variant in _random_regions.values():
		regions.append(region as RandomEncounterRegion)
	return regions


func random_region_by_index(index: int) -> RandomEncounterRegion:
	var suffix := ":rect:%d" % index
	for value: Variant in _random_regions.values():
		var region := value as RandomEncounterRegion
		if region.id.ends_with(suffix):
			return region
	return null
