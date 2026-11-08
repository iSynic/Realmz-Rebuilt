## Explicit adventure-owned departures from the default Classic rules.
class_name AdventureRules
extends RefCounted

const MAXIMUM_MONEY_TRANSFER_SPEED := 5

var free_targeting_cancellation: bool = false
## FD-INVENTORY-007: the stock Bard may use the dagger item category.
var bard_daggers: bool = false
## FD-ECONOMY-005: whole Classic Swap increments moved per transfer step, 1 (Classic) through 5.
var money_transfer_speed: int = 1


## Optional rules are written only when they depart from Classic, so saves without them stay readable by builds that predate them.
func to_data() -> Dictionary:
	var result := {"freeTargetingCancellation": free_targeting_cancellation}
	if bard_daggers:
		result["bardDaggers"] = true
	if money_transfer_speed != 1:
		result["moneyTransferSpeed"] = money_transfer_speed
	return result


func copy() -> AdventureRules:
	var result := AdventureRules.new()
	result.free_targeting_cancellation = free_targeting_cancellation
	result.bard_daggers = bard_daggers
	result.money_transfer_speed = money_transfer_speed
	return result


static func from_data(data: Variant) -> AdventureRules:
	if not data is Dictionary:
		return null
	var record: Dictionary = data
	var expected_size := 1 + int(record.has("bardDaggers")) + int(record.has("moneyTransferSpeed"))
	if record.size() != expected_size or not record.get("freeTargetingCancellation") is bool or not record.get("bardDaggers", false) is bool:
		return null
	var speed := _optional_speed(record.get("moneyTransferSpeed", 1))
	if speed < 1 or record.has("moneyTransferSpeed") and speed == 1:
		return null
	var result := AdventureRules.new()
	result.free_targeting_cancellation = record["freeTargetingCancellation"]
	result.bard_daggers = record.get("bardDaggers", false)
	result.money_transfer_speed = speed
	return result


static func _optional_speed(value: Variant) -> int:
	var number := -1
	if value is int:
		number = value
	elif value is float:
		var real: float = value
		number = roundi(real) if is_equal_approx(real, roundf(real)) else -1
	return number if number >= 1 and number <= MAXIMUM_MONEY_TRANSFER_SPEED else -1
