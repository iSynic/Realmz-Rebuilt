## Validates Scenario VM continuations before a restored playthrough can be committed.

class_name SessionScenarioRestoreValidator
extends RefCounted

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
		character_ids[String(character_id)] = true
	for character_id: String in reward.level_character_ids():
		character_ids[character_id] = true
	for character_id: String in reward.spell_character_ids():
		character_ids[character_id] = true
	if not reward.pending_level_result.is_empty():
		character_ids[String(reward.pending_level_result.get("characterId", ""))] = true
	for character_id: Variant in character_ids:
		if String(character_id).is_empty() or state.party.character_by_id(String(character_id)) == null:
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
	return update != null and not update.character_id.is_empty() and state.party.character_by_id(update.character_id) != null \
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
		and exploration.trigger_ids == ExplorationContinuationWorkflow.selected_placed_trigger_ids(content, cell, state.world) \
		and exploration.random_region_ids == state.world.triggers.random_region_ids_at(map, exploration.coordinate) \
		and exploration.random_region_index == exploration.random_region_ids.size() - 1
