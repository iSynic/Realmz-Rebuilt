## Defines the typed values carried by Party Wealth and location-service intents.

class_name EconomyIntentPayloads
extends RefCounted


class Money:
	extends PlayerIntentPayload
	var action: StringName
	var character_id: String
	var denomination: String
	var amount: int

	func _init(action_value: StringName, character: String, denomination_value: String, amount_value: int) -> void:
		action = action_value
		character_id = character
		denomination = denomination_value
		amount = maxi(0, amount_value)


class Service:
	extends PlayerIntentPayload
	var service_id: String
	var action: StringName
	var actor_id: String
	var amount: int

	func _init(service: String, action_value: StringName, actor: String, amount_value: int) -> void:
		service_id = service
		action = action_value
		actor_id = actor
		amount = maxi(0, amount_value)
