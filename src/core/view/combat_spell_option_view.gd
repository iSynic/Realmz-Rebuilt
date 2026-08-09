class_name CombatSpellOptionView
extends RefCounted

var spell_id: String
var spell_name: String
var power: int
var cost: int
var target_id: String
var target_name: String
var target_current_health: int
var target_maximum_health: int


func _init(spell: SpellDefinition, power_level: int, target: MonsterState) -> void:
	spell_id = spell.id
	spell_name = spell.name
	power = power_level
	cost = absi(spell.cost * power_level)
	target_id = target.id
	target_name = target.name
	target_current_health = target.current_health
	target_maximum_health = target.maximum_health
