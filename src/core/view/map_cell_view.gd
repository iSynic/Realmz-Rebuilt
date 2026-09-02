class_name MapCellView
extends RefCounted

var coordinate: Vector2i
var terrain_id: String
var render_tile: int
var tileset_id: String
var overlay_asset_id: String
var passable: bool
var blocks_los: bool
var visible: bool
var visited: bool
var has_trigger: bool
var in_random_region: bool
var _feature_kinds: Array[StringName]
var _feature_orientations: Dictionary = {}
var _edge_kinds: Dictionary = {}
var _edge_passability: Dictionary = {}


func _init(cell_coordinate: Vector2i, terrain: String, tile: int, cell_tileset_id: String, can_enter: bool, blocks_visibility: bool, is_visible: bool, was_visited: bool, trigger_present: bool, random_region_present: bool, feature_kinds: Array[StringName], feature_orientations: Dictionary, edge_kinds: Dictionary, edge_passability: Dictionary, cell_overlay_asset_id: String = "", static_source: MapCellView = null) -> void:
	if static_source != null:
		coordinate = static_source.coordinate
		terrain_id = static_source.terrain_id
		render_tile = static_source.render_tile
		tileset_id = static_source.tileset_id
		overlay_asset_id = static_source.overlay_asset_id
		passable = static_source.passable
		blocks_los = static_source.blocks_los
		visible = is_visible
		visited = was_visited
		has_trigger = static_source.has_trigger
		in_random_region = static_source.in_random_region
		_feature_kinds = static_source._feature_kinds
		_feature_orientations = static_source._feature_orientations
		_edge_kinds = static_source._edge_kinds
		_edge_passability = static_source._edge_passability
		return
	coordinate = cell_coordinate
	terrain_id = terrain
	render_tile = tile
	tileset_id = cell_tileset_id
	overlay_asset_id = cell_overlay_asset_id
	passable = can_enter
	blocks_los = blocks_visibility
	visible = is_visible
	visited = was_visited
	has_trigger = trigger_present
	in_random_region = random_region_present
	_feature_kinds = feature_kinds.duplicate()
	_feature_orientations = feature_orientations.duplicate()
	_edge_kinds = edge_kinds.duplicate()
	_edge_passability = edge_passability.duplicate()


func detached_with_visibility(is_visible: bool, was_visited: bool) -> MapCellView:
	var empty_features: Array[StringName] = []
	return get_script().new(coordinate, terrain_id, render_tile, tileset_id, passable, blocks_los, is_visible, was_visited, has_trigger, in_random_region, empty_features, {}, {}, {}, overlay_asset_id, self)


func has_feature(feature_kind: StringName) -> bool:
	return _feature_kinds.has(feature_kind)


func features() -> Array[StringName]:
	return _feature_kinds.duplicate()


func feature_orientation(feature_kind: StringName) -> StringName:
	return StringName(_feature_orientations.get(feature_kind, ""))


func edge_kind(direction: StringName) -> StringName:
	return StringName(_edge_kinds.get(direction, "wall"))


func edge_is_passable(direction: StringName) -> bool:
	return bool(_edge_passability.get(direction, false))
