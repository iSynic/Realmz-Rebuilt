class_name BattleTerrainSetDefinition
extends RefCounted

var id: String
var landlook: int
var base_tile: int
var _tiles_by_id: Dictionary = {}


func _init(definition_id: String, landlook_id: int, base_tile_id: int, tiles: Array[BattleTerrainTileDefinition]) -> void:
	id = definition_id
	landlook = landlook_id
	base_tile = base_tile_id
	for tile_definition: BattleTerrainTileDefinition in tiles:
		_tiles_by_id[tile_definition.tile] = tile_definition


func tile_by_id(tile_id: int) -> BattleTerrainTileDefinition:
	return _tiles_by_id.get(tile_id) as BattleTerrainTileDefinition


func tile_count() -> int:
	return _tiles_by_id.size()


func has_complete_range(first_tile: int, last_tile: int) -> bool:
	if first_tile < 0 or last_tile < first_tile or _tiles_by_id.size() != last_tile - first_tile + 1:
		return false
	for tile_id: int in range(first_tile, last_tile + 1):
		if not _tiles_by_id.has(tile_id):
			return false
	return true
