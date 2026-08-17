class_name MonsterView
extends RefCounted

var id: String
var definition_id: String
var classic_id: int = 0
var name: String
var current_health: int
var maximum_health: int
var hit_dice: int
var armor: int
var magic_resistance: int
var spell_points: int
var maximum_spell_points: int
var movement_maximum: int = 0
var attack_count: int = 0
var traitor: bool
var helpless: bool = false
var icon_id: int
var icon_resource_type: String = "cicn"
var conditions: Array[String] = []
var immunities: Array[String] = []
var vulnerabilities: Array[String] = []
var weapon_name: String = "Unarmed"


func _init(monster: MonsterState, definition: MonsterDefinition = null, content: RealmzContent = null) -> void:
	id = monster.id
	definition_id = monster.definition_id
	name = monster.name
	current_health = monster.current_health
	maximum_health = monster.maximum_health
	hit_dice = monster.hit_dice
	armor = monster.armor
	magic_resistance = monster.magic_resistance
	spell_points = monster.spell_points
	maximum_spell_points = monster.maximum_spell_points
	traitor = monster.traitor
	helpless = monster.conditions.is_active(ConditionRules.HELPLESS)
	icon_id = monster.icon_id
	for index: int in monster.conditions.values().size():
		if monster.conditions.value(index) != 0:
			conditions.append(CharacterView.CONDITION_NAMES[index] if index < CharacterView.CONDITION_NAMES.size() else "Classic condition %d" % (index + 1))
	if definition != null:
		classic_id = definition.classic_id
		movement_maximum = definition.movement_max
		attack_count = definition.attack_count
		for index: int in 6:
			if definition.spell_immune(index):
				immunities.append(CharacterView.SAVE_NAMES[index])
		for index: int in 5:
			if definition.save_value(index) < 0:
				vulnerabilities.append(CharacterView.SAVE_NAMES[index])
	if content != null and not monster.weapon_id.is_empty():
		var weapon := content.item_by_id(monster.weapon_id)
		if weapon != null:
			weapon_name = weapon.name
