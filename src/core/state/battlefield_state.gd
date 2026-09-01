class_name BattlefieldState
extends RefCounted

const SIZE: int = 90
const CELL_COUNT: int = SIZE * SIZE

var map_id: String
var source_origin: Vector2i
var map_shift: Vector2i
var party_anchor: Vector2i
var direction_degrees: int = 0
var rolled_distance: int = 0
var _terrain_tiles: Array[int] = []
var _terrain_revision: int = 0
var _character_positions: Dictionary = {}
var _monster_positions: Dictionary = {}
var _monster_sizes: Dictionary = {}


func _init(source_map_id: String, terrain_tiles: Array[int], origin: Vector2i = Vector2i.ZERO, shift: Vector2i = Vector2i.ZERO) -> void:
	map_id = source_map_id
	source_origin = origin
	map_shift = shift
	party_anchor = Vector2i(45, 45) + shift
	_terrain_tiles = terrain_tiles.duplicate()


func terrain_tiles() -> Array[int]:
	return _terrain_tiles.duplicate()


func terrain_at(coordinate: Vector2i) -> int:
	return -1 if not contains(coordinate) else _terrain_tiles[coordinate.y * SIZE + coordinate.x]


func set_terrain(coordinate: Vector2i, tile: int) -> bool:
	if not contains(coordinate) or tile < 0 or tile > 400:
		return false
	var index := coordinate.y * SIZE + coordinate.x
	if _terrain_tiles[index] != tile:
		_terrain_tiles[index] = tile
		_terrain_revision += 1
	return true


func terrain_revision() -> int:
	return _terrain_revision


func character_position(actor_id: String) -> Vector2i:
	return _coordinate(_character_positions.get(actor_id))


func monster_position(actor_id: String) -> Vector2i:
	return _coordinate(_monster_positions.get(actor_id))


func monster_size(actor_id: String) -> int:
	return int(_monster_sizes.get(actor_id, -1))


func has_actor(actor_id: String) -> bool:
	return _character_positions.has(actor_id) or _monster_positions.has(actor_id)


func actor_ids() -> Array[String]:
	var result: Array[String] = []
	for actor_id: Variant in _character_positions:
		result.append(String(actor_id))
	for actor_id: Variant in _monster_positions:
		result.append(String(actor_id))
	result.sort()
	return result


func actor_position(actor_id: String) -> Vector2i:
	if _character_positions.has(actor_id):
		return _coordinate(_character_positions[actor_id])
	return _coordinate(_monster_positions.get(actor_id))


func actor_size(actor_id: String) -> int:
	return int(_monster_sizes.get(actor_id, 0)) if _monster_positions.has(actor_id) else 0 if _character_positions.has(actor_id) else -1


func actor_footprint(actor_id: String) -> Array[Vector2i]:
	return actor_footprint_at(actor_id, actor_position(actor_id))


func actor_footprint_at(actor_id: String, anchor: Vector2i) -> Array[Vector2i]:
	var size := actor_size(actor_id)
	var result: Array[Vector2i] = []
	if size >= 0 and anchor.x >= 0:
		result = footprint_cells(anchor, size)
	return result


func actor_at(coordinate: Vector2i, excluding_actor_id: String = "") -> String:
	for actor_id: Variant in _character_positions:
		if actor_id != excluding_actor_id and _coordinate(_character_positions[actor_id]) == coordinate:
			return String(actor_id)
	for actor_id: Variant in _monster_positions:
		if actor_id == excluding_actor_id:
			continue
		if footprint_cells(_coordinate(_monster_positions[actor_id]), int(_monster_sizes.get(actor_id, 0))).has(coordinate):
			return String(actor_id)
	return ""


func place_character(actor_id: String, coordinate: Vector2i) -> bool:
	if actor_id.is_empty() or not contains(coordinate) or is_occupied(coordinate):
		return false
	_character_positions[actor_id] = coordinate
	return true


func remove_character(actor_id: String) -> void:
	_character_positions.erase(actor_id)


func place_monster(actor_id: String, coordinate: Vector2i, size: int) -> bool:
	if actor_id.is_empty() or size < 0 or size > 3:
		return false
	for cell: Vector2i in footprint_cells(coordinate, size):
		if not contains(cell) or is_occupied(cell):
			return false
	_monster_positions[actor_id] = coordinate
	_monster_sizes[actor_id] = size
	return true


func remove_monster(actor_id: String) -> void:
	_monster_positions.erase(actor_id)
	_monster_sizes.erase(actor_id)


func move_actor(actor_id: String, destination: Vector2i) -> bool:
	if not has_actor(actor_id):
		return false
	for coordinate: Vector2i in actor_footprint_at(actor_id, destination):
		if not contains(coordinate) or not actor_at(coordinate, actor_id).is_empty():
			return false
	if _character_positions.has(actor_id):
		_character_positions[actor_id] = destination
	else:
		_monster_positions[actor_id] = destination
	return true


func swap_size_zero_actors(first_actor_id: String, second_actor_id: String) -> bool:
	if first_actor_id.is_empty() or second_actor_id.is_empty() or first_actor_id == second_actor_id or actor_size(first_actor_id) != 0 or actor_size(second_actor_id) != 0:
		return false
	var first_position := actor_position(first_actor_id)
	var second_position := actor_position(second_actor_id)
	if not contains(first_position) or not contains(second_position):
		return false
	if _character_positions.has(first_actor_id):
		_character_positions[first_actor_id] = second_position
	else:
		_monster_positions[first_actor_id] = second_position
	if _character_positions.has(second_actor_id):
		_character_positions[second_actor_id] = first_position
	else:
		_monster_positions[second_actor_id] = first_position
	return true


func replace_monster_id(current_id: String, replacement_id: String) -> bool:
	if current_id.is_empty() or replacement_id.is_empty() or not _monster_positions.has(current_id) or _monster_positions.has(replacement_id) or _character_positions.has(replacement_id):
		return false
	_monster_positions[replacement_id] = _monster_positions[current_id]
	_monster_sizes[replacement_id] = _monster_sizes[current_id]
	_monster_positions.erase(current_id)
	_monster_sizes.erase(current_id)
	return true


func is_occupied(coordinate: Vector2i) -> bool:
	for value: Variant in _character_positions.values():
		if value == coordinate:
			return true
	for actor_id: Variant in _monster_positions:
		var anchor := _coordinate(_monster_positions[actor_id])
		for cell: Vector2i in footprint_cells(anchor, int(_monster_sizes.get(actor_id, 0))):
			if cell == coordinate:
				return true
	return false


func character_positions() -> Dictionary:
	return _character_positions.duplicate()


func monster_positions() -> Dictionary:
	return _monster_positions.duplicate()


func to_data() -> Dictionary:
	return {
		"mapId": map_id,
		"sourceOrigin": _vector_data(source_origin),
		"mapShift": _vector_data(map_shift),
		"partyAnchor": _vector_data(party_anchor),
		"directionDegrees": direction_degrees,
		"rolledDistance": rolled_distance,
		"terrainTiles": _terrain_tiles.duplicate(),
		"characterPositions": _positions_data(_character_positions),
		"monsterPositions": _positions_data(_monster_positions),
		"monsterSizes": _sorted_dictionary(_monster_sizes),
	}


static func from_data(data: Variant) -> BattlefieldState:
	if not data is Dictionary:
		return null
	for field: String in ["mapId", "sourceOrigin", "mapShift", "partyAnchor", "directionDegrees", "rolledDistance", "terrainTiles", "characterPositions", "monsterPositions", "monsterSizes"]:
		if not data.has(field):
			return null
	if not data["mapId"] is String or data["mapId"].is_empty() or not data["terrainTiles"] is Array or data["terrainTiles"].size() != CELL_COUNT:
		return null
	var origin := _parse_vector(data["sourceOrigin"])
	var shift := _parse_vector(data["mapShift"])
	var anchor := _parse_vector(data["partyAnchor"])
	var direction := _integer(data["directionDegrees"])
	var distance := _signed_integer(data["rolledDistance"])
	if origin == Vector2i(-100_000, -100_000) or shift == Vector2i(-100_000, -100_000) or anchor == Vector2i(-100_000, -100_000) or direction < 0 or direction > 360 or distance == -100_000:
		return null
	var tiles: Array[int] = []
	for value: Variant in data["terrainTiles"]:
		var tile := _integer(value)
		if tile < 0 or tile > 400:
			return null
		tiles.append(tile)
	var result := BattlefieldState.new(data["mapId"], tiles, origin, shift)
	if anchor != result.party_anchor:
		return null
	result.direction_degrees = direction
	result.rolled_distance = distance
	var characters: Variant = _parse_positions(data["characterPositions"])
	var monsters: Variant = _parse_positions(data["monsterPositions"])
	if characters == null or monsters == null or not data["monsterSizes"] is Dictionary:
		return null
	result._character_positions = characters
	result._monster_positions = monsters
	for actor_id: Variant in data["monsterSizes"]:
		var size := _integer(data["monsterSizes"][actor_id])
		if not actor_id is String or actor_id.is_empty() or not result._monster_positions.has(actor_id) or size < 0 or size > 3:
			return null
		result._monster_sizes[actor_id] = size
	if result._monster_sizes.size() != result._monster_positions.size() or not result._placements_are_valid():
		return null
	return result


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


func _placements_are_valid() -> bool:
	var occupied: Dictionary = {}
	for actor_id: Variant in _character_positions:
		if _monster_positions.has(actor_id):
			return false
		var coordinate := _coordinate(_character_positions[actor_id])
		if not contains(coordinate) or occupied.has(coordinate):
			return false
		occupied[coordinate] = true
	for actor_id: Variant in _monster_positions:
		var anchor := _coordinate(_monster_positions[actor_id])
		for coordinate: Vector2i in footprint_cells(anchor, int(_monster_sizes[actor_id])):
			if not contains(coordinate) or occupied.has(coordinate):
				return false
			occupied[coordinate] = true
	return true


static func _positions_data(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var ids: Array = source.keys()
	ids.sort()
	for actor_id: Variant in ids:
		result[String(actor_id)] = _vector_data(_coordinate(source[actor_id]))
	return result


static func _parse_positions(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var result: Dictionary = {}
	for actor_id: Variant in value:
		var coordinate := _parse_vector(value[actor_id])
		if not actor_id is String or actor_id.is_empty() or coordinate == Vector2i(-100_000, -100_000) or result.has(actor_id):
			return null
		result[actor_id] = coordinate
	return result


static func _vector_data(value: Vector2i) -> Array[int]:
	return [value.x, value.y]


static func _parse_vector(value: Variant) -> Vector2i:
	if not value is Array or value.size() != 2:
		return Vector2i(-100_000, -100_000)
	var x := _signed_integer(value[0])
	var y := _signed_integer(value[1])
	return Vector2i(-100_000, -100_000) if x == -100_000 or y == -100_000 else Vector2i(x, y)


static func _coordinate(value: Variant) -> Vector2i:
	return value as Vector2i if value is Vector2i else Vector2i(-1, -1)


static func _sorted_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = source.keys()
	keys.sort()
	for key: Variant in keys:
		result[key] = source[key]
	return result


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
