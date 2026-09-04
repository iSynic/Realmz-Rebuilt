## Defines the typed values carried by active-battle intents.

class_name CombatIntentPayloads
extends RefCounted


class Action:
	extends PlayerIntentPayload
	var action: StringName
	var actor_id: String
	var target_id: String

	func _init(action_value: StringName, actor: String, target: String) -> void:
		action = action_value
		actor_id = actor
		target_id = target


class Move:
	extends PlayerIntentPayload
	var actor_id: String
	var destination: Vector2i
	var auto_switch_to_melee: bool

	func _init(actor: String, value: Vector2i, switch_to_melee: bool = false) -> void:
		actor_id = actor
		destination = value
		auto_switch_to_melee = switch_to_melee


class Auto:
	extends PlayerIntentPayload
	var character_id: String
	var enabled: bool

	func _init(character: String, value: bool) -> void:
		character_id = character
		enabled = value
