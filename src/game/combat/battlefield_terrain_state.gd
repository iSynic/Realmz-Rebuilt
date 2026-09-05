## Stores mutable battlefield terrain and its navigation-cache revision.

class_name BattlefieldTerrainState
extends RefCounted


var _tiles: Array[int]
var _revision: int = 0


func _init(tiles: Array[int]) -> void:
	assert(tiles.size() == BattlefieldGrid.CELL_COUNT, "Battlefield terrain requires the complete fixed grid.")
	_tiles = tiles.duplicate()


func tiles() -> Array[int]:
	return _tiles.duplicate()


func tile_at(coordinate: Vector2i) -> int:
	return -1 if not BattlefieldGrid.contains(coordinate) else _tiles[coordinate.y * BattlefieldGrid.SIZE + coordinate.x]


func set_tile(coordinate: Vector2i, tile: int) -> bool:
	if not BattlefieldGrid.contains(coordinate) or tile < 0 or tile > 400:
		return false
	var index := coordinate.y * BattlefieldGrid.SIZE + coordinate.x
	if _tiles[index] != tile:
		_tiles[index] = tile
		_revision += 1
	return true


func revision() -> int:
	return _revision
