## Stores battlefield actor anchors, sizes, occupancy, and placement mutations.

class_name BattlefieldActorState
extends RefCounted


var _character_positions: Dictionary
var _monster_positions: Dictionary
var _monster_sizes: Dictionary


func _init(character_positions: Dictionary = {}, monster_positions: Dictionary = {}, monster_sizes: Dictionary = {}) -> void:
	_character_positions = character_positions.duplicate()
	_monster_positions = monster_positions.duplicate()
	_monster_sizes = monster_sizes.duplicate()


func character_position(actor_id: String) -> Vector2i:
	return _coordinate(_character_positions.get(actor_id))


func monster_position(actor_id: String) -> Vector2i:
	return _coordinate(_monster_positions.get(actor_id))


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
	return BattlefieldGrid.footprint_cells(anchor, size) if size >= 0 and anchor.x >= 0 else []


func actor_at(coordinate: Vector2i, excluding_actor_id: String = "") -> String:
	for actor_id: Variant in _character_positions:
		if actor_id != excluding_actor_id and _coordinate(_character_positions[actor_id]) == coordinate:
			return String(actor_id)
	for actor_id: Variant in _monster_positions:
		if actor_id != excluding_actor_id and BattlefieldGrid.footprint_cells(_coordinate(_monster_positions[actor_id]), int(_monster_sizes.get(actor_id, 0))).has(coordinate):
			return String(actor_id)
	return ""


func place_character(actor_id: String, coordinate: Vector2i) -> bool:
	if actor_id.is_empty() or not BattlefieldGrid.contains(coordinate) or is_occupied(coordinate):
		return false
	_character_positions[actor_id] = coordinate
	return true


func remove_character(actor_id: String) -> void:
	_character_positions.erase(actor_id)


func place_monster(actor_id: String, coordinate: Vector2i, size: int) -> bool:
	if actor_id.is_empty() or size < 0 or size > 3:
		return false
	for cell: Vector2i in BattlefieldGrid.footprint_cells(coordinate, size):
		if not BattlefieldGrid.contains(cell) or is_occupied(cell):
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
		if not BattlefieldGrid.contains(coordinate) or not actor_at(coordinate, actor_id).is_empty():
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
	if not BattlefieldGrid.contains(first_position) or not BattlefieldGrid.contains(second_position):
		return false
	_set_actor_position(first_actor_id, second_position)
	_set_actor_position(second_actor_id, first_position)
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
		if BattlefieldGrid.footprint_cells(_coordinate(_monster_positions[actor_id]), int(_monster_sizes.get(actor_id, 0))).has(coordinate):
			return true
	return false


func character_positions() -> Dictionary:
	return _character_positions.duplicate()


func monster_positions() -> Dictionary:
	return _monster_positions.duplicate()


func monster_sizes() -> Dictionary:
	return _monster_sizes.duplicate()


func _set_actor_position(actor_id: String, coordinate: Vector2i) -> void:
	if _character_positions.has(actor_id):
		_character_positions[actor_id] = coordinate
	else:
		_monster_positions[actor_id] = coordinate


static func _coordinate(value: Variant) -> Vector2i:
	return value as Vector2i if value is Vector2i else Vector2i(-1, -1)
