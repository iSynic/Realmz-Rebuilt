## Encodes and strictly restores the stable battlefield save representation.

class_name BattlefieldStateCodec
extends RefCounted


const INVALID_COORDINATE := Vector2i(-100_000, -100_000)


static func to_data(state: BattlefieldState) -> Dictionary:
	return {
		"mapId": state.map_id,
		"sourceOrigin": _vector_data(state.source_origin),
		"mapShift": _vector_data(state.map_shift),
		"partyAnchor": _vector_data(state.party_anchor),
		"directionDegrees": state.direction_degrees,
		"rolledDistance": state.rolled_distance,
		"terrainTiles": state.terrain.tiles(),
		"characterPositions": _positions_data(state.actors.character_positions()),
		"monsterPositions": _positions_data(state.actors.monster_positions()),
		"monsterSizes": _sorted_dictionary(state.actors.monster_sizes()),
	}


static func from_data(data: Variant) -> BattlefieldState:
	if not _has_valid_envelope(data):
		return null
	var origin := _parse_vector(data["sourceOrigin"])
	var shift := _parse_vector(data["mapShift"])
	var anchor := _parse_vector(data["partyAnchor"])
	var direction := _integer(data["directionDegrees"])
	var distance := _signed_integer(data["rolledDistance"])
	if origin == INVALID_COORDINATE or shift == INVALID_COORDINATE or anchor == INVALID_COORDINATE or direction < 0 or direction > 360 or distance == -100_000:
		return null
	var tiles := _parse_tiles(data["terrainTiles"])
	var characters: Variant = _parse_positions(data["characterPositions"])
	var monsters: Variant = _parse_positions(data["monsterPositions"])
	var sizes: Variant = _parse_monster_sizes(data["monsterSizes"], monsters)
	if tiles.is_empty() or characters == null or monsters == null or sizes == null or not _placements_are_valid(characters, monsters, sizes):
		return null
	var result := BattlefieldState.new(data["mapId"], tiles, origin, shift)
	if anchor != result.party_anchor:
		return null
	result.direction_degrees = direction
	result.rolled_distance = distance
	result.actors = BattlefieldActorState.new(characters, monsters, sizes)
	return result


static func _has_valid_envelope(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for field: String in ["mapId", "sourceOrigin", "mapShift", "partyAnchor", "directionDegrees", "rolledDistance", "terrainTiles", "characterPositions", "monsterPositions", "monsterSizes"]:
		if not data.has(field):
			return false
	return data["mapId"] is String and not data["mapId"].is_empty() and data["terrainTiles"] is Array and data["terrainTiles"].size() == BattlefieldGrid.CELL_COUNT and data["monsterSizes"] is Dictionary


static func _parse_tiles(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		var tile := _integer(value)
		if tile < 0 or tile > 400:
			return []
		result.append(tile)
	return result


static func _parse_monster_sizes(values: Dictionary, monster_positions: Variant) -> Variant:
	if monster_positions == null:
		return null
	var result: Dictionary = {}
	for actor_id: Variant in values:
		var size := _integer(values[actor_id])
		if not actor_id is String or actor_id.is_empty() or not monster_positions.has(actor_id) or size < 0 or size > 3:
			return null
		result[actor_id] = size
	return result if result.size() == monster_positions.size() else null


static func _placements_are_valid(characters: Dictionary, monsters: Dictionary, sizes: Dictionary) -> bool:
	var occupied: Dictionary = {}
	for actor_id: Variant in characters:
		var coordinate := characters[actor_id] as Vector2i
		if monsters.has(actor_id) or not BattlefieldGrid.contains(coordinate) or occupied.has(coordinate):
			return false
		occupied[coordinate] = true
	for actor_id: Variant in monsters:
		for coordinate: Vector2i in BattlefieldGrid.footprint_cells(monsters[actor_id] as Vector2i, int(sizes[actor_id])):
			if not BattlefieldGrid.contains(coordinate) or occupied.has(coordinate):
				return false
			occupied[coordinate] = true
	return true


static func _positions_data(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var ids: Array = source.keys()
	ids.sort()
	for actor_id: Variant in ids:
		result[String(actor_id)] = _vector_data(source[actor_id] as Vector2i)
	return result


static func _parse_positions(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var result: Dictionary = {}
	for actor_id: Variant in value:
		var coordinate := _parse_vector(value[actor_id])
		if not actor_id is String or actor_id.is_empty() or coordinate == INVALID_COORDINATE or result.has(actor_id):
			return null
		result[actor_id] = coordinate
	return result


static func _vector_data(value: Vector2i) -> Array[int]:
	return [value.x, value.y]


static func _parse_vector(value: Variant) -> Vector2i:
	if not value is Array or value.size() != 2:
		return INVALID_COORDINATE
	var x := _signed_integer(value[0])
	var y := _signed_integer(value[1])
	return INVALID_COORDINATE if x == -100_000 or y == -100_000 else Vector2i(x, y)


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
