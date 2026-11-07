## Defines fixed battlefield dimensions and actor-footprint geometry.

class_name BattlefieldGrid
extends RefCounted


const SIZE: int = 90
const CELL_COUNT: int = SIZE * SIZE


static func contains(coordinate: Vector2i) -> bool:
	return coordinate.x >= 0 and coordinate.y >= 0 and coordinate.x < SIZE and coordinate.y < SIZE


## Castle reads spell areas from field[90][90] by flat index: a row above or below the field continues in the
## neighbouring column, and an index outside the array hits nothing (returned as an off-grid cell).
static func classic_field_cell(cell: Vector2i) -> Vector2i:
	var index := cell.x * SIZE + cell.y
	if index < 0 or index >= CELL_COUNT:
		return Vector2i(-1, -1)
	return Vector2i(index / SIZE, index % SIZE)


static func footprint_cells(anchor: Vector2i, size: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = [anchor]
	if size == 1 or size == 3:
		result.append(anchor + Vector2i.UP)
	if size > 1:
		result.append(anchor + Vector2i.LEFT)
	if size == 3:
		result.append(anchor + Vector2i(-1, -1))
	return result
