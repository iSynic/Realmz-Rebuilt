## Coordinates session scenario coordinator responsibilities behind the public session boundary.

class_name SessionScenarioCoordinator
extends RefCounted

var _context: SessionContext


func _init(context: SessionContext) -> void:
	_context = context

func start_application_hook(hook: StringName, resume_kind: StringName, service_id: String, preceding_events: Array[DomainEvent], suspended: ScenarioApplicationContinuationBody = null) -> SessionCoordinatorResult:
	var continuation := ScenarioApplicationHookWorkflow.continuation(_context.content, hook, resume_kind, service_id, suspended)
	if continuation == null:
		return SessionCoordinatorResult.failed(&"invalid_application_hook_resume", "The application hook has an unsupported resume path.", preceding_events)
	_context.session_continuation = continuation
	var body := _context.session_continuation.body as ScenarioApplicationContinuationBody
	var program_id := body.program_id
	if program_id.is_empty():
		return continue_application_hook(preceding_events)
	var call := ScenarioProgramCall.application_call(program_id, ScenarioApplicationHookWorkflow.start_context(hook, service_id))
	var result := _context.scenario_vm.start_program_call(call, _context.runtime_api)
	body.application_owner_id = result.application_owner_id
	if result.state == ScenarioVmResult.State.FAILED and result.application_owner_id == 0:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, preceding_events)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	events.append(DomainEvent.new(&"application_hook_started", {"hook": String(hook), "programId": program_id}))
	events.append_array(result.events)
	if result.party_revived:
		body.party_revived = true
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return SessionCoordinatorResult.failed(&"nested_party_defeat_handoff", "An application hook cannot suspend another total-party defeat.", events)
	if result.state == ScenarioVmResult.State.FAILED:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, events)
	if result.state == ScenarioVmResult.State.WAITING:
		return SessionCoordinatorResult.waiting(result.interaction, events)
	return continue_application_hook(events, result.application_return)


func continue_application_hook(events: Array[DomainEvent], returned: ScenarioApplicationReturn = null) -> SessionCoordinatorResult:
	var body := _context.session_continuation.body as ScenarioApplicationContinuationBody
	if body == null:
		return SessionCoordinatorResult.failed(&"invalid_session_continuation", "Application-hook continuation body is unavailable.", events)
	var hook := body.hook
	var program_id := body.program_id
	var resume_kind := String(body.resume_kind)
	var service_id := body.service_id
	var party_revived := body.party_revived
	var suspended_owner := body.suspended_owner
	if not program_id.is_empty() and (returned == null or returned.owner_id != body.application_owner_id):
		return SessionCoordinatorResult.failed(&"invalid_application_return", "The completed hook does not match its saved operation owner.", events)
	_context.session_continuation.clear()
	if not program_id.is_empty():
		events.append(ScenarioApplicationHookWorkflow.completion_event(body))
	match resume_kind:
		"begin-adventure":
			events.append(DomainEvent.new(&"adventure_begun", {"campaignId": _context.content.campaign_id}))
			return SessionCoordinatorResult.completed(events)
		"service":
			return _context.responses().open_contextual_service(service_id, events)
		"end-adventure":
			return start_application_hook(ScenarioApplicationHooks.PARTY_DEATH, "end-adventure-close", "", events)
		"end-adventure-close":
			if party_revived:
				events.append(DomainEvent.new(&"adventure_end_suppressed", {"reason": "classic-party-death-revival"}))
				return SessionCoordinatorResult.completed(events)
			return SessionCoordinatorResult.closed(events, "end-adventure")
		"party-defeat":
			if not party_revived:
				return SessionCoordinatorResult.closed(events, "party-defeat")
			if _context.state.combat == null or not _context.state.combat.completed or _context.state.combat.outcome != &"defeat":
				return SessionCoordinatorResult.failed(&"invalid_battle_continuation", "Party Death revival lost its completed defeat.", events)
			_context.state.combat.outcome = &"retreated"
			_context.state.last_battle_outcome = &"retreated"
			events.append(DomainEvent.new(&"party_defeat_revived", {"battleId": _context.state.combat.battle_id, "source": "classic-party-death-hook"}))
			return finish_direct_battle_without_rewards(events)
		"scenario-party-defeat":
			if not party_revived:
				return SessionCoordinatorResult.closed(events, "party-defeat")
			return resume_scenario_party_defeat(suspended_owner, returned, events)
	return SessionCoordinatorResult.failed(&"invalid_session_continuation", "Application hook '%s' has invalid resume kind '%s'." % [hook, resume_kind], events)


func begin_scenario_handoff(result: ScenarioVmResult, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	if result == null or result.state != ScenarioVmResult.State.SUSPENDED or result.handoff == null or result.handoff.runtime == null:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(&"invalid_vm_handoff", "The Scenario VM did not provide a typed application handoff.", events)
	if _context.session_continuation.kind not in [&"post-clock", &"post-move", &"item-xap"]:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(&"unsupported_vm_handoff_owner", "Total-party defeat cannot suspend this scenario caller.", events)
	var saved := _context.scenario_vm.snapshot()
	if result.handoff.runtime.source_kind in [ScenarioRuntimeHandoff.CLASSIC_HEALTH, ScenarioRuntimeHandoff.CLASSIC_SPELL] and not _context.state.party.characters().all(func(character: CharacterState) -> bool: return character.current_health <= 0):
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(&"invalid_party_defeat_handoff", "Classic health damage did not defeat the complete party.", events)
	if not ScenarioVmHandoff.is_valid(result.handoff, saved) or not RealmzRuntimeApi.party_defeat_handoff_is_valid(_context.content, _context.state, result.handoff.runtime):
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(&"invalid_party_defeat_handoff", "The Scenario VM total-party defeat handoff is invalid.", events)
	var suspended := ScenarioApplicationContinuationBody.new()
	suspended.suspended_owner = _context.session_continuation.copy()
	return start_application_hook(ScenarioApplicationHooks.PARTY_DEATH, &"scenario-party-defeat", "", events, suspended)


func resume_scenario_party_defeat(suspended_owner: SessionContinuation, returned: ScenarioApplicationReturn, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var saved := _context.scenario_vm.snapshot()
	var vm_handoff := returned.handoff if returned != null else null
	if not ScenarioVmHandoff.is_valid(vm_handoff, saved) or not RealmzRuntimeApi.party_defeat_handoff_is_valid(_context.content, _context.state, vm_handoff.runtime) or not SessionRestoreValidator.suspended_scenario_owner_is_valid(_context.content, _context.state, suspended_owner, saved):
		return SessionCoordinatorResult.failed(&"invalid_party_defeat_handoff", "The suspended scenario defeat continuation is invalid.", events)
	var operation := _context.runtime_api.complete_party_defeat_handoff(vm_handoff.runtime)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return SessionCoordinatorResult.failed(operation.error_code, operation.error_message, events)
	var resumed := _context.scenario_vm.resume_handoff(vm_handoff, operation, _context.runtime_api)
	events.append_array(resumed.events)
	_context.set_continuation(suspended_owner.copy())
	if resumed.state == ScenarioVmResult.State.SUSPENDED:
		return begin_scenario_handoff(resumed, events)
	if resumed.state == ScenarioVmResult.State.WAITING:
		return SessionCoordinatorResult.waiting(resumed.interaction, events)
	if resumed.state == ScenarioVmResult.State.FAILED:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(resumed.error_code, resumed.error_message, events)
	if _context.session_continuation.is_empty():
		return SessionCoordinatorResult.completed(events)
	if _context.session_continuation.kind == &"item-xap":
		return _continue_item_xap(events)
	return _context.exploration().continue_exploration_continuation(events)


func finish_resumed_vm_result(result: ScenarioVmResult, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var application := _context.session_continuation.application_hook()
	if application != null and result.party_revived: application.party_revived = true
	if result.is_rejection:
		return SessionCoordinatorResult.rejected(result.error_code, result.error_message)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return begin_scenario_handoff(result, events)
	if result.state == ScenarioVmResult.State.WAITING:
		if _context.session_continuation.kind == &"post-clock" and not _context.session_continuation.exploration().active_timed_program_id.is_empty() and not _context.exploration().rebase_post_time_location():
			_context.session_continuation.clear()
			return SessionCoordinatorResult.failed(&"invalid_timed_encounter_location", "The timed encounter moved the party to an unavailable location.", events)
		return SessionCoordinatorResult.waiting(result.interaction, events)
	if result.state == ScenarioVmResult.State.FAILED:
		if _context.scenario_vm.pending_request() == null:
			_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, events)
	if not _context.session_continuation.is_empty():
		if _context.session_continuation.kind in [&"combat-round-macro", &"combat-death-macro"]:
			return SessionBattleMacroWorkflow.finish(_context, events, result.direct_combat_return)
		if _context.session_continuation.kind == &"item-xap":
			return _continue_item_xap(events)
		if _context.session_continuation.kind == &"application-hook":
			return continue_application_hook(events, result.application_return)
		return _context.exploration().continue_exploration_continuation(events)
	return SessionCoordinatorResult.completed(events)


func start_item_xap(character: CharacterState, instance: ItemInstance, item: ItemDefinition) -> SessionCoordinatorResult:
	var in_combat := _context.state.combat != null and not _context.state.combat.completed
	var probe := FieldItemWorkflow.door_item_probe(_context.workflow_context(), character, instance, item, in_combat)
	if not probe.allowed:
		return SessionCoordinatorResult.failed(&"item_cannot_be_used", probe.reason)
	var state_checkpoint := _context.state.to_data()
	var rng_checkpoint := _context.rng.checkpoint()
	var vm_checkpoint := _context.scenario_vm.snapshot()
	var action_checkpoint := _context.scenario_action_state.to_data()
	var native_checkpoint := _context.classic_execution.to_data()
	var body := ItemXapContinuationBody.new()
	body.character_id = character.id
	body.instance_id = instance.id
	body.item_id = item.id
	body.program_id = "xap:%d" % item.special_5
	body.source_battle_id = _context.state.combat.battle_id if in_combat else ""
	_context.set_continuation(InventoryContinuations.item_xap(body))
	if not _context.rules.inventory.use_charge(character, instance.id, item):
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(&"item_charge_commit_failed", "The validated door-item charge could not be committed.")
	var execution_context := ScenarioExecutionContext.calling(&"item")
	if in_combat:
		execution_context.set_battle(body.source_battle_id)
	var started := _context.scenario_vm.start_program(body.program_id, execution_context)
	if started.state == ScenarioVmResult.State.FAILED:
		_rollback_item_xap(state_checkpoint, rng_checkpoint, vm_checkpoint, action_checkpoint, native_checkpoint)
		return SessionCoordinatorResult.failed(started.error_code, started.error_message)
	var charges_remaining := -1
	var dropped := true
	for carried: ItemInstance in character.inventory():
		if carried.id == instance.id:
			charges_remaining = carried.charges
			dropped = false
			break
	var result := _context.scenario_vm.run(_context.runtime_api)
	var events: Array[DomainEvent] = [
		DomainEvent.new(&"item_used", {"characterId": character.id, "instanceId": instance.id, "itemId": item.id, "programId": body.program_id, "chargesRemaining": charges_remaining, "droppedOnEmpty": dropped, "source": "classic-door-item"}),
		DomainEvent.new(&"item_xap_started", {"characterId": character.id, "itemId": item.id, "programId": body.program_id, "sourceBattleId": body.source_battle_id}),
	]
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return begin_scenario_handoff(result, events)
	if result.state == ScenarioVmResult.State.FAILED:
		if not _rollback_item_xap(state_checkpoint, rng_checkpoint, vm_checkpoint, action_checkpoint, native_checkpoint):
			return SessionCoordinatorResult.failed(&"item_xap_rollback_failed", "The failed door-item action could not restore its session checkpoint.", events)
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, events)
	if result.state == ScenarioVmResult.State.WAITING:
		return SessionCoordinatorResult.waiting(result.interaction, events)
	return _continue_item_xap(events)


func _continue_item_xap(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var body := _context.session_continuation.item_xap_body()
	if body == null:
		return SessionCoordinatorResult.failed(&"invalid_session_continuation", "The door-item scenario continuation is unavailable.", events)
	events.append(DomainEvent.new(&"item_xap_completed", {"characterId": body.character_id, "itemId": body.item_id, "programId": body.program_id, "sourceBattleId": body.source_battle_id}))
	_context.session_continuation.clear()
	return SessionCoordinatorResult.completed(events)


func _rollback_item_xap(state_checkpoint: Dictionary, rng_checkpoint: Dictionary, vm_checkpoint: ScenarioVmSnapshot, action_checkpoint: Dictionary, native_checkpoint: Dictionary) -> bool:
	var restored_action := ScenarioActionState.from_data(action_checkpoint)
	var restored_native := ClassicExecutionState.from_data(native_checkpoint)
	if restored_action == null or restored_native == null or not _context.state.restore_from_data(state_checkpoint) or not _context.rng.rollback(rng_checkpoint) or not _context.scenario_vm.restore(vm_checkpoint):
		return false
	_context.scenario_action_state = restored_action
	_context.classic_execution = restored_native
	_context.runtime_api = RealmzRuntimeApi.new(_context.content, _context.state, _context.rng, restored_action, _context.rules, restored_native)
	_context.session_continuation.clear()
	return true



func start_session_death_macro(request: CombatDeathMacroRequest, preceding_events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var combat := _context.state.combat
	if request == null or combat == null:
		return SessionCoordinatorResult.failed(&"invalid_death_macro_request", "Monster death-macro execution requires an active combatant request.", preceding_events)
	return SessionBattleMacroWorkflow.start_call(_context,ScenarioMacroCall.death(request,combat.battle_id),preceding_events)


func append_session_battle_after_message(battle_id: String, events: Array[DomainEvent]) -> void:
	var battle := _context.content.combat.battle_by_id(battle_id)
	if battle == null or battle.message_after_id == 0:
		return
	var message := _context.content.scenario_records.message_by_id(absi(battle.message_after_id))
	if message != null:
		events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-battle-definition"}))


func finish_direct_battle(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	if _context.state.combat == null or not _context.state.combat.completed:
		return SessionCoordinatorResult.failed(&"invalid_battle_continuation", "Post-battle completion requires a completed battle.", events)
	if _context.state.combat.outcome == &"defeat":
		return start_application_hook(ScenarioApplicationHooks.PARTY_DEATH, "party-defeat", "", events)
	var payload := _context.rules.combat_flow.rounds.ally_selection_payload(_context.state, _context.content)
	if not payload.is_empty():
		var request_id := "session.ally-selection.%d" % _context.next_revision()
		var combat := CombatContinuationBody.new()
		combat.battle_id = _context.state.combat.battle_id
		_context.set_continuation(CombatContinuations.ally_selection(combat))
		_context.session_interaction = InteractionRequest.from_payload(request_id, &"ally_selection", payload)
		return SessionCoordinatorResult.waiting(_context.session_interaction, events)
	return finish_direct_battle_recovery(events)


func finish_direct_battle_recovery(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	return begin_direct_battle_reward(events)


func finish_direct_battle_without_rewards(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	if _context.state.combat == null or not _context.state.combat.completed:
		return SessionCoordinatorResult.failed(&"invalid_battle_continuation", "Suppressed battle rewards require a completed battle.", events)
	var battle_id := _context.state.combat.battle_id
	var return_continuation := _context.battle_return_continuation.copy()
	var battle_outcome := _context.state.combat.outcome
	events.append(DomainEvent.new(&"battle_returned", {"battleId": battle_id, "outcome": String(battle_outcome)}))
	_context.state.combat = null
	return finish_after_direct_battle(events, return_continuation, BattleReturnResult.new(battle_id,battle_outcome))


func begin_direct_battle_reward(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var return_continuation := _context.battle_return_continuation.copy()
	var request_id := "session.battle-reward.%d" % _context.next_revision()
	var operation := _context.runtime_api.begin_completed_battle_reward(request_id)
	events.append_array(operation.events)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return SessionCoordinatorResult.failed(operation.error_code, operation.error_message, events)
	if operation.state == ScenarioRuntimeOperationResult.State.WAITING:
		_context.set_continuation(CombatContinuations.reward(_context.state.combat.battle_id, operation.continuation))
		_context.session_interaction = operation.interaction
		return SessionCoordinatorResult.waiting(_context.session_interaction, events)
	_context.session_interaction = null
	_context.session_continuation.clear()
	return finish_after_direct_battle(events, return_continuation, operation.battle_return)


func finish_after_direct_battle(events: Array[DomainEvent], return_continuation: SessionContinuation, returned: BattleReturnResult) -> SessionCoordinatorResult:
	_context.battle_return_continuation.clear()
	if return_continuation == null or return_continuation.is_empty() or returned == null or returned.outcome == &"defeat":
		return SessionCoordinatorResult.completed(events)
	var exploration := return_continuation.exploration()
	if exploration != null and (_context.state.party.map_id != exploration.map_id or _context.state.party.coordinate != exploration.coordinate):
		# FD-COMBAT-021: a relocated battle cannot replay its old pending travel step.
		# Its clock and encounter work already committed before the battle began.
		return SessionCoordinatorResult.completed(events)
	_context.set_continuation(return_continuation.copy())
	return _context.exploration().continue_post_time(events)
