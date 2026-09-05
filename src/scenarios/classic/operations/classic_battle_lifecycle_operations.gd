## Coordinates Classic battle lifecycle operations operations for the validated scenario runtime.

class_name ClassicBattleLifecycleOperations
extends RefCounted

## Adapts Classic battle opcodes and resumable combat requests to game rules.

var _content: RealmzContent
var _game_state: GameState
var _rng: RealmzRng
var _rules: RealmzRules
var _rewards: RefCounted
var _request_builder: CombatInteractionRequestBuilder
var _runtime_api_ref: WeakRef


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, rules: RealmzRules, rewards: RefCounted) -> void:
	_content = content
	_game_state = game_state
	_rng = rng
	_rules = rules
	_rewards = rewards
	_request_builder = CombatInteractionRequestBuilder.new(content, game_state, rules)


func bind_runtime_api(runtime_api: RealmzRuntimeApi) -> void:
	_runtime_api_ref = weakref(runtime_api)


func _runtime_api() -> RealmzRuntimeApi:
	return _runtime_api_ref.get_ref() as RealmzRuntimeApi if _runtime_api_ref != null else null


func start_classic_battle(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	return _start_classic_battle(action, request_id)


func resume_battle(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	match continuation.kind:
		ScenarioRuntimeContinuation.CLASSIC_COMBAT, ScenarioRuntimeContinuation.SAFE_COMBAT:
			return _resume_battle(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT_RETREAT, ScenarioRuntimeContinuation.SAFE_COMBAT_RETREAT:
			return _resume_battle_retreat(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT_AGE, ScenarioRuntimeContinuation.SAFE_COMBAT_AGE:
			return _resume_combat_age_updates(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT_MACRO:
			return _resume_battle_macro(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT_DEATH_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT_DEATH_MACRO:
			return _resume_combat_death_macro(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT_ALLY, ScenarioRuntimeContinuation.SAFE_COMBAT_ALLY:
			return _resume_ally_selection(continuation, response)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT_FUMBLE, ScenarioRuntimeContinuation.SAFE_COMBAT_FUMBLE:
			return _resume_fumble_recovery(continuation, response, request_id)
	return ScenarioRuntimeOperationResult.failed(&"unknown_interaction_continuation", "Battle continuation is unavailable.")


func active_combat_request(request_id: String) -> InteractionRequest:
	return _request_builder.build(request_id)


func complete_debug_victory(continuation: ScenarioRuntimeContinuation, request_id: String, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	if continuation == null or continuation.kind not in [ScenarioRuntimeContinuation.CLASSIC_COMBAT, ScenarioRuntimeContinuation.SAFE_COMBAT]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Debug victory requires the active combat command continuation.")
	var combat_continuation := continuation.body as ScenarioCombatContinuationBody
	if combat_continuation == null or combat_continuation.caller == null or _game_state.combat == null or not _game_state.combat.completed or _game_state.combat.battle_id != combat_continuation.battle_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The completed debug battle does not match its issuing continuation.")
	return _finish_battle_with_allies(continuation.kind, combat_continuation.caller, request_id, events)

func _start_classic_battle(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	var battle_id := action.operand_id
	var prelude: Array[DomainEvent] = []
	if not action.extra_code.is_empty():
		var low := action.extra_code[0]
		var high := action.extra_code[1] if action.extra_code.size() > 1 else 0
		battle_id = absi(low)
		if high != 0:
			battle_id = _rng.draw_between(absi(low), absi(high), StringName("classic.opcode-%d.battle" % action.opcode))
		var sound_id := action.extra_code[3] if action.opcode == 56 else action.extra_code[2]
		var message_id := action.extra_code[4] if action.opcode == 56 else action.extra_code[3]
		if sound_id != 0:
			prelude.append(DomainEvent.new(&"sound_requested", {"soundId": sound_id, "source": "classic-battle"}))
		if message_id != 0:
			var message := _content.scenario_records.message_by_id(absi(message_id))
			if message == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode %d references unavailable battle message %d." % [action.opcode, message_id])
			prelude.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-battle"}))
	var caller_mode := action.extra_code[4] if action.opcode in [2, 48] and action.extra_code.size() > 4 else 0
	var caller := ScenarioBattleCaller.classic(action.opcode, action.gosub, caller_mode, action.extra_code[4] if action.opcode == 107 and action.extra_code.size() > 4 else action.extra_code[2] if action.opcode == 56 and action.extra_code.size() > 2 else 0)
	var battle := _content.combat.battle_by_classic_id(absi(battle_id))
	if battle == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_battle", "Classic opcode %d references unavailable battle %d." % [action.opcode, battle_id])
	var participants: Array[String] = []
	if action.opcode == 48:
		participants = _game_state.scenario_progress.selected_character_ids()
		if participants.is_empty():
			return ScenarioRuntimeOperationResult.failed(&"no_selected_characters", "Classic opcode 48 requires at least one selected party member.")
	var operation := start_battle_definition(battle, request_id, "classic", caller, participants)
	if operation.state != ScenarioRuntimeOperationResult.State.FAILED:
		operation.events = prelude + operation.events
	return operation


static func party_defeat_handoff_is_valid(content: RealmzContent, state: GameState, handoff: ScenarioRuntimeHandoff) -> bool:
	if content == null or state == null or state.combat == null or handoff == null or handoff.caller == null:
		return false
	if handoff.kind != ScenarioRuntimeHandoff.PARTY_DEFEAT or handoff.battle_id != state.combat.battle_id or handoff.source_kind not in [ScenarioRuntimeHandoff.CLASSIC_COMBAT, ScenarioRuntimeHandoff.SAFE_COMBAT]:
		return false
	if not state.combat.completed or state.combat.outcome != &"defeat":
		return false
	var caller := handoff.caller
	if handoff.source_kind == ScenarioRuntimeHandoff.SAFE_COMBAT:
		return caller.kind == ScenarioBattleCaller.SAFE
	if caller.kind != ScenarioBattleCaller.CLASSIC:
		return false
	var opcode := caller.opcode
	if opcode == 2 and caller.mode == 10:
		return false
	var target := caller.branch_target
	if opcode == 107 or opcode == 56 and target >= 0:
		return content.scenario.program_by_id("xap:%d" % target) != null
	return true


func complete_party_defeat_handoff(handoff: ScenarioRuntimeHandoff) -> ScenarioRuntimeOperationResult:
	if not party_defeat_handoff_is_valid(_content, _game_state, handoff):
		return ScenarioRuntimeOperationResult.failed(&"invalid_party_defeat_handoff", "The suspended total-party defeat no longer matches its battle caller.")
	var caller := handoff.caller
	if caller.kind == ScenarioBattleCaller.CLASSIC and caller.opcode == 56 and caller.branch_target == -1:
		return ScenarioRuntimeOperationResult.failed(&"classic_battle_loss_return_unresolved", "Classic opcode 56 uses a distinct experience-loss and party-backup return that is not yet available.")
	var combat := _game_state.combat
	var battle_id := combat.battle_id
	var directive: ScenarioVmDirective
	if caller.kind == ScenarioBattleCaller.CLASSIC:
		match caller.opcode:
			56:
				directive = ScenarioVmDirective.branch_xap(caller.branch_target, caller.gosub)
			107:
				directive = ScenarioVmDirective.branch_xap(caller.branch_target, false)
	combat.outcome = &"retreated"
	_game_state.last_battle_outcome = &"retreated"
	var events: Array[DomainEvent] = [
		DomainEvent.new(&"party_defeat_revived", {"battleId": battle_id, "source": "classic-party-death-hook", "callerOpcode": caller.opcode if caller.kind == ScenarioBattleCaller.CLASSIC else 0}),
		DomainEvent.new(&"battle_returned", {"battleId": battle_id, "outcome": "retreated"}),
	]
	_game_state.combat = null
	return ScenarioRuntimeOperationResult.completed(battle_id, events, directive)


func start_battle_definition(battle: BattleDefinition, request_id: String, source: String, caller: ScenarioBattleCaller, participant_character_ids: Array[String] = []) -> ScenarioRuntimeOperationResult:
	var result := _rules.combat_flow.start_battle(_game_state, _content, battle, _rng, 0, participant_character_ids)
	if not result.ok:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	var events: Array[DomainEvent] = []
	if battle.message_before_id != 0:
		var before := _content.scenario_records.message_by_id(absi(battle.message_before_id))
		if before == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Battle '%s' references unavailable before-message %d." % [battle.id, battle.message_before_id])
		events.append(DomainEvent.new(&"message_shown", {"messageId": before.id, "text": before.text, "source": "classic-battle-definition"}))
	events.append_array(result.events)
	var continuation_kind := ScenarioRuntimeContinuation.SAFE_COMBAT if source == "scenario-action" else ScenarioRuntimeContinuation.CLASSIC_COMBAT
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _wait_for_combat_age_updates(continuation_kind, caller, request_id, events, _game_state.combat.turns.round_number)
	if not _death_macro_request(result.events).is_empty():
		return _run_combat_death_macro(continuation_kind, caller, events, request_id)
	if result.completed:
		return _finish_battle_with_allies(continuation_kind, caller, request_id, events)
	return ScenarioRuntimeOperationResult.waiting(_request_builder.build(request_id), ScenarioCombatContinuations.battle(continuation_kind, battle.id, caller), events)


func _resume_battle(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.CombatBody
	if response.kind != &"combat_action" or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat response requires actorId, action, and optional targetId strings.")
	var combat_continuation := continuation.body as ScenarioCombatContinuationBody
	if _game_state.combat == null or _game_state.combat.battle_id != combat_continuation.battle_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending battle is unavailable.")
	var caller := combat_continuation.caller
	if caller == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending battle lost its originating caller.")
	var previous_round := _game_state.combat.turns.round_number
	var dispatch: Variant = _dispatch_combat_response(body, continuation, request_id)
	if dispatch is ScenarioRuntimeOperationResult:
		return dispatch
	var result := dispatch as CombatFlowResult
	return _continue_after_combat_result(result, body, continuation, caller, previous_round, request_id)


func _dispatch_combat_response(body: InteractionResponse.CombatBody, continuation: ScenarioRuntimeContinuation, request_id: String) -> Variant:
	match body.action:
		&"set_auto":
			return _set_combat_auto(body, continuation, request_id)
		&"retreat":
			return _request_explicit_retreat(body.actor_id, continuation, request_id)
		&"retreat_edge":
			return _request_edge_retreat(body, continuation, request_id)
		_:
			return _execute_combat_action(body)


func _set_combat_auto(body: InteractionResponse.CombatBody, continuation: ScenarioRuntimeContinuation, request_id: String) -> Variant:
	if _game_state.party.character_by_id(body.actor_id) == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Persistent Auto requires a party character and an enabled boolean.")
	var state_checkpoint := _game_state.to_data()
	var rng_checkpoint := _rng.checkpoint()
	if not _game_state.set_combat_auto(body.actor_id, body.enabled):
		return ScenarioRuntimeOperationResult.failed(&"invalid_combat_auto_character", "Persistent Auto could not be changed for this character.")
	var events: Array[DomainEvent] = [
		DomainEvent.new(&"sound_requested", {"soundId": 147 if body.enabled else 139, "waitForCompletion": false, "source": "classic-combat-auto-toggle"}),
		DomainEvent.new(&"combat_auto_changed", {"characterId": body.actor_id, "enabled": body.enabled, "source": "classic"}),
	]
	if not body.enabled or _game_state.combat.turns.active_actor_id() != body.actor_id:
		return ScenarioRuntimeOperationResult.waiting(_request_builder.build(request_id), continuation, events)
	events.append(DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-combat-auto-button"}))
	var result := _rules.combat_flow.run_persistent_auto_characters(_game_state, _content, _rng)
	if not result.ok:
		if not _game_state.restore_from_data(state_checkpoint) or not _rng.rollback(rng_checkpoint):
			return ScenarioRuntimeOperationResult.failed(&"combat_auto_rollback_failed", "Persistent Auto failed and could not restore its toggle transaction.")
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	var combined_events: Array[DomainEvent] = []
	combined_events.append_array(events)
	combined_events.append_array(result.events)
	result.events = combined_events
	return result


func _request_explicit_retreat(actor_id: String, continuation: ScenarioRuntimeContinuation, request_id: String) -> ScenarioRuntimeOperationResult:
	var probe: Variant = _rules.combat_flow.reactions.probe_character_retreat(_game_state.combat, _game_state.party.characters(), actor_id)
	if not probe.allowed:
		return ScenarioRuntimeOperationResult.failed(probe.reason, probe.reason_text)
	return _wait_for_battle_retreat(continuation, actor_id, &"explicit", CombatFlow.INVALID_COORDINATE, request_id)


func _request_edge_retreat(body: InteractionResponse.CombatBody, continuation: ScenarioRuntimeContinuation, request_id: String) -> Variant:
	var destination := body.destination if body.has_destination else CombatFlow.INVALID_COORDINATE
	var probe: Variant = _rules.combat_flow.reactions.probe_edge_retreat(_game_state.combat, body.actor_id, destination)
	if not probe.allowed:
		return ScenarioRuntimeOperationResult.failed(probe.reason, probe.reason_text)
	if not probe.forced:
		return _wait_for_battle_retreat(continuation, body.actor_id, &"edge", destination, request_id)
	return _rules.combat_flow.retreat_character(_game_state, _content, body.actor_id, &"edge", destination, _rng)


func _execute_combat_action(body: InteractionResponse.CombatBody) -> Variant:
	match body.action:
		&"move":
			if not body.has_destination:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat movement requires a two-integer destination.")
			return _rules.combat_flow.move_character(_game_state, _content, body.actor_id, body.destination, _rng, body.auto_switch_to_melee)
		&"cast_spell":
			if body.spell_id.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat spell casting requires a spellId string and integer power.")
			var target := body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE
			return _rules.combat_flow.cast_spell(_game_state, _content, body.actor_id, body.target_id, body.spell_id, body.power, _rng, target, body.rotation, body.target_ids, body.target_coordinates)
		&"use_item":
			if body.item_instance_id.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat item use requires an itemInstanceId string.")
			var target := body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE
			return _rules.combat_flow.use_spell_item(_game_state, _content, body.actor_id, body.target_id, body.item_instance_id, _rng, target, body.rotation, body.target_ids, body.target_coordinates)
		&"use_scroll":
			if body.scroll_slot < 0:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat scroll use requires an integer scrollSlot.")
			var target := body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE
			return _rules.combat_flow.use_combat_scroll(_game_state, _content, body.actor_id, body.scroll_slot, body.target_id, _rng, target, body.rotation, body.target_ids, body.target_coordinates)
	return _rules.combat_flow.submit_action(_game_state, _content, body.actor_id, body.action, body.target_id, _rng)


func _continue_after_combat_result(result: CombatFlowResult, body: InteractionResponse.CombatBody, continuation: ScenarioRuntimeContinuation, caller: ScenarioBattleCaller, previous_round: int, request_id: String) -> ScenarioRuntimeOperationResult:
	if not result.ok:
		if body.action == &"move" and result.error_code == &"melee_weapon_mode_required":
			var warning_events: Array[DomainEvent] = [
				DomainEvent.new(&"sound_requested", {"soundId": 6000, "waitForCompletion": false, "source": "classic-auto-weapon-switch-warning"}),
				DomainEvent.new(&"combat_action_unavailable", {"actorId": body.actor_id, "action": "move", "reason": String(result.error_code), "message": result.error_message, "source": "classic"}),
			]
			return ScenarioRuntimeOperationResult.waiting(_request_builder.build(request_id), continuation, warning_events)
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _wait_for_combat_age_updates(continuation.kind, caller, request_id, result.events, previous_round)
	if not _death_macro_request(result.events).is_empty():
		return _run_combat_death_macro(continuation.kind, caller, result.events, request_id)
	if result.completed:
		var completed_events: Array[DomainEvent] = []
		completed_events.assign(result.events)
		return _finish_battle_with_allies(continuation.kind, caller, request_id, completed_events)
	if _game_state.combat.turns.round_number > previous_round and _game_state.combat.macro_id < 0:
		return _run_battle_macro(continuation.kind, caller, result.events, request_id)
	return ScenarioRuntimeOperationResult.waiting(_request_builder.build(request_id), continuation, result.events)


func _wait_for_battle_retreat(continuation: ScenarioRuntimeContinuation, actor_id: String, mode: StringName, destination: Vector2i, request_id: String) -> ScenarioRuntimeOperationResult:
	var source_kind := continuation.kind
	var combat_continuation := continuation.body as ScenarioCombatContinuationBody
	var retreat_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_RETREAT if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_RETREAT
	var next_continuation := ScenarioCombatContinuations.retreat(retreat_kind, source_kind, _game_state.combat.battle_id, combat_continuation.caller, actor_id, mode, destination)
	var request := InteractionRequest.yes_no(request_id, "Will this character flee from battle?", "Embrace Cowardice", "Stay and Fight")
	return ScenarioRuntimeOperationResult.waiting(request, next_continuation)


func _resume_battle_retreat(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Escape confirmation requires a yes/no response.")
	var combat_continuation := continuation.body as ScenarioCombatContinuationBody
	if _game_state.combat == null or _game_state.combat.completed or _game_state.combat.battle_id != combat_continuation.battle_id or _game_state.combat.turns.active_actor_id() != combat_continuation.actor_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The character awaiting Escape confirmation is unavailable.")
	var source_kind := combat_continuation.source_kind
	var caller := combat_continuation.caller
	if caller == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending retreat lost its originating battle caller.")
	var mode := combat_continuation.mode
	var destination := combat_continuation.destination
	var probe: Variant = _rules.combat_flow.reactions.probe_character_retreat(_game_state.combat, _game_state.party.characters(), combat_continuation.actor_id) if mode == &"explicit" else _rules.combat_flow.reactions.probe_edge_retreat(_game_state.combat, combat_continuation.actor_id, destination) if mode == &"edge" else null
	if probe == null or not probe.allowed or probe.forced:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The saved Escape confirmation no longer represents a promptable Classic action.")
	if not body.accepted:
		return ScenarioRuntimeOperationResult.waiting(_request_builder.build(request_id), ScenarioCombatContinuations.battle(source_kind, combat_continuation.battle_id, caller), [DomainEvent.new(&"combat_retreat_declined", {"actorId": combat_continuation.actor_id, "mode": String(mode), "source": "classic"})])
	var previous_round := _game_state.combat.turns.round_number
	var result := _rules.combat_flow.retreat_character(_game_state, _content, combat_continuation.actor_id, mode, destination, _rng)
	if not result.ok:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _wait_for_combat_age_updates(source_kind, caller, request_id, result.events, previous_round)
	if not _death_macro_request(result.events).is_empty():
		return _run_combat_death_macro(source_kind, caller, result.events, request_id)
	if result.completed:
		var completed_events: Array[DomainEvent] = []
		completed_events.assign(result.events)
		return _finish_battle_with_allies(source_kind, caller, request_id, completed_events)
	if _game_state.combat.turns.round_number > previous_round and _game_state.combat.macro_id < 0:
		return _run_battle_macro(source_kind, caller, result.events, request_id)
	return ScenarioRuntimeOperationResult.waiting(_request_builder.build(request_id), ScenarioCombatContinuations.battle(source_kind, combat_continuation.battle_id, caller), result.events)


func _finish_battle_with_allies(source_kind: StringName, caller: ScenarioBattleCaller, request_id: String, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null or not combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Post-battle ally selection requires a completed battle.")
	if caller.kind == ScenarioBattleCaller.CLASSIC and caller.opcode == 2 and caller.mode == 10:
		var mode_ten: ScenarioRuntimeOperationResult = _rewards.begin_completed_battle_reward(request_id, caller)
		mode_ten.events = events + mode_ten.events
		return mode_ten
	if combat.outcome == &"defeat":
		if caller.kind == ScenarioBattleCaller.CLASSIC and caller.opcode == 48:
			var battle_id := combat.battle_id
			var participant_ids: Array[String] = []
			for actor_id: String in combat.turns.turn_order():
				if _game_state.party.character_by_id(actor_id) != null:
					participant_ids.append(actor_id)
			var defeat_events: Array[DomainEvent] = []
			defeat_events.assign(events)
			defeat_events.append(DomainEvent.new(&"classic_notification_requested", {"text": "There is nobody left to collect any treasure.", "soundId": 6000, "source": "classic-opcode-48"}))
			defeat_events.append(DomainEvent.new(&"battle_returned", {"battleId": battle_id, "outcome": "defeat", "participantCharacterIds": participant_ids}))
			_game_state.combat = null
			return ScenarioRuntimeOperationResult.completed(battle_id, defeat_events)
		return ScenarioRuntimeOperationResult.suspended(ScenarioRuntimeHandoff.party_defeat(combat.battle_id, source_kind, caller), events)
	var payload := _rules.combat_flow.rounds.ally_selection_payload(_game_state, _content)
	if not payload.is_empty():
		var ally_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_ALLY if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_ALLY
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.from_payload(request_id, &"ally_selection", payload), ScenarioCombatContinuations.terminal(ally_kind, source_kind, combat.battle_id, caller), events)
	return _finish_battle_with_fumbles(source_kind, caller, request_id, events)


func _finish_battle_with_fumbles(source_kind: StringName, caller: ScenarioBattleCaller, request_id: String, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null or not combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Post-battle fumbled-weapon recovery requires a completed battle.")
	var reward: ScenarioRuntimeOperationResult = _rewards.begin_completed_battle_reward(request_id, caller)
	reward.events = events + reward.events
	return reward


func _resume_ally_selection(continuation: ScenarioRuntimeContinuation, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.AllySelectionBody
	if response.kind != &"ally_selection" or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Ally selection requires selectedIds.")
	var combat_continuation := continuation.body as ScenarioCombatContinuationBody
	if _game_state.combat == null or not _game_state.combat.completed or _game_state.combat.battle_id != combat_continuation.battle_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The completed battle is unavailable for ally selection.")
	if _rules.combat_flow.rounds.ally_selection_payload(_game_state, _content).is_empty():
		return _finish_battle_with_fumbles(combat_continuation.source_kind, combat_continuation.caller, String(response.request_id), [])
	var selected := _rules.combat_flow.apply_ally_selection(_game_state, _content, body.selected_ids)
	if not selected.ok:
		return ScenarioRuntimeOperationResult.failed(selected.error_code, selected.error_message)
	var events: Array[DomainEvent] = []
	events.assign(selected.events)
	return _finish_battle_with_fumbles(combat_continuation.source_kind, combat_continuation.caller, String(response.request_id), events)


func _resume_fumble_recovery(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.TreasureBody
	if response.kind != InteractionRequest.TREASURE_DISTRIBUTION or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Fumbled-weapon recovery requires a treasure-distribution response.")
	var combat_continuation := continuation.body as ScenarioCombatContinuationBody
	if _game_state.combat == null or not _game_state.combat.completed or _game_state.combat.battle_id != combat_continuation.battle_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The completed battle is unavailable for fumbled-weapon recovery.")
	var recovered := _rules.combat_flow.apply_fumble_recovery(_game_state, _content, body.action, body.instance_id, body.character_id)
	if not recovered.ok:
		return ScenarioRuntimeOperationResult.failed(recovered.error_code, recovered.error_message)
	var events: Array[DomainEvent] = []
	events.assign(recovered.events)
	return _finish_battle_with_fumbles(combat_continuation.source_kind, combat_continuation.caller, request_id, events)


func _run_battle_macro(source_kind: StringName, caller: ScenarioBattleCaller, preceding_events: Array[DomainEvent], request_id: String) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null or combat.completed or combat.macro_id >= 0:
		return ScenarioRuntimeOperationResult.waiting(_request_builder.build(request_id), ScenarioCombatContinuations.battle(source_kind, combat.battle_id, caller), preceding_events)
	var program_id := "xap:%d" % absi(combat.macro_id)
	var vm := ScenarioVm.new()
	vm.configure(_content.scenario)
	var macro_context := ScenarioExecutionContext.calling(&"battle-macro").set_battle(combat.battle_id)
	var started := vm.start_program(program_id, macro_context)
	if started.state == ScenarioVmResult.State.FAILED:
		return ScenarioRuntimeOperationResult.failed(started.error_code, started.error_message)
	var result := vm.run(_runtime_api())
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	events.append(DomainEvent.new(&"battle_macro_started", {"battleId": combat.battle_id, "programId": program_id, "round": combat.turns.round_number}))
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.FAILED:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return ScenarioRuntimeOperationResult.failed(&"nested_host_handoff", "A battle macro cannot suspend a second battle into the application host.")
	if result.state == ScenarioVmResult.State.WAITING:
		var macro_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_MACRO if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_MACRO
		return ScenarioRuntimeOperationResult.waiting(result.interaction, ScenarioCombatContinuations.macro(macro_kind, source_kind, combat.battle_id, caller, program_id, vm.snapshot()), events)
	return _continue_after_battle_macro(source_kind, caller, request_id, program_id, events)


func _resume_battle_macro(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var combat_continuation := continuation.body as ScenarioCombatContinuationBody
	if _game_state.combat == null or _game_state.combat.battle_id != combat_continuation.battle_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending battle macro is unavailable.")
	var snapshot := combat_continuation.macro_vm
	if snapshot == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_macro_continuation", "The pending battle macro state is invalid.")
	var vm := ScenarioVm.new()
	vm.configure(_content.scenario)
	if not vm.restore(snapshot):
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_macro_continuation", "The pending battle macro cannot be restored.")
	var result := vm.resume(response, _runtime_api())
	if result.state == ScenarioVmResult.State.FAILED:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return ScenarioRuntimeOperationResult.failed(&"nested_host_handoff", "A resumed battle macro cannot suspend a second battle into the application host.")
	if result.state == ScenarioVmResult.State.WAITING:
		var next_continuation := ScenarioCombatContinuations.macro(continuation.kind, combat_continuation.source_kind, combat_continuation.battle_id, combat_continuation.caller, combat_continuation.program_id, vm.snapshot())
		return ScenarioRuntimeOperationResult.waiting(result.interaction, next_continuation, result.events)
	return _continue_after_battle_macro(combat_continuation.source_kind, combat_continuation.caller, request_id, combat_continuation.program_id, result.events)


func _continue_after_battle_macro(source_kind: StringName, caller: ScenarioBattleCaller, request_id: String, program_id: String, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var committed: Array[DomainEvent] = []
	committed.assign(events)
	committed.append(DomainEvent.new(&"battle_macro_completed", {"battleId": _game_state.combat.battle_id, "programId": program_id, "round": _game_state.combat.turns.round_number}))
	if _game_state.combat.completed:
		return _finish_battle_with_allies(source_kind, caller, request_id, committed)
	return ScenarioRuntimeOperationResult.waiting(_request_builder.build(request_id), ScenarioCombatContinuations.battle(source_kind, _game_state.combat.battle_id, caller), committed)


func _run_combat_death_macro(source_kind: StringName, caller: ScenarioBattleCaller, preceding_events: Array[DomainEvent], request_id: String) -> ScenarioRuntimeOperationResult:
	var request := _death_macro_request(preceding_events)
	var combat := _game_state.combat
	if request.is_empty() or combat == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_death_macro_request", "Monster death-macro execution requires an active combatant request.")
	var combatant_id := str(request.get("combatantId", ""))
	var program_id := str(request.get("programId", ""))
	var monster := combat.roster.monster_by_id(combatant_id)
	if monster == null or program_id.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_death_macro_request", "Monster death-macro execution references unavailable content.")
	var vm := ScenarioVm.new()
	vm.configure(_content.scenario)
	var death_context := ScenarioExecutionContext.calling(&"monster-death-macro")
	death_context.set_battle(combat.battle_id)
	death_context.set_combatant(combatant_id, int(request.get("classicMonsterId", 0)), bool(request.get("traitor", monster.traitor)), true)
	var started := vm.start_program(program_id, death_context)
	if started.state == ScenarioVmResult.State.FAILED:
		return ScenarioRuntimeOperationResult.failed(started.error_code, started.error_message)
	var result := vm.run(_runtime_api())
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	events.append(DomainEvent.new(&"monster_death_macro_started", {"battleId": combat.battle_id, "combatantId": combatant_id, "programId": program_id}))
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.FAILED:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return ScenarioRuntimeOperationResult.failed(&"nested_host_handoff", "A monster death macro cannot suspend a second battle into the application host.")
	if result.state == ScenarioVmResult.State.WAITING:
		var macro_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_DEATH_MACRO if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_DEATH_MACRO
		return ScenarioRuntimeOperationResult.waiting(result.interaction, ScenarioCombatContinuations.macro(macro_kind, source_kind, combat.battle_id, caller, program_id, vm.snapshot(), combatant_id, bool(request.get("resetTraitorOnComplete", true))), events)
	return _continue_after_combat_death_macro(source_kind, caller, request_id, combatant_id, program_id, events, bool(request.get("resetTraitorOnComplete", true)))


func _resume_combat_death_macro(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var combat_continuation := continuation.body as ScenarioCombatContinuationBody
	if _game_state.combat == null or _game_state.combat.battle_id != combat_continuation.battle_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending monster death macro is unavailable.")
	var snapshot := combat_continuation.macro_vm
	if snapshot == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_death_macro_continuation", "The pending monster death-macro state is invalid.")
	var vm := ScenarioVm.new()
	vm.configure(_content.scenario)
	if not vm.restore(snapshot):
		return ScenarioRuntimeOperationResult.failed(&"invalid_death_macro_continuation", "The pending monster death macro cannot be restored.")
	var result := vm.resume(response, _runtime_api())
	if result.state == ScenarioVmResult.State.FAILED:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return ScenarioRuntimeOperationResult.failed(&"nested_host_handoff", "A resumed monster death macro cannot suspend a second battle into the application host.")
	if result.state == ScenarioVmResult.State.WAITING:
		var next_continuation := ScenarioCombatContinuations.macro(continuation.kind, combat_continuation.source_kind, combat_continuation.battle_id, combat_continuation.caller, combat_continuation.program_id, vm.snapshot(), combat_continuation.combatant_id, combat_continuation.reset_traitor_on_complete)
		return ScenarioRuntimeOperationResult.waiting(result.interaction, next_continuation, result.events)
	return _continue_after_combat_death_macro(combat_continuation.source_kind, combat_continuation.caller, request_id, combat_continuation.combatant_id, combat_continuation.program_id, result.events, combat_continuation.reset_traitor_on_complete)


func _continue_after_combat_death_macro(source_kind: StringName, caller: ScenarioBattleCaller, request_id: String, combatant_id: String, program_id: String, events: Array[DomainEvent], reset_traitor_on_complete: bool = true) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Monster death-macro completion lost its battle.")
	var monster := combat.roster.monster_by_id(combatant_id)
	if monster != null and reset_traitor_on_complete:
		monster.traitor = false
	var committed: Array[DomainEvent] = []
	committed.assign(events)
	committed.append(DomainEvent.new(&"monster_death_macro_completed", {"battleId": combat.battle_id, "combatantId": combatant_id, "programId": program_id, "revived": monster != null and monster.current_health > 0}))
	var previous_round := combat.turns.round_number
	var continued := _rules.combat_flow.continue_after_monster_death_macro(_game_state, _content, _rng, combatant_id)
	if not continued.ok:
		return ScenarioRuntimeOperationResult.failed(continued.error_code, continued.error_message)
	committed.append_array(continued.events)
	if not CharacterAgingResult.update_payloads(continued.events).is_empty():
		return _wait_for_combat_age_updates(source_kind, caller, request_id, committed, previous_round)
	if not _death_macro_request(continued.events).is_empty():
		return _run_combat_death_macro(source_kind, caller, committed, request_id)
	if continued.completed:
		return _finish_battle_with_allies(source_kind, caller, request_id, committed)
	return ScenarioRuntimeOperationResult.waiting(_request_builder.build(request_id), ScenarioCombatContinuations.battle(source_kind, combat.battle_id, caller), committed)


func _wait_for_combat_age_updates(source_kind: StringName, caller: ScenarioBattleCaller, request_id: String, events: Array[DomainEvent], round_before: int) -> ScenarioRuntimeOperationResult:
	var updates := CharacterAgingResult.update_bodies(events)
	if updates.is_empty() or _game_state.combat == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_combat_age_update", "Monster aging did not provide a valid combat continuation.")
	var age_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_AGE if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_AGE
	var continuation := ScenarioCombatContinuations.age_updates(age_kind, source_kind, _game_state.combat.battle_id, caller, updates, 1, round_before)
	var committed: Array[DomainEvent] = []
	committed.assign(events)
	committed.append(CharacterAgingResult.sound_event_for_update(updates[0]))
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update_body(request_id, updates[0]), continuation, committed)


func _resume_combat_age_updates(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != InteractionRequest.AGE_UPDATE or response.body is not InteractionResponse.EmptyBody:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic combat age updates require an empty acknowledgement.")
	var combat_continuation := continuation.body as ScenarioCombatContinuationBody
	if _game_state.combat == null or _game_state.combat.battle_id != combat_continuation.battle_id or _game_state.combat.pending_monster_attack == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The monster age-update battle is unavailable.")
	var updates := combat_continuation.updates
	var index := combat_continuation.index
	if updates.is_empty() or index < 1 or index > updates.size():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_continuation", "The combat age-update queue is invalid.")
	var acknowledged: AgeUpdateRequestBody = updates[index - 1]
	var events: Array[DomainEvent] = [DomainEvent.new(&"character_age_update_acknowledged", {"characterId": acknowledged.character_id})]
	if index < updates.size():
		var next_payload: AgeUpdateRequestBody = updates[index]
		var next_continuation := ScenarioCombatContinuations.age_updates(continuation.kind, combat_continuation.source_kind, combat_continuation.battle_id, combat_continuation.caller, updates, index + 1, combat_continuation.round_before)
		events.append(CharacterAgingResult.sound_event_for_update(next_payload))
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update_body(request_id, next_payload), next_continuation, events)
	var source_kind := combat_continuation.source_kind
	var caller := combat_continuation.caller
	if caller == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The combat age update lost its originating battle caller.")
	var round_before := combat_continuation.round_before
	var continued := _rules.combat_flow.continue_after_age_update(_game_state, _content, _rng)
	if not continued.ok:
		return ScenarioRuntimeOperationResult.failed(continued.error_code, continued.error_message)
	events.append_array(continued.events)
	if not CharacterAgingResult.update_payloads(continued.events).is_empty():
		return _wait_for_combat_age_updates(source_kind, caller, request_id, events, round_before)
	if not _death_macro_request(continued.events).is_empty():
		return _run_combat_death_macro(source_kind, caller, events, request_id)
	if continued.completed:
		return _finish_battle_with_allies(source_kind, caller, request_id, events)
	if _game_state.combat.turns.round_number > round_before and _game_state.combat.macro_id < 0:
		return _run_battle_macro(source_kind, caller, events, request_id)
	return ScenarioRuntimeOperationResult.waiting(_request_builder.build(request_id), ScenarioCombatContinuations.battle(source_kind, _game_state.combat.battle_id, caller), events)


static func _death_macro_request(events: Array[DomainEvent]) -> Dictionary:
	for index: int in range(events.size() - 1, -1, -1):
		var event := events[index]
		if event.kind == &"monster_death_macro_requested":
			return event.payload
	return {}
