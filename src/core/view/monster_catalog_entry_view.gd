class_name MonsterCatalogEntryView
extends RefCounted

var definition_id: String
var classic_id: int
var classic_name_id: int
var name: String
var description: String
var icon_id: int
var hit_dice: int
var armor: int
var magic_resistance: int
var movement_maximum: int
var attack_count: int
var magic_attack_count: int
var weapon_name: String = "Unarmed"
var immunities: Array[String] = []
var vulnerabilities: Array[String] = []
var attack_rows: Array[String] = []


func _init(definition: MonsterDefinition, content: RealmzContent = null) -> void:
	definition_id = definition.id
	classic_id = definition.classic_id
	classic_name_id = definition.classic_name_id
	name = definition.name
	description = definition.description
	icon_id = definition.icon_id
	hit_dice = definition.hit_dice
	armor = definition.armor
	magic_resistance = definition.magic_resistance
	movement_maximum = definition.movement_max
	attack_count = definition.attack_count
	magic_attack_count = definition.magic_attack_count
	if content != null and not definition.weapon_id.is_empty():
		var weapon := content.item_by_id(definition.weapon_id)
		if weapon != null:
			weapon_name = weapon.name
	for index: int in 6:
		if definition.spell_immune(index):
			immunities.append(CharacterView.SAVE_NAMES[index])
	for index: int in 5:
		if definition.save_value(index) < 0:
			vulnerabilities.append(CharacterView.SAVE_NAMES[index])
	for attack: MonsterAttackDefinition in definition.attacks():
		attack_rows.append("%d–%d damage%s" % [attack.damage_min, attack.damage_max, " • special %d" % attack.special if attack.special != 0 else ""])
