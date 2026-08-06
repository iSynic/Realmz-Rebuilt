class_name CombatView
extends RefCounted

var battle_id: String
var round_number: int
var active_actor_id: String
var outcome: StringName
var monsters: Array[MonsterView] = []


func _init(combat: CombatState) -> void:
	battle_id = combat.battle_id
	round_number = combat.round_number
	active_actor_id = combat.active_actor_id()
	outcome = combat.outcome
	for monster: MonsterState in combat.monsters():
		monsters.append(MonsterView.new(monster))
