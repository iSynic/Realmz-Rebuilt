class_name CombatTurnState
extends RefCounted

var actor_id: String
var action: StringName = &""
var attack_index: int = 0
var target_id: String = ""
var physical_action_committed: bool = false
var movement_remaining: int = -1
var spell_cast_count: int = 0
var monster_cast_attempt_count: int = 0
var staged_item_instance_id: String = ""
var staged_item_power: int = 0


func _init(source_actor_id: String) -> void:
	actor_id = source_actor_id


func to_data() -> Dictionary:
	return {
		"actorId": actor_id,
		"action": String(action),
		"attackIndex": attack_index,
		"targetId": target_id,
		"physicalActionCommitted": physical_action_committed,
		"movementRemaining": movement_remaining,
		"spellCastCount": spell_cast_count,
		"monsterCastAttemptCount": monster_cast_attempt_count,
		"stagedItemInstanceId": staged_item_instance_id,
		"stagedItemPower": staged_item_power,
	}


static func from_data(data: Variant) -> CombatTurnState:
	if not data is Dictionary or data.size() not in [4, 5, 6, 7, 8, 10]:
		return null
	for field: String in ["actorId", "action", "attackIndex", "targetId"]:
		if not data.has(field):
			return null
	if not data["actorId"] is String or data["actorId"].is_empty() or not data["action"] is String or not data["targetId"] is String:
		return null
	if data.has("physicalActionCommitted") and not data["physicalActionCommitted"] is bool:
		return null
	if data.has("movementRemaining") and _integer(data["movementRemaining"]) < -1:
		return null
	if data.has("spellCastCount") and _integer(data["spellCastCount"]) < 0:
		return null
	if data.has("monsterCastAttemptCount") and _integer(data["monsterCastAttemptCount"]) < 0:
		return null
	if data.has("stagedItemInstanceId") != data.has("stagedItemPower") or data.has("stagedItemInstanceId") and (not data["stagedItemInstanceId"] is String or data["stagedItemInstanceId"].is_empty() != (_integer(data["stagedItemPower"]) == 0) or _integer(data["stagedItemPower"]) < 0 or _integer(data["stagedItemPower"]) > 7):
		return null
	var loaded_attack_index := _integer(data["attackIndex"])
	if loaded_attack_index < 0 or data["action"] not in ["", "advance", "missile", "cast", "retreat"]:
		return null
	var result := CombatTurnState.new(data["actorId"])
	result.action = StringName(data["action"])
	result.attack_index = loaded_attack_index
	result.target_id = data["targetId"]
	result.physical_action_committed = bool(data.get("physicalActionCommitted", false))
	result.movement_remaining = _integer(data.get("movementRemaining", -1))
	result.spell_cast_count = _integer(data.get("spellCastCount", 0))
	result.monster_cast_attempt_count = _integer(data.get("monsterCastAttemptCount", 0))
	result.staged_item_instance_id = String(data.get("stagedItemInstanceId", ""))
	result.staged_item_power = _integer(data.get("stagedItemPower", 0))
	return result


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1
