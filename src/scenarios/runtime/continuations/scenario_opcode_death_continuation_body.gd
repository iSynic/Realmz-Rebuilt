## Carries the remaining combatants for a Classic opcode death-macro drain.

class_name ScenarioOpcodeDeathContinuationBody
extends ScenarioRuntimeContinuationBody

var battle_id: String
var combatant_id: String
var program_id: String
var remaining_combatant_ids: Array[String]
var macro_vm: ScenarioVmSnapshot


func wire_payload() -> Dictionary:
	return {"battleId": battle_id, "combatantId": combatant_id, "programId": program_id, "remainingCombatantIds": remaining_combatant_ids.duplicate(), "macroVm": macro_vm.to_data()}
