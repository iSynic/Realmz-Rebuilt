class_name CombatTurnState
extends RefCounted

var actor_id: String
var action: StringName = &""
var attack_index: int = 0
var target_id: String = ""
var physical_action_committed: bool = false
var movement_remaining: int = -1


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
	}


static func from_data(data: Variant) -> CombatTurnState:
	if not data is Dictionary or data.size() not in [4, 5, 6]:
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
	var loaded_attack_index := _integer(data["attackIndex"])
	if loaded_attack_index < 0 or data["action"] not in ["", "advance", "missile", "cast", "retreat"]:
		return null
	var result := CombatTurnState.new(data["actorId"])
	result.action = StringName(data["action"])
	result.attack_index = loaded_attack_index
	result.target_id = data["targetId"]
	result.physical_action_committed = bool(data.get("physicalActionCommitted", false))
	result.movement_remaining = _integer(data.get("movementRemaining", -1))
	return result


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1
