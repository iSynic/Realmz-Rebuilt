## Owns the mutable monster roster for one battle.

class_name CombatRosterState
extends RefCounted

var _monsters: Array[MonsterState] = []
var _monsters_by_id: Dictionary = {}


func _init(initial_monsters: Array[MonsterState] = []) -> void:
	_monsters = initial_monsters.duplicate()
	for monster: MonsterState in _monsters:
		_monsters_by_id[monster.id] = monster


func monsters() -> Array[MonsterState]:
	return _monsters.duplicate()


func monster_by_id(monster_id: String) -> MonsterState:
	return _monsters_by_id.get(monster_id) as MonsterState


func add_monster(monster: MonsterState) -> bool:
	if monster == null or monster_by_id(monster.id) != null:
		return false
	_monsters.append(monster)
	_monsters_by_id[monster.id] = monster
	return true


func to_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for monster: MonsterState in _monsters:
		result.append(monster.to_data())
	return result
