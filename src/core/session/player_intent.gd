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


static func cast_spell(spell_id: String) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.CAST_SPELL)
	intent.target_id = spell_id
	return intent
