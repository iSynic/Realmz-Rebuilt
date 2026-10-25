## Converts historical VM state using only recorded owners and bound package facts.
class_name SessionLegacyExecutionRestoreRules
extends RefCounted


static func normalize(content: RealmzContent, saved: SessionSnapshot, state: GameState) -> ScenarioVmSnapshot:
	if saved.scenario_vm.execution != null: return saved.scenario_vm
	var execution := ScenarioLegacyExecutionCodec.convert(saved.scenario_vm, content.scenario)
	if execution == null: return null
	execution.classic.header = saved.classic_execution.copy()
	if not restore_encounter(content, state, execution) or not restore_loaded_records(content, saved.game_state, state) or not restore_macro_source(state, execution): return null
	var result := ScenarioVmSnapshot.new()
	result.set_execution(execution)
	return result


static func restore_loaded_records(content: RealmzContent, saved: GameState, state: GameState) -> bool:
	var source := saved.scenario_progress.encounters
	var memory := ClassicEncounterMemoryOperations.new(content, state.scenario_progress.encounters)
	for kind: StringName in [&"simple", &"complex"]:
		var id := source.classic_loaded_simple_id if kind == &"simple" else source.classic_loaded_complex_id
		if id >= 0 and not memory.load_record(kind, id, false): return false
	return state.scenario_progress.encounters.memory.is_bound_to(content)


static func restore_encounter(content: RealmzContent, state: GameState, execution: ScenarioExecutionState) -> bool:
	if execution.records.is_empty(): return true
	var shared := execution.classic
	var kind := shared.encounter_kind
	var id := shared.encounter_id
	var attempt := shared.encounter_attempt
	var pending_choice := false
	var reopen := false
	var last: ScenarioExecutionRecord = execution.records.back()
	var runtime := last.operation.continuation if last.kind == ScenarioExecutionRecord.Kind.OPERATION else null
	var choice := runtime.body as ScenarioChoiceContinuationBody if runtime != null else null
	if runtime != null and runtime.kind in [ScenarioRuntimeContinuation.CLASSIC_SIMPLE_ENCOUNTER, ScenarioRuntimeContinuation.CLASSIC_COMPLEX_ENCOUNTER]:
		if choice == null: return false
		kind = &"simple" if runtime.kind == ScenarioRuntimeContinuation.CLASSIC_SIMPLE_ENCOUNTER else &"complex"
		id = choice.encounter_id
		attempt = choice.encounter_attempt
		pending_choice = true
		reopen = choice.reopen_result
	elif runtime != null and runtime.kind in [ScenarioRuntimeContinuation.CLASSIC_THIEF_ENCOUNTER, ScenarioRuntimeContinuation.CLASSIC_PICK_LOCK, ScenarioRuntimeContinuation.CLASSIC_THIEF_RESOLUTION]:
		var thief := runtime.body as ScenarioThiefContinuationBody
		if thief == null: return false
		kind = &"complex"
		id = thief.encounter_id
		attempt = thief.encounter_attempt
		pending_choice = true
	if kind.is_empty(): return true
	var simple := content.scenario_records.simple_encounter_by_id(id) if kind == &"simple" else null
	var complex := content.scenario_records.complex_encounter_by_id(id) if kind == &"complex" else null
	if simple == null and complex == null: return false
	var maximum := simple.max_times if simple != null else complex.max_times
	var remaining := maximum - attempt + (0 if pending_choice and not reopen else 1)
	if remaining < -32768 or remaining > 32767: return false
	# The legacy owner names the record used by its old lookup-based runtime.
	# Unrelated historical buffers remain unavailable; no instruction is replayed.
	var memory := ClassicEncounterMemoryOperations.new(content, state.scenario_progress.encounters)
	if not memory.load_record(kind, id): return false
	if kind == &"simple": memory.prepare_simple_text()
	shared.encounter_kind = kind
	shared.encounter_id = id
	shared.encounter_attempt = attempt
	shared.encounter_remaining = remaining
	var owner_id := native_owner_id(execution, last)
	for record: ScenarioExecutionRecord in execution.records:
		if record.kind != ScenarioExecutionRecord.Kind.CLASSIC or record.id != owner_id: continue
		record.classic.encounter_reload = false
		record.classic.encounter_save_id = id
		if pending_choice and record.id == last.parent_id:
			capture_pending_exit(content.scenario, shared, record.classic, last.operation)
	return state.scenario_progress.encounters.memory.is_bound_to(content)


static func capture_pending_exit(definition: ScenarioDefinition, shared: ScenarioClassicExecutionState, entry: ScenarioClassicInvocationRecord, owner: ScenarioOperationExecutionRecord) -> void:
	if entry.encounter_exit != null or owner.instruction_cursor < 0: return
	var program := definition.program_by_id(owner.instruction_program_id)
	if program == null: return
	var instruction: Variant = program.instruction_at(owner.instruction_cursor)
	if not instruction is ClassicActionDefinition: return
	var action: ClassicActionDefinition = instruction
	if action.opcode not in [4, 5] or shared.code == null: return
	entry.encounter_exit = ScenarioClassicExecutionRules.capture(shared, entry)
	if entry.encounter_exit.destination == null: entry.encounter_exit.destination_state = ScenarioClassicReturnRecord.DestinationState.UNAVAILABLE


static func native_owner_id(execution: ScenarioExecutionState, last: ScenarioExecutionRecord) -> int:
	if last.kind == ScenarioExecutionRecord.Kind.CLASSIC: return last.id
	if last.kind == ScenarioExecutionRecord.Kind.SAFE: return last.safe.invocation_owner_id
	if last.operation.return_kind == ScenarioOperationExecutionRecord.ReturnKind.CLASSIC: return last.parent_id
	if last.operation.return_kind == ScenarioOperationExecutionRecord.ReturnKind.SAFE:
		for record: ScenarioExecutionRecord in execution.records:
			if record.id == last.parent_id and record.kind == ScenarioExecutionRecord.Kind.SAFE: return record.safe.invocation_owner_id
	return 0


static func restore_macro_source(state: GameState, execution: ScenarioExecutionState) -> bool:
	if state.combat == null: return true
	var monsters := state.combat.roster.monsters()
	for record: ScenarioExecutionRecord in execution.records:
		if record.kind != ScenarioExecutionRecord.Kind.CLASSIC or record.classic.mode != ScenarioClassicInvocationRecord.Mode.MACRO: continue
		var entry := record.classic
		if entry.context.calling_context != &"monster-death-macro" or entry.context.combatant_id.is_empty(): continue
		var subject := state.combat.roster.monster_by_id(entry.context.combatant_id)
		if subject == null: return false
		var index := monsters.find(subject)
		# killbody assigns an immediate subject and nonzero queued slot at entry.
		# A queued slot zero preserves the enclosing value, which may be unavailable.
		if entry.queued_source == null or index != 0: execution.classic.macro_monster_index = index
	return true
