## Carries the normalized source identity for one staged combat choice.

class_name CombatCastSelection
extends RefCounted

const ACTIONS: Array[StringName] = [&"cast_spell", &"use_scroll", &"use_item", &"attack"]

var action: StringName = &""
var actor_id: String = ""
var spell_id: String = ""
var power: int = 1
var item_instance_id: String = ""
var scroll_slot: int = -1


static func from_body(body: InteractionResponse.CombatBody) -> CombatCastSelection:
	if body == null:
		return null
	var normalized_action: StringName
	match body.action:
		&"begin_spell", &"adjust_cast", &"cast_spell": normalized_action = &"cast_spell"
		&"begin_scroll", &"use_scroll": normalized_action = &"use_scroll"
		&"begin_item", &"use_item": normalized_action = &"use_item"
		&"begin_projectile", &"attack": normalized_action = &"attack"
		&"abort_cast": normalized_action = &"cast_spell"
		_: return null
	var result := CombatCastSelection.new()
	result.action = normalized_action
	result.actor_id = body.actor_id
	if body.action == &"abort_cast":
		return result if not result.actor_id.is_empty() else null
	result.spell_id = body.spell_id
	result.power = body.power
	result.item_instance_id = body.item_instance_id
	result.scroll_slot = body.scroll_slot
	return result if result.is_valid() else null


func to_body() -> InteractionResponse.CombatBody:
	var body := InteractionResponse.CombatBody.new(action, actor_id)
	if action == &"cast_spell" and spell_id.is_empty():
		body.action = &"abort_cast"
	body.spell_id = spell_id
	body.power = power
	body.item_instance_id = item_instance_id
	body.scroll_slot = scroll_slot
	return body


func same_source(other: CombatCastSelection) -> bool:
	return other != null and action == other.action and actor_id == other.actor_id and spell_id == other.spell_id and item_instance_id == other.item_instance_id and scroll_slot == other.scroll_slot


func is_valid() -> bool:
	if action not in ACTIONS or actor_id.is_empty() or power < 1 or power > 7 or scroll_slot < -1:
		return false
	match action:
		&"cast_spell": return not spell_id.is_empty() and item_instance_id.is_empty() and scroll_slot == -1
		&"use_scroll": return not spell_id.is_empty() and item_instance_id.is_empty() and scroll_slot in range(5)
		&"use_item": return not item_instance_id.is_empty() and scroll_slot == -1
		&"attack": return scroll_slot == -1
	return false


func to_data() -> Dictionary:
	return {"action": String(action), "actorId": actor_id, "spellId": spell_id, "power": power, "itemInstanceId": item_instance_id, "scrollSlot": scroll_slot}


static func from_data(data: Variant) -> CombatCastSelection:
	if not data is Dictionary or data.size() != 6 or not _has_exact_keys(data, ["action", "actorId", "spellId", "power", "itemInstanceId", "scrollSlot"]):
		return null
	if not data["action"] is String or not data["actorId"] is String or not data["spellId"] is String or not _whole_number(data["power"]) or not data["itemInstanceId"] is String or not _whole_number(data["scrollSlot"]):
		return null
	var result := CombatCastSelection.new()
	result.action = StringName(data["action"])
	result.actor_id = data["actorId"]
	result.spell_id = data["spellId"]
	result.power = int(data["power"])
	result.item_instance_id = data["itemInstanceId"]
	result.scroll_slot = int(data["scrollSlot"])
	return result if result.is_valid() else null


static func _has_exact_keys(data: Dictionary, expected: Array[String]) -> bool:
	for key: Variant in data.keys():
		if not key is String or key not in expected:
			return false
	return true


static func _whole_number(value: Variant) -> bool:
	return value is int or value is float and is_finite(value) and value == floor(value)
