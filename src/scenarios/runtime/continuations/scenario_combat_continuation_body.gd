## Carries scenario-owned battle, retreat, age, macro, and terminal progress.

class_name ScenarioCombatContinuationBody
extends ScenarioRuntimeContinuationBody

var source_kind: StringName
var battle_id: String
var caller: ScenarioBattleCaller
var actor_id: String
var mode: StringName
var destination: Vector2i
var updates: Array[AgeUpdateRequestBody]
var index: int
var round_before: int
var program_id: String
var macro_vm: ScenarioVmSnapshot
var combatant_id: String
var reset_traitor_on_complete: bool = true


func wire_payload() -> Dictionary:
	var data := {"sourceKind": String(source_kind), "battleId": battle_id, "battleCaller": caller.to_data()}
	if not actor_id.is_empty():
		data["actorId"] = actor_id
		data["mode"] = String(mode)
		data["destination"] = [destination.x, destination.y]
	elif not updates.is_empty():
		var serialized: Array[Dictionary] = []
		for update: AgeUpdateRequestBody in updates:
			serialized.append(update.to_data())
		data["updates"] = serialized
		data["index"] = index
		data["roundBefore"] = round_before
	elif macro_vm != null:
		data["programId"] = program_id
		data["macroVm"] = macro_vm.to_data()
		if not combatant_id.is_empty():
			data["combatantId"] = combatant_id
			data["resetTraitorOnComplete"] = reset_traitor_on_complete
	return data
