class_name MoneyTransferView
extends RefCounted

var denomination: StringName
var amount: int
var to_pool: ActionAvailabilityView
var to_character: ActionAvailabilityView


func _init(kind: StringName, increment: int, pool_action: ActionAvailabilityView, character_action: ActionAvailabilityView) -> void:
	denomination = kind
	amount = increment
	to_pool = pool_action
	to_character = character_action
