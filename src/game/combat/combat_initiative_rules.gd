## Calculates deterministic combat initiative ordering.

class_name CombatInitiativeRules
extends RefCounted

const AttackPolicy := preload("res://src/game/combat/combat_attack_policy.gd")


func initiative_order(characters: Array[CharacterState], monsters: Array[MonsterState], surprise: int, rng: RealmzRng) -> Array[String]:
	return AttackPolicy.initiative_order(characters, monsters, surprise, rng)
