class_name PendingMonsterAttack
extends RefCounted

var actor_id: String
var target_id: String
var action: StringName
var damage: int
var chance: int
var roll: int
var weapon_condition_index: int = -1
var weapon_condition_before: int = 0
var weapon_condition_after: int = 0
var physical_feedback_sound_id: int = 0


func _init(source_actor_id: String, source_target_id: String, source_action: StringName, pending_damage: int, hit_chance: int, hit_roll: int, condition_index: int = -1, condition_before: int = 0, condition_after: int = 0, feedback_sound_id: int = 0) -> void:
	actor_id = source_actor_id
	target_id = source_target_id
	action = source_action
	damage = pending_damage
	chance = hit_chance
	roll = hit_roll
	weapon_condition_index = condition_index
	weapon_condition_before = condition_before
	weapon_condition_after = condition_after
	physical_feedback_sound_id = feedback_sound_id


func to_data() -> Dictionary:
	var data := {
		"actorId": actor_id,
		"targetId": target_id,
		"action": String(action),
		"damage": damage,
		"chance": chance,
		"roll": roll,
	}
	if weapon_condition_index >= 0:
		data["weaponConditionIndex"] = weapon_condition_index
		data["weaponConditionBefore"] = weapon_condition_before
		data["weaponConditionAfter"] = weapon_condition_after
	if physical_feedback_sound_id > 0:
		data["physicalFeedbackSoundId"] = physical_feedback_sound_id
	return data


static func from_data(data: Variant) -> PendingMonsterAttack:
	if not data is Dictionary or data.size() not in [6, 7, 9, 10]:
		return null
	for field: String in ["actorId", "targetId", "action", "damage", "chance", "roll"]:
		if not data.has(field):
			return null
	if not data["actorId"] is String or data["actorId"].is_empty() or not data["targetId"] is String or data["targetId"].is_empty() or not data["action"] is String or data["action"].is_empty():
		return null
	var pending_damage := _integer(data["damage"])
	var hit_chance := _integer(data["chance"])
	var hit_roll := _integer(data["roll"])
	if data["action"] not in ["advance", "missile", "guard", "withdrawal"] or pending_damage < 0 or hit_roll < 1 or hit_roll > 100 or hit_chance == -100_000:
		return null
	var condition_index := _integer(data.get("weaponConditionIndex", -1))
	var condition_before := _integer(data.get("weaponConditionBefore", 0))
	var condition_after := _integer(data.get("weaponConditionAfter", 0))
	var has_condition_fields: bool = data.has("weaponConditionIndex") and data.has("weaponConditionBefore") and data.has("weaponConditionAfter")
	var feedback_sound_id := _integer(data.get("physicalFeedbackSoundId", 0))
	var has_feedback_sound: bool = data.has("physicalFeedbackSoundId")
	var expected_size := 6 + (3 if has_condition_fields else 0) + (1 if has_feedback_sound else 0)
	if data.size() != expected_size or has_condition_fields != (condition_index >= 0) or condition_index < -1 or condition_index >= ConditionSet.CHARACTER_COUNT or condition_before == -100_000 or condition_after == -100_000 or feedback_sound_id < 0:
		return null
	return PendingMonsterAttack.new(data["actorId"], data["targetId"], StringName(data["action"]), pending_damage, hit_chance, hit_roll, condition_index, condition_before, condition_after, feedback_sound_id)


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
