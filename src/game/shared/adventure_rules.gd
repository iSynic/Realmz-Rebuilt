## Explicit adventure-owned departures from the default Classic rules.
class_name AdventureRules
extends RefCounted

var free_targeting_cancellation: bool = false


func to_data() -> Dictionary:
	return {"freeTargetingCancellation": free_targeting_cancellation}


func copy() -> AdventureRules:
	var result := AdventureRules.new()
	result.free_targeting_cancellation = free_targeting_cancellation
	return result


static func from_data(data: Variant) -> AdventureRules:
	if not data is Dictionary:
		return null
	var record: Dictionary = data
	if record.size() != 1 or not record.get("freeTargetingCancellation") is bool:
		return null
	var result := AdventureRules.new()
	result.free_targeting_cancellation = record["freeTargetingCancellation"]
	return result
