class_name RealmzRules
extends RefCounted

var arithmetic: RealmzArithmetic
var characters: CharacterRules
var conditions: ConditionRules
var inventory: InventoryRules
var economy: EconomyRules
var temple: TempleRules
var combat: CombatRules
var magic: MagicRules
var monsters: MonsterRules
var clock: ClockRules
var battlefield: BattlefieldRules
var spell_areas: SpellAreaRules
var combat_flow: CombatFlow


func _init() -> void:
	arithmetic = RealmzArithmetic.new()
	characters = CharacterRules.new()
	conditions = ConditionRules.new()
	inventory = InventoryRules.new()
	economy = EconomyRules.new()
	temple = TempleRules.new()
	combat = CombatRules.new(conditions, characters)
	monsters = MonsterRules.new()
	magic = MagicRules.new(characters, arithmetic, monsters)
	clock = ClockRules.new(conditions, characters, inventory)
	battlefield = BattlefieldRules.new()
	spell_areas = SpellAreaRules.new()
	combat_flow = CombatFlow.new(self)
