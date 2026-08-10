class_name TempleServiceResult
extends RefCounted

var service_id: StringName
var applied: bool = false
var health_before: int = 0
var health_after: int = 0
var condition_index: int = -1
var condition_before: int = 0
var condition_after: int = 0
var ability_before: int = 0
var ability_after: int = 0
var unequipped_item_ids: Array[String] = []


func _init(id: StringName, character: CharacterState) -> void:
	service_id = id
	health_before = character.current_health
	health_after = character.current_health
	ability_before = character.ability_value(2)
	ability_after = ability_before


func healing() -> int:
	return health_after - health_before


func to_event_data(character_id: String, cost: int) -> Dictionary:
	return {
		"serviceId": String(service_id),
		"characterId": character_id,
		"cost": cost,
		"applied": applied,
		"healthBefore": health_before,
		"health": health_after,
		"healing": healing(),
		"conditionIndex": condition_index,
		"conditionBefore": condition_before,
		"condition": condition_after,
		"abilityBefore": ability_before,
		"ability": ability_after,
		"unequippedItemIds": unequipped_item_ids.duplicate(),
	}
