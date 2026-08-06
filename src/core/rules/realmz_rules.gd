class_name RealmzRules
extends RefCounted

var arithmetic: RealmzArithmetic
var characters: CharacterRules
var conditions: ConditionRules
var inventory: InventoryRules
var economy: EconomyRules
var combat: CombatRules
var magic: MagicRules
var monsters: MonsterRules
var clock: ClockRules
var combat_flow: CombatFlow


func _init() -> void:
	arithmetic = RealmzArithmetic.new()
	characters = CharacterRules.new()
	conditions = ConditionRules.new()
	inventory = InventoryRules.new()
	economy = EconomyRules.new()
	combat = CombatRules.new(conditions)
	magic = MagicRules.new()
	monsters = MonsterRules.new()
	clock = ClockRules.new(conditions)
	combat_flow = CombatFlow.new(self)
