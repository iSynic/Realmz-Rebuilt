## Saves the next unprocessed Castle round effect across authored macro waits.
class_name CombatRoundCursor
extends RefCounted

const PHASES: Array[StringName] = [&"prior-death-macro", &"battle-macro", &"party", &"character-fields", &"monster-decay", &"monster-regeneration", &"monster-disease", &"monster-poison", &"monster-energy", &"monster-field", &"warning"]

var phase: StringName = &"party"
var actor_index: int = 0
var waiting_monster_id: String = ""


func to_data() -> Dictionary:
	return {"phase": String(phase), "actorIndex": actor_index, "waitingMonsterId": waiting_monster_id}


static func from_data(data: Variant) -> CombatRoundCursor:
	if not data is Dictionary:
		return null
	var record: Dictionary = data
	if record.size() != 3 or not record.get("phase") is String or not record.get("waitingMonsterId") is String:
		return null
	var raw_index: Variant = record.get("actorIndex")
	if not (raw_index is int or raw_index is float):
		return null
	var index: float = raw_index
	var phase_name: String = record["phase"]
	if not is_finite(index) or index != floor(index) or index < 0 or index > 100 or not PHASES.has(StringName(phase_name)):
		return null
	var result := CombatRoundCursor.new()
	result.phase = StringName(phase_name)
	result.actor_index = int(index)
	result.waiting_monster_id = record["waitingMonsterId"]
	return result
