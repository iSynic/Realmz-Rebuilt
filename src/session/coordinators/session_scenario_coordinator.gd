class_name SessionScenarioCoordinator
extends RefCounted

var _context: SessionCoordinatorContext


func _init(context: SessionCoordinatorContext) -> void:
	_context = context

func _start_application_hook(hook: StringName, resume_kind: StringName, service_id: String, preceding_events: Array[DomainEvent], suspended: SessionContinuation.ApplicationBody = null) -> SessionCoordinatorResult:
	var continuation = ScenarioApplicationHookWorkflow.continuation(_context.content, hook, resume_kind, service_id, suspended)
	if continuation == null:
		return _context.failed(&"invalid_application_hook_resume", "The application hook has an unsupported resume path.", preceding_events)
	_context.session_continuation = continuation
	var body = _context.session_continuation.body as SessionContinuation.ApplicationBody
	var program_id = body.program_id
	if program_id.is_empty():
		return _continue_application_hook(preceding_events)
	var started = _context.scenario_vm.start_program(program_id, ScenarioApplicationHookWorkflow.start_context(hook, service_id))
	if started.state == ScenarioVmResult.State.FAILED:
		_context.session_continuation.clear()
		return _context.failed(started.error_code, started.error_message, preceding_events)
	var result = _context.scenario_vm.run(_context.runtime_api)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	events.append(DomainEvent.new(&"application_hook_started", {"hook": String(hook), "programId": program_id}))
	events.append_array(result.events)
	if _events_have(result.events, &"party_revived"):
		body.party_revived = true
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return _context.failed(&"nested_party_defeat_handoff", "An application hook cannot suspend another total-party defeat.", events)
	if result.state == ScenarioVmResult.State.FAILED:
		_context.session_continuation.clear()
		return _context.failed(result.error_code, result.error_message, events)
	if result.state == ScenarioVmResult.State.WAITING:
		return _context.waiting(result.interaction, events)
	return _continue_application_hook(events)


func _continue_application_hook(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var body = _context.session_continuation.body as SessionContinuation.ApplicationBody
	if body == null:
		return _context.failed(&"invalid_session_continuation", "Application-hook continuation body is unavailable.", events)
	var hook = body.hook
	var program_id = body.program_id
	var resume_kind = String(body.resume_kind)
	var service_id = body.service_id
	var party_revived = body.party_revived
	var suspended_vm = ScenarioVmSnapshot.from_data(body.suspended_vm.to_data()) if body.suspended_vm != null else null
	var suspended_owner = body.suspended_owner
	var vm_handoff = body.vm_handoff.copy() if body.vm_handoff != null else null
	_context.session_continuation.clear()
	if not program_id.is_empty():
		events.append(ScenarioApplicationHookWorkflow.completion_event(body))
	match resume_kind:
		"begin-adventure":
			events.append(DomainEvent.new(&"adventure_begun", {"campaignId": _context.content.campaign_id}))
			return _context.completed(events)
		"service":
			return _context.responses()._open_contextual_service(service_id, events)
		"end-adventure":
			return _start_application_hook(ScenarioApplicationHooks.PARTY_DEATH, "end-adventure-close", "", events)
		"end-adventure-close":
			if party_revived:
				events.append(DomainEvent.new(&"adventure_end_suppressed", {"reason": "classic-party-death-revival"}))
				return _context.completed(events)
			return _context.closed(events, "end-adventure")
		"party-defeat":
			if not party_revived:
				return _context.closed(events, "party-defeat")
			if _context.state.combat == null or not _context.state.combat.completed or _context.state.combat.outcome != &"defeat":
				return _context.failed(&"invalid_battle_continuation", "Party Death revival lost its completed defeat.", events)
			_context.state.combat.outcome = &"retreated"
			_context.state.last_battle_outcome = &"retreated"
			events.append(DomainEvent.new(&"party_defeat_revived", {"battleId": _context.state.combat.battle_id, "source": "classic-party-death-hook"}))
			return _finish_direct_battle_without_rewards(events)
		"scenario-party-defeat":
			if not party_revived:
				return _context.closed(events, "party-defeat")
			return _resume_scenario_party_defeat(suspended_vm, suspended_owner, vm_handoff, events)
	return _context.failed(&"invalid_session_continuation", "Application hook '%s' has invalid resume kind '%s'." % [hook, resume_kind], events)


func _begin_scenario_handoff(result: ScenarioVmResult, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	if result == null or result.state != ScenarioVmResult.State.SUSPENDED or result.handoff == null or result.handoff.runtime == null:
		_context.session_continuation.clear()
		return _context.failed(&"invalid_vm_handoff", "The Scenario VM did not provide a typed application handoff.", events)
	if _context.session_continuation.kind not in [&"post-clock", &"post-move", &"item-xap"]:
		_context.session_continuation.clear()
		return _context.failed(&"unsupported_vm_handoff_owner", "Total-party defeat cannot suspend this scenario caller.", events)
	var saved = _context.scenario_vm.snapshot()
	if not ScenarioVm.handoff_is_valid(result.handoff, saved) or not RealmzRuntimeApi.party_defeat_handoff_is_valid(_context.content, _context.state, result.handoff.runtime):
		_context.session_continuation.clear()
		return _context.failed(&"invalid_party_defeat_handoff", "The Scenario VM total-party defeat handoff is invalid.", events)
	var suspended = SessionContinuation.ApplicationBody.new()
	suspended.suspended_vm = ScenarioVmSnapshot.from_data(saved.to_data())
	suspended.suspended_owner = _context.session_continuation.copy()
	suspended.vm_handoff = result.handoff.copy()
	_context.scenario_vm.reset()
	return _start_application_hook(ScenarioApplicationHooks.PARTY_DEATH, &"scenario-party-defeat", "", events, suspended)


func _resume_scenario_party_defeat(saved: ScenarioVmSnapshot, suspended_owner: SessionContinuation, vm_handoff: ScenarioVmHandoff, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	if not ScenarioVm.handoff_is_valid(vm_handoff, saved) or not RealmzRuntimeApi.party_defeat_handoff_is_valid(_context.content, _context.state, vm_handoff.runtime) or not SessionRestoreValidator.suspended_scenario_owner_is_valid(_context.content, _context.state, suspended_owner, saved):
		return _context.failed(&"invalid_party_defeat_handoff", "The saved scenario defeat continuation is invalid.", events)
	var restored_vm = ScenarioVm.new()
	restored_vm.configure(_context.content.scenario)
	if not restored_vm.restore(saved):
		return _context.failed(&"invalid_vm_state", "The suspended scenario cannot be restored after Party Death.", events)
	var operation = _context.runtime_api.complete_party_defeat_handoff(vm_handoff.runtime)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _context.failed(operation.error_code, operation.error_message, events)
	_context.scenario_vm = restored_vm
	var resumed = _context.scenario_vm.resume_handoff(vm_handoff, operation, _context.runtime_api)
	events.append_array(resumed.events)
	_context.set_continuation(suspended_owner.copy())
	if resumed.state == ScenarioVmResult.State.SUSPENDED:
		return _begin_scenario_handoff(resumed, events)
	if resumed.state == ScenarioVmResult.State.WAITING:
		return _context.waiting(resumed.interaction, events)
	if resumed.state == ScenarioVmResult.State.FAILED:
		_context.session_continuation.clear()
		return _context.failed(resumed.error_code, resumed.error_message, events)
	if _context.session_continuation.is_empty():
		return _context.completed(events)
	if _context.session_continuation.kind == &"item-xap":
		return _continue_item_xap(events)
	return _context.exploration()._continue_exploration_continuation(events)


func _start_item_xap(character: CharacterState, instance: ItemInstance, item: ItemDefinition) -> SessionCoordinatorResult:
	var in_combat := _context.state.combat != null and not _context.state.combat.completed
	var probe := InventoryMagicServicesWorkflow.door_item_probe(_context.workflow_context(), character, instance, item, in_combat)
	if not probe.allowed:
		return _context.failed(&"item_cannot_be_used", probe.reason)
	var state_checkpoint := _context.state.to_data()
	var rng_checkpoint := _context.rng.checkpoint()
	var vm_checkpoint := _context.scenario_vm.snapshot()
	var action_checkpoint := _context.scenario_action_state.to_data()
	var body := SessionContinuation.ItemBody.new()
	body.character_id = character.id
	body.instance_id = instance.id
	body.item_id = item.id
	body.program_id = "xap:%d" % item.special_5
	body.source_battle_id = _context.state.combat.battle_id if in_combat else ""
	_context.set_continuation(SessionContinuation.item_xap(body))
	if not _context.rules.inventory.use_charge(character, instance.id, item):
		_context.session_continuation.clear()
		return _context.failed(&"item_charge_commit_failed", "The validated door-item charge could not be committed.")
	var execution_context := ScenarioExecutionContext.calling(&"item")
	if in_combat:
		execution_context.set_battle(body.source_battle_id)
	var started := _context.scenario_vm.start_program(body.program_id, execution_context)
	if started.state == ScenarioVmResult.State.FAILED:
		_rollback_item_xap(state_checkpoint, rng_checkpoint, vm_checkpoint, action_checkpoint)
		return _context.failed(started.error_code, started.error_message)
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
		return _begin_scenario_handoff(result, events)
	if result.state == ScenarioVmResult.State.FAILED:
		if not _rollback_item_xap(state_checkpoint, rng_checkpoint, vm_checkpoint, action_checkpoint):
			return _context.failed(&"item_xap_rollback_failed", "The failed door-item action could not restore its session checkpoint.", events)
		return _context.failed(result.error_code, result.error_message, events)
	if result.state == ScenarioVmResult.State.WAITING:
		return _context.waiting(result.interaction, events)
	return _continue_item_xap(events)


func _continue_item_xap(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var body := _context.session_continuation.item_xap_body()
	if body == null:
		return _context.failed(&"invalid_session_continuation", "The door-item scenario continuation is unavailable.", events)
	events.append(DomainEvent.new(&"item_xap_completed", {"characterId": body.character_id, "itemId": body.item_id, "programId": body.program_id, "sourceBattleId": body.source_battle_id}))
	_context.session_continuation.clear()
	return _context.completed(events)


func _rollback_item_xap(state_checkpoint: Dictionary, rng_checkpoint: Dictionary, vm_checkpoint: ScenarioVmSnapshot, action_checkpoint: Dictionary) -> bool:
	var restored_action := ScenarioActionState.from_data(action_checkpoint)
	if restored_action == null or not _context.state.restore_from_data(state_checkpoint) or not _context.rng.rollback(rng_checkpoint) or not _context.scenario_vm.restore(vm_checkpoint):
		return false
	_context.scenario_action_state = restored_action
	_context.runtime_api = RealmzRuntimeApi.new(_context.content, _context.state, _context.rng, restored_action, _context.rules)
	_context.session_continuation.clear()
	return true


func _apply_trigger_destination(trigger: TriggerDefinition, events: Array[DomainEvent], allow_destination: bool) -> bool:
	var destination = trigger.post_action_location
	var destination_is_source: bool = destination != null and destination.map_id == trigger.map_id and destination.coordinate == trigger.coordinate
	if not allow_destination or destination == null or destination_is_source or destination.map_id == _context.state.party.map_id and destination.coordinate == _context.state.party.coordinate:
		return false
	var source_map_id = _context.state.party.map_id
	var source_coordinate = _context.state.party.coordinate
	_context.state.party.map_id = destination.map_id
	_context.state.party.coordinate = destination.coordinate
	_context.state.world.mark_visited(destination.map_id, destination.coordinate)
	events.append(DomainEvent.new(&"party_moved", {"fromMapId": source_map_id, "fromX": source_coordinate.x, "fromY": source_coordinate.y, "mapId": destination.map_id, "x": destination.coordinate.x, "y": destination.coordinate.y, "source": "action-point-destination", "triggerId": trigger.id}))
	return true


func _finalize_completed_trigger(trigger: TriggerDefinition, events: Array[DomainEvent]) -> void:
	if _events_keep_trigger(events, trigger.id) or _context.state.world.trigger_is_disabled(trigger.id):
		return
	_context.state.world.disable_trigger(trigger.id)
	events.append(DomainEvent.new(&"trigger_disabled", {"triggerId": trigger.id, "source": "classic-default-one-shot"}))


static func _events_have(events: Array[DomainEvent], kind: StringName) -> bool:
	for event: DomainEvent in events:
		if event.kind == kind:
			return true
	return false


static func _events_keep_trigger(events: Array[DomainEvent], trigger_id: String) -> bool:
	for event: DomainEvent in events:
		if event.kind == &"action_point_kept" and String(event.payload.get("triggerId", "")) == trigger_id:
			return true
	return false


static func _event_payload(events: Array[DomainEvent], kind: StringName) -> Dictionary:
	for index: int in range(events.size() - 1, -1, -1):
		if events[index].kind == kind:
			return events[index].payload
	return {}


func _start_session_death_macro(preceding_events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var request = _event_payload(preceding_events, &"monster_death_macro_requested")
	var combat = _context.state.combat
	if request.is_empty() or combat == null:
		return _context.failed(&"invalid_death_macro_request", "Monster death-macro execution requires an active combatant request.", preceding_events)
	var combatant_id = str(request.get("combatantId", ""))
	var program_id = str(request.get("programId", ""))
	var monster = combat.monster_by_id(combatant_id)
	if monster == null or _context.content.scenario.program_by_id(program_id) == null:
		return _context.failed(&"invalid_death_macro_request", "Monster death-macro execution references unavailable content.", preceding_events)
	var continuation_body = SessionContinuation.CombatBody.new()
	continuation_body.battle_id = combat.battle_id
	continuation_body.combatant_id = combatant_id
	continuation_body.program_id = program_id
	continuation_body.reset_traitor_on_complete = bool(request.get("resetTraitorOnComplete", true))
	_context.set_continuation(SessionContinuation.combat_state(&"combat-death-macro", continuation_body))
	var death_context = ScenarioExecutionContext.calling(&"monster-death-macro")
	death_context.set_battle(combat.battle_id)
	death_context.set_combatant(combatant_id, int(request.get("classicMonsterId", 0)), bool(request.get("traitor", monster.traitor)), true)
	var started = _context.scenario_vm.start_program(program_id, death_context)
	if started.state == ScenarioVmResult.State.FAILED:
		_context.session_continuation.clear()
		return _context.failed(started.error_code, started.error_message, preceding_events)
	var result = _context.scenario_vm.run(_context.runtime_api)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	events.append(DomainEvent.new(&"monster_death_macro_started", {"battleId": combat.battle_id, "combatantId": combatant_id, "programId": program_id}))
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		_context.session_continuation.clear()
		return _context.failed(&"unsupported_vm_handoff_owner", "A session-owned monster death macro cannot suspend a total-party defeat.", events)
	if result.state == ScenarioVmResult.State.FAILED:
		_context.session_continuation.clear()
		return _context.failed(result.error_code, result.error_message, events)
	if result.state == ScenarioVmResult.State.WAITING:
		return _context.waiting(result.interaction, events)
	return _continue_session_death_macro(events)


func _continue_session_death_macro(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var combat = _context.state.combat
	var continuation = _context.session_continuation.combat()
	if continuation == null:
		return _context.failed(&"invalid_battle_continuation", "Monster death-macro continuation is unavailable.", events)
	var battle_id = continuation.battle_id
	var combatant_id = continuation.combatant_id
	var program_id = continuation.program_id
	if combat == null or combat.battle_id != battle_id:
		_context.session_continuation.clear()
		return _context.failed(&"invalid_battle_continuation", "Monster death-macro completion lost its battle.", events)
	var monster = combat.monster_by_id(combatant_id)
	if monster != null and continuation.reset_traitor_on_complete:
		monster.traitor = false
	events.append(DomainEvent.new(&"monster_death_macro_completed", {"battleId": battle_id, "combatantId": combatant_id, "programId": program_id, "revived": monster != null and monster.current_health > 0}))
	_context.session_continuation.clear()
	var continued = _context.rules.combat_flow.continue_after_monster_death_macro(_context.state, _context.content, _context.rng, combatant_id)
	if not continued.ok:
		return _context.failed(continued.error_code, continued.error_message, events)
	events.append_array(continued.events)
	if not CharacterAgingResult.update_payloads(continued.events).is_empty():
		return _context.responses()._finish_with_age_updates(events, "combat-monster-turns")
	if not _event_payload(continued.events, &"monster_death_macro_requested").is_empty():
		return _start_session_death_macro(events)
	if continued.completed:
		return _finish_direct_battle(events)
	return _context.completed(events)


func _append_session_battle_after_message(battle_id: String, events: Array[DomainEvent]) -> void:
	var battle = _context.content.battle_by_id(battle_id)
	if battle == null or battle.message_after_id == 0:
		return
	var message = _context.content.message_by_id(absi(battle.message_after_id))
	if message != null:
		events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-battle-definition"}))


func _finish_direct_battle(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	if _context.state.combat == null or not _context.state.combat.completed:
		return _context.failed(&"invalid_battle_continuation", "Post-battle completion requires a completed battle.", events)
	if _context.state.combat.outcome == &"defeat":
		return _start_application_hook(ScenarioApplicationHooks.PARTY_DEATH, "party-defeat", "", events)
	var payload = _context.rules.combat_flow.ally_selection_payload(_context.state, _context.content)
	if not payload.is_empty():
		var request_id = "session.ally-selection.%d" % _context.next_revision()
		var combat = SessionContinuation.CombatBody.new()
		combat.battle_id = _context.state.combat.battle_id
		_context.set_continuation(SessionContinuation.combat_state(&"combat-ally-selection", combat))
		_context.session_interaction = InteractionRequest.from_payload(request_id, &"ally_selection", payload)
		return _context.waiting(_context.session_interaction, events)
	return _finish_direct_battle_recovery(events)


func _finish_direct_battle_recovery(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	return _begin_direct_battle_reward(events)


func _finish_direct_battle_without_rewards(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	if _context.state.combat == null or not _context.state.combat.completed:
		return _context.failed(&"invalid_battle_continuation", "Suppressed battle rewards require a completed battle.", events)
	var battle_id = _context.state.combat.battle_id
	var return_continuation = _context.battle_return_continuation.copy()
	var battle_outcome = _context.state.combat.outcome
	events.append(DomainEvent.new(&"battle_returned", {"battleId": battle_id, "outcome": String(battle_outcome)}))
	_context.state.combat = null
	return _finish_after_direct_battle(events, return_continuation, battle_outcome)


func _begin_direct_battle_reward(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var return_continuation = _context.battle_return_continuation.copy()
	var battle_outcome = _context.state.combat.outcome
	var request_id = "session.battle-reward.%d" % _context.next_revision()
	var operation = _context.runtime_api.begin_completed_battle_reward(request_id)
	events.append_array(operation.events)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _context.failed(operation.error_code, operation.error_message, events)
	if operation.state == ScenarioRuntimeOperationResult.State.WAITING:
		_context.set_continuation(SessionContinuation.combat_reward(_context.state.combat.battle_id, operation.continuation))
		_context.session_interaction = operation.interaction
		return _context.waiting(_context.session_interaction, events)
	_context.session_interaction = null
	_context.session_continuation.clear()
	return _finish_after_direct_battle(events, return_continuation, battle_outcome)


func _finish_after_direct_battle(events: Array[DomainEvent], return_continuation: SessionContinuation, battle_outcome: StringName) -> SessionCoordinatorResult:
	_context.battle_return_continuation.clear()
	if return_continuation == null or return_continuation.is_empty() or battle_outcome == &"defeat" or not _events_have(events, &"battle_returned"):
		return _context.completed(events)
	_context.set_continuation(return_continuation.copy())
	return _context.exploration()._continue_post_time(events)
