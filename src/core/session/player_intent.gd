class_name PlayerIntent
extends RefCounted

enum Kind {
	MOVE,
	SEARCH,
	CAMP,
	USE_ITEM,
	CAST_SPELL,
	CHOOSE_COMBAT_ACTION,
}

var kind: Kind
var direction: Vector2i = Vector2i.ZERO
var target_id: String = ""
var secondary_target_id: String = ""
var actor_id: String = ""
var action: StringName = &""
var power_level: int = 1


func _init(intent_kind: Kind) -> void:
	kind = intent_kind


static func move(move_direction: Vector2i) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.MOVE)
	intent.direction = move_direction
	return intent


static func use_item(item_id: String) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.USE_ITEM)
	intent.target_id = item_id
	return intent


static func camp() -> PlayerIntent:
	return PlayerIntent.new(Kind.CAMP)


static func cast_spell(spell_id: String, caster_id: String = "", target_combatant_id: String = "", power: int = 1) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.CAST_SPELL)
	intent.target_id = spell_id
	intent.actor_id = caster_id
	intent.secondary_target_id = target_combatant_id
	intent.power_level = power
	return intent


static func combat_action(action_kind: StringName, actor: String, target: String = "") -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.CHOOSE_COMBAT_ACTION)
	intent.action = action_kind
	intent.actor_id = actor
	intent.target_id = target
	return intent
