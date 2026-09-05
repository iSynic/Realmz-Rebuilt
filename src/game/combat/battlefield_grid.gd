## Defines fixed battlefield dimensions and actor-footprint geometry.

class_name BattlefieldGrid
extends RefCounted


const SIZE: int = 90
const CELL_COUNT: int = SIZE * SIZE


static func contains(coordinate: Vector2i) -> bool:
	return coordinate.x >= 0 and coordinate.y >= 0 and coordinate.x < SIZE and coordinate.y < SIZE


static func footprint_cells(anchor: Vector2i, size: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = [anchor]
	if size == 1 or size == 3:
		result.append(anchor + Vector2i.UP)
	if size > 1:
		result.append(anchor + Vector2i.LEFT)
	if size == 3:
		result.append(anchor + Vector2i(-1, -1))
	return result
