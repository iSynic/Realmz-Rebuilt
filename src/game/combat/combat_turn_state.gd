## Stores mutable combat turn state inside a deterministic playthrough.

class_name CombatTurnState
extends RefCounted

var actor_id: String
var action: StringName = &""
var attack_index: int = 0
var target_id: String = ""
var physical_action_committed: bool = false
var classic_physical_active: bool = false
var classic_spell_active: bool = false
var movement_remaining: int = -1
var spell_cast_count: int = 0
var monster_cast_attempt_count: int = 0
var staged_item_instance_id: String = ""
var staged_item_power: int = 0
## An animated character's juke loop saved while its step waits on a reaction (cost 0 when none is saved).
var juke_passes: int = -1
var juke_step_cost: int = 0
var cast_commitment: CombatCastCommitment


func _init(source_actor_id: String) -> void:
	actor_id = source_actor_id


func commit_physical_action() -> void:
	physical_action_committed = true
	classic_physical_active = true


func to_data() -> Dictionary:
	var data := {
		"actorId": actor_id,
		"action": String(action),
		"attackIndex": attack_index,
		"targetId": target_id,
		"physicalActionCommitted": physical_action_committed,
		"classicPhysicalActive": classic_physical_active,
		"classicSpellActive": classic_spell_active,
		"movementRemaining": movement_remaining,
		"spellCastCount": spell_cast_count,
		"monsterCastAttemptCount": monster_cast_attempt_count,
		"stagedItemInstanceId": staged_item_instance_id,
		"stagedItemPower": staged_item_power,
	}
	if cast_commitment != null:
		data["castCommitment"] = cast_commitment.to_data()
	if juke_step_cost > 0:
		data["jukePasses"] = juke_passes
		data["jukeStepCost"] = juke_step_cost
	return data


static func from_data(data: Variant) -> CombatTurnState:
	if not data is Dictionary:
		return null
	var fields: Dictionary = data
	var juke_fields := 2 if fields.has("jukeStepCost") else 0
	var juke_passes := _integer(fields.get("jukePasses", -1))
	var juke_cost := _integer(fields.get("jukeStepCost", 0))
	if fields.has("jukePasses") != fields.has("jukeStepCost") or fields.size() - juke_fields not in [4, 5, 6, 7, 8, 10, 11, 12, 13]:
		return null
	if juke_fields > 0 and (juke_passes < -1 or juke_passes > 21 or juke_cost < 1 or juke_cost > 127):
		return null
	var allowed_fields: Array[String] = ["actorId", "action", "attackIndex", "targetId", "physicalActionCommitted", "movementRemaining", "spellCastCount", "monsterCastAttemptCount", "stagedItemInstanceId", "stagedItemPower", "castCommitment", "classicPhysicalActive", "classicSpellActive", "jukePasses", "jukeStepCost"]
	for key: Variant in data.keys():
		if not key is String or key not in allowed_fields:
			return null
	if data.has("classicPhysicalActive") != data.has("classicSpellActive") or data.has("classicPhysicalActive") and (not data["classicPhysicalActive"] is bool or not data["classicSpellActive"] is bool):
		return null
	if data.has("castCommitment") and data.size() - juke_fields != (13 if data.has("classicPhysicalActive") else 11):
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
	if loaded_attack_index < 0 or data["action"] not in ["", "advance", "missile", "cast", "retreat", "flee_question", "stay"]:
		return null
	var result := CombatTurnState.new(data["actorId"])
	result.action = StringName(data["action"])
	result.attack_index = loaded_attack_index
	result.target_id = data["targetId"]
	result.physical_action_committed = bool(data.get("physicalActionCommitted", false))
	# V5 retains its recorded effective physical guard; no past macro is replayed.
	result.classic_physical_active = data.get("classicPhysicalActive", result.physical_action_committed)
	result.classic_spell_active = data.get("classicSpellActive", data.has("castCommitment"))
	result.movement_remaining = _integer(data.get("movementRemaining", -1))
	result.spell_cast_count = _integer(data.get("spellCastCount", 0))
	result.monster_cast_attempt_count = _integer(data.get("monsterCastAttemptCount", 0))
	result.staged_item_instance_id = String(data.get("stagedItemInstanceId", ""))
	result.staged_item_power = _integer(data.get("stagedItemPower", 0))
	result.juke_passes = juke_passes
	result.juke_step_cost = juke_cost
	if data.has("castCommitment"):
		result.cast_commitment = CombatCastCommitment.from_data(data["castCommitment"])
		if result.cast_commitment == null or result.cast_commitment.selection.actor_id != result.actor_id or result.cast_commitment.reserved_spell_count and result.spell_cast_count == 0:
			return null
	return result


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1
