## Carries one battle identity, command handoff, or death-macro handoff.

class_name CombatContinuationBody
extends SessionContinuationBody

var battle_id: String
var actor_id: String
var mode: StringName
var destination: Vector2i
var combatant_id: String
var program_id: String
var reset_traitor_on_complete: bool = true


func wire_payload(kind: StringName) -> Dictionary:
	if kind in [&"combat-retreat-confirmation", &"combat-friendly-collision"]:
		return {"kind": String(kind), "battleId": battle_id, "actorId": actor_id, "mode": String(mode), "destination": [destination.x, destination.y]}
	if kind == &"combat-death-macro":
		return {"kind": String(kind), "battleId": battle_id, "combatantId": combatant_id, "programId": program_id, "resetTraitorOnComplete": reset_traitor_on_complete}
	return {"kind": String(kind), "battleId": battle_id}
