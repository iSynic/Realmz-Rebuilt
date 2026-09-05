## Owns Treasure interaction, reward assignment, level gains, and spell learning.

class_name ClassicRewardWorkflow
extends ClassicRewardOperationsSupport

class RewardItemSelection:
	extends RefCounted

	var definitions: Array[ItemDefinition] = []
	var magic_detected: Array[bool] = []
	var error: ScenarioRuntimeOperationResult


class RewardExperienceAwards:
	extends RefCounted

	var recipients: Array[CharacterState] = []
	var awards: Dictionary = {}
	var error: ScenarioRuntimeOperationResult


func resume_reward(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var state_checkpoint := _game_state.to_data()
	var rng_checkpoint := _rng.checkpoint()
	var operation := _resume_reward(continuation, response, request_id)
	return _rollback_failed_reward(operation, state_checkpoint, rng_checkpoint)

func begin_reward(origin: StringName, source_id: String, total_experience: int, wealth: WealthState, item_ids: Array[String], request_id: String, battle_stage: StringName = ClassicRewardState.NO_BATTLE_STAGE, bonus_treasure_classic_id: int = 0, leading_items: Array[ItemInstance] = [], item_magic_detected: Array[bool] = []) -> ScenarioRuntimeOperationResult:
	if wealth == null or item_ids.size() + leading_items.size() > ClassicRewardState.MAX_PENDING_ITEMS or not item_magic_detected.is_empty() and item_magic_detected.size() != item_ids.size():
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The reward exceeds the supported Classic reward bounds.")
	var experience_multiplier := _reward_experience_multiplier()
	var scaled_experience := PartySetupRules.scale_experience_by_multiplier(total_experience, experience_multiplier)
	var scaled_wealth := WealthState.new(
		PartySetupRules.scale_money(wealth.gold, _game_state.difficulty),
		PartySetupRules.scale_money(wealth.gems, _game_state.difficulty),
		PartySetupRules.scale_money(wealth.jewelry, _game_state.difficulty),
	)
	var item_selection := _select_reward_items(source_id, item_ids, item_magic_detected)
	if item_selection.error != null:
		return item_selection.error
	var reward := ClassicRewardState.new(origin, source_id, scaled_experience, scaled_wealth)
	reward.battle_stage = battle_stage
	reward.bonus_treasure_classic_id = bonus_treasure_classic_id
	var item_error := _create_reward_items(reward, leading_items, item_selection)
	if item_error != null:
		return item_error
	var experience_awards := _prepare_experience_awards(reward, origin)
	if experience_awards.error != null:
		return experience_awards.error
	_game_state.party.pooled_wealth.gold += scaled_wealth.gold
	_game_state.party.pooled_wealth.gems += scaled_wealth.gems
	_game_state.party.pooled_wealth.jewelry += scaled_wealth.jewelry
	for character: CharacterState in experience_awards.recipients:
		character.experience += int(experience_awards.awards[character.id])
	var events: Array[DomainEvent] = [DomainEvent.new(&"reward_opened", {"origin": String(origin), "sourceId": source_id, "experiencePool": reward.experience_pool, "experienceShare": reward.experience_share, "experienceByCharacter": experience_awards.awards, "wealth": scaled_wealth.to_data(), "itemCount": reward.items().size()})]
	if reward.items().is_empty() and scaled_wealth.gold == 0 and scaled_wealth.gems == 0 and scaled_wealth.jewelry == 0 and scaled_experience == 0:
		return _complete_reward(reward, request_id, events)
	return _wait_for_reward(reward, request_id, events)


func _reward_experience_multiplier() -> float:
	if _game_state.experience_multiplier >= 0.0:
		return _game_state.experience_multiplier
	var campaign := _content.campaign
	var current_levels := 0
	for party_character: CharacterState in _game_state.party.characters():
		current_levels += party_character.level
	return PartySetupRules.experience_multiplier(campaign.recommended_party_levels, current_levels, _game_state.difficulty) if campaign != null and campaign.guidance_authored and campaign.recommended_party_levels > 0 else 1.0


func _select_reward_items(source_id: String, item_ids: Array[String], item_magic_detected: Array[bool]) -> RewardItemSelection:
	var selection := RewardItemSelection.new()
	var unique_owned: Dictionary = {}
	for character: CharacterState in _game_state.party.characters():
		for carried: ItemInstance in character.inventory():
			unique_owned[carried.definition_id] = true
	for index: int in item_ids.size():
		var item_id: String = item_ids[index]
		var definition := _content.items.item_by_id(item_id)
		if definition == null:
			selection.error = ScenarioRuntimeOperationResult.failed(&"unknown_item", "Reward '%s' references unavailable item '%s'." % [source_id, item_id])
			return selection
		if definition.cost < 0 and unique_owned.has(definition.id):
			continue
		selection.definitions.append(definition)
		selection.magic_detected.append(not item_magic_detected.is_empty() and item_magic_detected[index] and definition.magical)
		if definition.cost < 0:
			unique_owned[definition.id] = true
	return selection


func _create_reward_items(reward: ClassicRewardState, leading_items: Array[ItemInstance], selection: RewardItemSelection) -> ScenarioRuntimeOperationResult:
	var items: Array[ItemInstance] = leading_items.duplicate()
	var detected_instance_ids: Array[String] = []
	for index: int in selection.definitions.size():
		var definition: ItemDefinition = selection.definitions[index]
		var identified := absi(definition.item_type) == 24
		var item := ItemInstance.new(_game_state.next_instance_id("reward.item"), definition.id, definition.initial_charges, false, identified)
		items.append(item)
		if selection.magic_detected[index]:
			detected_instance_ids.append(item.id)
	if not reward.set_items(items) or not reward.set_magic_detected_item_ids(detected_instance_ids):
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The reward contains invalid item instances.")
	return null


func _prepare_experience_awards(reward: ClassicRewardState, origin: StringName) -> RewardExperienceAwards:
	var result := RewardExperienceAwards.new()
	result.recipients = _reward_experience_recipients(origin)
	var recipients := result.recipients
	var share := 0 if recipients.is_empty() else int(float(reward.experience_pool) / float(recipients.size()))
	reward.experience_share = share
	for character: CharacterState in recipients:
		var race := _content.characters.race_by_id(character.race_id)
		var awarded := _rules.characters.battle_experience(character, race, share)
		result.awards[character.id] = awarded
	if not reward.set_experience_awards(result.awards):
		result.error = ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The reward experience recipients are invalid.")
	return result


func _reward_experience_recipients(origin: StringName) -> Array[CharacterState]:
	var result: Array[CharacterState] = []
	for character: CharacterState in _game_state.party.characters():
		if character.current_health <= 0 or character.conditions.value(ConditionRules.ANIMATED) < 0:
			continue
		if origin == &"battle" and (_game_state.combat == null or _game_state.combat.battlefield == null or not _game_state.combat.battlefield.actors.has_actor(character.id)):
			continue
		result.append(character)
	return result


func _wait_for_reward(reward: ClassicRewardState, request_id: String, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	var request := _reward_request(reward, request_id)
	if request == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_continuation", "The reward has no valid interaction for its current phase.")
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioRewardContinuations.reward(reward), events)


func _reward_request(reward: ClassicRewardState, request_id: String) -> InteractionRequest:
	if reward.phase == ClassicRewardState.LEVEL_PHASE:
		return _level_result_request(reward, request_id)
	if reward.phase == ClassicRewardState.SPELL_PHASE:
		return _reward_spell_request(reward, request_id)
	if reward.completion_pending:
		var summary := "%d unclaimed item%s and %d gold, %d gems, %d jewelry will be left behind." % [reward.items().size(), "" if reward.items().size() == 1 else "s", _game_state.party.pooled_wealth.gold, _game_state.party.pooled_wealth.gems, _game_state.party.pooled_wealth.jewelry]
		return InteractionRequest.from_payload(request_id, InteractionRequest.TREASURE_DISTRIBUTION, {"mode": "completion-confirmation", "prompt": "Leave the remaining treasure behind?", "summary": summary})
	var pending_items := reward.items()
	var item_payloads: Array[Dictionary] = []
	for pending: ItemInstance in pending_items:
		var item_payload := _reward_item_payload(reward, pending)
		if item_payload.is_empty():
			return null
		item_payloads.append(item_payload)
	var characters: Array[Dictionary] = []
	var has_share_capacity := false
	for character: CharacterState in _game_state.party.characters():
		var enabled := pending_items.any(func(item: ItemInstance) -> bool:
			var definition := _content.items.item_by_id(item.definition_id)
			return definition != null and _rules.inventory.can_restore_item(character, item, definition)
		)
		var reason := "" if enabled or pending_items.is_empty() else "This character cannot receive any remaining item."
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
			"itemCount": character.inventory().size(),
			"maximumMovement": character.maximum_movement,
			"load": character.carried_load,
			"maximumLoad": character.maximum_load,
		})
		has_share_capacity = has_share_capacity or character.carried_load < character.maximum_load
	var detect_rows := _reward_caster_rows(63, 5)
	var identify_rows := _reward_caster_rows(48, 25)
	var has_pending_items := not pending_items.is_empty()
	return InteractionRequest.from_payload(request_id, InteractionRequest.TREASURE_DISTRIBUTION, {
		"mode": "ordinary",
		"prompt": "Distribute the treasure, then choose Done.",
		"origin": String(reward.origin),
		"sourceId": reward.source_id,
		"experiencePool": reward.experience_pool,
		"experienceShare": reward.experience_share,
		"wealth": _game_state.party.pooled_wealth.to_data(),
		"items": item_payloads,
		"remaining": pending_items.size(),
		"characters": characters,
		"hasShareCapacity": has_share_capacity,
		"detect": {"visible": has_pending_items, "casters": [] if reward.magic_detected else detect_rows, "reason": "Magic has already been detected for this treasure." if reward.magic_detected else "No living caster knows Detect Magic with 5 spell points."},
		"identify": {"visible": has_pending_items, "casters": [] if reward.identified else identify_rows, "reason": "This treasure has already been identified." if reward.identified else "No living caster knows Identify with 25 spell points."},
	})


func _reward_item_payload(reward: ClassicRewardState, item: ItemInstance) -> Dictionary:
	var definition := _content.items.item_by_id(item.definition_id)
	if definition == null:
		return {}
	var assignments: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		var enabled := _rules.inventory.can_restore_item(character, item, definition)
		var reason := ""
		if character.inventory().size() >= InventoryRules.MAX_ITEMS:
			reason = "Inventory is full."
		elif character.carried_load + definition.instance_weight(item.charges) > character.maximum_load:
			reason = "The item would exceed maximum load."
		elif not enabled:
			reason = "This character cannot receive the item."
		assignments.append({"characterId": character.id, "enabled": enabled, "reason": reason})
	return {
		"instanceId": item.id,
		"definitionId": item.definition_id,
		"name": definition.name if item.identified else definition.unidentified_name,
		"charges": item.charges,
		"identified": item.identified,
		"magical": (reward.magic_detected or reward.is_magic_detected(item.id)) and definition.magical,
		"iconResourceType": "cicn",
		"iconId": definition.visible_icon_id(item.identified),
		"description": definition.description if item.identified else "Specials are unknown.",
		"facts": _reward_item_facts(item, definition),
		"assignments": assignments,
	}


func _reward_item_facts(item: ItemInstance, definition: ItemDefinition) -> Array[Dictionary]:
	var hidden := not item.identified
	var facts: Array[Dictionary] = [{"label": "Weight", "value": str(definition.instance_weight(item.charges))}]
	if definition.hands != 0:
		facts.append({"label": "Hands", "value": str(definition.hands)})
	if definition.vs_small != 0:
		facts.append({"label": "Damage", "value": "?" if hidden else "%d–%d" % [1 + definition.damage_bonus, definition.damage_bonus + definition.vs_small]})
	if definition.vs_large != 0:
		facts.append({"label": "Large damage", "value": "?" if hidden else "%d–%d" % [1 + definition.damage_bonus, definition.damage_bonus + definition.vs_large]})
	if definition.armor_bonus != 0:
		facts.append({"label": "Armor", "value": "?" if hidden else "%+d" % definition.armor_bonus})
	if not hidden:
		_append_nonzero_item_fact(facts, "Damage bonus", definition.damage_bonus)
		_append_nonzero_item_fact(facts, "Strength", definition.strength_bonus)
		_append_nonzero_item_fact(facts, "Luck", definition.luck_bonus)
		_append_nonzero_item_fact(facts, "Movement", definition.movement_bonus)
		_append_nonzero_item_fact(facts, "Magic resistance", definition.magic_resistance_bonus)
		_append_nonzero_item_fact(facts, "Spell points", definition.spell_point_bonus)
		_append_nonzero_item_fact(facts, "Heat damage", definition.heat)
		_append_nonzero_item_fact(facts, "Cold damage", definition.cold)
		_append_nonzero_item_fact(facts, "Electrical damage", definition.electric)
		_append_nonzero_item_fact(facts, "Versus undead", definition.vs_undead)
		_append_nonzero_item_fact(facts, "Versus demons/devils", definition.vs_demon_devil)
		_append_nonzero_item_fact(facts, "Versus evil", definition.vs_evil)
	if item.charges > 0:
		facts.append({"label": "Charges", "value": "?" if hidden else str(item.charges)})
	return facts


static func _append_nonzero_item_fact(facts: Array[Dictionary], label: String, value: int) -> void:
	if value != 0:
		facts.append({"label": label, "value": "%+d" % value})


func _resume_reward(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var restored: Variant = _restore_reward_continuation(continuation)
	if restored is ScenarioRuntimeOperationResult:
		return restored
	var reward: ClassicRewardState = restored
	if reward.phase == ClassicRewardState.LEVEL_PHASE:
		return _resume_reward_level(reward, response, request_id)
	if reward.phase == ClassicRewardState.SPELL_PHASE:
		return _resume_reward_spells(reward, response, request_id)
	var body := response.body as InteractionResponse.TreasureBody
	if response.kind != InteractionRequest.TREASURE_DISTRIBUTION or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Treasure distribution requires a typed action.")
	var action := String(body.action)
	if reward.completion_pending:
		return _resume_reward_completion(reward, action, request_id)
	return _resume_treasure_action(reward, body, action, request_id)


func _restore_reward_continuation(continuation: ScenarioRuntimeContinuation) -> Variant:
	if continuation == null or continuation.kind != ScenarioRuntimeContinuation.CLASSIC_REWARD:
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_continuation", "The reward continuation is malformed.")
	var reward_body := continuation.body as ScenarioRewardContinuationBody
	var reward := ClassicRewardState.from_data(reward_body.state.to_data()) if reward_body != null and reward_body.state != null else null
	if reward == null or not _reward_state_is_valid(reward):
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_continuation", "The saved reward state is invalid.")
	return reward


func _resume_reward_completion(reward: ClassicRewardState, action: String, request_id: String) -> ScenarioRuntimeOperationResult:
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
	var events: Array[DomainEvent] = [DomainEvent.new(&"reward_remainder_left", {"itemCount": abandoned, "wealth": forfeited})]
	return _begin_reward_progression(reward, request_id, events)


func _resume_treasure_action(reward: ClassicRewardState, body: InteractionResponse.TreasureBody, action: String, request_id: String) -> ScenarioRuntimeOperationResult:
	var events: Array[DomainEvent] = []
	match action:
		"assign":
			var mutation := _assign_reward_item(reward, body)
			if not mutation.is_empty():
				return ScenarioRuntimeOperationResult.failed(StringName(mutation["code"]), mutation["message"])
			events.append(DomainEvent.new(&"reward_item_assigned", {"instanceId": body.instance_id, "characterId": body.character_id}))
		"discard":
			var discarded := reward.remove_item(body.instance_id)
			if discarded == null:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "The item being left behind is not pending treasure.")
			events.append(DomainEvent.new(&"reward_item_left", {"instanceId": discarded.id, "itemId": discarded.definition_id}))
		"pool", "share":
			var money_error := _apply_reward_wealth_action(action, events)
			if not money_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(StringName(money_error["code"]), money_error["message"])
		"transfer":
			var transfer_error := _transfer_reward_wealth(body)
			if not transfer_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(StringName(transfer_error["code"]), transfer_error["message"])
			events.append(DomainEvent.new(&"reward_wealth_transferred", {"characterId": body.character_id, "direction": String(body.direction), "kind": String(body.wealth_kind), "amount": body.amount}))
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


func _apply_reward_wealth_action(action: String, events: Array[DomainEvent]) -> Dictionary:
	var movement_error := _money_movement_context_error()
	if not movement_error.is_empty():
		return {"code": "invalid_money_context", "message": movement_error}
	var probe := _rules.economy.pool_probe(_game_state.party) if action == "pool" else _rules.economy.share_probe(_game_state.party)
	if not probe.allowed:
		return {"code": "money_action_unavailable", "message": probe.reason}
	if action == "pool":
		_rules.economy.pool_party_wealth(_game_state.party)
	else:
		_rules.economy.share_pooled_wealth(_game_state.party)
	_recalculate_party_movement()
	var event_kind: StringName = &"reward_wealth_pooled" if action == "pool" else &"reward_wealth_shared"
	events.append(DomainEvent.new(event_kind, _game_state.party.pooled_wealth.to_data()))
	events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-reward-%s" % action}))
	return {}


func _assign_reward_item(reward: ClassicRewardState, body: InteractionResponse.TreasureBody) -> Dictionary:
	if body.instance_id.is_empty() or body.character_id.is_empty():
		return {"code": "invalid_interaction_response", "message": "Treasure assignment requires item and character IDs."}
	var pending: ItemInstance = null
	for item: ItemInstance in reward.items():
		if item.id == body.instance_id:
			pending = item
			break
	var character := _game_state.party.character_by_id(body.character_id)
	var definition: ItemDefinition = null if pending == null else _content.items.item_by_id(pending.definition_id)
	if pending == null or character == null or definition == null or not _rules.inventory.can_restore_item(character, pending, definition):
		return {"code": "reward_assignment_unavailable", "message": "The selected character cannot receive the selected item."}
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
			var spell := _content.magic.spell_by_id(spell_id)
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
		var race: RaceDefinition = null if character == null else _content.characters.race_by_id(character.race_id)
		var caste: CasteDefinition = null if character == null else _content.characters.caste_by_id(character.caste_id)
		if character == null or race == null or caste == null or character.current_health <= 0 or character.experience <= 0:
			return ScenarioRuntimeOperationResult.failed(&"invalid_reward_progression", "A character in the level-up queue is no longer eligible.")
		var threshold_index := clampi(character.level, 1, 30) - 1
		var threshold := caste.progression.victory_threshold(threshold_index)
		if threshold <= 0:
			events.append(DomainEvent.new(&"reward_threshold_corrected", {"characterId": character.id, "level": character.level, "authoredThreshold": threshold, "source": "invalid-content-guard"}))
			character.experience = -1
			reward.level_index += 1
			continue
		character.experience -= threshold
		var level_result := _rules.characters.level_up(character, race, caste, _rng)
		if level_result == null:
			return ScenarioRuntimeOperationResult.failed(&"character_level_failed", "Character '%s' could not level." % character.id)
		reward.pending_level_result = {"characterId": character.id, "characterName": character.name, "level": character.level, "stamina": level_result.stamina_gained, "spellPoints": level_result.spell_points_gained, "toHit": level_result.to_hit_gained, "magicResistance": level_result.magic_resistance_gained}
		if character.spellcaster_type > 0 and character.maximum_spell_points > 0:
			var spell_ids := reward.spell_character_ids()
			if not spell_ids.has(character.id):
				spell_ids.append(character.id)
				reward.set_spell_character_ids(spell_ids)
		var level_event_payload := reward.pending_level_result.duplicate(true)
		level_event_payload["experienceRemaining"] = character.experience
		events.append(DomainEvent.new(&"character_leveled", level_event_payload))
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
	var character := _game_state.party.character_by_id(character_id)
	# Drain every level earned by this reward before advancing to the next
	# recipient. Castle's one-level close leaves a large positive balance that
	# makes a later one-point award appear to grant another level.
	if character == null or character.experience <= 0:
		reward.level_index += 1
	return _advance_reward_levels(reward, request_id, [DomainEvent.new(&"level_result_acknowledged", {"characterId": character_id})])


func _advance_reward_spells(reward: ClassicRewardState, request_id: String, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	if reward.spell_index >= reward.spell_character_ids().size():
		return _complete_reward(reward, request_id, events)
	return _wait_for_reward(reward, request_id, events)


func _reward_spell_request(reward: ClassicRewardState, request_id: String) -> InteractionRequest:
	var ids := reward.spell_character_ids()
	if reward.spell_index < 0 or reward.spell_index >= ids.size():
		return null
	var character := _game_state.party.character_by_id(ids[reward.spell_index])
	var caste: CasteDefinition = null if character == null else _content.characters.caste_by_id(character.caste_id)
	if character == null or caste == null:
		return null
	var spells: Array[Dictionary] = []
	for spell: SpellDefinition in _reward_spell_candidates(character, caste):
		spells.append({"id": spell.id, "name": spell.name, "description": spell.description, "classicId": spell.classic_id, "cost": _rules.characters.spell_selection_cost(spell), "selected": character.known_spells().has(spell.id)})
	return InteractionRequest.from_payload(request_id, InteractionRequest.LEVEL_UP, {"mode": "spell-selection", "prompt": "Choose the spells this character knows.", "characterId": character.id, "characterName": character.name, "pointTotal": _rules.characters.spell_selection_total(character, caste), "spells": spells})


func _resume_reward_spells(reward: ClassicRewardState, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var ids := reward.spell_character_ids()
	var body := response.body as InteractionResponse.LevelUpBody
	if response.kind != InteractionRequest.LEVEL_UP or body == null or body.action != &"confirm-spells" or reward.spell_index < 0 or reward.spell_index >= ids.size() or body.character_id != ids[reward.spell_index]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Spell selection requires the pending character and spell IDs.")
	var character := _game_state.party.character_by_id(ids[reward.spell_index])
	var caste: CasteDefinition = null if character == null else _content.characters.caste_by_id(character.caste_id)
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
	for spell: SpellDefinition in _content.magic.definitions():
		if int(float(spell.classic_id) / 1000.0) == character.spellcaster_type and spell.classic_tier() >= 0 and spell.classic_tier() < maximum_level and spell.classic_slot() >= 1 and spell.classic_slot() <= 12:
			result.append(spell)
	result.sort_custom(func(left: SpellDefinition, right: SpellDefinition) -> bool: return left.classic_id < right.classic_id)
	return result


func _complete_reward(reward: ClassicRewardState, request_id: String, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	var completed_events: Array[DomainEvent] = []
	completed_events.assign(events)
	completed_events.append(DomainEvent.new(&"reward_completed", {"origin": String(reward.origin), "sourceId": reward.source_id, "experienceByCharacter": reward.experience_awards()}))
	if reward.origin == &"battle":
		if _game_state.combat == null or _game_state.combat.battle_id != reward.source_id or not _game_state.combat.rewards_started:
			return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The battle reward no longer matches its completed battle.")
		var combat := _game_state.combat
		if reward.battle_stage == ClassicRewardState.ORDINARY_BATTLE_STAGE and reward.bonus_treasure_classic_id != 0:
			var bonus_treasure := _content.economy.treasure_by_classic_id(reward.bonus_treasure_classic_id)
			if bonus_treasure == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_treasure", "The pending opcode 48 bonus treasure is unavailable.")
			var bonus_roll := _rules.economy.roll_treasure(bonus_treasure, _rng)
			completed_events.append(DomainEvent.new(&"battle_bonus_reward_started", {"battleId": combat.battle_id, "treasureId": bonus_treasure.id, "classicTreasureId": reward.bonus_treasure_classic_id}))
			var bonus := begin_reward(&"battle", combat.battle_id, bonus_roll.experience, bonus_roll.wealth, bonus_roll.item_ids, request_id, ClassicRewardState.BONUS_BATTLE_STAGE)
			bonus.events = completed_events + bonus.events
			return bonus
		combat.rewards_completed = true
		var outcome := combat.outcome
		var battle := _content.combat.battle_by_id(reward.source_id)
		if battle != null:
			_append_battle_after_message(battle, completed_events)
		completed_events.append(DomainEvent.new(&"battle_returned", {"battleId": reward.source_id, "outcome": String(outcome)}))
		# The completed battle remains session-owned through every ally, fumble,
		# treasure, level, and spell boundary. Release it only after the terminal
		# reward transaction has committed so both direct and VM callers return once.
		var directive := ScenarioVmDirective.finish_timeline() if combat.classic_post_battle_sentinel == 8 else null
		_game_state.combat = null
		return ScenarioRuntimeOperationResult.completed(reward.source_id, completed_events, directive)
	return ScenarioRuntimeOperationResult.completed(reward.source_id, completed_events)


func _reward_state_is_valid(reward: ClassicRewardState) -> bool:
	if reward.source_id.is_empty() or reward.origin not in [&"scenario", &"battle"]:
		return false
	if reward.origin == &"battle" and (_game_state.combat == null or not _game_state.combat.completed or not _game_state.combat.rewards_started or _game_state.combat.rewards_completed or _game_state.combat.battle_id != reward.source_id):
		return false
	if (reward.origin == &"battle" and reward.battle_stage not in [ClassicRewardState.ORDINARY_BATTLE_STAGE, ClassicRewardState.BONUS_BATTLE_STAGE]) or (reward.origin != &"battle" and (reward.battle_stage != ClassicRewardState.NO_BATTLE_STAGE or reward.bonus_treasure_classic_id != 0)) or (reward.battle_stage == ClassicRewardState.BONUS_BATTLE_STAGE and reward.bonus_treasure_classic_id != 0):
		return false
	if reward.bonus_treasure_classic_id != 0 and _content.economy.treasure_by_classic_id(reward.bonus_treasure_classic_id) == null:
		return false
	for item: ItemInstance in reward.items():
		if _content.items.item_by_id(item.definition_id) == null:
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
		if _content.characters.race_by_id(character.race_id) == null or _content.characters.caste_by_id(character.caste_id) == null:
			return "Character '%s' has no package-backed race or class for Classic movement recalculation." % character.id
	return ""


func _recalculate_party_movement() -> void:
	for character: CharacterState in _game_state.party.characters():
		var race := _content.characters.race_by_id(character.race_id)
		var caste := _content.characters.caste_by_id(character.caste_id)
		_rules.characters.recalculate_movement(character, race, caste.movement_bonus)


func grant_item(character_id: String, item_id: String, identified: bool) -> ScenarioRuntimeOperationResult:
	var character := _game_state.party.character_by_id(character_id)
	var item := _content.items.item_by_id(item_id)
	if character == null or item == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_item_target", "Grant Item references an unavailable character or item.")
	var instance := _rules.inventory.add_item(character, item, _game_state.next_instance_id("scenario.item"), identified)
	if instance == null:
		return ScenarioRuntimeOperationResult.failed(&"inventory_full", "The character cannot carry the granted item.")
	return ScenarioRuntimeOperationResult.completed(instance.id, [DomainEvent.new(&"item_granted", {"characterId": character.id, "itemId": item.id, "instanceId": instance.id, "identified": identified})])


static func _whole_number(value: Variant) -> bool:
	return value is int or value is float and is_equal_approx(value, round(value))
