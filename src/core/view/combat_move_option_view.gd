class_name CombatMoveOptionView
extends RefCounted

var direction: Vector2i
var destination: Vector2i
var movement_cost: int
var enabled: bool
var reason: StringName
var reason_text: String
var retreats_from_battle: bool = false
var forced_retreat: bool = false


func _init(move_direction: Vector2i, result: BattlefieldStepResult, is_retreat: bool = false, is_forced_retreat: bool = false) -> void:
	direction = move_direction
	destination = result.destination
	movement_cost = result.movement_cost
	retreats_from_battle = is_retreat
	forced_retreat = is_forced_retreat
	enabled = result.allowed or retreats_from_battle
	reason = &"" if retreats_from_battle else result.reason
	reason_text = "" if retreats_from_battle else _reason_text(result)


static func _reason_text(result: BattlefieldStepResult) -> String:
	match result.reason:
		&"":
			return ""
		&"outside_battlefield":
			return "The destination is outside the battlefield."
		&"occupied":
			return "The destination is occupied."
		&"solid_terrain":
			return "The destination terrain is solid."
		&"insufficient_movement":
			return "The step costs %d movement points." % result.movement_cost
		_:
			return "Tactical movement is unavailable: %s." % String(result.reason)
