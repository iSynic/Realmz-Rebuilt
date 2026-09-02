class_name MapWindowView
extends RefCounted

const CHUNK_SIZE: int = 8

class Chunk:
	extends RefCounted
	var cells: Array[MapCellView] = []

	func _init(source: Array[MapCellView] = []) -> void:
		if source.is_empty():
			cells.resize(CHUNK_SIZE * CHUNK_SIZE)
		else:
			cells = source.duplicate()

	func set_cell(coordinate: Vector2i, cell: MapCellView) -> void:
		cells[_local_index(coordinate)] = cell

	func cell_at(coordinate: Vector2i) -> MapCellView:
		return cells[_local_index(coordinate)]

	static func _local_index(coordinate: Vector2i) -> int:
		var local_x := posmod(coordinate.x, CHUNK_SIZE)
		var local_y := posmod(coordinate.y, CHUNK_SIZE)
		return local_y * CHUNK_SIZE + local_x

var bounds: Rect2i
var _chunks: Dictionary = {}


func _init(window_bounds: Rect2i, chunks: Dictionary = {}, source_cells: Array[MapCellView] = []) -> void:
	bounds = window_bounds
	_chunks = chunks.duplicate()
	for cell: MapCellView in source_cells:
		var key := _chunk_key(cell.coordinate)
		var chunk := _chunks.get(key) as Chunk
		if chunk == null:
			chunk = Chunk.new()
			_chunks[key] = chunk
		chunk.set_cell(cell.coordinate, cell)


func patched(window_bounds: Rect2i, replacements: Dictionary) -> RefCounted:
	var chunks: Dictionary = {}
	for key: Vector2i in _chunks:
		if _chunk_rect(key).intersects(window_bounds):
			chunks[key] = _chunks[key]
	var copied: Dictionary = {}
	for coordinate: Vector2i in replacements:
		if not window_bounds.has_point(coordinate):
			continue
		var key := _chunk_key(coordinate)
		var chunk := chunks.get(key) as Chunk
		if not copied.has(key):
			var source: Array[MapCellView] = []
			if chunk != null:
				source = chunk.cells
			chunk = Chunk.new(source)
			chunks[key] = chunk
			copied[key] = true
		chunk.set_cell(coordinate, replacements[coordinate])
	return get_script().new(window_bounds, chunks)


func cell_at(coordinate: Vector2i) -> MapCellView:
	if not bounds.has_point(coordinate):
		return null
	return retained_cell_at(coordinate)


func retained_cell_at(coordinate: Vector2i) -> MapCellView:
	var chunk := _chunks.get(_chunk_key(coordinate)) as Chunk
	return null if chunk == null else chunk.cell_at(coordinate)


func cells() -> Array[MapCellView]:
	var result: Array[MapCellView] = []
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var cell := cell_at(Vector2i(x, y))
			if cell != null:
				result.append(cell)
	return result


static func _chunk_key(coordinate: Vector2i) -> Vector2i:
	return Vector2i(floori(float(coordinate.x) / CHUNK_SIZE), floori(float(coordinate.y) / CHUNK_SIZE))


static func _chunk_rect(key: Vector2i) -> Rect2i:
	return Rect2i(key * CHUNK_SIZE, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
