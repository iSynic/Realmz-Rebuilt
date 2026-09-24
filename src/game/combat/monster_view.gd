## Carries detached monster data from gameplay into presentation.

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
var summoned: bool = false
var helpless: bool = false
var icon_id: int
var icon_resource_type: String = "cicn"
var conditions: Array[String] = []
var condition_values: Array[int] = []
var immunities: Array[String] = []
var vulnerabilities: Array[String] = []
var weapon_name: String = "Unarmed"
var attack_rows: Array[String] = []
var items: Array[String] = []


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
	summoned = monster.summoned
	helpless = monster.conditions.is_active(ConditionRules.HELPLESS)
	icon_id = monster.icon_id
	condition_values.assign(monster.conditions.values())
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
	var live_weapon: ItemDefinition = null
	if content != null and not monster.weapon_id.is_empty():
		live_weapon = content.items.item_by_id(monster.weapon_id)
		if live_weapon != null:
			weapon_name = ClassicMonsterInspection.carried_item_name(live_weapon)
	var monster_attacks: Array[MonsterAttackDefinition] = []
	if definition != null:
		monster_attacks = definition.attacks()
	attack_rows = ClassicMonsterInspection.attack_rows(
		monster_attacks,
		live_weapon,
		ClassicMonsterInspection.carried_item_name(live_weapon),
		definition.damage_bonus if definition != null else 0,
		0,
		not monster.weapon_id.is_empty() and live_weapon == null,
	)
	_project_carried_items(monster, content)


func _project_carried_items(monster: MonsterState, content: RealmzContent) -> void:
	var item_ids := monster.loot_item_ids()
	var detected_values := monster.loot_magic_detected()
	for slot: int in item_ids.size():
		var item_id := item_ids[slot]
		if item_id.is_empty():
			continue
		var item := content.items.item_by_id(item_id) if content != null else null
		if item == null:
			continue
		var detected := slot < detected_values.size() and detected_values[slot]
		items.append(ClassicMonsterInspection.carried_item_row(item, item_id == monster.weapon_id, detected))
	if monster.weapon_id.is_empty() or item_ids.has(monster.weapon_id) or content == null:
		return
	var weapon := content.items.item_by_id(monster.weapon_id)
	if weapon == null:
		return
	items.append(ClassicMonsterInspection.carried_item_row(weapon, true, false))
