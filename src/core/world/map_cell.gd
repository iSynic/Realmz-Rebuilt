class_name MapCell
extends RefCounted

var id: String
var coordinate: Vector2i
var terrain_id: String
var passable: bool
var movement_cost: int
var blocks_los: bool
var is_land: bool
var is_water: bool
var is_shore: bool
var is_path: bool
var boat_required: bool
var fly_float_required: bool
var _trigger_ids: Array[String]
var _random_rect_ids: Array[String]


func _init(cell_id: String, cell_coordinate: Vector2i, terrain: String, can_enter: bool, cost: int, los_blocked: bool, land: bool, water: bool, shore: bool, path: bool, needs_boat: bool, needs_fly_float: bool, cell_trigger_ids: Array[String], cell_random_rect_ids: Array[String]) -> void:
	id = cell_id
	coordinate = cell_coordinate
	terrain_id = terrain
	passable = can_enter
	movement_cost = cost
	blocks_los = los_blocked
	is_land = land
	is_water = water
	is_shore = shore
	is_path = path
	boat_required = needs_boat
	fly_float_required = needs_fly_float
	_trigger_ids = cell_trigger_ids.duplicate()
	_random_rect_ids = cell_random_rect_ids.duplicate()


func trigger_ids() -> Array[String]:
	return _trigger_ids.duplicate()


func random_rect_ids() -> Array[String]:
	return _random_rect_ids.duplicate()
