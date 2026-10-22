## Executes Castle's clock edit, zero-time refresh and resumable timer calls.
class_name ClassicTimeOperations
extends ClassicOpcodeHandler

var _content: RealmzContent
var _state: GameState
var _rng: RealmzRng
var _rules: RealmzRules
var _runtime_ref: WeakRef
var _timer_call_depth: int = 0
const TIMER_CALL_LIMIT: int = 32


func _init(content: RealmzContent, state: GameState, rng: RealmzRng, rules: RealmzRules) -> void:
	_content = content
	_state = state
	_rng = rng
	_rules = rules


func bind_runtime_api(runtime: RealmzRuntimeApi) -> void:
	_runtime_ref = weakref(runtime)


func opcode_ids() -> Array[int]:
	return [63]


func execute(action: ClassicActionDefinition, request_id: String, _context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() != 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 63 requires all five Extra Code words.")
	var events := _rules.clock.alter_classic_time(_state, _content, action.extra_code[0], action.extra_code[1], action.extra_code[2], action.extra_code[3])
	var body := ScenarioClockContinuationBody.new()
	body.resume_slot = action.slot + 1
	body.updates.assign(CharacterAgingResult.update_bodies(events))
	body.scan_pending = events[0].kind == &"game_time_changed" and events[0].payload["timerScan"]
	return _continue_refresh(body, events, request_id)


func resume(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := continuation.body as ScenarioClockContinuationBody
	if body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_clock_continuation", "The clock refresh has no saved scan.")
	if body.timer_vm != null:
		var vm := ScenarioVm.new()
		vm.configure(_content.scenario)
		if not vm.restore(body.timer_vm):
			return ScenarioRuntimeOperationResult.failed(&"invalid_clock_continuation", "The clock refresh cannot restore its timed program.")
		if _timer_call_depth >= TIMER_CALL_LIMIT:
			return ScenarioRuntimeOperationResult.failed(&"clock_timer_depth", "Nested timed programs exceeded the engine safety bound.")
		_timer_call_depth += 1
		var result := vm.resume(response, _runtime_ref.get_ref())
		_timer_call_depth -= 1
		return _after_timer(body, vm, result, request_id)
	if body.age_index < 1:
		return ScenarioRuntimeOperationResult.failed(&"invalid_clock_continuation", "The clock refresh has no pending age acknowledgement.")
	if response.kind != InteractionRequest.AGE_UPDATE or not response.body is InteractionResponse.EmptyBody:
		return ScenarioRuntimeOperationResult.rejected(&"invalid_interaction_response", "The clock refresh requires an age acknowledgement.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"character_age_update_acknowledged", {"characterId": body.updates[body.age_index - 1].character_id})]
	return _continue_refresh(body, events, request_id)


func complete_handoff(handoff: ScenarioRuntimeHandoff) -> ScenarioRuntimeOperationResult:
	# FD-SCENARIO-026 retains the coherent typed caller after Party Death revival.
	var body := handoff.clock_continuation.body as ScenarioClockContinuationBody
	var vm := ScenarioVm.new()
	vm.configure(_content.scenario)
	if body == null or not vm.restore(body.timer_vm):
		return ScenarioRuntimeOperationResult.failed(&"invalid_clock_handoff", "The suspended timed program cannot be restored.")
	if _timer_call_depth >= TIMER_CALL_LIMIT:
		return ScenarioRuntimeOperationResult.failed(&"clock_timer_depth", "Nested timed programs exceeded the engine safety bound.")
	_timer_call_depth += 1
	var operation: ScenarioRuntimeOperationResult = _runtime_ref.get_ref().complete_party_defeat_handoff(handoff.nested_handoff.runtime)
	var result := operation if operation.state == ScenarioRuntimeOperationResult.State.FAILED else _after_timer(body, vm, vm.resume_handoff(handoff.nested_handoff, operation, _runtime_ref.get_ref()), "clock.handoff")
	_timer_call_depth -= 1
	return result


static func handoff_is_valid(content: RealmzContent, state: GameState, handoff: ScenarioRuntimeHandoff) -> bool:
	if handoff.clock_continuation == null or handoff.nested_handoff == null: return false
	var body := handoff.clock_continuation.body as ScenarioClockContinuationBody
	var encounters := content.scenario_records.timed_encounters()
	if body == null or body.timer_vm == null or body.timer_index < 1 or body.timer_index > encounters.size() or encounters[body.timer_index - 1].program_id != body.program_id: return false
	var vm := ScenarioVm.new()
	vm.configure(content.scenario)
	return vm.restore(body.timer_vm) and ScenarioVmHandoff.is_valid(handoff.nested_handoff, body.timer_vm) and RealmzRuntimeApi.party_defeat_handoff_is_valid(content, state, handoff.nested_handoff.runtime)


func _continue_refresh(body: ScenarioClockContinuationBody, events: Array[DomainEvent], request_id: String) -> ScenarioRuntimeOperationResult:
	if body.age_index < body.updates.size():
		var update := body.updates[body.age_index]
		body.age_index += 1
		events.append(CharacterAgingResult.sound_event_for_update(update))
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update_body(request_id, update), body.as_continuation(), events)
	var encounters := _content.scenario_records.timed_encounters()
	while body.scan_pending and body.timer_index < encounters.size():
		var encounter := encounters[body.timer_index]
		body.timer_index += 1
		var map := _content.world.map_by_id(_state.party.map_id)
		if map == null:
			return ScenarioRuntimeOperationResult.failed(&"invalid_clock_location", "The timed scan references an unavailable current map.")
		var checked := ClassicTimedEncounterRules.check(encounter, _content, _state, _rng, map, _state.party.coordinate, _state.clock.day())
		events.append_array(checked.events)
		if checked.stop_scan: break
		if not checked.eligible: continue
		if _content.scenario.program_by_id(encounter.program_id) == null:
			if _content.scenario.native_xap_is_unavailable(encounter.classic_macro_id):
				events.append(DomainEvent.new(&"classic_reference_skipped", {"operation": "timed-macro", "nativePath": "Data ED3", "nativeId": encounter.classic_macro_id, "encounterId": encounter.id}))
				continue
			return ScenarioRuntimeOperationResult.failed(&"unknown_timed_encounter_program", "A defined timed program is missing from the package.")
		body.program_id = encounter.program_id
		var context := ScenarioExecutionContext.trigger(&"action", "", map.id, _state.party.coordinate, true).set_timed_encounter(encounter.id)
		var vm := ScenarioVm.new()
		vm.configure(_content.scenario)
		var started := vm.start_program(body.program_id, context)
		if started.state == ScenarioVmResult.State.FAILED:
			return ScenarioRuntimeOperationResult.failed(started.error_code, started.error_message, started.events)
		events.append(DomainEvent.new(&"timed_encounter_triggered", {"encounterId": encounter.id, "classicMacroId": encounter.classic_macro_id, "programId": encounter.program_id}))
		if _timer_call_depth >= TIMER_CALL_LIMIT:
			return ScenarioRuntimeOperationResult.failed(&"clock_timer_depth", "Nested timed programs exceeded the engine safety bound.")
		_timer_call_depth += 1
		var result := vm.run(_runtime_ref.get_ref())
		_timer_call_depth -= 1
		result.events = events + result.events
		return _after_timer(body, vm, result, request_id)
	body.scan_pending = false
	var directive: ScenarioVmDirective
	if not body.return_program_id.is_empty():
		var program := _content.scenario.program_by_id(body.return_program_id)
		if program == null:
			return ScenarioRuntimeOperationResult.failed(&"invalid_clock_return", "The last timed program is unavailable.")
		var cursor := 0
		while cursor < program.instruction_count():
			var instruction: Variant = program.instruction_at(cursor)
			if not instruction is ClassicActionDefinition or instruction.slot >= body.resume_slot: break
			cursor += 1
		directive = ScenarioVmDirective.clock_timer_return(program.id, cursor)
	return ScenarioRuntimeOperationResult.completed(_state.clock.total_minutes(), events, directive)


func _after_timer(body: ScenarioClockContinuationBody, vm: ScenarioVm, result: ScenarioVmResult, request_id: String) -> ScenarioRuntimeOperationResult:
	if result.is_rejection:
		return ScenarioRuntimeOperationResult.rejected(result.error_code, result.error_message)
	if result.state == ScenarioVmResult.State.FAILED:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message, result.events)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		body.timer_vm = vm.snapshot()
		return ScenarioRuntimeOperationResult.suspended(ScenarioRuntimeHandoff.clock_timer(body.as_continuation(), result.handoff), result.events)
	if result.state == ScenarioVmResult.State.WAITING:
		body.timer_vm = vm.snapshot()
		return ScenarioRuntimeOperationResult.waiting(result.interaction, body.as_continuation(), result.events)
	body.timer_vm = null
	body.return_program_id = vm.classic_record_id()
	body.program_id = ""
	return _continue_refresh(body, result.events, request_id)

