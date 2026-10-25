## Converts historical macro snapshots to explicit calls without replaying entry.
class_name ScenarioLegacyMacroCodec
extends RefCounted


static func normalize(state: ScenarioExecutionState, definition: ScenarioDefinition, depth: int) -> ScenarioExecutionState:
	var owner: ScenarioExecutionRecord = state.records.back()
	var operation := owner.operation
	var combat := operation.continuation.combat()
	if combat != null and not prepare_battle_owner(state, operation, combat, definition): return null
	var destruction := operation.continuation.opcode_death()
	var saved := combat.macro_vm if combat != null else destruction.macro_vm if destruction != null else null
	if saved == null: return state
	var call := ScenarioMacroCall.new()
	if combat != null:
		call.battle_id = combat.battle_id
		call.program_id = combat.program_id
		call.caller = combat.caller.copy()
		call.return_kind = ScenarioMacroCall.ReturnKind.SAFE if operation.return_kind == ScenarioOperationExecutionRecord.ReturnKind.SAFE else ScenarioMacroCall.ReturnKind.CLASSIC
		call.combatant_id = combat.combatant_id
		call.reset_traitor_on_complete = combat.reset_traitor_on_complete
	else:
		call.battle_id = destruction.battle_id
		call.program_id = destruction.program_id
		call.combatant_id = destruction.combatant_id
		call.remaining_combatant_ids.assign(destruction.remaining_combatant_ids)
		call.return_kind = ScenarioMacroCall.ReturnKind.DESTRUCTION
	call.kind = ScenarioMacroCall.Kind.ROUND if call.combatant_id.is_empty() else ScenarioMacroCall.Kind.DEATH
	var child := ScenarioLegacyExecutionCodec.convert(saved, definition, depth + 1)
	if child == null or child.pending_request == null or child.pending_request.to_data() != state.pending_request.to_data(): return null
	return state if attach(state, child, call) else null


static func prepare_battle_owner(state: ScenarioExecutionState, operation: ScenarioOperationExecutionRecord, body: ScenarioCombatContinuationBody, definition: ScenarioDefinition) -> bool:
	if operation.return_kind == ScenarioOperationExecutionRecord.ReturnKind.SAFE:
		if body.caller.kind != ScenarioBattleCaller.SAFE: return false
		operation.restore_code = state.classic.code.copy() if state.classic.code != null else null
		return true
	if body.caller.kind != ScenarioBattleCaller.CLASSIC or operation.instruction_cursor < 0: return false
	var program := definition.program_by_id(operation.instruction_program_id)
	if program == null: return false
	var instruction: Variant = program.instruction_at(operation.instruction_cursor)
	if not instruction is ClassicActionDefinition: return false
	var action: ClassicActionDefinition = instruction
	if action.opcode != body.caller.opcode: return false
	if action.opcode == 48:
		operation.restore_encounter_flag = ScenarioClassicExecutionState.ENCOUNTER_KINDS.find(state.classic.encounter_kind)
	else:
		if action.opcode not in [2, 56, 107] or state.classic.code == null: return false
		operation.restore_code = state.classic.code.copy()
	return true


static func attach(state: ScenarioExecutionState, child: ScenarioExecutionState, call: ScenarioMacroCall) -> bool:
	if child.records.is_empty() or child.records[0].kind != ScenarioExecutionRecord.Kind.CLASSIC: return false
	var entry := child.records[0].classic
	var context := entry.context
	if context.battle_id != call.battle_id or context.combatant_id != call.combatant_id or context.calling_context != (&"battle-macro" if call.kind == ScenarioMacroCall.Kind.ROUND else &"monster-death-macro"): return false
	if not context.original_program_id.is_empty() and context.original_program_id != call.program_id: return false
	call.classic_monster_id = context.classic_monster_id
	call.has_classic_monster_id = context.has_classic_monster_id
	call.traitor = context.traitor
	call.has_traitor = context.has_traitor
	if call.kind == ScenarioMacroCall.Kind.DEATH and not call.reset_traitor_on_complete: call.queued_source = CombatQueuedMacroSource.new()
	if not call.is_valid(): return false
	entry.mode = ScenarioClassicInvocationRecord.Mode.MACRO
	entry.entry_program_id = call.program_id
	entry.context = call.entry_context()
	entry.placed_trigger_id = ""
	entry.queued_source = call.queued_source.copy() if call.queued_source != null else null
	var owner: ScenarioExecutionRecord = state.records.back()
	owner.operation.phase = ScenarioOperationExecutionRecord.Phase.CHILD
	owner.operation.continuation = null
	owner.operation.handoff = null
	owner.operation.child_call = ScenarioProgramCall.macro_call(call)
	if call.kind == ScenarioMacroCall.Kind.DEATH:
		owner.operation.child_restore_code = state.classic.code.copy() if state.classic.code != null else ScenarioClassicProgramState.new("", null, ScenarioClassicProgramState.Kind.UNAVAILABLE)
	child.classic.battle_macro_active = child.classic.battle_macro_active or state.classic.battle_macro_active or call.kind == ScenarioMacroCall.Kind.ROUND
	return ScenarioLegacyCallCodec.append_child(state, child)
