class_name MapDefinition
extends RefCounted

var id: String
var name: String
var level_type: StringName
var level_index: int
var topology: MapTopology


func _init(map_id: String, map_name: String, type: StringName, index: int, map_topology: MapTopology) -> void:
	id = map_id
	name = map_name
	level_type = type
	level_index = index
	topology = map_topology
