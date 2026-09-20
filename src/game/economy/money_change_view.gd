## Carries one Castle money-changing rate and its current availability to presentation.
class_name MoneyChangeView
extends RefCounted

var action: StringName
var source: StringName
var source_amount: int
var result: StringName
var result_amount: int
var availability: ActionAvailabilityView


func _init(action_value: StringName, source_value: StringName, cost: int, result_value: StringName, yield_amount: int, action_availability: ActionAvailabilityView) -> void:
	action = action_value
	source = source_value
	source_amount = cost
	result = result_value
	result_amount = yield_amount
	availability = action_availability
