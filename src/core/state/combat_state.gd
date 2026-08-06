class_name CombatState
extends RefCounted

var battle_id: String
var macro_id: int = 0
var round_number: int = 1
var turn_index: int = 0
var completed: bool = false
var outcome: StringName = &"active"
var _turn_order: Array[String] = []
var _monsters: Array[MonsterState] = []


func _init(source_battle_id: String, initial_monsters: Array[MonsterState] = [], battle_macro_id: int = 0) -> void:
	battle_id = source_battle_id
	_monsters = initial_monsters.duplicate()
	macro_id = battle_macro_id


func monsters() -> Array[MonsterState]:
	return _monsters.duplicate()


func turn_order() -> Array[String]:
	return _turn_order.duplicate()


func set_turn_order(order: Array[String]) -> void:
	_turn_order = order.duplicate()
	turn_index = 0


func active_actor_id() -> String:
	return "" if _turn_order.is_empty() or turn_index < 0 or turn_index >= _turn_order.size() else _turn_order[turn_index]


func monster_by_id(monster_id: String) -> MonsterState:
	for monster: MonsterState in _monsters:
		if monster.id == monster_id:
			return monster
	return null


func add_monster(monster: MonsterState) -> bool:
	if monster == null or monster_by_id(monster.id) != null:
		return false
	_monsters.append(monster)
	return true


func advance_turn() -> void:
	if _turn_order.is_empty():
		return
	turn_index += 1
	if turn_index >= _turn_order.size():
		turn_index = 0
		round_number += 1


func append_turn_actor(actor_id: String) -> void:
	if not actor_id.is_empty() and not _turn_order.has(actor_id):
		_turn_order.append(actor_id)


func to_data() -> Dictionary:
	var monster_data: Array[Dictionary] = []
	for monster: MonsterState in _monsters:
		monster_data.append(monster.to_data())
	return {"battleId": battle_id, "macroId": macro_id, "round": round_number, "turnIndex": turn_index, "completed": completed, "outcome": String(outcome), "turnOrder": _turn_order.duplicate(), "monsters": monster_data}


static func from_data(data: Variant) -> CombatState:
	if not data is Dictionary:
		return null
	for field: String in ["battleId", "round", "turnIndex", "completed", "outcome", "turnOrder", "monsters"]:
		if not data.has(field):
			return null
	var loaded_round := _integer(data["round"])
	var loaded_turn := _integer(data["turnIndex"])
	var loaded_macro := _signed_integer(data.get("macroId", 0))
	if not data["battleId"] is String or data["battleId"].is_empty() or loaded_macro == -100_000 or loaded_round < 1 or loaded_turn < 0 or not data["completed"] is bool or not data["outcome"] is String or not data["turnOrder"] is Array or not data["monsters"] is Array:
		return null
	var loaded_monsters: Array[MonsterState] = []
	for entry: Variant in data["monsters"]:
		var monster := MonsterState.from_data(entry)
		if monster == null:
			return null
		loaded_monsters.append(monster)
	var result := CombatState.new(data["battleId"], loaded_monsters, loaded_macro)
	var order: Array[String] = []
	for entry: Variant in data["turnOrder"]:
		if not entry is String or entry.is_empty():
			return null
		order.append(entry)
	result.round_number = loaded_round
	result.turn_index = loaded_turn
	result.completed = data["completed"]
	result.outcome = StringName(data["outcome"])
	result._turn_order = order
	if result.turn_index > result._turn_order.size():
		return null
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
