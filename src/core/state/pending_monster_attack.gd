class_name PendingMonsterAttack
extends RefCounted

var actor_id: String
var target_id: String
var action: StringName
var damage: int
var chance: int
var roll: int


func _init(source_actor_id: String, source_target_id: String, source_action: StringName, pending_damage: int, hit_chance: int, hit_roll: int) -> void:
	actor_id = source_actor_id
	target_id = source_target_id
	action = source_action
	damage = pending_damage
	chance = hit_chance
	roll = hit_roll


func to_data() -> Dictionary:
	return {
		"actorId": actor_id,
		"targetId": target_id,
		"action": String(action),
		"damage": damage,
		"chance": chance,
		"roll": roll,
	}


static func from_data(data: Variant) -> PendingMonsterAttack:
	if not data is Dictionary or data.size() != 6:
		return null
	for field: String in ["actorId", "targetId", "action", "damage", "chance", "roll"]:
		if not data.has(field):
			return null
	if not data["actorId"] is String or data["actorId"].is_empty() or not data["targetId"] is String or data["targetId"].is_empty() or not data["action"] is String or data["action"].is_empty():
		return null
	var pending_damage := _integer(data["damage"])
	var hit_chance := _integer(data["chance"])
	var hit_roll := _integer(data["roll"])
	if data["action"] not in ["advance", "missile"] or pending_damage < 0 or hit_roll < 1 or hit_roll > 100 or hit_chance == -100_000:
		return null
	return PendingMonsterAttack.new(data["actorId"], data["targetId"], StringName(data["action"]), pending_damage, hit_chance, hit_roll)


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
