class_name CombatMoveOptionView
extends RefCounted

var direction: Vector2i
var destination: Vector2i
var movement_cost: int
var enabled: bool
var reason: StringName
var reason_text: String


func _init(move_direction: Vector2i, result: BattlefieldStepResult) -> void:
	direction = move_direction
	destination = result.destination
	movement_cost = result.movement_cost
	enabled = result.allowed
	reason = result.reason
	reason_text = _reason_text(result)


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
		&"withdrawal_attack_unavailable":
			return "The step would leave an adjacent enemy; withdrawal attacks are not implemented yet."
		&"guard_reaction_unavailable":
			return "The step could trigger a guarding enemy; guard reactions are not implemented yet."
		_:
			return "Tactical movement is unavailable: %s." % String(result.reason)
