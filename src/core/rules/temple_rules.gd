class_name TempleRules
extends RefCounted

const HEAL_SMALL: StringName = &"heal-small"
const HEAL_MEDIUM: StringName = &"heal-medium"
const HEAL_LARGE: StringName = &"heal-large"
const HEAL_DISEASE: StringName = &"heal-disease"
const RESTORE_FLESH: StringName = &"restore-flesh"
const HEAL_POISON: StringName = &"heal-poison"
const HEAL_BLINDNESS: StringName = &"heal-blindness"
const REMOVE_CURSE: StringName = &"remove-curse"
const REVIVE_DEAD: StringName = &"revive-dead"

const CONDITION_CURSED: int = 3
const CONDITION_POISONED: int = 9
const CONDITION_ANIMATED: int = 25
const CONDITION_STONE: int = 26
const CONDITION_BLIND: int = 27
const CONDITION_DISEASED: int = 28

const SERVICE_IDS: Array[StringName] = [
	HEAL_SMALL,
	HEAL_MEDIUM,
	HEAL_LARGE,
	HEAL_DISEASE,
	RESTORE_FLESH,
	HEAL_POISON,
	HEAL_BLINDNESS,
	REMOVE_CURSE,
	REVIVE_DEAD,
]
const BASE_COSTS: Array[int] = [250, 350, 850, 200, 750, 200, 350, 550, 1500]
const LABELS: Array[String] = [
	"Heal Small Wounds",
	"Heal Medium Wounds",
	"Heal Large Wounds",
	"Heal Disease",
	"Restore Flesh",
	"Heal Poison",
	"Heal Blindness",
	"Remove Cursed Items",
	"Revive Dead",
]
const DESCRIPTIONS: Array[String] = [
	"Restore 1-8 stamina.",
	"Restore 3-24 stamina.",
	"Restore stamina up to the character's maximum.",
	"Remove disease.",
	"Reverse petrification.",
	"Remove poison.",
	"Remove blindness.",
	"Remove the Cursed condition and force cursed equipment off.",
	"Restore an eligible dead or Animated character at -9 stamina.",
]
const CONDITION_NAMES: Array[String] = [
	"In Retreat", "Is Helpless", "Entangled", "Cursed", "Magic Aura", "Stupid", "Moving Slowly", "Shielded from Hits", "Missile Shield", "Poisoned",
	"Regenerating", "Fire Protection", "Cold Protection", "Electrical Protection", "Chemical Protection", "Psi Protection", "Protection from First Level Spells", "Protection from Second Level Spells", "Protection from Third Level Spells", "Protection from Fourth Level Spells",
	"Protection from Fifth Level Spells", "Strong", "Protection from Foe", "Speedy", "Invisible", "Animated", "Turned to Stone", "Blind", "Is Diseased", "Confused",
	"Reflecting Spells", "Reflecting Attacks", "Bonus Damage", "Absorbing Energy", "Losing Energy", "Absorbing Spell Energy", "Hindered Attacks", "Hindered Defense", "Increased Defense", "Silenced",
]


func service_rows(cost_percent: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index: int in SERVICE_IDS.size():
		rows.append({
			"id": String(SERVICE_IDS[index]),
			"label": LABELS[index],
			"description": DESCRIPTIONS[index],
			"cost": service_cost(SERVICE_IDS[index], cost_percent),
		})
	return rows


func service_cost(service_id: StringName, cost_percent: int) -> int:
	var index := SERVICE_IDS.find(service_id)
	if index < 0:
		return 0
	return RealmzArithmetic.new().signed_16(int(float(BASE_COSTS[index] * cost_percent) / 100.0))


func condition_name(index: int) -> String:
	return "Condition %d" % index if index < 0 or index >= CONDITION_NAMES.size() else CONDITION_NAMES[index]


func apply_service(character: CharacterState, service_id: StringName, rng: RealmzRng, item_definitions: Array[ItemDefinition]) -> TempleServiceResult:
	if character == null or rng == null or not SERVICE_IDS.has(service_id):
		return null
	var result := TempleServiceResult.new(service_id, character)
	match service_id:
		HEAL_SMALL:
			_apply_healing(character, rng.draw(8, &"temple.heal-small"), result)
		HEAL_MEDIUM:
			_apply_healing(character, rng.draw_between(3, 24, &"temple.heal-medium"), result)
		HEAL_LARGE:
			_apply_healing(character, 5000, result)
		HEAL_DISEASE:
			_clear_condition(character, CONDITION_DISEASED, result)
		RESTORE_FLESH:
			_clear_condition(character, CONDITION_STONE, result)
		HEAL_POISON:
			_clear_condition(character, CONDITION_POISONED, result)
		HEAL_BLINDNESS:
			_clear_condition(character, CONDITION_BLIND, result)
		REMOVE_CURSE:
			_remove_curse(character, item_definitions, result)
		REVIVE_DEAD:
			_revive(character, result)
	result.health_after = character.current_health
	result.ability_after = character.ability_value(2)
	return result


func _apply_healing(character: CharacterState, amount: int, result: TempleServiceResult) -> void:
	if character.conditions.is_active(CONDITION_STONE) or character.current_health < -9:
		return
	var wrapped_health := RealmzArithmetic.new().signed_16(character.current_health + amount)
	character.current_health = mini(character.maximum_health, maxi(-10, wrapped_health))
	result.applied = character.current_health != result.health_before


func _clear_condition(character: CharacterState, index: int, result: TempleServiceResult) -> void:
	result.condition_index = index
	result.condition_before = character.conditions.value(index)
	character.conditions.set_value(index, 0)
	result.condition_after = 0
	result.applied = result.condition_before != 0


func _remove_curse(character: CharacterState, item_definitions: Array[ItemDefinition], result: TempleServiceResult) -> void:
	_clear_condition(character, CONDITION_CURSED, result)
	var definitions: Dictionary = {}
	for definition: ItemDefinition in item_definitions:
		definitions[definition.id] = definition
	for instance: ItemInstance in character.inventory():
		var definition: ItemDefinition = definitions.get(instance.definition_id)
		if instance.equipped and definition != null and not definition.cursed_item_id.is_empty():
			instance.equipped = false
			result.unequipped_item_ids.append(instance.id)
	result.applied = result.applied or not result.unequipped_item_ids.is_empty()


func _revive(character: CharacterState, result: TempleServiceResult) -> void:
	var stone_before := character.conditions.value(CONDITION_STONE)
	var animated_before := character.conditions.value(CONDITION_ANIMATED)
	if stone_before == 0 and (character.current_health < -9 or animated_before != 0):
		character.current_health = -9
		character.set_ability_value(2, RealmzArithmetic.new().signed_16(character.ability_value(2) - 2))
	character.conditions.set_value(CONDITION_ANIMATED, 0)
	character.conditions.set_value(CONDITION_STONE, 0)
	result.condition_index = CONDITION_ANIMATED if animated_before != 0 else CONDITION_STONE
	result.condition_before = animated_before if animated_before != 0 else stone_before
	result.condition_after = 0
	result.applied = character.current_health != result.health_before or character.ability_value(2) != result.ability_before or animated_before != 0 or stone_before != 0
