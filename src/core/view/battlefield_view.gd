class_name BattlefieldView
extends RefCounted

var map_id: String
var upper_tileset_id: String
var source_origin: Vector2i
var map_shift: Vector2i
var party_anchor: Vector2i
var direction_degrees: int
var rolled_distance: int
var _terrain_tiles: Array[int]
var _character_positions: Dictionary
var _monster_positions: Dictionary
var _monster_sizes: Dictionary


func _init(battlefield: BattlefieldState, terrain_upper_tileset_id: String = "") -> void:
	map_id = battlefield.map_id
	upper_tileset_id = terrain_upper_tileset_id
	source_origin = battlefield.source_origin
	map_shift = battlefield.map_shift
	party_anchor = battlefield.party_anchor
	direction_degrees = battlefield.direction_degrees
	rolled_distance = battlefield.rolled_distance
	_terrain_tiles = battlefield.terrain_tiles()
	_character_positions = battlefield.character_positions()
	_monster_positions = battlefield.monster_positions()
	for actor_id: Variant in _monster_positions:
		_monster_sizes[actor_id] = battlefield.monster_size(String(actor_id))


func terrain_tiles() -> Array[int]:
	return _terrain_tiles.duplicate()


func terrain_at(coordinate: Vector2i) -> int:
	return -1 if not BattlefieldState.contains(coordinate) else _terrain_tiles[coordinate.y * BattlefieldState.SIZE + coordinate.x]


func character_position(actor_id: String) -> Vector2i:
	return _character_positions.get(actor_id, Vector2i(-1, -1)) as Vector2i


func monster_position(actor_id: String) -> Vector2i:
	return _monster_positions.get(actor_id, Vector2i(-1, -1)) as Vector2i


func monster_size(actor_id: String) -> int:
	return int(_monster_sizes.get(actor_id, -1))


func monster_footprint(actor_id: String) -> Array[Vector2i]:
	var anchor := monster_position(actor_id)
	var size := monster_size(actor_id)
	var footprint: Array[Vector2i] = []
	if anchor.x < 0 or size < 0:
		return footprint
	return BattlefieldState.footprint_cells(anchor, size)
