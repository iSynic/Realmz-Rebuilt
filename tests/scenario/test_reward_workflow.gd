extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func run() -> void:
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "reward workflow fixture loads: %s" % loaded.error_message)
	if not loaded.is_ok():
		return
	_test_ordinary_distribution_and_restore(loaded.content)
	_test_experience_level_and_spell_restore(loaded.content)
	_test_terminal_battle_rewards_once(loaded.content)
	_test_corrupt_reward_boundaries(loaded.content)


func _test_ordinary_distribution_and_restore(content: RealmzContent) -> void:
	var blocked := _character(content, "reward.blocked", "Blocked", 0, -100_000)
	var caster := _character(content, "reward.caster", "Caster", 500, -100_000, 6)
	caster.spell_points = 30
	caster.maximum_spell_points = 30
	caster.set_known_spells([_spell_by_special(content, 63).id, _spell_by_special(content, 48).id])
	blocked.money.gold = 5
	var treasure := content.treasure_by_id("classic.treasure.0")
	var treasure_item := content.item_by_id(treasure.item_ids()[0])
	var exact_load := _character(content, "reward.exact-load", "Exact Load", treasure_item.instance_weight(treasure_item.initial_charges), -100_000)
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [blocked, caster, exact_load])
	var state := GameState.new(party, RealmzClock.new())
	var rng := RealmzRng.new(17)
	var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new(), RealmzRules.new())
	var opened := api.execute_safe("core.economy.grant-treasure", {"treasureId": "classic.treasure.0"}, "reward.open")
	assert_equal(opened.state, ScenarioRuntimeOperationResult.State.WAITING, "ordinary treasure opens one typed distribution continuation")
	assert_equal(opened.interaction.kind, InteractionRequest.TREASURE_DISTRIBUTION, "ordinary treasure reuses the dedicated treasure interaction")
	assert_equal([party.pooled_wealth.gold, opened.interaction.payload["remaining"]], [25, 1], "rolled wealth and exact pending item commit before presentation")
	assert_false(bool(opened.interaction.payload["characters"][0]["enabled"]), "a recipient without item capacity is disabled by core inventory rules")
	assert_true(bool(opened.interaction.payload["characters"][1]["enabled"]), "a source-legal recipient remains available")
	assert_true(bool(opened.interaction.payload["characters"][2]["enabled"]), "FD-ECONOMY-002 permits an exact-instance assignment that lands precisely at maximum load")
	var pending_item: Dictionary = opened.interaction.payload["item"]
	var rejected := api.resume_safe(opened.continuation, InteractionResponse.new(opened.interaction.request_id, opened.interaction.kind, {"action": "assign", "instanceId": pending_item["instanceId"], "characterId": blocked.id}), "reward.retry")
	assert_equal(rejected.error_code, &"reward_assignment_unavailable", "capacity rejection cannot mutate or consume the pending exact instance")
	assert_equal([blocked.inventory().size(), caster.inventory().size(), party.pooled_wealth.gold], [0, 0, 25], "a rejected assignment leaves all reward state unchanged")

	var detected := api.resume_safe(opened.continuation, InteractionResponse.new(opened.interaction.request_id, opened.interaction.kind, {"action": "detect", "characterId": caster.id}), "reward.detected")
	assert_equal([detected.state, caster.spell_points, detected.interaction.payload["item"]["magical"], detected.interaction.payload["item"]["identified"]], [ScenarioRuntimeOperationResult.State.WAITING, 25, true, false], "Detect Magic costs five points and reveals magic without identifying the item")
	var saved_state := GameState.from_data(state.to_data())
	var saved_rng_state := rng.snapshot()
	var saved_continuation: Dictionary = JSON.parse_string(JSON.stringify(detected.continuation))
	assert_not_null(saved_state, "treasure detection state serializes through the central game-state boundary")
	assert_not_null(ClassicRewardState.from_data(saved_continuation.get("state")), "the exact treasure continuation survives canonical JSON")
	var fractional_continuation := saved_continuation.duplicate(true)
	fractional_continuation["state"]["experiencePool"] = 1.5
	assert_equal(ClassicRewardState.from_data(fractional_continuation["state"]), null, "a non-integral serialized reward total is rejected rather than truncated")
	var restored_rng := RealmzRng.new(1)
	assert_true(restored_rng.restore(saved_rng_state), "the treasure boundary restores the exact RNG state")
	var restored_api := RealmzRuntimeApi.new(content, saved_state, restored_rng, ScenarioActionState.new(), RealmzRules.new())
	var restored_caster := saved_state.party.character_by_id(caster.id)
	saved_state.party.pooled_wealth.gems = 1
	saved_state.party.pooled_wealth.jewelry = 1
	var identified := restored_api.resume_safe(saved_continuation, InteractionResponse.new(detected.interaction.request_id, detected.interaction.kind, {"action": "identify", "characterId": caster.id}), "reward.identified")
	assert_equal([restored_caster.spell_points, identified.interaction.payload["item"]["identified"]], [0, true], "Identify Objects costs twenty-five points and identifies the whole pending pool")
	var assigned := restored_api.resume_safe(identified.continuation, InteractionResponse.new(identified.interaction.request_id, identified.interaction.kind, {"action": "assign", "instanceId": identified.interaction.payload["item"]["instanceId"], "characterId": caster.id}), "reward.assigned")
	assert_equal([restored_caster.inventory().size(), restored_caster.inventory()[0].identified, assigned.interaction.payload["remaining"]], [1, true, 0], "assignment transfers the exact identified instance once")
	var pooled := restored_api.resume_safe(assigned.continuation, InteractionResponse.new(assigned.interaction.request_id, assigned.interaction.kind, {"action": "pool"}), "reward.pooled")
	assert_equal(saved_state.party.pooled_wealth.gold, 30, "Pool moves personal wealth into the reward workspace before manual Swap")
	assert_true(pooled.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 128), "reward Pool requests its source sound")
	var duplicate_pool := restored_api.resume_safe(pooled.continuation, InteractionResponse.new(pooled.interaction.request_id, pooled.interaction.kind, {"action": "pool"}), "reward.duplicate-pool")
	assert_equal(duplicate_pool.error_code, &"money_action_unavailable", "a forged no-op reward Pool response fails instead of publishing a second success")
	assert_equal(saved_state.party.pooled_wealth.gold, 30, "rejected duplicate Pool preserves the committed reward wealth")
	var took_gem := restored_api.resume_safe(pooled.continuation, InteractionResponse.new(pooled.interaction.request_id, pooled.interaction.kind, {"action": "transfer", "direction": "to-character", "kind": "gems", "amount": 1, "characterId": caster.id}), "reward.gem-taken")
	assert_equal([saved_state.party.pooled_wealth.gems, restored_caster.money.gems], [0, 1], "treasure Swap transfers one gem in the Castle increment")
	assert_true(took_gem.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 10051), "reward pool-to-character Swap requests Castle sound 10051")
	var returned_gem := restored_api.resume_safe(took_gem.continuation, InteractionResponse.new(took_gem.interaction.request_id, took_gem.interaction.kind, {"action": "transfer", "direction": "to-pool", "kind": "gems", "amount": 1, "characterId": caster.id}), "reward.gem-returned")
	assert_equal([saved_state.party.pooled_wealth.gems, restored_caster.money.gems], [1, 0], "treasure Swap reverses the exact gem transfer")
	assert_true(returned_gem.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 663), "reward character-to-pool Swap requests Castle sound 663")
	var took_jewelry := restored_api.resume_safe(returned_gem.continuation, InteractionResponse.new(returned_gem.interaction.request_id, returned_gem.interaction.kind, {"action": "transfer", "direction": "to-character", "kind": "jewelry", "amount": 1, "characterId": caster.id}), "reward.jewelry-taken")
	assert_equal([saved_state.party.pooled_wealth.jewelry, restored_caster.money.jewelry], [0, 1], "treasure Swap transfers one jewelry and its fifteen load units")
	var returned_jewelry := restored_api.resume_safe(took_jewelry.continuation, InteractionResponse.new(took_jewelry.interaction.request_id, took_jewelry.interaction.kind, {"action": "transfer", "direction": "to-pool", "kind": "jewelry", "amount": 1, "characterId": caster.id}), "reward.jewelry-returned")
	assert_equal([saved_state.party.pooled_wealth.jewelry, restored_caster.money.jewelry], [1, 0], "treasure Swap reverses one jewelry without losing denomination state")
	var shared := restored_api.resume_safe(returned_jewelry.continuation, InteractionResponse.new(returned_jewelry.interaction.request_id, returned_jewelry.interaction.kind, {"action": "share"}), "reward.shared")
	assert_equal([saved_state.party.pooled_wealth.gold, saved_state.party.pooled_wealth.gems, saved_state.party.pooled_wealth.jewelry], [0, 0, 0], "Share drains the pool through the source denomination order")
	assert_true(shared.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 128), "reward Share requests its source sound")
	var duplicate_share := restored_api.resume_safe(shared.continuation, InteractionResponse.new(shared.interaction.request_id, shared.interaction.kind, {"action": "share"}), "reward.duplicate-share")
	assert_equal(duplicate_share.error_code, &"money_action_unavailable", "a forged no-op reward Share response fails instead of publishing a second success")
	var completed := restored_api.resume_safe(shared.continuation, InteractionResponse.new(shared.interaction.request_id, shared.interaction.kind, {"action": "done"}), "reward.done")
	assert_equal(completed.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Done returns to the issuing flow after all treasure is resolved")
	assert_true(completed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"reward_completed"), "ordinary distribution publishes one committed completion event")


func _test_experience_level_and_spell_restore(content: RealmzContent) -> void:
	var character := _character(content, "reward.leveler", "Leveler", 500, -1, 6)
	character.knowledge = 18
	character.judgment = 16
	character.vitality = 15
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [character]), RealmzClock.new())
	var rng := RealmzRng.new(23)
	var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new(), RealmzRules.new())
	var instructions: Array[ClassicActionDefinition] = [ClassicActionDefinition.new(0, 11, 11, 10_000, false, [])]
	var program := ScenarioProgramDefinition.new("reward.level-program", &"trigger", "reward.level", instructions)
	var definition := ScenarioDefinition.new([program], [])
	var vm := ScenarioVm.new()
	vm.configure(definition)
	assert_equal(vm.start_program(program.id, {"callingContext": "action"}).state, ScenarioVmResult.State.COMPLETED, "experience fixture starts through the ordinary VM")
	var treasure_stage := vm.run(api)
	assert_equal([treasure_stage.state, treasure_stage.interaction.kind, treasure_stage.interaction.payload["experienceShare"]], [ScenarioVmResult.State.WAITING, InteractionRequest.TREASURE_DISTRIBUTION, 10_000], "experience is awarded once before the empty treasure stage")
	var level_stage := vm.resume(InteractionResponse.new(treasure_stage.interaction.request_id, treasure_stage.interaction.kind, {"action": "done"}), api)
	assert_equal([level_stage.state, level_stage.interaction.kind, level_stage.interaction.payload["mode"], character.level], [ScenarioVmResult.State.WAITING, InteractionRequest.LEVEL_UP, "result", 2], "positive residual experience produces one staged source-backed level result")
	assert_equal(character.experience, 6_499, "one reward close subtracts one threshold and retains positive residual experience without auto-looping")
	var saved_vm := ScenarioVmSnapshot.from_data(JSON.parse_string(JSON.stringify(vm.snapshot().to_data())))
	var saved_game := GameState.from_data(state.to_data())
	var saved_rng := rng.snapshot()
	assert_not_null(saved_vm, "the pending level-result VM frame serializes")
	assert_not_null(saved_game, "the level mutation and residual experience serialize with the session state")
	var restored_rng := RealmzRng.new(1)
	assert_true(restored_rng.restore(saved_rng), "level-up restoration resumes at the exact post-roll RNG position")
	var restored_vm := ScenarioVm.new()
	restored_vm.configure(definition)
	assert_true(restored_vm.restore(saved_vm), "the pending level result restores against the same scenario definition")
	var restored_api := RealmzRuntimeApi.new(content, saved_game, restored_rng, ScenarioActionState.new(), RealmzRules.new())
	var wrong_level := restored_api.resume_classic(saved_vm.pending_continuation["runtime"], InteractionResponse.new(saved_vm.pending_request.request_id, InteractionRequest.LEVEL_UP, {"action": "continue", "characterId": "reward.someone-else"}), saved_vm.pending_request.request_id)
	assert_equal(wrong_level.error_code, &"invalid_interaction_response", "a level-result response cannot acknowledge a different character")
	var spell_stage := restored_vm.resume(InteractionResponse.new(saved_vm.pending_request.request_id, InteractionRequest.LEVEL_UP, {"action": "continue", "characterId": character.id}), restored_api)
	assert_equal([spell_stage.state, spell_stage.interaction.kind, spell_stage.interaction.payload["mode"]], [ScenarioVmResult.State.WAITING, InteractionRequest.LEVEL_UP, "spell-selection"], "a qualifying caster advances to a dedicated spell-selection stage")
	var spell_boundary := ScenarioVmSnapshot.from_data(JSON.parse_string(JSON.stringify(restored_vm.snapshot().to_data())))
	assert_not_null(spell_boundary, "the spell-selection stage is independently serializable")
	var completed := restored_vm.resume(InteractionResponse.new(spell_stage.interaction.request_id, InteractionRequest.LEVEL_UP, {"action": "confirm-spells", "characterId": character.id, "spellIds": []}), restored_api)
	assert_equal(completed.state, ScenarioVmResult.State.COMPLETED, "confirmed spell selection resumes and completes the issuing VM exactly once")
	assert_equal([saved_game.party.character_by_id(character.id).level, saved_game.party.character_by_id(character.id).experience], [2, 6_499], "the source-limited one-level result survives the complete continuation")


func _test_terminal_battle_rewards_once(content: RealmzContent) -> void:
	var battle: BattleDefinition = content.battle_by_id("classic.battle.0")
	var character := _character(content, "reward.victor", "Victor", 5_000, -10_000_000)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [character]), RealmzClock.new())
	var rng := RealmzRng.new(31)
	var rules := RealmzRules.new()
	var setup := rules.combat_flow.start_battle(state, content, battle, rng)
	assert_true(setup.ok, "terminal reward fixture starts a source-backed battle")
	if not setup.ok:
		return
	for monster: MonsterState in state.combat.monsters():
		if monster.traitor:
			monster.current_health = 0
	state.combat.active_turn = null
	state.combat.pending_monster_attack = null
	state.combat.pending_reaction = null
	state.combat.completed = true
	state.combat.outcome = &"victory"
	state.last_battle_outcome = &"victory"
	var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new(), rules)
	var reward := api.begin_completed_battle_reward("battle.reward")
	assert_true(reward.state in [ScenarioRuntimeOperationResult.State.WAITING, ScenarioRuntimeOperationResult.State.COMPLETED], "victory transitions into the typed reward pipeline")
	var guard := 2_000
	while reward.state == ScenarioRuntimeOperationResult.State.WAITING and guard > 0:
		var response := _reward_response(reward.interaction)
		var serialized: Dictionary = JSON.parse_string(JSON.stringify(reward.continuation))
		assert_not_null(ClassicRewardState.from_data(serialized.get("state")), "every terminal reward interaction retains a valid serialized continuation")
		reward = api.resume_classic(serialized, response, reward.interaction.request_id + ".next")
		guard -= 1
	assert_true(guard > 0, "terminal reward completion stays within the bounded interaction count")
	assert_equal([reward.state, state.combat, state.last_battle_outcome], [ScenarioRuntimeOperationResult.State.COMPLETED, null, &"victory"], "victory completes reward ownership and releases the terminal battle exactly once")
	assert_equal(reward.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"battle_returned").size(), 1, "victory publishes one terminal battle-return event")
	var terminal_kinds := reward.events.map(func(event: DomainEvent) -> StringName: return event.kind)
	assert_true(terminal_kinds.find(&"reward_completed") < terminal_kinds.find(&"battle_returned"), "the reward commits before the terminal battle return is published")
	if battle.message_after_id != 0:
		assert_true(terminal_kinds.find(&"message_shown") > terminal_kinds.find(&"reward_completed") and terminal_kinds.find(&"message_shown") < terminal_kinds.find(&"battle_returned"), "the authored after-message is staged between reward completion and return")
	var draw_count := rng.snapshot().draw_count
	var repeated := api.begin_completed_battle_reward("battle.reward.repeat")
	assert_equal([repeated.state, repeated.error_code, rng.snapshot().draw_count], [ScenarioRuntimeOperationResult.State.FAILED, &"invalid_battle_continuation", draw_count], "a returned battle cannot be re-entered, reroll loot, or consume RNG")

	var defeat_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [_character(content, "reward.defeated", "Defeated", 500, -100_000)]), RealmzClock.new())
	defeat_state.combat = CombatState.new(battle.id)
	defeat_state.combat.completed = true
	defeat_state.combat.outcome = &"defeat"
	defeat_state.last_battle_outcome = &"defeat"
	var defeat_rng := RealmzRng.new(31)
	var defeat := RealmzRuntimeApi.new(content, defeat_state, defeat_rng, ScenarioActionState.new(), RealmzRules.new()).begin_completed_battle_reward("battle.defeat")
	assert_equal([defeat.state, defeat_state.combat, defeat_state.last_battle_outcome, defeat_rng.snapshot().draw_count], [ScenarioRuntimeOperationResult.State.COMPLETED, null, &"defeat", 0], "defeat closes and releases the terminal chain without inventing loot or reward draws")
	assert_equal(defeat.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"battle_returned").size(), 1, "defeat publishes one terminal battle-return event")

	var retreat_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [_character(content, "reward.retreat", "Retreated", 500, -100_000)]), RealmzClock.new())
	retreat_state.combat = CombatState.new(battle.id)
	retreat_state.combat.completed = true
	retreat_state.combat.outcome = &"retreated"
	retreat_state.last_battle_outcome = &"retreated"
	var retreat_rng := RealmzRng.new(31)
	var retreated := RealmzRuntimeApi.new(content, retreat_state, retreat_rng, ScenarioActionState.new(), RealmzRules.new()).begin_completed_battle_reward("battle.retreat")
	assert_equal([retreated.state, retreat_state.combat, retreat_state.last_battle_outcome, retreat_rng.snapshot().draw_count], [ScenarioRuntimeOperationResult.State.COMPLETED, null, &"retreated", 0], "full-party retreat returns without victory rewards or reward RNG")

	var escaped := _character(content, "reward.partial-escaped", "Escaped", 5_000, -100_000)
	var stayed := _character(content, "reward.partial-stayed", "Stayed", 5_000, -100_000)
	var partial_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [escaped, stayed]), RealmzClock.new())
	var partial_rng := RealmzRng.new(37)
	var partial_setup := rules.combat_flow.start_battle(partial_state, content, battle, partial_rng)
	assert_true(partial_setup.ok, "partial-retreat reward fixture starts a source-backed battle")
	if partial_setup.ok:
		partial_state.combat.mark_character_retreated(escaped.id)
		partial_state.combat.battlefield.remove_character(escaped.id)
		for monster: MonsterState in partial_state.combat.monsters():
			if monster.traitor:
				monster.current_health = 0
		partial_state.combat.active_turn = null
		partial_state.combat.pending_monster_attack = null
		partial_state.combat.pending_reaction = null
		partial_state.combat.completed = true
		partial_state.combat.outcome = &"victory"
		partial_state.last_battle_outcome = &"victory"
		var partial_api := RealmzRuntimeApi.new(content, partial_state, partial_rng, ScenarioActionState.new(), rules)
		var partial_reward := partial_api.begin_completed_battle_reward("battle.partial")
		var opened_payload: Dictionary = {}
		for event: DomainEvent in partial_reward.events:
			if event.kind == &"reward_opened":
				opened_payload = event.payload
				break
		var partial_awards: Dictionary = opened_payload.get("experienceByCharacter", {})
		assert_false(partial_awards.has(escaped.id), "a character who escaped before victory is not an experience divider or recipient")
		assert_true(partial_awards.has(stayed.id), "a living character still on the battlefield receives the partial-retreat victory share")
		guard = 2_000
		while partial_reward.state == ScenarioRuntimeOperationResult.State.WAITING and guard > 0:
			partial_reward = partial_api.resume_classic(partial_reward.continuation, _reward_response(partial_reward.interaction), partial_reward.interaction.request_id + ".next")
			guard -= 1
		assert_equal([partial_reward.state, partial_state.combat], [ScenarioRuntimeOperationResult.State.COMPLETED, null], "partial retreat completes one ordinary reward return for the characters who stayed")


func _test_corrupt_reward_boundaries(content: RealmzContent) -> void:
	var character := _character(content, "reward.corrupt", "Corrupt", 500, -100_000)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [character]), RealmzClock.new())
	var rng := RealmzRng.new(41)
	var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new(), RealmzRules.new())
	var opened := api.execute_safe("core.economy.grant-treasure", {"treasureId": "classic.treasure.0"}, "reward.corrupt.open")
	var pooled_before := state.party.pooled_wealth.to_data()
	var fractional_transfer := api.resume_safe(opened.continuation, InteractionResponse.new(opened.interaction.request_id, opened.interaction.kind, {"action": "transfer", "direction": "to-character", "kind": "gold", "amount": 5.5, "characterId": character.id}), "reward.corrupt.transfer")
	assert_equal(fractional_transfer.error_code, &"invalid_interaction_response", "a non-integral transfer amount is rejected without coercion")
	assert_equal(state.party.pooled_wealth.to_data(), pooled_before, "a corrupt transfer leaves pooled wealth unchanged")
	var unknown_denomination := api.resume_safe(opened.continuation, InteractionResponse.new(opened.interaction.request_id, opened.interaction.kind, {"action": "transfer", "direction": "to-character", "kind": "silver", "amount": 1, "characterId": character.id}), "reward.corrupt.kind")
	assert_equal(unknown_denomination.error_code, &"invalid_interaction_response", "an unknown reward denomination fails explicitly")

	var battle: BattleDefinition = content.battle_by_id("classic.battle.0")
	var battle_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [_character(content, "reward.invalid-battle", "Invalid Battle", 500, -100_000)]), RealmzClock.new())
	var battle_rng := RealmzRng.new(43)
	var rules := RealmzRules.new()
	var setup := rules.combat_flow.start_battle(battle_state, content, battle, battle_rng)
	assert_true(setup.ok, "invalid-reward characterization begins from a valid battle")
	if not setup.ok:
		return
	for monster: MonsterState in battle_state.combat.monsters():
		if monster.traitor:
			monster.current_health = 0
			monster.definition_id = "classic.monster.unavailable"
			break
	battle_state.combat.active_turn = null
	battle_state.combat.pending_monster_attack = null
	battle_state.combat.pending_reaction = null
	battle_state.combat.completed = true
	battle_state.combat.outcome = &"victory"
	var draws_before := battle_rng.snapshot().draw_count
	var invalid_reward := RealmzRuntimeApi.new(content, battle_state, battle_rng, ScenarioActionState.new(), rules).begin_completed_battle_reward("battle.invalid-reward")
	assert_equal(invalid_reward.error_code, &"unknown_monster", "a malformed battle reward fails before committing its continuation")
	assert_equal([battle_state.combat.rewards_started, battle_rng.snapshot().draw_count], [false, draws_before], "battle reward validation neither claims the one-shot stage nor consumes reward RNG")


func _character(content: RealmzContent, id: String, name: String, maximum_load: int, experience: int, caste_id: int = 1) -> CharacterState:
	var caste: CasteDefinition = content.caste_by_id("classic.caste.%d" % caste_id)
	var race: RaceDefinition = null
	for candidate: RaceDefinition in content.race_definitions():
		if caste.eligible_race_ids.has(candidate.id):
			race = candidate
			break
	if race == null:
		race = content.race_definitions()[0]
	var result := CharacterState.new(id, name, 20, 20)
	result.race_id = race.id
	result.caste_id = caste.id
	result.level = 1
	result.experience = experience
	result.maximum_load = maximum_load
	result.carried_load = 0
	return result


func _spell_by_special(content: RealmzContent, special: int) -> SpellDefinition:
	for spell: SpellDefinition in content.spell_definitions():
		if spell.special == special:
			return spell
	return null


func _reward_response(request: InteractionRequest) -> InteractionResponse:
	if request.kind == InteractionRequest.LEVEL_UP:
		if request.payload.get("mode") == "result":
			return InteractionResponse.new(request.request_id, request.kind, {"action": "continue", "characterId": request.payload["characterId"]})
		return InteractionResponse.new(request.request_id, request.kind, {"action": "confirm-spells", "characterId": request.payload["characterId"], "spellIds": []})
	if request.payload.get("mode") == "completion-confirmation":
		return InteractionResponse.new(request.request_id, request.kind, {"action": "confirm-completion"})
	var item: Variant = request.payload.get("item")
	if item is Dictionary:
		return InteractionResponse.new(request.request_id, request.kind, {"action": "discard", "instanceId": item["instanceId"]})
	return InteractionResponse.new(request.request_id, request.kind, {"action": "done"})
