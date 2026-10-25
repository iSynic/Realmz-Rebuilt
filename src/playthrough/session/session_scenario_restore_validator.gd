## Validates Scenario VM continuations before a restored playthrough can be committed.

class_name SessionScenarioRestoreValidator
extends RefCounted

static func combat_vm_continuation_is_valid(state: GameState, rules: RealmzRules, snapshot: ScenarioVmSnapshot, depth: int = 0) -> bool:
	if depth > 32 or snapshot == null:
		return false
	var pending := snapshot.pending_continuation
	var runtime := pending.runtime if pending != null else null
	if runtime == null:
		return true
	var body := runtime.combat()
	if runtime.kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_FRIENDLY_COLLISION, ScenarioRuntimeContinuation.SAFE_COMBAT_FRIENDLY_COLLISION]:
		var request := snapshot.pending_request
		if body == null or body.mode != &"friendly" or request == null or request.to_data() != CombatInteractionRequestBuilder.friendly_collision(request.request_id).to_data():
			return false
		var combat := state.combat
		if combat == null or combat.completed or combat.battle_id != body.battle_id or combat.turns.active_actor_id() != body.actor_id:
			return false
		var reaction := combat.pending_reaction
		return reaction != null and reaction.awaits_friendly_collision_choice() and reaction.mover_id == body.actor_id and reaction.destination == body.destination and rules.combat_flow.reactions.friendly_collision_target_id(state, body.actor_id, body.destination) == reaction.friendly_collision_target_id
	if runtime.kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT, ScenarioRuntimeContinuation.SAFE_COMBAT]:
		return state.combat == null or state.combat.pending_reaction == null or not state.combat.pending_reaction.awaits_friendly_collision_choice()
	var nested := body.macro_vm if body != null else runtime.opcode_death().macro_vm if runtime.opcode_death() != null else null
	if runtime.body is ScenarioClockContinuationBody:
		nested = (runtime.body as ScenarioClockContinuationBody).timer_vm
	return nested == null or nested.pending_request != null and snapshot.pending_request != null and nested.pending_request.to_data() == snapshot.pending_request.to_data() and combat_vm_continuation_is_valid(state, rules, nested, depth + 1)


static func native_operation_continuation_is_valid(content: RealmzContent, state: GameState, snapshot: ScenarioVmSnapshot, depth: int = 0) -> bool:
	if depth > 32 or snapshot == null: return false
	if snapshot.execution != null and not execution_calls_are_valid(content, state, snapshot.execution): return false
	var runtime := snapshot.pending_continuation.runtime if snapshot.pending_continuation != null else null
	if runtime == null: return true
	var age := runtime.body as ScenarioAgeContinuationBody
	if age != null: return _age_batch_is_valid(state, age.updates, age.index, snapshot.pending_request)
	if runtime.kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_AGE, ScenarioRuntimeContinuation.SAFE_COMBAT_AGE]:
		var combat_age := runtime.combat()
		if state.combat == null or state.combat.completed or state.combat.pending_monster_attack == null or combat_age == null or combat_age.battle_id != state.combat.battle_id: return false
		return _age_batch_is_valid(state, combat_age.updates, combat_age.index, snapshot.pending_request)
	if runtime.body is ScenarioClockScanBody:
		var scan := runtime.body as ScenarioClockScanBody
		if scan.timer_index > content.scenario_records.timed_encounters().size() or snapshot.pending_request == null: return false
		for update: AgeUpdateRequestBody in scan.updates:
			if not age_update_payload_is_valid(state, update): return false
		var request := InteractionRequest.age_update_body(snapshot.pending_request.request_id, scan.updates[scan.age_index - 1])
		return request.to_data() == snapshot.pending_request.to_data()
	var clock_body := runtime.body as ScenarioClockContinuationBody
	var nested := runtime.nested_vm()
	if runtime.body is ScenarioFumbleContinuationBody:
		var fumble := runtime.body as ScenarioFumbleContinuationBody
		var message := content.scenario_records.message_by_id(fumble.message_id)
		if state.combat == null or state.combat.battle_id != fumble.battle_id or state.combat.turns.active_actor_id() != fumble.actor_id or not CombatFlowActions.scripted_fumble_guard_reason(state).is_empty() or message == null or snapshot.pending_request == null: return false
		var request := InteractionRequest.from_payload(snapshot.pending_request.request_id, InteractionRequest.ACKNOWLEDGE, {"prompt": message.text, "messageId": message.id, "presentation": "classic-textbox", "journalEligible": ScenarioProgressState.journal_message_id_is_valid(message.id), "journalRecorded": state.scenario_progress.journal_message_is_recorded(message.id)})
		if request.to_data() != snapshot.pending_request.to_data(): return false
	if clock_body != null:
		var encounters := content.scenario_records.timed_encounters()
		if clock_body.timer_index > encounters.size(): return false
		if not clock_body.return_program_id.is_empty() and content.scenario.program_by_id(clock_body.return_program_id) == null: return false
		if nested != null:
			if clock_body.timer_index < 1 or encounters[clock_body.timer_index - 1].program_id != clock_body.program_id: return false
			var execution := nested.execution if nested.execution != null else ScenarioLegacyExecutionCodec.convert(nested, content.scenario)
			if not ScenarioExecutionRestoreRules.is_valid(execution, content.scenario): return false
		else:
			for update: AgeUpdateRequestBody in clock_body.updates:
				if not age_update_payload_is_valid(state, update): return false
			var request := InteractionRequest.age_update_body("clock.validation", clock_body.updates[clock_body.age_index - 1])
			if snapshot.pending_request == null: return false
			request.request_id = snapshot.pending_request.request_id
			if request.to_data() != snapshot.pending_request.to_data(): return false
	return nested == null or nested.pending_request != null and snapshot.pending_request != null and nested.pending_request.to_data() == snapshot.pending_request.to_data() and native_operation_continuation_is_valid(content, state, nested, depth + 1)


static func _age_batch_is_valid(state: GameState, updates: Array[AgeUpdateRequestBody], index: int, request: InteractionRequest) -> bool:
	if request == null or request.kind != InteractionRequest.AGE_UPDATE or index < 1 or index > updates.size(): return false
	for update: AgeUpdateRequestBody in updates:
		if not age_update_payload_is_valid(state, update): return false
	var body := request.body as AgeUpdateRequestBody
	return body != null and body.same_values(updates[index - 1])


static func vm_reward_continuation_is_valid(content: RealmzContent, state: GameState, vm: ScenarioVm) -> bool:
	var snapshot := vm.snapshot()
	if snapshot.pending_continuation == null:
		return true
	var runtime := snapshot.pending_continuation.runtime
	if runtime == null or runtime.kind != ScenarioRuntimeContinuation.CLASSIC_REWARD:
		return true
	var runtime_body := runtime.body as ScenarioRewardContinuationBody
	var reward := runtime_body.state if runtime_body != null else null
	return reward != null and reward_continuation_is_valid(content, state, reward, vm.pending_request())


static func player_map_vm_continuation_is_valid(content: RealmzContent, state: GameState, vm: ScenarioVm) -> bool:
	var snapshot := vm.snapshot()
	if snapshot.pending_continuation == null:
		return true
	var runtime := snapshot.pending_continuation.runtime
	if runtime == null or runtime.kind != ScenarioRuntimeContinuation.CLASSIC_PLAYER_MAP:
		return true
	var request := vm.pending_request()
	var runtime_body := runtime.body as ScenarioTextContinuationBody
	var player_map_id := "" if runtime_body == null else runtime_body.player_map_id
	var body: AcknowledgeRequestBody = null
	if request != null:
		body = request.body as AcknowledgeRequestBody
	return request != null and request.kind == InteractionRequest.ACKNOWLEDGE and body != null and body.presentation == &"player-map" and body.player_map_id == player_map_id and body.has_presentation and body.has_player_map_id and not body.has_message_id and not body.has_journal_state and not body.has_sound_id and content.world.player_map_by_id(player_map_id) != null and state.world.exploration.has_map(player_map_id)


static func thief_vm_continuation_is_valid(content: RealmzContent, state: GameState, rng_state: RealmzRngState, vm: ScenarioVm) -> bool:
	var snapshot := vm.snapshot()
	if snapshot.pending_continuation == null:
		return true
	var runtime := snapshot.pending_continuation.runtime
	if runtime == null or runtime.kind not in [ScenarioRuntimeContinuation.CLASSIC_THIEF_ENCOUNTER, ScenarioRuntimeContinuation.CLASSIC_PICK_LOCK, ScenarioRuntimeContinuation.CLASSIC_THIEF_RESOLUTION]:
		return true
	var owner := runtime.body as ScenarioThiefContinuationBody
	var encounter := content.scenario_records.complex_encounter_by_id(owner.encounter_id) if owner != null else null
	var thief := content.scenario_records.thief_encounter_by_id(encounter.thief_success) if encounter != null and encounter.thief else null
	var request := vm.pending_request()
	if owner == null or encounter == null or thief == null or request == null:
		return false
	if runtime.kind == ScenarioRuntimeContinuation.CLASSIC_THIEF_ENCOUNTER:
		var body := request.body as ThiefEncounterRequestBody
		return request.kind == InteractionRequest.THIEF_ENCOUNTER and body != null and body.encounter_id == encounter.id and _valid_thief_request(content, state, thief, body)
	if runtime.kind == ScenarioRuntimeContinuation.CLASSIC_THIEF_RESOLUTION:
		return _valid_thief_resolution_request(content, state, thief, owner, request)
	var body := request.body as PickLockRequestBody
	var character := state.party.character_by_id(owner.character_id)
	if request.kind != InteractionRequest.PICK_LOCK or body == null or owner.action_index not in [2, 4, 6, 7] or body.encounter_id != encounter.id or body.action_index != owner.action_index or body.character_id != owner.character_id or character == null or character.current_health <= 0 or character.conditions.is_active(ConditionRules.ANIMATED):
		return false
	var flags := state.scenario_progress.encounters.thief_type_flags(thief)
	var chance := ClassicPickLockRules.chance(character.ability_value(ClassicPickLockRules.ability_index(owner.action_index)), thief.modifiers()[owner.action_index])
	var expected_frames := ClassicPickLockRules.preview(rng_state, thief.tumblers, chance)
	return flags.size() == 10 and not flags[owner.action_index] and chance > 0 and body.action_label == ClassicPickLockRules.action_label(owner.action_index) and body.character_name == character.name and body.portrait_id == character.portrait_id and body.chance_percent == chance and body.yellow_threshold == ClassicPickLockRules.yellow_threshold(chance) and body.green_threshold == ClassicPickLockRules.green_threshold(chance) and body.frame_rate == ClassicPickLockRules.FRAME_RATE and body.time_limit_frames == ClassicPickLockRules.time_limit_frames(thief.tumblers) and body.frames == expected_frames


static func _valid_thief_request(content: RealmzContent, state: GameState, thief: ThiefEncounterDefinition, body: ThiefEncounterRequestBody) -> bool:
	var prompt_id := absi(thief.prompts()[0]) if not thief.prompts().is_empty() else 0
	var message := content.scenario_records.message_by_id(prompt_id)
	if body.prompt != (message.text if message != null else "Choose a thief action."):
		return false
	var opening_sounds := thief.prompt_sounds()
	if body.sound_id not in [0, opening_sounds[0] if not opening_sounds.is_empty() else 0]:
		return false
	var flags := state.scenario_progress.encounters.thief_type_flags(thief)
	var eligible: Array[CharacterState] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and not character.conditions.is_active(ConditionRules.ANIMATED):
			eligible.append(character)
	if flags.size() != 10 or body.characters.size() != eligible.size():
		return false
	for index: int in eligible.size():
		var character := eligible[index]
		var detached := body.characters[index]
		if detached.id != character.id or detached.name != character.name or detached.portrait_id != character.portrait_id or detached.actions.size() != 8:
			return false
		for action_index: int in 8:
			var action := detached.actions[action_index]
			var ability := character.ability_value(ClassicPickLockRules.ability_index(action_index))
			var effective := ability + thief.modifiers()[action_index]
			var expected_enabled := flags[action_index] and ability != 0 and effective > 0
			var expected_reason := "" if expected_enabled else "This action is no longer available." if not flags[action_index] else "This character lacks the required ability." if ability == 0 else "The authored modifier reduces this action below zero."
			if action.index != action_index or action.label != ClassicPickLockRules.action_label(action_index) or action.value != (effective if ability != 0 else 0) or action.enabled != expected_enabled or action.reason != expected_reason:
				return false
	return true


static func _valid_thief_resolution_request(content: RealmzContent, state: GameState, thief: ThiefEncounterDefinition, owner: ScenarioThiefContinuationBody, request: InteractionRequest) -> bool:
	var body := request.body as AcknowledgeRequestBody
	var character := state.party.character_by_id(owner.character_id)
	if request.kind != InteractionRequest.ACKNOWLEDGE or body == null or character == null or owner.action_index < 0 or owner.action_index > 7 or body.presentation != &"classic-textbox" or not body.has_presentation or body.has_journal_state or body.has_player_map_id:
		return false
	var flags := state.scenario_progress.encounters.thief_type_flags(thief)
	if flags.size() != 10:
		return false
	if owner.phase == &"trap-message":
		return owner.trap_pending and flags[9] and body.prompt == "A trap is sprung." and not body.has_message_id and not body.has_sound_id
	if owner.phase != &"action-message" or flags[owner.action_index]:
		return false
	var text_ids := thief.success_text() if owner.succeeded else thief.failure_text()
	var sound_ids := thief.success_sounds() if owner.succeeded else thief.failure_sounds()
	var signed_message_id := text_ids[owner.action_index]
	var message_id := absi(signed_message_id)
	var message := content.scenario_records.message_by_id(message_id)
	return signed_message_id > 0 and message != null and body.has_message_id and body.message_id == message_id and body.prompt == message.text and body.has_sound_id and body.sound_id == sound_ids[owner.action_index] and (not owner.trap_pending or not owner.succeeded and flags[9])


static func reward_continuation_is_valid(content: RealmzContent, state: GameState, reward: ClassicRewardState, request: InteractionRequest) -> bool:
	if reward == null or request == null or reward.source_id.is_empty() or reward.origin not in [&"scenario", &"battle"]:
		return false
	if reward.origin == &"battle" and (state.combat == null or not state.combat.completed or not state.combat.rewards_started or state.combat.rewards_completed or state.combat.battle_id != reward.source_id):
		return false
	if (reward.origin == &"battle" and reward.battle_stage not in [ClassicRewardState.ORDINARY_BATTLE_STAGE, ClassicRewardState.BONUS_BATTLE_STAGE]) or (reward.origin != &"battle" and (reward.battle_stage != ClassicRewardState.NO_BATTLE_STAGE or reward.bonus_treasure_classic_id != 0)) or (reward.battle_stage == ClassicRewardState.BONUS_BATTLE_STAGE and reward.bonus_treasure_classic_id != 0):
		return false
	if reward.bonus_treasure_classic_id != 0 and content.economy.treasure_by_classic_id(reward.bonus_treasure_classic_id) == null:
		return false
	for item: ItemInstance in reward.items():
		if content.items.item_by_id(item.definition_id) == null:
			return false
	var character_ids: Dictionary = {}
	for character_id: Variant in reward.experience_awards():
		character_ids[str(character_id)] = true
	for character_id: String in reward.level_character_ids():
		character_ids[character_id] = true
	for character_id: String in reward.spell_character_ids():
		character_ids[character_id] = true
	if not reward.pending_level_result.is_empty():
		character_ids[str(reward.pending_level_result.get("characterId", ""))] = true
	for character_id: Variant in character_ids:
		if str(character_id).is_empty() or state.party.character_by_id(str(character_id)) == null:
			return false
	if reward.phase == ClassicRewardState.ITEM_PHASE:
		var treasure_body := request.body as TreasureRequestBody
		if request.kind != InteractionRequest.TREASURE_DISTRIBUTION or treasure_body == null:
			return false
		var expected_mode := &"completion-confirmation" if reward.completion_pending else &"ordinary"
		if treasure_body.mode != expected_mode:
			return false
		if reward.completion_pending:
			return not treasure_body.has_item and not treasure_body.has_items
		var pending_items := reward.items()
		if not treasure_body.has_items or treasure_body.has_item or treasure_body.items.size() != pending_items.size():
			return false
		for index: int in pending_items.size():
			if treasure_body.items[index].instance_id != pending_items[index].id or treasure_body.items[index].definition_id != pending_items[index].definition_id:
				return false
		return true
	if reward.phase == ClassicRewardState.LEVEL_PHASE:
		var level_body := request.body as LevelUpRequestBody
		return not reward.pending_level_result.is_empty() and request.kind == InteractionRequest.LEVEL_UP and level_body != null and level_body.mode == &"result" and level_body.character_id == reward.pending_level_result.get("characterId")
	if reward.phase == ClassicRewardState.SPELL_PHASE:
		var spell_ids := reward.spell_character_ids()
		var level_body := request.body as LevelUpRequestBody
		return reward.spell_index < spell_ids.size() and request.kind == InteractionRequest.LEVEL_UP and level_body != null and level_body.mode == &"spell-selection" and level_body.character_id == spell_ids[reward.spell_index]
	return false


static func age_update_payload_is_valid(state: GameState, update: AgeUpdateRequestBody) -> bool:
	var character := state.party.character_by_id(update.character_id) if update != null else null
	return character != null and update.character_name == character.name and update.race_id == character.race_id \
		and update.portrait_id == character.portrait_id and update.combat_icon_id == character.combat_icon_id \
		and update.presentation == &"classic-age-update" \
		and update.age_group >= 1 and update.age_group <= 5 \
		and update.transition in [-1, 1] \
		and update.changes.size() == 15


static func ready_post_move_continuation_is_valid(content: RealmzContent, state: GameState, continuation: SessionContinuation) -> bool:
	if continuation == null or continuation.kind != &"post-move":
		return false
	var exploration := continuation.exploration()
	if exploration == null or exploration.trigger_index != 0 or not exploration.active_trigger_id.is_empty() or not exploration.active_random_program_id.is_empty() or not exploration.active_random_region_id.is_empty() or not exploration.random_battle_stage.is_empty() or exploration.action_point_destination_depth < 0 or exploration.action_point_destination_depth > 1:
		return false
	var map := content.world.map_by_id(exploration.map_id)
	var cell: MapCell = null if map == null else map.topology.cell_at(exploration.coordinate)
	return cell != null and state.party.map_id == map.id and state.party.coordinate == exploration.coordinate \
		and exploration.trigger_ids == ClassicActionPointRules.selected_placed_trigger_ids(content, map, exploration.coordinate, state.world, exploration.action_point_destination_depth > 0) \
		and exploration.random_region_ids == state.world.triggers.random_region_ids_at(map, exploration.coordinate) \
		and exploration.random_region_index == exploration.random_region_ids.size() - 1


static func round_cursor_owner_is_valid(state: GameState, continuation: SessionContinuation, snapshot: ScenarioVmSnapshot) -> bool:
	if snapshot != null and snapshot.execution != null and not direct_macro_owner_is_valid(continuation, snapshot.execution): return false
	var combat := state.combat
	if combat == null or combat.round_cursor == null: return true
	var cursor := combat.round_cursor
	var macro_wait := cursor.phase == &"battle-macro"
	var subject := cursor.waiting_monster_id if not cursor.waiting_monster_id.is_empty() else combat.death_macros.pending_id()
	if not macro_wait and subject.is_empty(): return false
	if snapshot != null and snapshot.execution != null:
		for record: ScenarioExecutionRecord in snapshot.execution.records:
			if record.kind != ScenarioExecutionRecord.Kind.OPERATION or record.operation.child_call == null: continue
			if record.operation.child_call.kind != ScenarioProgramCall.Kind.MACRO: continue
			var call := record.operation.child_call.macro
			if call.battle_id != combat.battle_id: continue
			if macro_wait and call.kind == ScenarioMacroCall.Kind.ROUND and call.program_id == "xap:%d" % absi(combat.macro_id): return true
			if not macro_wait and call.kind == ScenarioMacroCall.Kind.DEATH and call.combatant_id == subject: return true
		return false
	var direct := continuation.combat()
	if direct != null:
		if direct.battle_id != combat.battle_id: return false
		if macro_wait:
			return continuation.kind == &"combat-round-macro" and direct.program_id == "xap:%d" % absi(combat.macro_id)
		return continuation.kind == &"combat-death-macro" and direct.combatant_id == subject
	for _depth: int in 32:
		if snapshot == null or snapshot.pending_request == null or snapshot.pending_continuation == null: return false
		var runtime := snapshot.pending_continuation.runtime
		if runtime == null: return false
		var body := runtime.combat()
		if body != null and body.battle_id == combat.battle_id:
			if macro_wait and runtime.kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT_MACRO]:
				return body.program_id == "xap:%d" % absi(combat.macro_id)
			if not macro_wait and runtime.kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_DEATH_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT_DEATH_MACRO]:
				return body.combatant_id == subject
		snapshot = runtime.nested_vm()
	return false


static func execution_calls_are_valid(content: RealmzContent, state: GameState, execution: ScenarioExecutionState) -> bool:
	var shared := execution.classic
	if shared.encounter_kind == &"simple" and content.scenario_records.simple_encounter_by_id(shared.encounter_id) == null: return false
	if shared.encounter_kind == &"complex" and content.scenario_records.complex_encounter_by_id(shared.encounter_id) == null: return false
	for record: ScenarioExecutionRecord in execution.records:
		if record.kind != ScenarioExecutionRecord.Kind.OPERATION or record.operation.child_call == null: continue
		var child := record.operation.child_call
		if child.kind == ScenarioProgramCall.Kind.TIMER:
			var encounters := content.scenario_records.timed_encounters()
			var index := child.timer_scan.timer_index
			if index < 1 or index > encounters.size() or encounters[index - 1].program_id != child.timer_program_id or encounters[index - 1].id != child.timer_context.timed_encounter_id: return false
			continue
		if child.kind == ScenarioProgramCall.Kind.APPLICATION:
			if content.scenario.application_hook_program_id(child.application.context.application_hook) != child.application.program_id: return false
			continue
		var call := child.macro
		if state.combat == null or call.battle_id != state.combat.battle_id: return false
		if call.kind == ScenarioMacroCall.Kind.DEATH and state.combat.roster.monster_by_id(call.combatant_id) == null: return false
		if call.queued_source != null:
			if state.combat.death_macros.actor_id().is_empty(): return false
			var queued := state.combat.death_macros.pending_request()
			if queued == null or queued.combatant_id != call.combatant_id: return false
			if queued.macro_id != 0 and (queued.program_id() != call.program_id or queued.classic_monster_id != call.classic_monster_id or queued.source.to_data() != call.queued_source.to_data()): return false
	return true


static func pending_combat_work_is_valid(state: GameState, owner: SessionContinuation, saved: ScenarioVmSnapshot, interaction: InteractionRequest) -> bool:
	if not _captured_death_queue_has_owner(state, owner, saved, interaction): return false
	if state.combat != null and not state.combat.pending_operations.age_updates.is_empty(): return false
	if state.combat == null or state.combat.pending_operations.death_macro == null: return true
	if state.combat.completed: return false
	var age := owner.age() if owner != null else null
	if age != null:
		return age.resume_kind == &"combat-monster-turns" and interaction != null and interaction.kind == InteractionRequest.AGE_UPDATE
	if saved.pending_request == null or saved.pending_request.kind != InteractionRequest.AGE_UPDATE or saved.pending_continuation == null: return false
	var runtime := saved.pending_continuation.runtime
	var combat := runtime.combat() if runtime != null else null
	return combat != null and combat.battle_id == state.combat.battle_id and not combat.updates.is_empty()


static func _captured_death_queue_has_owner(state: GameState, owner: SessionContinuation, saved: ScenarioVmSnapshot, interaction: InteractionRequest) -> bool:
	var combat := state.combat
	if combat == null or combat.death_macros.pending_id().is_empty() or not combat.death_macros.actor_id().is_empty(): return true
	if combat.completed or saved.execution == null: return false
	for request: CombatDeathMacroRequest in combat.death_macros.facts():
		if request.macro_id == 0 or not request.source.available: return false
	for record: ScenarioExecutionRecord in saved.execution.records:
		if record.kind != ScenarioExecutionRecord.Kind.OPERATION or record.operation.phase != ScenarioOperationExecutionRecord.Phase.CHILD: continue
		var child := record.operation.child_call
		if child != null and child.kind == ScenarioProgramCall.Kind.MACRO and child.macro.battle_id == combat.battle_id: return true
	var pending := interaction if interaction != null else saved.pending_request
	if combat.pending_reaction == null or pending == null: return false
	var runtime := saved.pending_continuation.runtime if saved.pending_continuation != null else null
	if pending.kind == InteractionRequest.AGE_UPDATE:
		return combat.pending_monster_attack != null and (owner != null and owner.kind == &"age-updates" or runtime != null and runtime.kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_AGE, ScenarioRuntimeContinuation.SAFE_COMBAT_AGE])
	return combat.pending_reaction.awaits_friendly_collision_choice() and (owner != null and owner.kind == &"combat-friendly-collision" or runtime != null and runtime.kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_FRIENDLY_COLLISION, ScenarioRuntimeContinuation.SAFE_COMBAT_FRIENDLY_COLLISION])


static func direct_macro_owner_is_valid(continuation: SessionContinuation, execution: ScenarioExecutionState) -> bool:
	var direct_wait := continuation != null and continuation.kind in [&"combat-round-macro", &"combat-death-macro"]
	if execution.records.is_empty(): return not direct_wait
	var root := execution.records[0]
	if root.kind != ScenarioExecutionRecord.Kind.OPERATION or root.operation.return_kind != ScenarioOperationExecutionRecord.ReturnKind.DIRECT:
		return not direct_wait
	if root.operation.child_call == null or root.operation.child_call.kind != ScenarioProgramCall.Kind.MACRO: return false
	var call := root.operation.child_call.macro
	var caller := continuation.combat() if continuation != null else null
	if call.return_kind != ScenarioMacroCall.ReturnKind.DIRECT or caller == null or caller.battle_id != call.battle_id or caller.program_id != call.program_id: return false
	if call.kind == ScenarioMacroCall.Kind.ROUND: return continuation.kind == &"combat-round-macro"
	return continuation.kind == &"combat-death-macro" and caller.combatant_id == call.combatant_id and caller.reset_traitor_on_complete == call.reset_traitor_on_complete
