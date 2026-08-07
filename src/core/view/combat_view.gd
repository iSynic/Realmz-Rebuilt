class_name CombatView
extends RefCounted

var battle_id: String
var round_number: int
var active_actor_id: String
var outcome: StringName
var turn_order: Array[String] = []
var legal_actions: Array[StringName] = []
var targets: Array[MonsterView] = []
var monsters: Array[MonsterView] = []


func _init(combat: CombatState) -> void:
	battle_id = combat.battle_id
	round_number = combat.round_number
	active_actor_id = combat.active_actor_id()
	outcome = combat.outcome
	turn_order = combat.turn_order()
	if not combat.completed:
		legal_actions.append(&"attack")
		legal_actions.append(&"defend")
		legal_actions.append(&"retreat")
	for monster: MonsterState in combat.monsters():
		var view := MonsterView.new(monster)
		monsters.append(view)
		targets.append(view)
