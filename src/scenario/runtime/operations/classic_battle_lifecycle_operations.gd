class_name ClassicBattleLifecycleOperations
extends RefCounted

var _content: RealmzContent
var _game_state: GameState
var _rng: RealmzRng
var _rules: RealmzRules
var _rewards: RefCounted
var _runtime_api_ref: WeakRef


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, rules: RealmzRules, rewards: RefCounted) -> void:
	_content = content
	_game_state = game_state
	_rng = rng
	_rules = rules
	_rewards = rewards


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


func complete_debug_victory(continuation: ScenarioRuntimeContinuation, request_id: String, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	if continuation == null or continuation.kind not in [ScenarioRuntimeContinuation.CLASSIC_COMBAT, ScenarioRuntimeContinuation.SAFE_COMBAT]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Debug victory requires the active combat command continuation.")
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
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
			var message := _content.message_by_id(absi(message_id))
			if message == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode %d references unavailable battle message %d." % [action.opcode, message_id])
			prelude.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-battle"}))
	var caller_mode := action.extra_code[4] if action.opcode in [2, 48] and action.extra_code.size() > 4 else 0
	var caller := ScenarioBattleCaller.classic(action.opcode, action.gosub, caller_mode, action.extra_code[4] if action.opcode == 107 and action.extra_code.size() > 4 else action.extra_code[2] if action.opcode == 56 and action.extra_code.size() > 2 else 0)
	var battle := _content.battle_by_classic_id(absi(battle_id))
	if battle == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_battle", "Classic opcode %d references unavailable battle %d." % [action.opcode, battle_id])
	var participants: Array[String] = []
	if action.opcode == 48:
		participants = _game_state.selected_character_ids()
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
		var before := _content.message_by_id(absi(battle.message_before_id))
		if before == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Battle '%s' references unavailable before-message %d." % [battle.id, battle.message_before_id])
		events.append(DomainEvent.new(&"message_shown", {"messageId": before.id, "text": before.text, "source": "classic-battle-definition"}))
	events.append_array(result.events)
	var continuation_kind := ScenarioRuntimeContinuation.SAFE_COMBAT if source == "scenario-action" else ScenarioRuntimeContinuation.CLASSIC_COMBAT
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _wait_for_combat_age_updates(continuation_kind, caller, request_id, events, _game_state.combat.round_number)
	if not _death_macro_request(result.events).is_empty():
		return _run_combat_death_macro(continuation_kind, caller, events, request_id)
	if result.completed:
		return _finish_battle_with_allies(continuation_kind, caller, request_id, events)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), ScenarioRuntimeContinuation.combat(continuation_kind, battle.id, caller), events)


func _resume_battle(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.CombatBody
	if response.kind != &"combat_action" or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat response requires actorId, action, and optional targetId strings.")
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
	if _game_state.combat == null or _game_state.combat.battle_id != combat_continuation.battle_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending battle is unavailable.")
	var previous_round := _game_state.combat.round_number
	var caller := combat_continuation.caller
	if caller == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending battle lost its originating caller.")
	var result: CombatFlowResult
	if body.action == &"set_auto":
		if _game_state.party.character_by_id(body.actor_id) == null:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Persistent Auto requires a party character and an enabled boolean.")
		var auto_state_checkpoint := _game_state.to_data()
		var auto_rng_checkpoint := _rng.checkpoint()
		if not _game_state.set_combat_auto(body.actor_id, body.enabled):
			return ScenarioRuntimeOperationResult.failed(&"invalid_combat_auto_character", "Persistent Auto could not be changed for this character.")
		var toggle_sound := 147 if body.enabled else 139
		var auto_events: Array[DomainEvent] = [
			DomainEvent.new(&"sound_requested", {"soundId": toggle_sound, "waitForCompletion": false, "source": "classic-combat-auto-toggle"}),
			DomainEvent.new(&"combat_auto_changed", {"characterId": body.actor_id, "enabled": body.enabled, "source": "classic"}),
		]
		if not body.enabled or _game_state.combat.active_actor_id() != body.actor_id:
			return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), continuation, auto_events)
		auto_events.append(DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-combat-auto-button"}))
		result = _rules.combat_flow.run_persistent_auto_characters(_game_state, _content, _rng)
		if not result.ok:
			if not _game_state.restore_from_data(auto_state_checkpoint) or not _rng.rollback(auto_rng_checkpoint):
				return ScenarioRuntimeOperationResult.failed(&"combat_auto_rollback_failed", "Persistent Auto failed and could not restore its toggle transaction.")
			return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
		if result.ok:
			var combined_events: Array[DomainEvent] = []
			combined_events.append_array(auto_events)
			combined_events.append_array(result.events)
			result.events = combined_events
	elif body.action == &"retreat":
		var retreat_probe: Variant = _rules.combat_flow.probe_character_retreat(_game_state.combat, _game_state.party.characters(), body.actor_id)
		if not retreat_probe.allowed:
			return ScenarioRuntimeOperationResult.failed(retreat_probe.reason, retreat_probe.reason_text)
		return _wait_for_battle_retreat(continuation, body.actor_id, &"explicit", Vector2i(-100_000, -100_000), request_id)
	elif body.action == &"retreat_edge":
		var edge_destination := body.destination if body.has_destination else CombatFlow.INVALID_COORDINATE
		var edge_probe: Variant = _rules.combat_flow.probe_edge_retreat(_game_state.combat, body.actor_id, edge_destination)
		if not edge_probe.allowed:
			return ScenarioRuntimeOperationResult.failed(edge_probe.reason, edge_probe.reason_text)
		if not edge_probe.forced:
			return _wait_for_battle_retreat(continuation, body.actor_id, &"edge", edge_destination, request_id)
		result = _rules.combat_flow.retreat_character(_game_state, _content, body.actor_id, &"edge", edge_destination, _rng)
	elif body.action == &"move":
		if not body.has_destination:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat movement requires a two-integer destination.")
		result = _rules.combat_flow.move_character(_game_state, _content, body.actor_id, body.destination, _rng, body.auto_switch_to_melee)
	elif body.action == &"cast_spell":
		if body.spell_id.is_empty():
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat spell casting requires a spellId string and integer power.")
		var target_coordinate := body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE
		result = _rules.combat_flow.cast_spell(_game_state, _content, body.actor_id, body.target_id, body.spell_id, body.power, _rng, target_coordinate, body.rotation, body.target_ids, body.target_coordinates)
	elif body.action == &"use_item":
		if body.item_instance_id.is_empty():
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat item use requires an itemInstanceId string.")
		var item_target_coordinate := body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE
		result = _rules.combat_flow.use_spell_item(_game_state, _content, body.actor_id, body.target_id, body.item_instance_id, _rng, item_target_coordinate, body.rotation, body.target_ids, body.target_coordinates)
	elif body.action == &"use_scroll":
		if body.scroll_slot < 0:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat scroll use requires an integer scrollSlot.")
		var scroll_target_coordinate := body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE
		result = _rules.combat_flow.use_combat_scroll(_game_state, _content, body.actor_id, body.scroll_slot, body.target_id, _rng, scroll_target_coordinate, body.rotation, body.target_ids, body.target_coordinates)
	else:
		result = _rules.combat_flow.submit_action(_game_state, _content, body.actor_id, body.action, body.target_id, _rng)
	if not result.ok:
		if body.action == &"move" and result.error_code == &"melee_weapon_mode_required":
			var warning_events: Array[DomainEvent] = [
				DomainEvent.new(&"sound_requested", {"soundId": 6000, "waitForCompletion": false, "source": "classic-auto-weapon-switch-warning"}),
				DomainEvent.new(&"combat_action_unavailable", {"actorId": body.actor_id, "action": "move", "reason": String(result.error_code), "message": result.error_message, "source": "classic"}),
			]
			return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), continuation, warning_events)
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _wait_for_combat_age_updates(continuation.kind, caller, request_id, result.events, previous_round)
	if not _death_macro_request(result.events).is_empty():
		return _run_combat_death_macro(continuation.kind, caller, result.events, request_id)
	if result.completed:
		var completed_events: Array[DomainEvent] = []
		completed_events.assign(result.events)
		return _finish_battle_with_allies(continuation.kind, caller, request_id, completed_events)
	if _game_state.combat.round_number > previous_round and _game_state.combat.macro_id < 0:
		return _run_battle_macro(continuation.kind, caller, result.events, request_id)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), continuation, result.events)


func _wait_for_battle_retreat(continuation: ScenarioRuntimeContinuation, actor_id: String, mode: StringName, destination: Vector2i, request_id: String) -> ScenarioRuntimeOperationResult:
	var source_kind := continuation.kind
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
	var retreat_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_RETREAT if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_RETREAT
	var next_continuation := ScenarioRuntimeContinuation.combat_retreat(retreat_kind, source_kind, _game_state.combat.battle_id, combat_continuation.caller, actor_id, mode, destination)
	var request := InteractionRequest.yes_no(request_id, "Will this character flee from battle?", "Embrace Cowardice", "Stay and Fight")
	return ScenarioRuntimeOperationResult.waiting(request, next_continuation)


func _resume_battle_retreat(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Escape confirmation requires a yes/no response.")
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
	if _game_state.combat == null or _game_state.combat.completed or _game_state.combat.battle_id != combat_continuation.battle_id or _game_state.combat.active_actor_id() != combat_continuation.actor_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The character awaiting Escape confirmation is unavailable.")
	var source_kind := combat_continuation.source_kind
	var caller := combat_continuation.caller
	if caller == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending retreat lost its originating battle caller.")
	var mode := combat_continuation.mode
	var destination := combat_continuation.destination
	var probe: Variant = _rules.combat_flow.probe_character_retreat(_game_state.combat, _game_state.party.characters(), combat_continuation.actor_id) if mode == &"explicit" else _rules.combat_flow.probe_edge_retreat(_game_state.combat, combat_continuation.actor_id, destination) if mode == &"edge" else null
	if probe == null or not probe.allowed or probe.forced:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The saved Escape confirmation no longer represents a promptable Classic action.")
	if not body.accepted:
		return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), ScenarioRuntimeContinuation.combat(source_kind, combat_continuation.battle_id, caller), [DomainEvent.new(&"combat_retreat_declined", {"actorId": combat_continuation.actor_id, "mode": String(mode), "source": "classic"})])
	var previous_round := _game_state.combat.round_number
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
	if _game_state.combat.round_number > previous_round and _game_state.combat.macro_id < 0:
		return _run_battle_macro(source_kind, caller, result.events, request_id)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), ScenarioRuntimeContinuation.combat(source_kind, combat_continuation.battle_id, caller), result.events)


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
			for actor_id: String in combat.turn_order():
				if _game_state.party.character_by_id(actor_id) != null:
					participant_ids.append(actor_id)
			var defeat_events: Array[DomainEvent] = []
			defeat_events.assign(events)
			defeat_events.append(DomainEvent.new(&"classic_notification_requested", {"text": "There is nobody left to collect any treasure.", "soundId": 6000, "source": "classic-opcode-48"}))
			defeat_events.append(DomainEvent.new(&"battle_returned", {"battleId": battle_id, "outcome": "defeat", "participantCharacterIds": participant_ids}))
			_game_state.combat = null
			return ScenarioRuntimeOperationResult.completed(battle_id, defeat_events)
		return ScenarioRuntimeOperationResult.suspended(ScenarioRuntimeHandoff.party_defeat(combat.battle_id, source_kind, caller), events)
	var payload := _rules.combat_flow.ally_selection_payload(_game_state, _content)
	if not payload.is_empty():
		var ally_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_ALLY if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_ALLY
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.from_payload(request_id, &"ally_selection", payload), ScenarioRuntimeContinuation.combat_terminal(ally_kind, source_kind, combat.battle_id, caller), events)
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
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
	if _game_state.combat == null or not _game_state.combat.completed or _game_state.combat.battle_id != combat_continuation.battle_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The completed battle is unavailable for ally selection.")
	if _rules.combat_flow.ally_selection_payload(_game_state, _content).is_empty():
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
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
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
		return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), ScenarioRuntimeContinuation.combat(source_kind, combat.battle_id, caller), preceding_events)
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
	events.append(DomainEvent.new(&"battle_macro_started", {"battleId": combat.battle_id, "programId": program_id, "round": combat.round_number}))
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.FAILED:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return ScenarioRuntimeOperationResult.failed(&"nested_host_handoff", "A battle macro cannot suspend a second battle into the application host.")
	if result.state == ScenarioVmResult.State.WAITING:
		var macro_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_MACRO if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_MACRO
		return ScenarioRuntimeOperationResult.waiting(result.interaction, ScenarioRuntimeContinuation.combat_macro(macro_kind, source_kind, combat.battle_id, caller, program_id, vm.snapshot()), events)
	return _continue_after_battle_macro(source_kind, caller, request_id, program_id, events)


func _resume_battle_macro(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
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
		var next_continuation := ScenarioRuntimeContinuation.combat_macro(continuation.kind, combat_continuation.source_kind, combat_continuation.battle_id, combat_continuation.caller, combat_continuation.program_id, vm.snapshot())
		return ScenarioRuntimeOperationResult.waiting(result.interaction, next_continuation, result.events)
	return _continue_after_battle_macro(combat_continuation.source_kind, combat_continuation.caller, request_id, combat_continuation.program_id, result.events)


func _continue_after_battle_macro(source_kind: StringName, caller: ScenarioBattleCaller, request_id: String, program_id: String, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var committed: Array[DomainEvent] = []
	committed.assign(events)
	committed.append(DomainEvent.new(&"battle_macro_completed", {"battleId": _game_state.combat.battle_id, "programId": program_id, "round": _game_state.combat.round_number}))
	if _game_state.combat.completed:
		return _finish_battle_with_allies(source_kind, caller, request_id, committed)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), ScenarioRuntimeContinuation.combat(source_kind, _game_state.combat.battle_id, caller), committed)


func _run_combat_death_macro(source_kind: StringName, caller: ScenarioBattleCaller, preceding_events: Array[DomainEvent], request_id: String) -> ScenarioRuntimeOperationResult:
	var request := _death_macro_request(preceding_events)
	var combat := _game_state.combat
	if request.is_empty() or combat == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_death_macro_request", "Monster death-macro execution requires an active combatant request.")
	var combatant_id := str(request.get("combatantId", ""))
	var program_id := str(request.get("programId", ""))
	var monster := combat.monster_by_id(combatant_id)
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
		return ScenarioRuntimeOperationResult.waiting(result.interaction, ScenarioRuntimeContinuation.combat_macro(macro_kind, source_kind, combat.battle_id, caller, program_id, vm.snapshot(), combatant_id, bool(request.get("resetTraitorOnComplete", true))), events)
	return _continue_after_combat_death_macro(source_kind, caller, request_id, combatant_id, program_id, events, bool(request.get("resetTraitorOnComplete", true)))


func _resume_combat_death_macro(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
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
		var next_continuation := ScenarioRuntimeContinuation.combat_macro(continuation.kind, combat_continuation.source_kind, combat_continuation.battle_id, combat_continuation.caller, combat_continuation.program_id, vm.snapshot(), combat_continuation.combatant_id, combat_continuation.reset_traitor_on_complete)
		return ScenarioRuntimeOperationResult.waiting(result.interaction, next_continuation, result.events)
	return _continue_after_combat_death_macro(combat_continuation.source_kind, combat_continuation.caller, request_id, combat_continuation.combatant_id, combat_continuation.program_id, result.events, combat_continuation.reset_traitor_on_complete)


func _continue_after_combat_death_macro(source_kind: StringName, caller: ScenarioBattleCaller, request_id: String, combatant_id: String, program_id: String, events: Array[DomainEvent], reset_traitor_on_complete: bool = true) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Monster death-macro completion lost its battle.")
	var monster := combat.monster_by_id(combatant_id)
	if monster != null and reset_traitor_on_complete:
		monster.traitor = false
	var committed: Array[DomainEvent] = []
	committed.assign(events)
	committed.append(DomainEvent.new(&"monster_death_macro_completed", {"battleId": combat.battle_id, "combatantId": combatant_id, "programId": program_id, "revived": monster != null and monster.current_health > 0}))
	var previous_round := combat.round_number
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
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), ScenarioRuntimeContinuation.combat(source_kind, combat.battle_id, caller), committed)


func _wait_for_combat_age_updates(source_kind: StringName, caller: ScenarioBattleCaller, request_id: String, events: Array[DomainEvent], round_before: int) -> ScenarioRuntimeOperationResult:
	var updates := CharacterAgingResult.update_bodies(events)
	if updates.is_empty() or _game_state.combat == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_combat_age_update", "Monster aging did not provide a valid combat continuation.")
	var age_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_AGE if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_AGE
	var continuation := ScenarioRuntimeContinuation.combat_age(age_kind, source_kind, _game_state.combat.battle_id, caller, updates, 1, round_before)
	var committed: Array[DomainEvent] = []
	committed.assign(events)
	committed.append(CharacterAgingResult.sound_event_for_update(updates[0]))
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update_body(request_id, updates[0]), continuation, committed)


func _resume_combat_age_updates(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != InteractionRequest.AGE_UPDATE or response.body is not InteractionResponse.EmptyBody:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic combat age updates require an empty acknowledgement.")
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
	if _game_state.combat == null or _game_state.combat.battle_id != combat_continuation.battle_id or _game_state.combat.pending_monster_attack == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The monster age-update battle is unavailable.")
	var updates := combat_continuation.updates
	var index := combat_continuation.index
	if updates.is_empty() or index < 1 or index > updates.size():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_continuation", "The combat age-update queue is invalid.")
	var acknowledged: InteractionRequest.AgeUpdateBody = updates[index - 1]
	var events: Array[DomainEvent] = [DomainEvent.new(&"character_age_update_acknowledged", {"characterId": acknowledged.character_id})]
	if index < updates.size():
		var next_payload: InteractionRequest.AgeUpdateBody = updates[index]
		var next_continuation := ScenarioRuntimeContinuation.combat_age(continuation.kind, combat_continuation.source_kind, combat_continuation.battle_id, combat_continuation.caller, updates, index + 1, combat_continuation.round_before)
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
	if _game_state.combat.round_number > round_before and _game_state.combat.macro_id < 0:
		return _run_battle_macro(source_kind, caller, events, request_id)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), ScenarioRuntimeContinuation.combat(source_kind, _game_state.combat.battle_id, caller), events)


static func _death_macro_request(events: Array[DomainEvent]) -> Dictionary:
	for index: int in range(events.size() - 1, -1, -1):
		var event := events[index]
		if event.kind == &"monster_death_macro_requested":
			return event.payload
	return {}


func _combat_request(request_id: String) -> InteractionRequest:
	var combat := _game_state.combat
	var combat_view := CombatView.new(combat, _game_state.party.characters(), _content, _rules.inventory, _rules.battlefield, _rules.combat_flow, _game_state)
	var actions: Array[String] = []
	for action: StringName in combat_view.legal_actions:
		actions.append(String(action))
	var weapon_switch := {
		"enabled": combat_view.weapon_switch_available,
		"targetMode": String(combat_view.weapon_switch_target_mode),
		"reason": combat_view.weapon_switch_unavailable_reason,
	}
	var ranged_attack := {"enabled": combat_view.weapon_mode == &"missile" and combat_view.legal_actions.has(&"attack"), "reason": combat_view.ranged_attack_unavailable_reason}
	var targets: Array[Dictionary] = []
	for monster: MonsterView in combat_view.targets:
		targets.append({"id": monster.id, "kind": "monster", "name": monster.name, "currentHealth": monster.current_health, "maximumHealth": monster.maximum_health})
	for character: CharacterView in combat_view.character_targets:
		targets.append({"id": character.id, "kind": "character", "name": character.name, "currentHealth": character.current_health, "maximumHealth": character.maximum_health})
	var combatants_by_id: Dictionary = {}
	var terrain_set := _combat_terrain_set()
	for character_state: CharacterState in _game_state.party.characters():
		if _game_state.combat.battlefield == null or not _game_state.combat.battlefield.has_actor(character_state.id):
			continue
		var character := CharacterView.new(character_state, _content)
		var equipment := _rules.inventory.combat_equipment(character_state, _content.item_definitions())
		character.apply_equipment(equipment)
		var payload := _character_combatant_payload(character, equipment)
		_append_combatant_position_facts(payload, combat_view.active_actor_id, character.id, terrain_set)
		_append_character_weapon_facts(payload, character_state, equipment, combat_view.weapon_mode if character.id == combat_view.active_actor_id else &"melee")
		combatants_by_id[character.id] = payload
	for monster: MonsterView in combat_view.monsters:
		if _game_state.combat.battlefield == null or not _game_state.combat.battlefield.has_actor(monster.id):
			continue
		var payload := _monster_combatant_payload(monster, _content.monster_by_id(monster.definition_id))
		_append_combatant_position_facts(payload, combat_view.active_actor_id, monster.id, terrain_set)
		combatants_by_id[monster.id] = payload
	var combatants: Array[Dictionary] = []
	for combatant_id: String in combat_view.turn_order:
		if combatants_by_id.has(combatant_id):
			combatants.append(combatants_by_id[combatant_id])
			combatants_by_id.erase(combatant_id)
	for remaining: Dictionary in combatants_by_id.values():
		combatants.append(remaining)
	var movement: Array[Dictionary] = []
	for option: CombatMoveOptionView in combat_view.movement_options:
		movement.append({"direction": [option.direction.x, option.direction.y], "destination": [option.destination.x, option.destination.y], "cost": option.movement_cost, "enabled": option.enabled, "reasonCode": String(option.reason), "reason": option.reason_text, "retreat": option.retreats_from_battle, "forcedRetreat": option.forced_retreat, "attackTargetId": option.attack_target_id, "attackTargetName": option.attack_target_name})
	var spell_casts: Array[Dictionary] = []
	for option: CombatSpellOptionView in _rules.combat_flow.character_spell_options(_game_state, _content, combat_view.active_actor_id):
		var spell_cast := {"spellId": option.spell_id, "spellName": option.spell_name, "power": option.power, "cost": option.cost, "targetId": option.target_id, "targetName": option.target_name, "targetCurrentHealth": option.target_current_health, "targetMaximumHealth": option.target_maximum_health, "targetMode": String(option.target_mode)}
		if option.target_mode in [&"sequence", &"coordinate_sequence"]:
			spell_cast["maximumTargets"] = option.maximum_targets
		if option.target_mode == &"sequence":
			var candidates: Array[Dictionary] = []
			for candidate: CombatSpellTargetView in option.target_candidates:
				candidates.append({"id": candidate.id, "kind": String(candidate.kind), "name": candidate.name, "currentHealth": candidate.current_health, "maximumHealth": candidate.maximum_health})
			spell_cast["targetCandidates"] = candidates
		if option.target_mode == &"area":
			spell_cast["areaShape"] = option.area_shape
			spell_cast["defaultTargetCoordinate"] = [option.default_target_coordinate.x, option.default_target_coordinate.y]
			spell_cast["areaOffsets"] = option.area_offsets.map(func(offset: Vector2i) -> Array[int]: return [offset.x, offset.y])
			spell_cast["areaRotationOffsets"] = option.area_rotation_offsets.map(func(offsets: Array) -> Array: return offsets.map(func(offset: Vector2i) -> Array[int]: return [offset.x, offset.y]))
			spell_cast["legalTargetCoordinates"] = option.legal_target_coordinates.map(func(coordinate: Vector2i) -> Array[int]: return [coordinate.x, coordinate.y])
		spell_casts.append(spell_cast)
	if not spell_casts.is_empty():
		actions.append("cast_spell")
	var spell_cast_reason := _rules.combat_flow.character_spell_unavailable_reason(_game_state, _content, combat_view.active_actor_id)
	var fast_spells: Array[Dictionary] = []
	var active_character := _game_state.party.character_by_id(combat_view.active_actor_id)
	if active_character != null:
		for index: int in active_character.fast_spells().size():
			var binding := active_character.fast_spell_at(index)
			var bound_spell := _content.spell_by_id(binding.spell_id) if binding != null and not binding.is_empty() else null
			var binding_enabled := false
			if bound_spell != null:
				for cast: Dictionary in spell_casts:
					if cast.get("spellId") == binding.spell_id and int(cast.get("power", 0)) == binding.power:
						binding_enabled = true
						break
			var binding_reason := "This Fast Spell slot is undefined." if binding == null or binding.is_empty() else "The stored spell is unavailable to this character." if bound_spell == null or not active_character.known_spells().has(binding.spell_id) else "No legal target or casting action is currently available."
			fast_spells.append({"slot": index, "spellId": binding.spell_id if binding != null else "", "spellName": bound_spell.name if bound_spell != null else "Undefined Spell", "power": binding.power if binding != null else 0, "enabled": binding_enabled, "reason": "" if binding_enabled else binding_reason})
	var item_casts: Array[Dictionary] = []
	for option: CombatItemOptionView in _rules.combat_flow.character_item_spell_options(_game_state, _content, combat_view.active_actor_id):
		var item_cast := {"itemInstanceId": option.item_instance_id, "itemId": option.item_definition_id, "itemName": option.item_name, "charges": option.charges, "powerStaged": option.power_staged, "spellId": option.spell_id, "spellName": option.spell_name, "power": option.power, "targetId": option.target_id, "targetName": option.target_name, "targetCurrentHealth": option.target_current_health, "targetMaximumHealth": option.target_maximum_health, "targetMode": String(option.target_mode)}
		if option.target_mode in [&"sequence", &"coordinate_sequence"]: item_cast["maximumTargets"] = option.maximum_targets
		if option.target_mode == &"sequence":
			var candidates: Array[Dictionary] = []
			for candidate: CombatSpellTargetView in option.target_candidates:
				candidates.append({"id": candidate.id, "kind": String(candidate.kind), "name": candidate.name, "currentHealth": candidate.current_health, "maximumHealth": candidate.maximum_health})
			item_cast["targetCandidates"] = candidates
		if option.target_mode == &"area":
			item_cast["areaShape"] = option.area_shape
			item_cast["defaultTargetCoordinate"] = [option.default_target_coordinate.x, option.default_target_coordinate.y]
			item_cast["areaOffsets"] = option.area_offsets.map(func(offset: Vector2i) -> Array[int]: return [offset.x, offset.y])
			item_cast["areaRotationOffsets"] = option.area_rotation_offsets.map(func(offsets: Array) -> Array: return offsets.map(func(offset: Vector2i) -> Array[int]: return [offset.x, offset.y]))
			item_cast["legalTargetCoordinates"] = option.legal_target_coordinates.map(func(coordinate: Vector2i) -> Array[int]: return [coordinate.x, coordinate.y])
		item_casts.append(item_cast)
	if not item_casts.is_empty():
		actions.append("use_item")
	var item_cast_reason := _rules.combat_flow.character_item_spell_unavailable_reason(_game_state, _content, combat_view.active_actor_id)
	var scroll_casts: Array[Dictionary] = []
	for option: Variant in _rules.combat_flow.character_scroll_options(_game_state, _content, combat_view.active_actor_id):
		var scroll_cast := {"scrollSlot": option.scroll_slot, "spellId": option.spell_id, "spellName": option.spell_name, "power": option.power, "targetId": option.target_id, "targetName": option.target_name, "targetCurrentHealth": option.target_current_health, "targetMaximumHealth": option.target_maximum_health, "targetMode": String(option.target_mode)}
		if option.target_mode in [&"sequence", &"coordinate_sequence"]:
			scroll_cast["maximumTargets"] = option.maximum_targets
		if option.target_mode == &"sequence":
			var candidates: Array[Dictionary] = []
			for candidate: CombatSpellTargetView in option.target_candidates:
				candidates.append({"id": candidate.id, "kind": String(candidate.kind), "name": candidate.name, "currentHealth": candidate.current_health, "maximumHealth": candidate.maximum_health})
			scroll_cast["targetCandidates"] = candidates
		if option.target_mode == &"area":
			scroll_cast["areaShape"] = option.area_shape
			scroll_cast["defaultTargetCoordinate"] = [option.default_target_coordinate.x, option.default_target_coordinate.y]
			scroll_cast["areaOffsets"] = option.area_offsets.map(func(offset: Vector2i) -> Array[int]: return [offset.x, offset.y])
			scroll_cast["areaRotationOffsets"] = option.area_rotation_offsets.map(func(offsets: Array) -> Array: return offsets.map(func(offset: Vector2i) -> Array[int]: return [offset.x, offset.y]))
			scroll_cast["legalTargetCoordinates"] = option.legal_target_coordinates.map(func(coordinate: Vector2i) -> Array[int]: return [coordinate.x, coordinate.y])
		scroll_casts.append(scroll_cast)
	if not scroll_casts.is_empty():
		actions.append("use_scroll")
	var scroll_cast_reason := _rules.combat_flow.character_scroll_unavailable_reason(_game_state, _content, combat_view.active_actor_id)
	var retreat := {"enabled": combat_view.retreat_available, "reason": combat_view.retreat_unavailable_reason, "nearestEnemyRange": combat_view.nearest_enemy_range}
	var enemies_remaining := combat_view.hostile_actor_ids.size()
	var bandage_targets: Array[Dictionary] = []
	for candidate: CharacterView in combat_view.bandage_candidates:
		bandage_targets.append({"id": candidate.id, "name": candidate.name, "currentHealth": candidate.current_health, "maximumHealth": candidate.maximum_health})
	var turn_targets: Array[Dictionary] = []
	for target: MonsterView in combat_view.turn_undead_targets:
		turn_targets.append({"id": target.id, "name": target.name, "hitDice": target.hit_dice, "magicResistance": target.magic_resistance})
	var request := InteractionRequest.from_payload(request_id, &"combat_action", {"battleId": combat_view.battle_id, "round": combat_view.round_number, "actorId": combat_view.active_actor_id, "attackUnitsRemaining": combat_view.attack_units_remaining, "movementRemaining": combat_view.movement_remaining, "enemiesRemaining": enemies_remaining, "actions": actions, "weaponMode": String(combat_view.weapon_mode), "weaponSwitch": weapon_switch, "rangedAttack": ranged_attack, "retreat": retreat, "meleeAttackReason": combat_view.melee_attack_unavailable_reason, "targets": targets, "combatants": combatants, "movement": movement, "spellCasts": spell_casts, "spellCastReason": spell_cast_reason, "fastSpells": fast_spells, "itemCasts": item_casts, "itemCastReason": item_cast_reason, "scrollCasts": scroll_casts, "scrollCastReason": scroll_cast_reason, "autoTurn": {"enabled": combat_view.auto_turn.enabled, "reason": combat_view.auto_turn.reason}, "autoCharacterIds": combat_view.auto_character_ids.duplicate(), "delay": {"enabled": combat_view.delay.enabled, "reason": combat_view.delay.reason}, "bandage": {"enabled": combat_view.bandage.enabled, "reason": combat_view.bandage.reason, "targets": bandage_targets}, "turnUndead": {"enabled": combat_view.turn_undead.enabled, "reason": combat_view.turn_undead.reason, "targets": turn_targets}, "undo": {"enabled": combat_view.undo.enabled, "reason": combat_view.undo.reason}})
	if request != null:
		request.transient_combat_view = combat_view
	return request


func active_combat_request(request_id: String) -> InteractionRequest:
	return _combat_request(request_id)


static func _character_combatant_payload(character: CharacterView, equipment: CharacterCombatEquipment) -> Dictionary:
	var items: Array[String] = []
	for item: ItemView in character.items:
		var row := "%s • %s" % [item.name, "Equipped" if item.equipped else "Carried"]
		if item.charges >= 0:
			row += " • %d charge%s" % [item.charges, "" if item.charges == 1 else "s"]
		items.append(row)
	var attack_rows: Array[String] = []
	var melee: ItemDefinition = equipment.melee_weapon if equipment != null and equipment.valid else null
	var missile: ItemDefinition = equipment.missile_weapon if equipment != null and equipment.valid else null
	attack_rows.append(_character_attack_row("Melee", melee, character.attacks_per_round))
	if missile != null:
		attack_rows.append(_character_attack_row("Missile", missile, character.attacks_per_round))
	return {"id": character.id, "kind": "character", "name": character.name, "currentHealth": character.current_health, "maximumHealth": character.maximum_health, "spellPoints": character.spell_points, "maximumSpellPoints": character.maximum_spell_points, "armor": character.armor, "magicResistance": character.magic_resistance, "attacks": character.attacks_per_round, "movement": character.movement, "maximumMovement": character.maximum_movement, "traitor": character.traitor, "helpless": character.condition_values[ConditionRules.HELPLESS] != 0, "conditions": character.conditions.map(func(condition: CharacterMetricView) -> String: return condition.name), "items": items, "attackRows": attack_rows}


static func _monster_combatant_payload(monster: MonsterView, definition: MonsterDefinition) -> Dictionary:
	var attack_rows: Array[String] = []
	if definition != null:
		var attacks := definition.attacks()
		for index: int in attacks.size():
			var attack := attacks[index]
			attack_rows.append("Attack %d • %d–%d damage" % [index + 1, attack.damage_min, attack.damage_max])
	var items: Array[String] = []
	if not monster.weapon_name.is_empty() and monster.weapon_name != "Unarmed":
		items.append("%s • Equipped" % monster.weapon_name)
	return {"id": monster.id, "kind": "monster", "name": monster.name, "currentHealth": monster.current_health, "maximumHealth": monster.maximum_health, "spellPoints": monster.spell_points, "maximumSpellPoints": monster.maximum_spell_points, "armor": monster.armor, "magicResistance": monster.magic_resistance, "hitDice": monster.hit_dice, "attacks": str(monster.attack_count), "movement": monster.movement_maximum, "maximumMovement": monster.movement_maximum, "traitor": monster.traitor, "helpless": monster.helpless, "conditions": monster.conditions.duplicate(), "items": items, "attackRows": attack_rows, "immunities": monster.immunities.duplicate(), "vulnerabilities": monster.vulnerabilities.duplicate(), "weapon": monster.weapon_name}


static func _character_attack_row(label: String, weapon: ItemDefinition, attacks: String) -> String:
	if weapon == null:
		return "%s • Unarmed • %s attack%s" % [label, attacks, "" if attacks == "1" else "s"]
	var damage := ""
	if weapon.vs_small > 0:
		damage = " • %d–%d damage" % [1 + weapon.damage_bonus, weapon.damage_bonus + weapon.vs_small]
	return "%s • %s%s • %s attack%s" % [label, weapon.name, damage, attacks, "" if attacks == "1" else "s"]


func _append_combatant_position_facts(payload: Dictionary, active_actor_id: String, combatant_id: String, terrain_set: BattleTerrainSetDefinition) -> void:
	if _game_state.combat == null or _game_state.combat.battlefield == null or active_actor_id.is_empty() or combatant_id.is_empty():
		return
	payload["range"] = _rules.battlefield.classic_range(_game_state.combat.battlefield, active_actor_id, combatant_id)
	payload["blocked"] = terrain_set == null or not _rules.battlefield.has_line_of_sight(_game_state.combat.battlefield, terrain_set, active_actor_id, combatant_id)


func _append_character_weapon_facts(payload: Dictionary, character: CharacterState, equipment: CharacterCombatEquipment, weapon_mode: StringName) -> void:
	if equipment == null or not equipment.valid:
		return
	var weapon := equipment.missile_weapon if weapon_mode == &"missile" else equipment.melee_weapon
	var instance_id := equipment.missile_weapon_instance_id if weapon_mode == &"missile" else equipment.melee_weapon_instance_id
	payload["weapon"] = weapon.name if weapon != null else "Unarmed"
	payload["weaponCharges"] = -1
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id:
			payload["weaponCharges"] = instance.charges
			break


func _combat_terrain_set() -> BattleTerrainSetDefinition:
	if _game_state.combat == null or _game_state.combat.battlefield == null:
		return null
	var map := _content.world.map_by_id(_game_state.combat.battlefield.map_id)
	return _content.world.battle_terrain_set_for_map(map, _game_state.world) if map != null else null


static func _combat_destination(value: Variant) -> Vector2i:
	if not value is Array or value.size() != 2 or not value[0] is int or not value[1] is int:
		return Vector2i(-100_000, -100_000)
	return Vector2i(value[0], value[1])
