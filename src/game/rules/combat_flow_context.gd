class_name CombatFlowContext
extends RefCounted

var arithmetic: RealmzArithmetic
var inventory: InventoryRules
var combat: CombatRules
var magic: MagicRules
var monsters: MonsterRules
var battlefield: BattlefieldRules
var spell_areas: SpellAreaRules
var processing_auto: bool = false


func _init(rules: RealmzRules) -> void:
	arithmetic = rules.arithmetic
	inventory = rules.inventory
	combat = rules.combat
	magic = rules.magic
	monsters = rules.monsters
	battlefield = rules.battlefield
	spell_areas = rules.spell_areas
