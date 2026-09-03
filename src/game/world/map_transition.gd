class_name MapTransition
extends RefCounted

var id: String
var source_map_id: String
var source_edge: StringName
var target_map_id: String
var target_edge: StringName


func _init(transition_id: String, from_map_id: String, from_edge: StringName, to_map_id: String, to_edge: StringName) -> void:
	id = transition_id
	source_map_id = from_map_id
	source_edge = from_edge
	target_map_id = to_map_id
	target_edge = to_edge
