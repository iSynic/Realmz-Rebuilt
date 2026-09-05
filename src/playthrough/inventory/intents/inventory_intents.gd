## Creates typed commands for carried-item use, equipment, stacks, drops, and trade.

class_name InventoryIntents
extends RefCounted


static func use(item_id: String, user_id: String = "") -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.USE_ITEM, InventoryIntentPayloads.Use.new(item_id, user_id))


static func use_on_target(item_id: String, user_id: String, target_combatant_id: String = "", target_combatant_ids: Array[String] = [], coordinate: Vector2i = Vector2i(-100_000, -100_000), area_rotation: int = 0, target_coordinates: Array[Vector2i] = []) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.USE_ITEM_ON_TARGET, InventoryIntentPayloads.Target.new(item_id, user_id, target_combatant_id, target_combatant_ids, coordinate, area_rotation, target_coordinates))


static func equip(item_id: String, actor_id: String = "", quantity: int = 1) -> PlayerIntent:
	return _action(PlayerIntent.Kind.EQUIP_ITEM, item_id, actor_id, quantity)


static func unequip(item_id: String, actor_id: String = "", quantity: int = 1) -> PlayerIntent:
	return _action(PlayerIntent.Kind.UNEQUIP_ITEM, item_id, actor_id, quantity)


static func drop(item_id: String, actor_id: String = "", quantity: int = 1) -> PlayerIntent:
	return _action(PlayerIntent.Kind.DROP_ITEM, item_id, actor_id, quantity)


static func split(item_id: String, actor_id: String = "", quantity: int = 1) -> PlayerIntent:
	return _action(PlayerIntent.Kind.SPLIT_ITEM, item_id, actor_id, quantity)


static func join(item_id: String, actor_id: String = "", quantity: int = 1) -> PlayerIntent:
	return _action(PlayerIntent.Kind.JOIN_ITEM, item_id, actor_id, quantity)


static func trade(item_id: String, from_character_id: String, to_character_id: String) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.TRADE_ITEM, InventoryIntentPayloads.Action.new(item_id, from_character_id, 1, to_character_id))


static func _action(kind: PlayerIntent.Kind, item_id: String, actor_id: String, quantity: int = 1) -> PlayerIntent:
	return PlayerIntent.new(kind, InventoryIntentPayloads.Action.new(item_id, actor_id, quantity))
