class_name BattleDefinition
extends RefCounted

var id: String
var classic_id: int
var distance: int
var message_before_id: int
var message_after_id: int
var macro_id: int
var _monster_slots: Array[BattleMonsterSlotDefinition]


func _init(definition_id: String, native_id: int, battle_monster_slots: Array[BattleMonsterSlotDefinition], battle_distance: int = 0, before_message: int = 0, after_message: int = 0, battle_macro: int = 0) -> void:
	id = definition_id
	classic_id = native_id
	_monster_slots = battle_monster_slots.duplicate()
	distance = battle_distance
	message_before_id = before_message
	message_after_id = after_message
	macro_id = battle_macro


func monster_slots() -> Array[BattleMonsterSlotDefinition]:
	return _monster_slots.duplicate()
