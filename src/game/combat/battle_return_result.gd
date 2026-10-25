## Carries the committed battle return independently of presentation history.
class_name BattleReturnResult
extends RefCounted

var battle_id: String
var outcome: StringName


func _init(battle: String, reason: StringName) -> void:
	battle_id = battle
	outcome = reason
