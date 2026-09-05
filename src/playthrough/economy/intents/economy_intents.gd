## Creates typed commands for pooled wealth and contextual services.

class_name EconomyIntents
extends RefCounted


static func money(action: StringName, character_id: String = "", denomination: String = "", amount: int = 0) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.MONEY_ACTION, EconomyIntentPayloads.Money.new(action, character_id, denomination, amount))


static func service(service_id: String, action: StringName, actor_id: String = "", amount: int = 0) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.SERVICE_ACTION, EconomyIntentPayloads.Service.new(service_id, action, actor_id, amount))
