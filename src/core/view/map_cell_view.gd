class_name MapCellView
extends RefCounted

var coordinate: Vector2i
var terrain_id: String
var passable: bool
var blocks_los: bool
var visible: bool
var visited: bool
var has_trigger: bool
var in_random_region: bool
var _feature_kinds: Array[StringName]
var _edge_kinds: Dictionary = {}
var _edge_passability: Dictionary = {}


func _init(cell_coordinate: Vector2i, terrain: String, can_enter: bool, blocks_visibility: bool, is_visible: bool, was_visited: bool, trigger_present: bool, random_region_present: bool, feature_kinds: Array[StringName], edge_kinds: Dictionary, edge_passability: Dictionary) -> void:
	coordinate = cell_coordinate
	terrain_id = terrain
	passable = can_enter
	blocks_los = blocks_visibility
	visible = is_visible
	visited = was_visited
	has_trigger = trigger_present
	in_random_region = random_region_present
	_feature_kinds = feature_kinds.duplicate()
	_edge_kinds = edge_kinds.duplicate()
	_edge_passability = edge_passability.duplicate()


func has_feature(feature_kind: StringName) -> bool:
	return _feature_kinds.has(feature_kind)


func features() -> Array[StringName]:
	return _feature_kinds.duplicate()


func edge_kind(direction: StringName) -> StringName:
	return StringName(_edge_kinds.get(direction, "wall"))


func edge_is_passable(direction: StringName) -> bool:
	return bool(_edge_passability.get(direction, false))
