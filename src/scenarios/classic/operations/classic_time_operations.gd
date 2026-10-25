## Applies Castle clock edits and returns typed age/scan work to the one runner.
class_name ClassicTimeOperations
extends ClassicOpcodeHandler

var _content: RealmzContent
var _state: GameState
var _rng: RealmzRng
var _rules: RealmzRules


func _init(content: RealmzContent, state: GameState, rng: RealmzRng, rules: RealmzRules) -> void:
	_content = content
	_state = state
	_rng = rng
	_rules = rules


func opcode_ids() -> Array[int]:
	return [63]


func execute(action: ClassicActionDefinition, request_id: String, _context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() != 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 63 requires all five Extra Code words.")
	var changed := _rules.clock.alter_classic_time(_state, _content, action.extra_code[0], action.extra_code[1], action.extra_code[2], action.extra_code[3])
	var scan := ScenarioClockScanBody.new()
	scan.updates.assign(changed.age_updates)
	scan.scan_pending = changed.scan_timers
	return _continue_refresh(scan, changed.events, request_id)


func resume(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var scan := continuation.body as ScenarioClockScanBody
	if scan == null:
		return ScenarioRuntimeOperationResult.failed(&"legacy_execution_requires_restore", "Historical clock execution must be converted before resuming.")
	if scan.age_index < 1 or scan.age_index > scan.updates.size():
		return ScenarioRuntimeOperationResult.failed(&"invalid_clock_continuation", "The clock refresh has no pending age acknowledgement.")
	if response.kind != InteractionRequest.AGE_UPDATE or not response.body is InteractionResponse.EmptyBody:
		return ScenarioRuntimeOperationResult.rejected(&"invalid_interaction_response", "The clock refresh requires an age acknowledgement.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"character_age_update_acknowledged", {"characterId": scan.updates[scan.age_index - 1].character_id})]
	return _continue_refresh(scan, events, request_id)


func complete_timer(scan: ScenarioClockScanBody, request_id: String) -> ScenarioRuntimeOperationResult:
	return _continue_refresh(scan, [], request_id)


func _continue_refresh(scan: ScenarioClockScanBody, events: Array[DomainEvent], request_id: String) -> ScenarioRuntimeOperationResult:
	if scan.age_index < scan.updates.size():
		var update := scan.updates[scan.age_index]
		scan.age_index += 1
		events.append(CharacterAgingResult.sound_event_for_update(update))
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update_body(request_id, update), scan.as_continuation(), events)
	var encounters := _content.scenario_records.timed_encounters()
	while scan.scan_pending and scan.timer_index < encounters.size():
		var encounter := encounters[scan.timer_index]
		scan.timer_index += 1
		var map := _content.world.map_by_id(_state.party.map_id)
		if map == null:
			return ScenarioRuntimeOperationResult.failed(&"invalid_clock_location", "The timed scan references an unavailable current map.")
		var checked := ClassicTimedEncounterRules.check(encounter, _content, _state, _rng, map, _state.party.coordinate, _state.clock.day())
		events.append_array(checked.events)
		if checked.stop_scan: break
		if not checked.eligible: continue
		if _content.scenario.program_by_id(encounter.program_id) == null:
			if not _content.scenario.native_xap_is_unavailable(encounter.classic_macro_id):
				return ScenarioRuntimeOperationResult.failed(&"unknown_timed_encounter_program", "A defined timed program is missing from the package.")
			events.append(DomainEvent.new(&"classic_reference_skipped", {"operation": "timed-macro", "nativePath": "Data ED3", "nativeId": encounter.classic_macro_id, "encounterId": encounter.id}))
		var context := ScenarioExecutionContext.trigger(&"action", "", map.id, _state.party.coordinate, true).set_timed_encounter(encounter.id)
		events.append(DomainEvent.new(&"timed_encounter_triggered", {"encounterId": encounter.id, "classicMacroId": encounter.classic_macro_id, "programId": encounter.program_id}))
		return ScenarioRuntimeOperationResult.calling(ScenarioProgramCall.timer_call(scan, encounter.program_id, context), events)
	scan.scan_pending = false
	return ScenarioRuntimeOperationResult.completed(_state.clock.total_minutes(), events)
