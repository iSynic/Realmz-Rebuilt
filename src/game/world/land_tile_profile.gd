class_name LandTileProfile
extends RefCounted

var terrain_id: String
var movement_cost: int
var passable: bool
var blocks_los: bool
var is_water: bool
var is_shore: bool
var is_path: bool
var boat_requirement: int
var fly_float_required: bool
var is_forest: bool
var movement_sound_id: int
var render_tile: int
var blocked_attempt_timeclicks: int


func _init(terrain: String, cost: int, semantic_flags: int, sound_id: int, tile: int, classic_boat_requirement: int, blocked_timeclicks: int) -> void:
	terrain_id = terrain
	movement_cost = cost
	passable = bool(semantic_flags & 1)
	blocks_los = bool(semantic_flags & 2)
	is_water = bool(semantic_flags & 8)
	is_shore = bool(semantic_flags & 16)
	is_path = bool(semantic_flags & 32)
	boat_requirement = classic_boat_requirement
	fly_float_required = bool(semantic_flags & 128)
	is_forest = bool(semantic_flags & 256)
	movement_sound_id = sound_id
	render_tile = tile
	blocked_attempt_timeclicks = blocked_timeclicks


func apply_to(cell: MapCell) -> MapCell:
	var edges: Dictionary = {}
	for direction: StringName in [&"north", &"east", &"south", &"west"]:
		edges[direction] = cell.edge(direction)
	return MapCell.new(
		cell.id,
		cell.coordinate,
		terrain_id,
		passable,
		movement_cost,
		blocks_los,
		true,
		is_water,
		is_shore,
		is_path,
		boat_requirement != 0,
		fly_float_required,
		movement_sound_id,
		render_tile,
		cell.tileset_id,
		cell.trigger_ids(),
		cell.random_rect_ids(),
		edges,
		cell.features(),
		"",
		boat_requirement,
		blocked_attempt_timeclicks,
		is_forest,
	)
