class_name ClassicBattleRewardOperations
extends ClassicOpcodeHandler

var _content: RealmzContent
var _game_state: GameState
var _rng: RealmzRng
var _rules: RealmzRules
var _runtime_api_ref: WeakRef


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, rules: RealmzRules) -> void:
	_content = content
	_game_state = game_state
	_rng = rng
	_rules = rules


func bind_runtime_api(runtime_api: RealmzRuntimeApi) -> void:
	_runtime_api_ref = weakref(runtime_api)


func _runtime_api() -> RealmzRuntimeApi:
	return _runtime_api_ref.get_ref() as RealmzRuntimeApi if _runtime_api_ref != null else null


func opcode_ids() -> Array[int]:
	return [2, 10, 11, 48, 56, 65, 107]


func execute(action: ClassicActionDefinition, request_id: String, context: Dictionary) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		2, 48, 56, 107:
			return _start_classic_battle(action, request_id)
		10:
			return _grant_treasure(action.operand_id, request_id)
		11:
			var no_experience_items: Array[String] = []
			return _begin_reward(&"scenario", "classic.experience.%d" % action.operand_id, maxi(0, action.operand_id), WealthState.new(), no_experience_items, request_id)
		65:
			return _grant_random_items(action, request_id)
	return super.execute(action, request_id, context)


func resume(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
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
		ScenarioRuntimeContinuation.CLASSIC_REWARD:
			return _resume_reward(continuation, response, request_id)
	return ScenarioRuntimeOperationResult.failed(&"unknown_interaction_continuation", "Battle/reward continuation is unavailable.")


func _grant_random_items(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 3:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 65 requires a five-value Extra Code row.")
	var count := action.extra_code[0]
	if count < 0:
		count = _rng.draw(absi(count), &"classic.random-item-count")
	if count < 0 or count > 20 or action.extra_code[1] > action.extra_code[2]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_random_item_range", "Classic opcode 65 has an invalid count or item range.")
	var item_ids: Array[String] = []
	for index: int in count:
		var classic_item_id := _rng.draw_between(action.extra_code[1], action.extra_code[2], StringName("classic.random-item.%d" % index))
		var definition := _content.item_by_classic_id(classic_item_id)
		if definition == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Classic opcode 65 generated unavailable item %d." % classic_item_id)
		item_ids.append(definition.id)
	return _begin_reward(&"scenario", "classic.random-items", 0, WealthState.new(), item_ids, request_id)




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
	var caller := ScenarioBattleCaller.classic(action.opcode, action.gosub, action.extra_code[4] if action.opcode == 2 and action.extra_code.size() > 4 else 0, action.extra_code[4] if action.opcode == 107 and action.extra_code.size() > 4 else action.extra_code[2] if action.opcode == 56 and action.extra_code.size() > 2 else 0)
	var battle := _content.battle_by_classic_id(absi(battle_id))
	if battle == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_battle", "Classic opcode %d references unavailable battle %d." % [action.opcode, battle_id])
	var operation := start_battle_definition(battle, request_id, "classic", caller)
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
	var target := caller.branch_target
	if opcode == 107 or opcode == 56 and target >= 0:
		return content.scenario.program_by_id("xap:%d" % target) != null
	return true


func complete_party_defeat_handoff(handoff: ScenarioRuntimeHandoff) -> ScenarioRuntimeOperationResult:
	if not party_defeat_handoff_is_valid(_content, _game_state, handoff):
		return ScenarioRuntimeOperationResult.failed(&"invalid_party_defeat_handoff", "The suspended total-party defeat no longer matches its battle caller.")
	var caller := handoff.caller
	if caller.kind == ScenarioBattleCaller.CLASSIC and caller.opcode == 2 and caller.mode == 10:
		return ScenarioRuntimeOperationResult.failed(&"classic_mode_10_defeat_unresolved", "Classic battle mode 10 revives and restarts its caller without running Party Death; that source-specific restart is not yet available.")
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


func start_battle_definition(battle: BattleDefinition, request_id: String, source: String, caller: ScenarioBattleCaller) -> ScenarioRuntimeOperationResult:
	var result := _rules.combat_flow.start_battle(_game_state, _content, battle, _rng)
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
		result = _rules.combat_flow.cast_spell(_game_state, _content, body.actor_id, body.target_id, body.spell_id, body.power, _rng, target_coordinate, body.rotation, body.target_ids)
	elif body.action == &"use_item":
		if body.item_instance_id.is_empty():
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat item use requires an itemInstanceId string.")
		result = _rules.combat_flow.use_spell_item(_game_state, _content, body.actor_id, body.target_id, body.item_instance_id, _rng)
	elif body.action == &"use_scroll":
		if body.scroll_slot < 0:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat scroll use requires an integer scrollSlot.")
		var scroll_target_coordinate := body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE
		result = _rules.combat_flow.use_combat_scroll(_game_state, _content, body.actor_id, body.scroll_slot, body.target_id, _rng, scroll_target_coordinate, body.rotation, body.target_ids)
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


func _append_battle_after_message(battle: BattleDefinition, events: Array[DomainEvent]) -> void:
	if battle.message_after_id == 0:
		return
	var after := _content.message_by_id(absi(battle.message_after_id))
	if after != null:
		events.append(DomainEvent.new(&"message_shown", {"messageId": after.id, "text": after.text, "source": "classic-battle-definition"}))


func _finish_battle_with_allies(source_kind: StringName, caller: ScenarioBattleCaller, request_id: String, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null or not combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Post-battle ally selection requires a completed battle.")
	if combat.outcome == &"defeat":
		if caller.kind == ScenarioBattleCaller.CLASSIC and caller.opcode == 2 and caller.mode == 10:
			return ScenarioRuntimeOperationResult.failed(&"classic_mode_10_defeat_unresolved", "Classic battle mode 10 bypasses Party Death and restarts its encounter; that caller-specific path is unresolved.")
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
	var payload := _rules.combat_flow.fumble_recovery_payload(_game_state, _content)
	if not payload.is_empty():
		var fumble_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_FUMBLE if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_FUMBLE
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.from_payload(request_id, InteractionRequest.TREASURE_DISTRIBUTION, payload), ScenarioRuntimeContinuation.combat_terminal(fumble_kind, source_kind, combat.battle_id, caller), events)
	var reward := begin_completed_battle_reward(request_id)
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
	var started := vm.start_program(program_id, {"callingContext": "battle-macro", "battleId": combat.battle_id})
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
	var started := vm.start_program(program_id, {
		"callingContext": "monster-death-macro",
		"battleId": combat.battle_id,
		"combatantId": combatant_id,
		"classicMonsterId": int(request.get("classicMonsterId", 0)),
		"traitor": bool(request.get("traitor", monster.traitor)),
	})
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
		var payload := _character_combatant_payload(character)
		_append_combatant_position_facts(payload, combat_view.active_actor_id, character.id, terrain_set)
		_append_character_weapon_facts(payload, character_state, equipment, combat_view.weapon_mode if character.id == combat_view.active_actor_id else &"melee")
		combatants_by_id[character.id] = payload
	for monster: MonsterView in combat_view.monsters:
		if _game_state.combat.battlefield == null or not _game_state.combat.battlefield.has_actor(monster.id):
			continue
		var payload := _monster_combatant_payload(monster)
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
		if option.target_mode == &"sequence":
			spell_cast["maximumTargets"] = option.maximum_targets
			var candidates: Array[Dictionary] = []
			for candidate: CombatSpellTargetView in option.target_candidates:
				candidates.append({"id": candidate.id, "kind": String(candidate.kind), "name": candidate.name, "currentHealth": candidate.current_health, "maximumHealth": candidate.maximum_health})
			spell_cast["targetCandidates"] = candidates
		if option.target_mode == &"area":
			spell_cast["areaShape"] = option.area_shape
			spell_cast["defaultTargetCoordinate"] = [option.default_target_coordinate.x, option.default_target_coordinate.y]
			spell_cast["areaOffsets"] = option.area_offsets.map(func(offset: Vector2i) -> Array[int]: return [offset.x, offset.y])
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
		item_casts.append({"itemInstanceId": option.item_instance_id, "itemId": option.item_definition_id, "itemName": option.item_name, "charges": option.charges, "spellId": option.spell_id, "spellName": option.spell_name, "power": option.power, "targetId": option.target_id, "targetName": option.target_name, "targetCurrentHealth": option.target_current_health, "targetMaximumHealth": option.target_maximum_health, "targetMode": String(option.target_mode)})
	if not item_casts.is_empty():
		actions.append("use_item")
	var item_cast_reason := _rules.combat_flow.character_item_spell_unavailable_reason(_game_state, _content, combat_view.active_actor_id)
	var scroll_casts: Array[Dictionary] = []
	for option: Variant in _rules.combat_flow.character_scroll_options(_game_state, _content, combat_view.active_actor_id):
		var scroll_cast := {"scrollSlot": option.scroll_slot, "spellId": option.spell_id, "spellName": option.spell_name, "power": option.power, "targetId": option.target_id, "targetName": option.target_name, "targetCurrentHealth": option.target_current_health, "targetMaximumHealth": option.target_maximum_health, "targetMode": String(option.target_mode)}
		if option.target_mode == &"sequence":
			scroll_cast["maximumTargets"] = option.maximum_targets
			var candidates: Array[Dictionary] = []
			for candidate: CombatSpellTargetView in option.target_candidates:
				candidates.append({"id": candidate.id, "kind": String(candidate.kind), "name": candidate.name, "currentHealth": candidate.current_health, "maximumHealth": candidate.maximum_health})
			scroll_cast["targetCandidates"] = candidates
		if option.target_mode == &"area":
			scroll_cast["areaShape"] = option.area_shape
			scroll_cast["defaultTargetCoordinate"] = [option.default_target_coordinate.x, option.default_target_coordinate.y]
			scroll_cast["areaOffsets"] = option.area_offsets.map(func(offset: Vector2i) -> Array[int]: return [offset.x, offset.y])
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
	return InteractionRequest.from_payload(request_id, &"combat_action", {"battleId": combat_view.battle_id, "round": combat_view.round_number, "actorId": combat_view.active_actor_id, "attackUnitsRemaining": combat_view.attack_units_remaining, "movementRemaining": combat_view.movement_remaining, "enemiesRemaining": enemies_remaining, "actions": actions, "weaponMode": String(combat_view.weapon_mode), "weaponSwitch": weapon_switch, "rangedAttack": ranged_attack, "retreat": retreat, "meleeAttackReason": combat_view.melee_attack_unavailable_reason, "targets": targets, "combatants": combatants, "movement": movement, "spellCasts": spell_casts, "spellCastReason": spell_cast_reason, "fastSpells": fast_spells, "itemCasts": item_casts, "itemCastReason": item_cast_reason, "scrollCasts": scroll_casts, "scrollCastReason": scroll_cast_reason, "autoTurn": {"enabled": combat_view.auto_turn.enabled, "reason": combat_view.auto_turn.reason}, "autoCharacterIds": combat_view.auto_character_ids.duplicate(), "delay": {"enabled": combat_view.delay.enabled, "reason": combat_view.delay.reason}, "bandage": {"enabled": combat_view.bandage.enabled, "reason": combat_view.bandage.reason, "targets": bandage_targets}, "turnUndead": {"enabled": combat_view.turn_undead.enabled, "reason": combat_view.turn_undead.reason, "targets": turn_targets}, "undo": {"enabled": combat_view.undo.enabled, "reason": combat_view.undo.reason}})


static func _character_combatant_payload(character: CharacterView) -> Dictionary:
	return {"id": character.id, "kind": "character", "name": character.name, "currentHealth": character.current_health, "maximumHealth": character.maximum_health, "spellPoints": character.spell_points, "maximumSpellPoints": character.maximum_spell_points, "armor": character.armor, "magicResistance": character.magic_resistance, "attacks": character.attacks_per_round, "movement": character.movement, "maximumMovement": character.maximum_movement, "traitor": character.traitor, "helpless": character.condition_values[ConditionRules.HELPLESS] != 0, "conditions": character.conditions.map(func(condition: CharacterMetricView) -> String: return condition.name)}


static func _monster_combatant_payload(monster: MonsterView) -> Dictionary:
	return {"id": monster.id, "kind": "monster", "name": monster.name, "currentHealth": monster.current_health, "maximumHealth": monster.maximum_health, "spellPoints": monster.spell_points, "maximumSpellPoints": monster.maximum_spell_points, "armor": monster.armor, "magicResistance": monster.magic_resistance, "hitDice": monster.hit_dice, "attacks": str(monster.attack_count), "movement": monster.movement_maximum, "maximumMovement": monster.movement_maximum, "traitor": monster.traitor, "helpless": monster.helpless, "conditions": monster.conditions.duplicate(), "immunities": monster.immunities.duplicate(), "vulnerabilities": monster.vulnerabilities.duplicate(), "weapon": monster.weapon_name}


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
	return _content.world.battle_terrain_set_by_id(map.battle_terrain_set_id) if map != null else null


static func _combat_destination(value: Variant) -> Vector2i:
	if not value is Array or value.size() != 2 or not value[0] is int or not value[1] is int:
		return Vector2i(-100_000, -100_000)
	return Vector2i(value[0], value[1])


func _grant_treasure(classic_treasure_id: int, request_id: String) -> ScenarioRuntimeOperationResult:
	var treasure := _content.treasure_by_classic_id(absi(classic_treasure_id))
	if treasure == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_treasure", "Classic opcode 10 references unavailable treasure %d." % classic_treasure_id)
	return grant_treasure_definition(treasure, request_id)


func grant_treasure_definition(treasure: TreasureDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	var roll := _rules.economy.roll_treasure(treasure, _rng)
	return _begin_reward(&"scenario", treasure.id, roll.experience, roll.wealth, roll.item_ids, request_id)


func begin_completed_battle_reward(request_id: String) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null or not combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Battle rewards require a completed battle.")
	if combat.rewards_completed:
		return ScenarioRuntimeOperationResult.completed(String(combat.outcome))
	if combat.rewards_started:
		return ScenarioRuntimeOperationResult.failed(&"battle_reward_already_started", "The completed battle already has an active reward continuation.")
	var defeated_monsters: Array[Dictionary] = []
	var pending_item_count := 0
	if combat.outcome == &"victory":
		for monster: MonsterState in combat.monsters():
			var definition := _content.monster_by_id(monster.definition_id)
			if definition == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Battle reward references unavailable monster content.")
			if not monster.traitor or monster.current_health >= 1:
				continue
			var loot := monster.loot_item_ids()
			if loot.is_empty():
				loot = definition.item_ids()
				if not loot.is_empty() and definition.random_weapon_table > 0:
					loot[0] = monster.weapon_id
			for item_id: String in loot:
				if item_id.is_empty():
					continue
				if _content.item_by_id(item_id) == null:
					return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Battle reward references unavailable item '%s'." % item_id)
				pending_item_count += 1
				if pending_item_count > ClassicRewardState.MAX_PENDING_ITEMS:
					return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The battle reward exceeds the supported Classic reward bounds.")
			defeated_monsters.append({"monster": monster, "definition": definition, "loot": loot})
	# Validate the whole source-owned reward before consuming RNG or claiming its
	# one-shot battle continuation. A malformed package therefore remains retryable.
	combat.rewards_started = true
	var item_ids: Array[String] = []
	var wealth := WealthState.new()
	var experience := 0
	var events: Array[DomainEvent] = []
	if combat.outcome == &"victory":
		for row: Dictionary in defeated_monsters:
			var monster: MonsterState = row["monster"]
			var definition: MonsterDefinition = row["definition"]
			var money := definition.money_values()
			for kind: WealthState.Kind in [WealthState.Kind.GOLD, WealthState.Kind.GEMS, WealthState.Kind.JEWELRY]:
				var maximum := maxi(0, money[kind] if kind < money.size() else 0)
				if maximum > 0:
					wealth.add(kind, _rng.draw_between(0, maximum, StringName("battle.reward.%s.money.%d" % [monster.id, kind])))
			experience += _monster_reward_experience(monster, definition)
			for item_id: String in row["loot"]:
				if not item_id.is_empty():
					item_ids.append(item_id)
		events.append(DomainEvent.new(&"battle_reward_constructed", {"battleId": combat.battle_id, "experience": experience, "wealth": wealth.to_data(), "itemCount": item_ids.size()}))
	var operation := _begin_reward(&"battle", combat.battle_id, experience, wealth, item_ids, request_id)
	operation.events = events + operation.events
	return operation


func _begin_reward(origin: StringName, source_id: String, total_experience: int, wealth: WealthState, item_ids: Array[String], request_id: String) -> ScenarioRuntimeOperationResult:
	if wealth == null or item_ids.size() > ClassicRewardState.MAX_PENDING_ITEMS:
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The reward exceeds the supported Classic reward bounds.")
	var experience_multiplier := _game_state.experience_multiplier
	if experience_multiplier < 0.0:
		var campaign := _content.campaign_definition()
		var current_levels := 0
		for party_character: CharacterState in _game_state.party.characters():
			current_levels += party_character.level
		experience_multiplier = PartySetupRules.experience_multiplier(campaign.recommended_party_levels, current_levels, _game_state.difficulty) if campaign != null and campaign.guidance_authored and campaign.recommended_party_levels > 0 else 1.0
	var scaled_experience := PartySetupRules.scale_experience_by_multiplier(total_experience, experience_multiplier)
	var scaled_wealth := WealthState.new(
		PartySetupRules.scale_money(wealth.gold, _game_state.difficulty),
		PartySetupRules.scale_money(wealth.gems, _game_state.difficulty),
		PartySetupRules.scale_money(wealth.jewelry, _game_state.difficulty),
	)
	var reward_definitions: Array[ItemDefinition] = []
	var unique_owned: Dictionary = {}
	for character: CharacterState in _game_state.party.characters():
		for carried: ItemInstance in character.inventory():
			unique_owned[carried.definition_id] = true
	for item_id: String in item_ids:
		var definition := _content.item_by_id(item_id)
		if definition == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Reward '%s' references unavailable item '%s'." % [source_id, item_id])
		if definition.cost < 0 and unique_owned.has(definition.id):
			continue
		reward_definitions.append(definition)
		if definition.cost < 0:
			unique_owned[definition.id] = true
	var reward := ClassicRewardState.new(origin, source_id, scaled_experience, scaled_wealth)
	var items: Array[ItemInstance] = []
	for definition: ItemDefinition in reward_definitions:
		var identified := absi(definition.item_type) == 24
		items.append(ItemInstance.new(_game_state.next_instance_id("reward.item"), definition.id, definition.initial_charges, false, identified))
	if not reward.set_items(items):
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The reward contains invalid item instances.")
	var awards: Dictionary = {}
	var recipients := _reward_experience_recipients(origin)
	var share := 0 if recipients.is_empty() else int(float(reward.experience_pool) / float(recipients.size()))
	reward.experience_share = share
	for character: CharacterState in recipients:
		var race := _content.race_by_id(character.race_id)
		var awarded := _rules.characters.battle_experience(character, race, share)
		awards[character.id] = awarded
	if not reward.set_experience_awards(awards):
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The reward experience recipients are invalid.")
	_game_state.party.pooled_wealth.gold += scaled_wealth.gold
	_game_state.party.pooled_wealth.gems += scaled_wealth.gems
	_game_state.party.pooled_wealth.jewelry += scaled_wealth.jewelry
	for character: CharacterState in recipients:
		character.experience += int(awards[character.id])
	var events: Array[DomainEvent] = [DomainEvent.new(&"reward_opened", {"origin": String(origin), "sourceId": source_id, "experiencePool": reward.experience_pool, "experienceShare": reward.experience_share, "experienceByCharacter": awards, "wealth": scaled_wealth.to_data(), "itemCount": items.size()})]
	if items.is_empty() and scaled_wealth.gold == 0 and scaled_wealth.gems == 0 and scaled_wealth.jewelry == 0 and scaled_experience == 0:
		return _complete_reward(reward, events)
	return _wait_for_reward(reward, request_id, events)


func _reward_experience_recipients(origin: StringName) -> Array[CharacterState]:
	var result: Array[CharacterState] = []
	for character: CharacterState in _game_state.party.characters():
		if character.current_health <= 0 or character.conditions.value(ConditionRules.ANIMATED) < 0:
			continue
		if origin == &"battle" and (_game_state.combat == null or _game_state.combat.battlefield == null or not _game_state.combat.battlefield.has_actor(character.id)):
			continue
		result.append(character)
	return result


func _wait_for_reward(reward: ClassicRewardState, request_id: String, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	var request := _reward_request(reward, request_id)
	if request == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_continuation", "The reward has no valid interaction for its current phase.")
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.reward(reward), events)


func _reward_request(reward: ClassicRewardState, request_id: String) -> InteractionRequest:
	if reward.phase == ClassicRewardState.LEVEL_PHASE:
		return _level_result_request(reward, request_id)
	if reward.phase == ClassicRewardState.SPELL_PHASE:
		return _reward_spell_request(reward, request_id)
	if reward.completion_pending:
		var summary := "%d unclaimed item%s and %d gold, %d gems, %d jewelry will be left behind." % [reward.items().size(), "" if reward.items().size() == 1 else "s", _game_state.party.pooled_wealth.gold, _game_state.party.pooled_wealth.gems, _game_state.party.pooled_wealth.jewelry]
		return InteractionRequest.from_payload(request_id, InteractionRequest.TREASURE_DISTRIBUTION, {"mode": "completion-confirmation", "prompt": "Leave the remaining treasure behind?", "summary": summary})
	var pending := reward.first_item()
	var item_payload: Variant = null
	if pending != null:
		var definition := _content.item_by_id(pending.definition_id)
		if definition == null:
			return null
		item_payload = {
			"instanceId": pending.id,
			"definitionId": pending.definition_id,
			"name": definition.name if pending.identified else definition.unidentified_name,
			"charges": pending.charges,
			"identified": pending.identified,
			"magical": reward.magic_detected and definition.magical,
		}
	var characters: Array[Dictionary] = []
	var has_share_capacity := false
	for character: CharacterState in _game_state.party.characters():
		var enabled := false
		var reason := ""
		if pending != null:
			var definition := _content.item_by_id(pending.definition_id)
			enabled = _rules.inventory.can_restore_item(character, pending, definition)
			if character.inventory().size() >= InventoryRules.MAX_ITEMS:
				reason = "Inventory is full."
			elif character.carried_load + definition.instance_weight(pending.charges) > character.maximum_load:
				reason = "The item would exceed maximum load."
			elif not enabled:
				reason = "This character cannot receive the item."
		characters.append({
			"id": character.id,
			"name": character.name,
			"enabled": enabled,
			"reason": reason,
			"wealth": character.money.to_data(),
			"canTakeGold": _game_state.party.pooled_wealth.gold >= 5 and character.carried_load + 5 <= character.maximum_load,
			"canTakeGems": _game_state.party.pooled_wealth.gems >= 1 and character.carried_load + 1 <= character.maximum_load,
			"canTakeJewelry": _game_state.party.pooled_wealth.jewelry >= 1 and character.carried_load + 15 <= character.maximum_load,
			"goldReason": "The pool has fewer than 5 gold or the character cannot carry it.",
			"gemsReason": "The pool has no gems or the character cannot carry one.",
			"jewelryReason": "The pool has no jewelry or the character cannot carry one.",
		})
		has_share_capacity = has_share_capacity or character.carried_load < character.maximum_load
	var detect_rows := _reward_caster_rows(63, 5)
	var identify_rows := _reward_caster_rows(48, 25)
	return InteractionRequest.from_payload(request_id, InteractionRequest.TREASURE_DISTRIBUTION, {
		"mode": "ordinary",
		"prompt": "Distribute the treasure, then choose Done.",
		"origin": String(reward.origin),
		"sourceId": reward.source_id,
		"experiencePool": reward.experience_pool,
		"experienceShare": reward.experience_share,
		"wealth": _game_state.party.pooled_wealth.to_data(),
		"item": item_payload,
		"remaining": reward.items().size(),
		"characters": characters,
		"hasShareCapacity": has_share_capacity,
		"detect": {"visible": pending != null and not reward.magic_detected, "casters": detect_rows, "reason": "No living caster knows Detect Magic with 5 spell points."},
		"identify": {"visible": pending != null and not reward.identified, "casters": identify_rows, "reason": "No living caster knows Identify with 25 spell points."},
	})


func _resume_reward(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if continuation == null or continuation.kind != ScenarioRuntimeContinuation.CLASSIC_REWARD:
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_continuation", "The reward continuation is malformed.")
	var reward_body := continuation.body as ScenarioRuntimeContinuation.RewardBody
	var reward := ClassicRewardState.from_data(reward_body.state.to_data()) if reward_body != null and reward_body.state != null else null
	if reward == null or not _reward_state_is_valid(reward):
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_continuation", "The saved reward state is invalid.")
	if reward.phase == ClassicRewardState.LEVEL_PHASE:
		return _resume_reward_level(reward, response, request_id)
	if reward.phase == ClassicRewardState.SPELL_PHASE:
		return _resume_reward_spells(reward, response, request_id)
	var body := response.body as InteractionResponse.TreasureBody
	if response.kind != InteractionRequest.TREASURE_DISTRIBUTION or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Treasure distribution requires a typed action.")
	var action := String(body.action)
	var events: Array[DomainEvent] = []
	if reward.completion_pending:
		if action == "cancel-completion":
			reward.completion_pending = false
			return _wait_for_reward(reward, request_id)
		if action != "confirm-completion":
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Treasure completion must be confirmed or cancelled.")
		var abandoned := reward.items().size()
		var no_items: Array[ItemInstance] = []
		reward.set_items(no_items)
		var forfeited := _game_state.party.pooled_wealth.to_data()
		_game_state.party.pooled_wealth = WealthState.new()
		reward.completion_pending = false
		events.append(DomainEvent.new(&"reward_remainder_left", {"itemCount": abandoned, "wealth": forfeited}))
		return _begin_reward_progression(reward, request_id, events)
	match action:
		"assign":
			var mutation := _assign_reward_item(reward, body)
			if not mutation.is_empty():
				return ScenarioRuntimeOperationResult.failed(StringName(mutation["code"]), mutation["message"])
			events.append(DomainEvent.new(&"reward_item_assigned", {"instanceId": body.instance_id, "characterId": body.character_id}))
		"discard":
			var pending := reward.first_item()
			if pending == null or body.instance_id != pending.id or reward.remove_item(pending.id) == null:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "The item being left behind is not the current reward item.")
			events.append(DomainEvent.new(&"reward_item_left", {"instanceId": pending.id, "itemId": pending.definition_id}))
		"pool":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var pool_probe := _rules.economy.pool_probe(_game_state.party)
			if not pool_probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", pool_probe.reason)
			_rules.economy.pool_party_wealth(_game_state.party)
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"reward_wealth_pooled", _game_state.party.pooled_wealth.to_data()))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-reward-pool"}))
		"share":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var share_probe := _rules.economy.share_probe(_game_state.party)
			if not share_probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", share_probe.reason)
			_rules.economy.share_pooled_wealth(_game_state.party)
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"reward_wealth_shared", _game_state.party.pooled_wealth.to_data()))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-reward-share"}))
		"transfer":
			var transfer_error := _transfer_reward_wealth(body)
			if not transfer_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(StringName(transfer_error["code"]), transfer_error["message"])
			events.append(DomainEvent.new(&"reward_wealth_transferred", body.to_data()))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 10051 if body.direction == &"to-character" else 663, "waitForCompletion": false, "source": "classic-reward-swap"}))
		"detect", "identify":
			var detection_error := _apply_reward_detection(reward, action, body)
			if not detection_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(StringName(detection_error["code"]), detection_error["message"])
			events.append(DomainEvent.new(&"reward_magic_%s" % ("detected" if action == "detect" else "identified"), {"characterId": body.character_id}))
		"done":
			if not reward.items().is_empty() or _reward_has_pooled_wealth():
				reward.completion_pending = true
				return _wait_for_reward(reward, request_id)
			return _begin_reward_progression(reward, request_id)
		_:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "The treasure action is unavailable.")
	return _wait_for_reward(reward, request_id, events)


func _assign_reward_item(reward: ClassicRewardState, body: InteractionResponse.TreasureBody) -> Dictionary:
	if body.instance_id.is_empty() or body.character_id.is_empty():
		return {"code": "invalid_interaction_response", "message": "Treasure assignment requires item and character IDs."}
	var pending := reward.first_item()
	var character := _game_state.party.character_by_id(body.character_id)
	var definition: ItemDefinition = null if pending == null else _content.item_by_id(pending.definition_id)
	if pending == null or pending.id != body.instance_id or character == null or definition == null or not _rules.inventory.can_restore_item(character, pending, definition):
		return {"code": "reward_assignment_unavailable", "message": "The selected character cannot receive the pending item."}
	if not _rules.inventory.restore_item(character, pending, definition):
		return {"code": "reward_assignment_failed", "message": "The item assignment could not be committed."}
	if reward.identified:
		pending.identified = true
	if reward.remove_item(pending.id) == null:
		_rules.inventory.remove_item(character, pending.id, definition)
		return {"code": "reward_assignment_failed", "message": "The committed item could not be removed from the reward queue."}
	return {}


func _transfer_reward_wealth(body: InteractionResponse.TreasureBody) -> Dictionary:
	if body.character_id.is_empty() or body.direction.is_empty() or body.wealth_kind.is_empty() or body.amount < 1:
		return {"code": "invalid_interaction_response", "message": "Treasure transfer requires character, direction, denomination, and amount."}
	var character := _game_state.party.character_by_id(body.character_id)
	var kind := _wealth_kind(String(body.wealth_kind))
	var amount := body.amount
	if character == null or kind < 0 or amount != (5 if kind == WealthState.Kind.GOLD else 1):
		return {"code": "invalid_interaction_response", "message": "The requested Classic wealth increment is invalid."}
	var transferred := _rules.economy.transfer_pool_to_character(_game_state.party, character, kind as WealthState.Kind, amount) if body.direction == &"to-character" else _rules.economy.transfer_character_to_pool(_game_state.party, character, kind as WealthState.Kind, amount) if body.direction == &"to-pool" else false
	if transferred:
		_recalculate_party_movement()
	return {} if transferred else {"code": "reward_transfer_unavailable", "message": "The selected wealth transfer is no longer available."}


func _apply_reward_detection(reward: ClassicRewardState, action: String, body: InteractionResponse.TreasureBody) -> Dictionary:
	if body.character_id.is_empty():
		return {"code": "invalid_interaction_response", "message": "Magic detection requires a caster."}
	var special := 63 if action == "detect" else 48
	var cost := 5 if action == "detect" else 25
	var caster_id := body.character_id
	var available := false
	for row: Dictionary in _reward_caster_rows(special, cost):
		if row["id"] == caster_id:
			available = true
			break
	if not available or reward.first_item() == null or (reward.magic_detected if action == "detect" else reward.identified):
		return {"code": "reward_spell_unavailable", "message": "The selected treasure spell is unavailable."}
	var caster := _game_state.party.character_by_id(caster_id)
	caster.spell_points -= cost
	if action == "detect":
		reward.magic_detected = true
	else:
		reward.identified = true
		for item: ItemInstance in reward.items():
			item.identified = true
	return {}


func _reward_caster_rows(special: int, cost: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		if not _character_can_cast_reward_spell(character) or character.spell_points < cost:
			continue
		var knows := false
		for spell_id: String in character.known_spells():
			var spell := _content.spell_by_id(spell_id)
			if spell != null and spell.special == special:
				knows = true
				break
		if knows:
			result.append({"id": character.id, "name": character.name, "spellPoints": character.spell_points, "cost": cost})
	return result


static func _character_can_cast_reward_spell(character: CharacterState) -> bool:
	return character != null and character.current_health > 0 and character.spell_points > 0 and character.conditions.value(ConditionRules.CONFUSED) == 0 and character.conditions.value(ConditionRules.SILENCED) == 0 and character.conditions.value(ConditionRules.HELPLESS) == 0 and character.conditions.value(ConditionRules.STUPID) == 0 and character.conditions.value(ConditionRules.ANIMATED) == 0


func _begin_reward_progression(reward: ClassicRewardState, request_id: String, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	reward.phase = ClassicRewardState.LEVEL_PHASE
	var character_ids: Array[String] = []
	for character: CharacterState in _game_state.party.characters():
		if character.current_health > 0 and character.experience > 0:
			character_ids.append(character.id)
	if not reward.set_level_character_ids(character_ids):
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_progression", "The level-up queue is invalid.")
	return _advance_reward_levels(reward, request_id, events)


func _advance_reward_levels(reward: ClassicRewardState, request_id: String, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	var ids := reward.level_character_ids()
	while reward.level_index < ids.size():
		var character := _game_state.party.character_by_id(ids[reward.level_index])
		var race: RaceDefinition = null if character == null else _content.race_by_id(character.race_id)
		var caste: CasteDefinition = null if character == null else _content.caste_by_id(character.caste_id)
		if character == null or race == null or caste == null or character.current_health <= 0 or character.experience <= 0:
			return ScenarioRuntimeOperationResult.failed(&"invalid_reward_progression", "A character in the level-up queue is no longer eligible.")
		var threshold_index := clampi(character.level, 1, 30) - 1
		character.experience -= caste.victory_threshold(threshold_index)
		var level_result := _rules.characters.level_up(character, race, caste, _rng)
		if level_result == null:
			return ScenarioRuntimeOperationResult.failed(&"character_level_failed", "Character '%s' could not level." % character.id)
		reward.pending_level_result = {"characterId": character.id, "characterName": character.name, "level": character.level, "stamina": level_result.stamina_gained, "spellPoints": level_result.spell_points_gained, "toHit": level_result.to_hit_gained, "magicResistance": level_result.magic_resistance_gained}
		if character.spellcaster_type > 0 and character.maximum_spell_points > 0:
			var spell_ids := reward.spell_character_ids()
			spell_ids.append(character.id)
			reward.set_spell_character_ids(spell_ids)
		events.append(DomainEvent.new(&"character_leveled", reward.pending_level_result))
		return _wait_for_reward(reward, request_id, events)
	reward.phase = ClassicRewardState.SPELL_PHASE
	return _advance_reward_spells(reward, request_id, events)


func _level_result_request(reward: ClassicRewardState, request_id: String) -> InteractionRequest:
	if reward.pending_level_result.is_empty():
		return null
	var result := reward.pending_level_result
	return InteractionRequest.from_payload(request_id, InteractionRequest.LEVEL_UP, {"mode": "result", "prompt": "Review the level gained.", "characterId": result["characterId"], "characterName": result["characterName"], "level": result["level"], "gains": {"stamina": result["stamina"], "spellPoints": result["spellPoints"], "toHit": result["toHit"], "magicResistance": result["magicResistance"]}})


func _resume_reward_level(reward: ClassicRewardState, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.LevelUpBody
	if response.kind != InteractionRequest.LEVEL_UP or body == null or body.action != &"continue" or body.character_id != reward.pending_level_result.get("characterId"):
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "The level result must be acknowledged by its character ID.")
	var character_id := String(reward.pending_level_result.get("characterId", ""))
	reward.pending_level_result.clear()
	reward.level_index += 1
	return _advance_reward_levels(reward, request_id, [DomainEvent.new(&"level_result_acknowledged", {"characterId": character_id})])


func _advance_reward_spells(reward: ClassicRewardState, request_id: String, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	if reward.spell_index >= reward.spell_character_ids().size():
		return _complete_reward(reward, events)
	return _wait_for_reward(reward, request_id, events)


func _reward_spell_request(reward: ClassicRewardState, request_id: String) -> InteractionRequest:
	var ids := reward.spell_character_ids()
	if reward.spell_index < 0 or reward.spell_index >= ids.size():
		return null
	var character := _game_state.party.character_by_id(ids[reward.spell_index])
	var caste: CasteDefinition = null if character == null else _content.caste_by_id(character.caste_id)
	if character == null or caste == null:
		return null
	var spells: Array[Dictionary] = []
	for spell: SpellDefinition in _reward_spell_candidates(character, caste):
		spells.append({"id": spell.id, "name": spell.name, "classicId": spell.classic_id, "cost": _rules.characters.spell_selection_cost(spell), "selected": character.known_spells().has(spell.id)})
	return InteractionRequest.from_payload(request_id, InteractionRequest.LEVEL_UP, {"mode": "spell-selection", "prompt": "Choose the spells this character knows.", "characterId": character.id, "characterName": character.name, "pointTotal": _rules.characters.spell_selection_total(character, caste), "spells": spells})


func _resume_reward_spells(reward: ClassicRewardState, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var ids := reward.spell_character_ids()
	var body := response.body as InteractionResponse.LevelUpBody
	if response.kind != InteractionRequest.LEVEL_UP or body == null or body.action != &"confirm-spells" or reward.spell_index < 0 or reward.spell_index >= ids.size() or body.character_id != ids[reward.spell_index]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Spell selection requires the pending character and spell IDs.")
	var character := _game_state.party.character_by_id(ids[reward.spell_index])
	var caste: CasteDefinition = null if character == null else _content.caste_by_id(character.caste_id)
	if character == null or caste == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_progression", "The spell-selection character is unavailable.")
	var candidates: Dictionary = {}
	for spell: SpellDefinition in _reward_spell_candidates(character, caste):
		candidates[spell.id] = spell
	var selected: Array[String] = []
	var spent := 0
	for value: String in body.spell_ids:
		if selected.has(value) or not candidates.has(value):
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "The selected spell list contains an unavailable or duplicate spell.")
		selected.append(value)
		spent += _rules.characters.spell_selection_cost(candidates[value])
	var total := _rules.characters.spell_selection_total(character, caste)
	if spent > total:
		return ScenarioRuntimeOperationResult.failed(&"spell_selection_budget_exceeded", "The selected spells exceed the Classic point budget.")
	character.set_known_spells(selected)
	reward.spell_index += 1
	return _advance_reward_spells(reward, request_id, [DomainEvent.new(&"level_spells_selected", {"characterId": character.id, "spellIds": selected, "pointsRemaining": total - spent})])


func _reward_spell_candidates(character: CharacterState, caste: CasteDefinition) -> Array[SpellDefinition]:
	var result: Array[SpellDefinition] = []
	var maximum_level := _rules.characters.maximum_spell_selection_level(caste)
	for spell: SpellDefinition in _content.spell_definitions():
		if int(float(spell.classic_id) / 1000.0) == character.spellcaster_type and spell.classic_tier() >= 0 and spell.classic_tier() < maximum_level and spell.classic_slot() >= 1 and spell.classic_slot() <= 12:
			result.append(spell)
	result.sort_custom(func(left: SpellDefinition, right: SpellDefinition) -> bool: return left.classic_id < right.classic_id)
	return result


func _complete_reward(reward: ClassicRewardState, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	var completed_events: Array[DomainEvent] = []
	completed_events.assign(events)
	completed_events.append(DomainEvent.new(&"reward_completed", {"origin": String(reward.origin), "sourceId": reward.source_id, "experienceByCharacter": reward.experience_awards()}))
	if reward.origin == &"battle":
		if _game_state.combat == null or _game_state.combat.battle_id != reward.source_id or not _game_state.combat.rewards_started:
			return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The battle reward no longer matches its completed battle.")
		var combat := _game_state.combat
		combat.rewards_completed = true
		var outcome := combat.outcome
		var battle := _content.battle_by_id(reward.source_id)
		if battle != null:
			_append_battle_after_message(battle, completed_events)
		completed_events.append(DomainEvent.new(&"battle_returned", {"battleId": reward.source_id, "outcome": String(outcome)}))
		# The completed battle remains session-owned through every ally, fumble,
		# treasure, level, and spell boundary. Release it only after the terminal
		# reward transaction has committed so both direct and VM callers return once.
		_game_state.combat = null
	return ScenarioRuntimeOperationResult.completed(reward.source_id, completed_events)


func _reward_state_is_valid(reward: ClassicRewardState) -> bool:
	if reward.source_id.is_empty() or reward.origin not in [&"scenario", &"battle"]:
		return false
	if reward.origin == &"battle" and (_game_state.combat == null or not _game_state.combat.completed or not _game_state.combat.rewards_started or _game_state.combat.rewards_completed or _game_state.combat.battle_id != reward.source_id):
		return false
	for item: ItemInstance in reward.items():
		if _content.item_by_id(item.definition_id) == null:
			return false
	for character_id: Variant in reward.experience_awards():
		if _game_state.party.character_by_id(String(character_id)) == null:
			return false
	for character_id: String in reward.level_character_ids():
		if _game_state.party.character_by_id(character_id) == null:
			return false
	for character_id: String in reward.spell_character_ids():
		if _game_state.party.character_by_id(character_id) == null:
			return false
	if not reward.pending_level_result.is_empty() and _game_state.party.character_by_id(String(reward.pending_level_result.get("characterId", ""))) == null:
		return false
	return true


func _reward_has_pooled_wealth() -> bool:
	return _game_state.party.pooled_wealth.gold > 0 or _game_state.party.pooled_wealth.gems > 0 or _game_state.party.pooled_wealth.jewelry > 0


static func _wealth_kind(value: String) -> int:
	match value:
		"gold": return WealthState.Kind.GOLD
		"gems": return WealthState.Kind.GEMS
		"jewelry": return WealthState.Kind.JEWELRY
	return -1


func _money_movement_context_error() -> String:
	for character: CharacterState in _game_state.party.characters():
		if _content.race_by_id(character.race_id) == null or _content.caste_by_id(character.caste_id) == null:
			return "Character '%s' has no package-backed race or class for Classic movement recalculation." % character.id
	return ""


func _recalculate_party_movement() -> void:
	for character: CharacterState in _game_state.party.characters():
		var race := _content.race_by_id(character.race_id)
		var caste := _content.caste_by_id(character.caste_id)
		_rules.characters.recalculate_movement(character, race, caste.movement_bonus)


static func _monster_reward_experience(monster: MonsterState, definition: MonsterDefinition) -> int:
	var base_values: Array[int] = [15, 30, 45, 65, 80, 100, 140, 200, 300, 450, 700, 1100, 1800, 2300, 2800, 3200, 3700, 4200, 4700, 5200, 5700]
	var increment_values: Array[int] = [3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 39, 42, 45, 50, 55, 60, 65, 70, 75]
	var index := clampi(monster.hit_dice, 0, 20)
	var base := base_values[index] if monster.hit_dice <= 20 else 6200
	var increment := increment_values[index] if monster.hit_dice <= 20 else 80
	return base + definition.experience + monster.maximum_health * increment


func grant_item(character_id: String, item_id: String, identified: bool) -> ScenarioRuntimeOperationResult:
	var character := _game_state.party.character_by_id(character_id)
	var item := _content.item_by_id(item_id)
	if character == null or item == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_item_target", "Grant Item references an unavailable character or item.")
	var instance := _rules.inventory.add_item(character, item, _game_state.next_instance_id("scenario.item"), identified)
	if instance == null:
		return ScenarioRuntimeOperationResult.failed(&"inventory_full", "The character cannot carry the granted item.")
	return ScenarioRuntimeOperationResult.completed(instance.id, [DomainEvent.new(&"item_granted", {"characterId": character.id, "itemId": item.id, "instanceId": instance.id, "identified": identified})])


static func _whole_number(value: Variant) -> bool:
	return value is int or value is float and is_equal_approx(value, round(value))
