## Creates typed commands for battle actions, movement, and persistent Party Auto.

class_name CombatIntents
extends RefCounted


static func choose_action(action: StringName, actor_id: String, target_id: String = "") -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CHOOSE_COMBAT_ACTION, CombatIntentPayloads.Action.new(action, actor_id, target_id))


static func move(actor_id: String, destination: Vector2i, auto_switch_to_melee: bool = false) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.COMBAT_MOVE, CombatIntentPayloads.Move.new(actor_id, destination, auto_switch_to_melee))


static func set_auto(character_id: String, enabled: bool) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.SET_COMBAT_AUTO, CombatIntentPayloads.Auto.new(character_id, enabled))
