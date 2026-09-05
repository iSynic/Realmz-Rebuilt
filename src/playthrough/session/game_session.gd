## Defines the typed game session contract used by playthrough transactions.

class_name GameSession
extends RefCounted

var _context: SessionContext = SessionContext.new()
var _started: bool = false
var _view_projector := SessionViewProjector.new()
var _exploration_coordinator: RefCounted
var _scenario_coordinator: RefCounted
var _response_coordinator: RefCounted
var _debug_coordinator: RefCounted
var _intent_coordinator: RefCounted
var _debug_operation_active: bool = false


func _ensure_coordinators() -> void:
	if _exploration_coordinator != null:
		return
	_exploration_coordinator = SessionExplorationCoordinator.new(_context)
	_scenario_coordinator = SessionScenarioCoordinator.new(_context)
	_response_coordinator = SessionResponsesCoordinator.new(_context)
	_context.bind_coordinators(_exploration_coordinator, _scenario_coordinator, _response_coordinator)
	_debug_coordinator = SessionDebugCoordinator.new(_context)
	_intent_coordinator = SessionIntentCoordinator.new(_context)


func _release_coordinators() -> void:
	_context.release_coordinators()
	_exploration_coordinator = null
	_scenario_coordinator = null
	_response_coordinator = null
	_debug_coordinator = null
	_intent_coordinator = null


func _commit_coordinator_result(result: SessionCoordinatorResult) -> SessionStep:
	_release_coordinators()
	if result == null:
		return _finish_failed(&"invalid_coordinator_result", "The session coordinator returned no typed result.", [])
	match result.state:
		SessionCoordinatorResult.State.COMPLETED:
			return _finish_completed(result.events)
		SessionCoordinatorResult.State.WAITING:
			return _finish_waiting(result.interaction, result.events)
		SessionCoordinatorResult.State.FAILED:
			return _finish_failed(result.error_code, result.error_message, result.events) if result.commit_failure else SessionStep.failed(_context.current_revision(), result.error_code, result.error_message)
		SessionCoordinatorResult.State.CLOSE:
			return _commit_close(result.events, result.close_reason)
	return _finish_failed(&"invalid_coordinator_result", "The session coordinator returned an unknown state.", [])


func start(content: RealmzContent, initial_seed: int) -> SessionStep:
	if _started:
		return SessionStep.failed(_context.current_revision(), &"session_already_started", "The session has already started.")
	if content == null or content.scenario == null:
		return SessionStep.failed(_context.current_revision(), &"invalid_content", "Validated Realmz content is required.")
	var start_map := content.world.map_by_id(content.start_map_id)
	if start_map == null or start_map.topology.cell_at(content.start_coordinate) == null:
		return SessionStep.failed(_context.current_revision(), &"invalid_start_location", "The package start location is unavailable.")
	_context.begin(content, initial_seed)
	_view_projector.clear()
	_started = true
	_record_current_visibility()
	return SessionStep.completed(_context.current_revision(), [DomainEvent.new("session_started", {"campaignId": content.campaign_id})])


func restore(content: RealmzContent, save_envelope: SessionSnapshot) -> SessionStep:
	var result := SessionRestoreValidator.validate(content, save_envelope)
	if not result.ok:
		return SessionStep.failed(_context.current_revision(), result.error_code, result.error_message)
	_context.restore(content, result.candidate)
	_view_projector.clear()
	_started = true
	_record_current_visibility()
	return SessionStep.completed(_context.current_revision(), [DomainEvent.new("session_restored")])


func close() -> SessionStep:
	if not _started:
		return SessionStep.failed(_context.current_revision(), &"session_not_started", "There is no active session to close.")
	var pending := _pending_interaction()
	if (_context.scenario_vm.is_active() and pending == null) or (pending != null and pending.kind != InteractionRequest.COMBAT):
		return SessionStep.failed(_context.current_revision(), &"session_not_committed", "The session can close only at a committed boundary.")
	# Castle permits End Adventure during combat after confirmation. Abandon the
	# interrupted combat/VM interaction before the synchronous Global hooks run.
	if pending != null:
		_context.reset_scenario_execution()
	return _start_application_hook(ScenarioApplicationHooks.END_ADVENTURE, "end-adventure", "", [])


func _commit_close(events: Array[DomainEvent], reason: String) -> SessionStep:
	var campaign_id := _context.content.campaign_id
	_context.clear()
	_view_projector.clear()
	_started = false
	_context.set_revision(_context.next_revision())
	var completed_events: Array[DomainEvent] = []
	completed_events.assign(events)
	completed_events.append(DomainEvent.new(&"session_ended", {"campaignId": campaign_id, "reason": reason}))
	return SessionStep.completed(_context.current_revision(), completed_events)


func submit_intent(intent: PlayerIntent) -> SessionStep:
	if not _started:
		return SessionStep.failed(_context.current_revision(), &"session_not_started", "Start or restore the session first.")
	if intent == null:
		return SessionStep.failed(_context.current_revision(), &"invalid_intent", "A typed player intent is required.")
	if not intent.is_valid():
		return SessionStep.failed(_context.current_revision(), &"invalid_intent_payload", "The player intent payload does not match its kind.")
	if intent.kind == PlayerIntent.Kind.SET_COMBAT_AUTO:
		return _set_combat_auto(intent)
	if _pending_interaction() != null or _context.scenario_vm.is_active():
		return SessionStep.failed(_context.current_revision(), &"interaction_pending", "Respond to the pending interaction first.")
	if not _context.state.party_setup_completed and intent.kind not in [PlayerIntent.Kind.CREATE_PARTY, PlayerIntent.Kind.BEGIN_ADVENTURE, PlayerIntent.Kind.IMPORT_VAULT_CHARACTER, PlayerIntent.Kind.GENERATE_CHARACTER_DRAFT, PlayerIntent.Kind.CANCEL_CHARACTER_DRAFT, PlayerIntent.Kind.SET_CHARACTER_DRAFT_SPELLS, PlayerIntent.Kind.FINALIZE_CHARACTER, PlayerIntent.Kind.REMOVE_PARTY_MEMBER, PlayerIntent.Kind.SET_PARTY_SETUP_OPTIONS]:
		return SessionStep.failed(_context.current_revision(), &"party_setup_incomplete", "Finish party setup before beginning the adventure.")
	if _context.state.combat != null and not _context.state.combat.completed and intent.kind not in [PlayerIntent.Kind.USE_ITEM, PlayerIntent.Kind.USE_ITEM_ON_TARGET, PlayerIntent.Kind.CAST_SPELL, PlayerIntent.Kind.CHOOSE_COMBAT_ACTION, PlayerIntent.Kind.COMBAT_MOVE]:
		return SessionStep.failed(_context.current_revision(), &"battle_in_progress", "Resolve the active battle before returning to exploration.")
	_ensure_coordinators()
	return _commit_coordinator_result(_intent_coordinator.submit(intent))


func apply_debug_command(command: SessionDebugCommand) -> SessionStep:
	if not _started:
		return SessionStep.failed(_context.current_revision(), &"debug_command_unavailable", "Debug commands require a committed active adventure boundary.")
	_ensure_coordinators()
	var result: SessionCoordinatorResult = _debug_coordinator.run(command)
	if _debug_coordinator.started_ephemeral_operation:
		_debug_operation_active = true
	return _commit_coordinator_result(result)


func respond(response: InteractionResponse) -> SessionStep:
	if not _started:
		return SessionStep.failed(_context.current_revision(), &"session_not_started", "Start or restore the session first.")
	var pending := _pending_interaction()
	if pending == null:
		return SessionStep.failed(_context.current_revision(), &"no_interaction_pending", "There is no interaction to resume.")
	if response == null or response.request_id != pending.request_id:
		return SessionStep.failed(_context.current_revision(), &"interaction_mismatch", "The response does not match the pending request.")
	if not response.is_supported_kind():
		return SessionStep.failed(_context.current_revision(), &"invalid_interaction_response", "The response payload does not match its interaction kind.")
	if _context.session_interaction != null:
		return _respond_session_interaction(response)
	var result := _context.scenario_vm.resume(response, _context.runtime_api)
	if _debug_operation_active and result.state != ScenarioVmResult.State.WAITING:
		_debug_operation_active = false
	var events: Array[DomainEvent] = []
	events.append_array(result.events)
	if _context.session_continuation.kind == &"application-hook" and _events_have(result.events, &"party_revived"):
		_context.session_continuation.application_hook().party_revived = true
	return _finish_resumed_vm_result(result, events)


func _finish_resumed_vm_result(result: ScenarioVmResult, events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_scenario_coordinator.finish_resumed_vm_result(result, events))


func view(events: Array[DomainEvent] = []) -> GameView:
	var result := _view_projector.project(_context.workflow_context(), _pending_interaction(), _context.current_revision(), _started, events)
	if result != null and result.combat_action_request == null and result.pending_interaction == null and result.combat_view != null and result.combat_view.outcome == &"active":
		result.combat_action_request = _context.runtime_api.active_combat_request("session.combat-command:%d" % _context.current_revision())
	return result


func set_map_projection_size(requested_size: Vector2i) -> bool:
	return _view_projector.set_map_projection_size(requested_size)


func snapshot() -> SessionSnapshot:
	if not _started or _debug_operation_active or (_context.scenario_vm.is_active() and _context.scenario_vm.pending_request() == null):
		return null
	return _context.create_snapshot()


func rng_trace() -> Array[Dictionary]:
	return [] if _context.rng == null else _context.rng.trace()


func scenario_trace() -> Array[Dictionary]:
	return [] if _context.scenario_vm == null else _context.scenario_vm.trace()


func _set_combat_auto(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as CombatIntentPayloads.Auto
	if _context.state == null or _context.state.combat == null or _context.state.combat.completed:
		return SessionStep.failed(_context.current_revision(), &"combat_auto_unavailable", "Persistent Auto can be changed only during an active battle.")
	var character := _context.state.party.character_by_id(payload.character_id)
	if character == null or character.current_health <= 0:
		return SessionStep.failed(_context.current_revision(), &"invalid_combat_auto_character", "Persistent Auto requires a living party character.")
	var pending := _pending_interaction()
	if pending != null:
		if pending.kind != InteractionRequest.COMBAT or _context.session_interaction != null:
			return SessionStep.failed(_context.current_revision(), &"interaction_pending", "Persistent Auto cannot replace this pending interaction.")
		if _context.scenario_vm != null and _context.scenario_vm.pending_request() == pending:
			var response_body := InteractionResponse.CombatBody.new(&"set_auto", payload.character_id)
			response_body.enabled = payload.enabled
			return respond(InteractionResponse.new(pending.request_id, pending.kind, response_body))
	var result := CombatCommandWorkflow.set_persistent_auto(_context.workflow_context(), payload)
	if not result.ok:
		return SessionStep.failed(_context.current_revision(), result.error_code, result.error_message)
	_ensure_coordinators()
	return _commit_coordinator_result(_response_coordinator.finish_combat_result(result))


func _continue_post_move(events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_exploration_coordinator.continue_post_move(events))


func _start_application_hook(hook: StringName, resume_kind: StringName, service_id: String, preceding_events: Array[DomainEvent], suspended: ScenarioApplicationContinuationBody = null) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_scenario_coordinator.start_application_hook(hook, resume_kind, service_id, preceding_events, suspended))


func _events_have(events: Array[DomainEvent], kind: StringName) -> bool:
	return _context.events_have(events, kind)


func _finish_completed(events: Array[DomainEvent]) -> SessionStep:
	_record_current_visibility()
	_context.set_revision(_context.next_revision())
	return SessionStep.completed(_context.current_revision(), events)


func _finish_waiting(request: InteractionRequest, events: Array[DomainEvent]) -> SessionStep:
	_record_current_visibility()
	_context.set_revision(_context.next_revision())
	return SessionStep.waiting(_context.current_revision(), request, events)


func _finish_failed(code: StringName, message: String, events: Array[DomainEvent]) -> SessionStep:
	_context.set_revision(_context.next_revision())
	return SessionStep.failed(_context.current_revision(), code, message, events)


func _record_current_visibility() -> void:
	if not _started or _context.content == null or _context.state == null:
		return
	var map := _context.content.world.map_by_id(_context.state.party.map_id)
	if map == null or not map.uses_los:
		return
	var wizard_eye := _context.state.party.conditions.is_active(ConditionRules.PARTY_WIZARDS_EYE)
	var visible_coordinates := map.topology.exploration_visible_cells(_context.state.party.coordinate, _context.state.world, true, wizard_eye)
	_context.state.world.exploration.mark_seen_many(map.id, visible_coordinates)
	_view_projector.record_visibility(map.id, _context.state.party.coordinate, visible_coordinates, _context.state.world.topology.revision(), wizard_eye)


func _pending_interaction() -> InteractionRequest:
	if _context.session_interaction != null:
		return _context.session_interaction
	return _context.scenario_vm.pending_request() if _context.scenario_vm != null else null


func _respond_session_interaction(response: InteractionResponse) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_response_coordinator.respond_session_interaction(response))
