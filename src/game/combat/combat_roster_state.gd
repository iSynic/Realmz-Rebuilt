## Owns the mutable monster roster for one battle.

class_name CombatRosterState
extends RefCounted

var _monsters: Array[MonsterState] = []
var _monsters_by_id: Dictionary = {}
var _sidelined: Dictionary = {}


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


## A death-macro subject revived by its own macro stays out of the battle, as in Castle killbody.
func mark_sidelined(monster_id: String) -> bool:
	if monster_by_id(monster_id) == null:
		return false
	_sidelined[monster_id] = true
	return true


func is_sidelined(monster_id: String) -> bool:
	return _sidelined.has(monster_id)


func sidelined_ids() -> Array[String]:
	var result: Array[String] = []
	for monster: MonsterState in _monsters:
		if _sidelined.has(monster.id):
			result.append(monster.id)
	return result


func to_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for monster: MonsterState in _monsters:
		result.append(monster.to_data())
	return result
