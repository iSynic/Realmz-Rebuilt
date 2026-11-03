## Explicit adventure-owned departures from the default Classic rules.
class_name AdventureRules
extends RefCounted

var free_targeting_cancellation: bool = false
## FD-INVENTORY-007: the stock Bard may use the dagger item category.
var bard_daggers: bool = false


## Bard Daggers is written only when enabled, so saves without it stay readable by builds that predate it.
func to_data() -> Dictionary:
	var result := {"freeTargetingCancellation": free_targeting_cancellation}
	if bard_daggers:
		result["bardDaggers"] = true
	return result


func copy() -> AdventureRules:
	var result := AdventureRules.new()
	result.free_targeting_cancellation = free_targeting_cancellation
	result.bard_daggers = bard_daggers
	return result


static func from_data(data: Variant) -> AdventureRules:
	if not data is Dictionary:
		return null
	var record: Dictionary = data
	if record.size() != (2 if record.has("bardDaggers") else 1) or not record.get("freeTargetingCancellation") is bool or not record.get("bardDaggers", false) is bool:
		return null
	var result := AdventureRules.new()
	result.free_targeting_cancellation = record["freeTargetingCancellation"]
	result.bard_daggers = record.get("bardDaggers", false)
	return result
