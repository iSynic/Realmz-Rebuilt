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
var boat_requirement: int
var blocked_attempt_timeclicks: int
var fly_float_required: bool
var is_forest: bool
var movement_sound_id: int
var render_tile: int
var tileset_id: String
var overlay_asset_id: String
var _trigger_ids: Array[String]
var _random_rect_ids: Array[String]
var _edges: Dictionary = {}
var _features: Array[MapFeature]


func _init(cell_id: String, cell_coordinate: Vector2i, terrain: String, can_enter: bool, cost: int, los_blocked: bool, land: bool, water: bool, shore: bool, path: bool, needs_boat: bool, needs_fly_float: bool, sound_id: int, tile: int, cell_tileset_id: String, cell_trigger_ids: Array[String], cell_random_rect_ids: Array[String], cell_edges: Dictionary, cell_features: Array[MapFeature], cell_overlay_asset_id: String = "", classic_boat_requirement: int = -1, classic_blocked_attempt_timeclicks: int = -1, forest: bool = false) -> void:
	id = cell_id
	coordinate = cell_coordinate
	terrain_id = terrain
	passable = can_enter
	movement_cost = cost
	blocks_los = los_blocked
	is_land = land
	boat_requirement = classic_boat_requirement if classic_boat_requirement >= 0 else (2 if water else (1 if needs_boat else 0))
	is_water = boat_requirement == 2
	is_shore = shore
	is_path = path
	boat_required = boat_requirement != 0
	blocked_attempt_timeclicks = classic_blocked_attempt_timeclicks if classic_blocked_attempt_timeclicks >= 0 else (maxi(0, cost) if land else 0)
	fly_float_required = needs_fly_float
	is_forest = forest
	movement_sound_id = sound_id
	render_tile = tile
	tileset_id = cell_tileset_id
	overlay_asset_id = cell_overlay_asset_id
	_trigger_ids = cell_trigger_ids.duplicate()
	_random_rect_ids = cell_random_rect_ids.duplicate()
	_edges = cell_edges.duplicate()
	_features = cell_features.duplicate()


func trigger_ids() -> Array[String]:
	return _trigger_ids.duplicate()


func random_rect_ids() -> Array[String]:
	return _random_rect_ids.duplicate()


func edge(direction: StringName) -> MapEdge:
	return _edges.get(direction) as MapEdge


func features() -> Array[MapFeature]:
	return _features.duplicate()


func feature_by_kind(feature_kind: StringName) -> MapFeature:
	for feature: MapFeature in _features:
		if feature.kind == feature_kind:
			return feature
	return null
