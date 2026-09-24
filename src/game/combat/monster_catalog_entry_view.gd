## Carries detached monster catalog entry data from gameplay into presentation.

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
var immunities: Array[String] = []
var vulnerabilities: Array[String] = []
var attack_rows: Array[String] = []
var weapon_name: String = "Unarmed"


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
	var catalog_weapon: ItemDefinition = null
	if definition.random_weapon_table > 0:
		weapon_name = ""
	elif not definition.weapon_id.is_empty():
		weapon_name = ""
		if content != null:
			catalog_weapon = content.items.item_by_id(definition.weapon_id)
			if catalog_weapon != null:
				weapon_name = catalog_weapon.name
	for index: int in 6:
		if definition.spell_immune(index):
			immunities.append(CharacterView.SAVE_NAMES[index])
	for index: int in 5:
		if definition.save_value(index) < 0:
			vulnerabilities.append(CharacterView.SAVE_NAMES[index])
	attack_rows = ClassicMonsterInspection.attack_rows(
		definition.attacks(),
		catalog_weapon,
		catalog_weapon.name if catalog_weapon != null else "",
		definition.damage_bonus,
		definition.random_weapon_table,
		definition.random_weapon_table == 0 and not definition.weapon_id.is_empty() and catalog_weapon == null,
	)
