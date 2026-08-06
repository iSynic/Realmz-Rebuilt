class_name MapEdge
extends RefCounted

var kind: StringName
var passable: bool
var blocks_los: bool
var door_id: String
var secret_id: String
var initially_discovered: bool


func _init(edge_kind: StringName, allows_passage: bool, blocks_visibility: bool, linked_door_id: String = "", linked_secret_id: String = "", discovered: bool = true) -> void:
	kind = edge_kind
	passable = allows_passage
	blocks_los = blocks_visibility
	door_id = linked_door_id
	secret_id = linked_secret_id
	initially_discovered = discovered
