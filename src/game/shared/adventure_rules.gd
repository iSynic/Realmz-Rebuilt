## Explicit adventure-owned departures from the default Classic rules.
class_name AdventureRules
extends RefCounted

const MAXIMUM_MONEY_TRANSFER_SPEED := 5
## Classic leaves monster reinforcements unlimited.
const UNLIMITED_REINFORCEMENTS := -1
## Choices offered for Limit Monster Reinforcements, in reinforcement waves per battle.
const REINFORCEMENT_LIMITS: Array[int] = [UNLIMITED_REINFORCEMENTS, 0, 1, 2, 3, 5]

var free_targeting_cancellation: bool = false
## FD-INVENTORY-007: the stock Bard may use the dagger item category.
var bard_daggers: bool = false
## FD-ECONOMY-005: whole Classic Swap increments moved per transfer step, 1 (Classic) through 5.
var money_transfer_speed: int = 1
## Limit Monster Reinforcements: how many times a battle's round script may bring in monsters.
## UNLIMITED_REINFORCEMENTS (Classic) or 0 (none) through 5.
var reinforcement_limit: int = UNLIMITED_REINFORCEMENTS


## Optional rules are written only when they depart from Classic, so saves without them stay readable by builds that predate them.
func to_data() -> Dictionary:
	var result := {"freeTargetingCancellation": free_targeting_cancellation}
	if bard_daggers:
		result["bardDaggers"] = true
	if money_transfer_speed != 1:
		result["moneyTransferSpeed"] = money_transfer_speed
	if reinforcement_limit != UNLIMITED_REINFORCEMENTS:
		result["reinforcementLimit"] = reinforcement_limit
	return result


func copy() -> AdventureRules:
	var result := AdventureRules.new()
	result.free_targeting_cancellation = free_targeting_cancellation
	result.bard_daggers = bard_daggers
	result.money_transfer_speed = money_transfer_speed
	result.reinforcement_limit = reinforcement_limit
	return result


static func from_data(data: Variant) -> AdventureRules:
	if not data is Dictionary:
		return null
	var record: Dictionary = data
	var expected_size := 1 + int(record.has("bardDaggers")) + int(record.has("moneyTransferSpeed")) + int(record.has("reinforcementLimit"))
	if record.size() != expected_size or not record.get("freeTargetingCancellation") is bool or not record.get("bardDaggers", false) is bool:
		return null
	var speed := _optional_speed(record.get("moneyTransferSpeed", 1))
	if speed < 1 or record.has("moneyTransferSpeed") and speed == 1:
		return null
	var limit := _optional_limit(record.get("reinforcementLimit", UNLIMITED_REINFORCEMENTS))
	if limit < UNLIMITED_REINFORCEMENTS or record.has("reinforcementLimit") and limit == UNLIMITED_REINFORCEMENTS:
		return null
	var result := AdventureRules.new()
	result.free_targeting_cancellation = record["freeTargetingCancellation"]
	result.bard_daggers = record.get("bardDaggers", false)
	result.money_transfer_speed = speed
	result.reinforcement_limit = limit
	return result


static func _optional_speed(value: Variant) -> int:
	var number := -1
	if value is int:
		number = value
	elif value is float:
		var real: float = value
		number = roundi(real) if is_equal_approx(real, roundf(real)) else -1
	return number if number >= 1 and number <= MAXIMUM_MONEY_TRANSFER_SPEED else -1

## One of REINFORCEMENT_LIMITS as a whole JSON number, or -2 when the value is not one.
static func _optional_limit(value: Variant) -> int:
	var number := -2
	if value is int:
		number = value
	elif value is float:
		var real: float = value
		number = roundi(real) if is_equal_approx(real, roundf(real)) else -2
	return number if REINFORCEMENT_LIMITS.has(number) else -2
