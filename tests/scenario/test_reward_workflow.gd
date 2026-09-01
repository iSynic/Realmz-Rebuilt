extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const LEVEL_DRAIN_CORRECTION_PATH: String = "res://tests/fixtures/oracle/reward-earned-level-drain-correction.json"


func selected_case_arguments() -> Array:
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "reward workflow fixture loads: %s" % loaded.error_message)
	return [loaded.content] if loaded.is_ok() else []


func run() -> void:
	var level_drain_correction: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEVEL_DRAIN_CORRECTION_PATH))
	assert_true(level_drain_correction is Dictionary, "the earned-level drain fidelity decision is parseable")
	if level_drain_correction is Dictionary:
		assert_equal(level_drain_correction["castleSourceObservation"]["levelChecksPerRecipientPerRewardClose"], 1, "the fixture records Castle's single level check per recipient")
		assert_equal(level_drain_correction["realmz2ChosenResult"]["levelChecks"], "repeat for the same eligible recipient while carried victory points remain positive", "the fixture records the correction that drains every level earned by the reward")
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "reward workflow fixture loads: %s" % loaded.error_message)
	if not loaded.is_ok():
		return
	_test_ordinary_distribution_and_restore(loaded.content)
	_test_experience_level_and_spell_restore(loaded.content)
	_test_terminal_battle_rewards_once(loaded.content)
	_test_battle_mode_five_and_incidental_rewards(loaded.content)
	_test_opcode_48_bonus_reward_chain(loaded.content)
	_test_corrupt_reward_boundaries(loaded.content)


func _test_ordinary_distribution_and_restore(content: RealmzContent) -> void:
	var blocked := _character(content, "reward.blocked", "Blocked", 0, -100_000); var caster := _character(content, "reward.caster", "Caster", 500, -100_000, 6); caster.spell_points = 30; caster.maximum_spell_points = 30; caster.set_known_spells([_spell_by_special(content, 63).id, _spell_by_special(content, 48).id])
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
	assert_equal([party.pooled_wealth.gold, opened.interaction.body.to_data()["remaining"]], [25, 1], "rolled wealth and exact pending item commit before presentation")
	assert_false(bool(opened.interaction.body.to_data()["characters"][0]["enabled"]), "a recipient without item capacity is disabled by core inventory rules")
	assert_true(bool(opened.interaction.body.to_data()["characters"][1]["enabled"]), "a source-legal recipient remains available")
	assert_true(bool(opened.interaction.body.to_data()["characters"][2]["enabled"]), "FD-ECONOMY-002 permits an exact-instance assignment that lands precisely at maximum load")
	var pending_item: Dictionary = opened.interaction.body.to_data()["items"][0]
	var rejected := api.resume_safe(opened.continuation, InteractionResponse.from_data(opened.interaction.request_id, opened.interaction.kind, {"action": "assign", "instanceId": pending_item["instanceId"], "characterId": blocked.id}), "reward.retry")
	assert_equal(rejected.error_code, &"reward_assignment_unavailable", "capacity rejection cannot mutate or consume the pending exact instance")
	assert_equal([blocked.inventory().size(), caster.inventory().size(), party.pooled_wealth.gold], [0, 0, 25], "a rejected assignment leaves all reward state unchanged")

	var detected := api.resume_safe(opened.continuation, InteractionResponse.from_data(opened.interaction.request_id, opened.interaction.kind, {"action": "detect", "characterId": caster.id}), "reward.detected")
	assert_equal([detected.state, caster.spell_points, detected.interaction.body.to_data()["items"][0]["magical"], detected.interaction.body.to_data()["items"][0]["identified"]], [ScenarioRuntimeOperationResult.State.WAITING, 25, true, false], "Detect Magic costs five points and reveals magic without identifying the item"); assert_equal([detected.interaction.body.to_data()["detect"]["visible"], detected.interaction.body.to_data()["detect"]["casters"].size(), detected.interaction.body.to_data()["identify"]["casters"][0]["spellPoints"]], [true, 0, 25], "the used Detect control remains visibly settled while Identify is recomputed from the caster's remaining points")
	var saved_state := GameState.from_data(state.to_data())
	var saved_rng_state := rng.snapshot()
	var saved_continuation_data: Dictionary = JSON.parse_string(JSON.stringify(detected.continuation.to_data()))
	var saved_continuation := ScenarioRuntimeContinuation.from_data(saved_continuation_data)
	assert_not_null(saved_state, "treasure detection state serializes through the central game-state boundary")
	var saved_reward_body := saved_continuation.body as ScenarioRuntimeContinuation.RewardBody
	assert_not_null(saved_reward_body, "the exact treasure continuation survives canonical JSON")
	assert_not_null(saved_reward_body.state, "the typed reward state survives canonical JSON")
	var pre_sequence_reward: Dictionary = saved_continuation_data.duplicate(true)
	pre_sequence_reward["data"]["state"].erase("battleStage")
	pre_sequence_reward["data"]["state"].erase("bonusTreasureClassicId")
	assert_not_null(ScenarioRuntimeContinuation.from_data(pre_sequence_reward), "an existing version-four reward continuation defaults safely before the battle-sequence fields existed")
	var fractional_continuation := saved_continuation_data.duplicate(true)
	fractional_continuation["data"]["state"]["experiencePool"] = 1.5
	assert_equal(ScenarioRuntimeContinuation.from_data(fractional_continuation), null, "a non-integral serialized reward total is rejected rather than truncated")
	var restored_rng := RealmzRng.new(1)
	assert_true(restored_rng.restore(saved_rng_state), "the treasure boundary restores the exact RNG state")
	var restored_api := RealmzRuntimeApi.new(content, saved_state, restored_rng, ScenarioActionState.new(), RealmzRules.new())
	var restored_caster := saved_state.party.character_by_id(caster.id)
	saved_state.party.pooled_wealth.gems = 1
	saved_state.party.pooled_wealth.jewelry = 1
	var identified := restored_api.resume_safe(saved_continuation, InteractionResponse.from_data(detected.interaction.request_id, detected.interaction.kind, {"action": "identify", "characterId": caster.id}), "reward.identified")
	assert_equal([restored_caster.spell_points, identified.interaction.body.to_data()["items"][0]["identified"]], [0, true], "Identify Objects costs twenty-five points and identifies the whole pending pool"); assert_equal([identified.interaction.body.to_data()["detect"]["visible"], identified.interaction.body.to_data()["identify"]["visible"], identified.interaction.body.to_data()["identify"]["casters"].size()], [true, true, 0], "both Treasure lore controls remain in place after their actions settle"); var reverse_caster := _character(content, "reward.reverse-caster", "Reverse Caster", 500, -100_000, 6); reverse_caster.spell_points = 30; reverse_caster.maximum_spell_points = 30; reverse_caster.set_known_spells([_spell_by_special(content, 63).id, _spell_by_special(content, 48).id]); var reverse_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [reverse_caster]), RealmzClock.new()); var reverse_api := RealmzRuntimeApi.new(content, reverse_state, RealmzRng.new(19), ScenarioActionState.new(), RealmzRules.new()); var reverse_opened := reverse_api.execute_safe("core.economy.grant-treasure", {"treasureId": "classic.treasure.0"}, "reward.reverse.open"); var reverse_identified := reverse_api.resume_safe(reverse_opened.continuation, InteractionResponse.from_data(reverse_opened.interaction.request_id, reverse_opened.interaction.kind, {"action": "identify", "characterId": reverse_caster.id}), "reward.reverse.identify"); var reverse_detected := reverse_api.resume_safe(reverse_identified.continuation, InteractionResponse.from_data(reverse_identified.interaction.request_id, reverse_identified.interaction.kind, {"action": "detect", "characterId": reverse_caster.id}), "reward.reverse.detect"); assert_equal([reverse_identified.state, reverse_identified.interaction.body.to_data()["detect"]["casters"][0]["spellPoints"], reverse_caster.spell_points, reverse_detected.state, reverse_detected.interaction.body.to_data()["items"][0]["magical"], reverse_detected.interaction.body.to_data()["items"][0]["identified"]], [ScenarioRuntimeOperationResult.State.WAITING, 5, 0, ScenarioRuntimeOperationResult.State.WAITING, true, true], "Identify then Detect remains legal at the exact remaining five-point boundary and reveals magic without losing identification")
	var assigned := restored_api.resume_safe(identified.continuation, InteractionResponse.from_data(identified.interaction.request_id, identified.interaction.kind, {"action": "assign", "instanceId": identified.interaction.body.to_data()["items"][0]["instanceId"], "characterId": caster.id}), "reward.assigned")
	assert_equal([restored_caster.inventory().size(), restored_caster.inventory()[0].identified, assigned.interaction.body.to_data()["remaining"]], [1, true, 0], "assignment transfers the exact identified instance once")
	var pooled := restored_api.resume_safe(assigned.continuation, InteractionResponse.from_data(assigned.interaction.request_id, assigned.interaction.kind, {"action": "pool"}), "reward.pooled")
	assert_equal(saved_state.party.pooled_wealth.gold, 30, "Pool moves personal wealth into the reward workspace before manual Swap")
	assert_true(pooled.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 128), "reward Pool requests its source sound")
	var duplicate_pool := restored_api.resume_safe(pooled.continuation, InteractionResponse.from_data(pooled.interaction.request_id, pooled.interaction.kind, {"action": "pool"}), "reward.duplicate-pool")
	assert_equal(duplicate_pool.error_code, &"money_action_unavailable", "a forged no-op reward Pool response fails instead of publishing a second success")
	assert_equal(saved_state.party.pooled_wealth.gold, 30, "rejected duplicate Pool preserves the committed reward wealth")
	var took_gem := restored_api.resume_safe(pooled.continuation, InteractionResponse.from_data(pooled.interaction.request_id, pooled.interaction.kind, {"action": "transfer", "direction": "to-character", "kind": "gems", "amount": 1, "characterId": caster.id}), "reward.gem-taken")
	assert_equal([saved_state.party.pooled_wealth.gems, restored_caster.money.gems], [0, 1], "treasure Swap transfers one gem in the Castle increment")
	assert_true(took_gem.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 10051), "reward pool-to-character Swap requests Castle sound 10051")
	var returned_gem := restored_api.resume_safe(took_gem.continuation, InteractionResponse.from_data(took_gem.interaction.request_id, took_gem.interaction.kind, {"action": "transfer", "direction": "to-pool", "kind": "gems", "amount": 1, "characterId": caster.id}), "reward.gem-returned")
	assert_equal([saved_state.party.pooled_wealth.gems, restored_caster.money.gems], [1, 0], "treasure Swap reverses the exact gem transfer")
	assert_true(returned_gem.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 663), "reward character-to-pool Swap requests Castle sound 663")
	var took_jewelry := restored_api.resume_safe(returned_gem.continuation, InteractionResponse.from_data(returned_gem.interaction.request_id, returned_gem.interaction.kind, {"action": "transfer", "direction": "to-character", "kind": "jewelry", "amount": 1, "characterId": caster.id}), "reward.jewelry-taken")
	assert_equal([saved_state.party.pooled_wealth.jewelry, restored_caster.money.jewelry], [0, 1], "treasure Swap transfers one jewelry and its fifteen load units")
	var returned_jewelry := restored_api.resume_safe(took_jewelry.continuation, InteractionResponse.from_data(took_jewelry.interaction.request_id, took_jewelry.interaction.kind, {"action": "transfer", "direction": "to-pool", "kind": "jewelry", "amount": 1, "characterId": caster.id}), "reward.jewelry-returned")
	assert_equal([saved_state.party.pooled_wealth.jewelry, restored_caster.money.jewelry], [1, 0], "treasure Swap reverses one jewelry without losing denomination state")
	var shared := restored_api.resume_safe(returned_jewelry.continuation, InteractionResponse.from_data(returned_jewelry.interaction.request_id, returned_jewelry.interaction.kind, {"action": "share"}), "reward.shared")
	assert_equal([saved_state.party.pooled_wealth.gold, saved_state.party.pooled_wealth.gems, saved_state.party.pooled_wealth.jewelry], [0, 0, 0], "Share drains the pool through the source denomination order")
	assert_true(shared.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 128), "reward Share requests its source sound")
	var duplicate_share := restored_api.resume_safe(shared.continuation, InteractionResponse.from_data(shared.interaction.request_id, shared.interaction.kind, {"action": "share"}), "reward.duplicate-share")
	assert_equal(duplicate_share.error_code, &"money_action_unavailable", "a forged no-op reward Share response fails instead of publishing a second success")
	var completed := restored_api.resume_safe(shared.continuation, InteractionResponse.from_data(shared.interaction.request_id, shared.interaction.kind, {"action": "done"}), "reward.done")
	assert_equal(completed.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Done returns to the issuing flow after all treasure is resolved")
	assert_true(completed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"reward_completed"), "ordinary distribution publishes one committed completion event")


func _test_experience_level_and_spell_restore(content: RealmzContent) -> void:
	var ordinary := _character(content, "reward.ordinary", "Ordinary", 100, -1_000); ordinary.race_id = (content.race_definitions().filter(func(race: RaceDefinition) -> bool: return race.max_age > 0)[0] as RaceDefinition).id; var ordinary_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [ordinary]), RealmzClock.new()); ordinary_state.experience_multiplier = 1.0; var ordinary_api := RealmzRuntimeApi.new(content, ordinary_state, RealmzRng.new(19), ScenarioActionState.new(), RealmzRules.new()); var ordinary_reward: ScenarioRuntimeOperationResult = ordinary_api.execute_classic(ClassicActionDefinition.new(0, 11, 11, 100, false, []), "reward.ordinary"); var ordinary_done: ScenarioRuntimeOperationResult = ordinary_api.resume_safe(ordinary_reward.continuation, InteractionResponse.from_data(ordinary_reward.interaction.request_id, ordinary_reward.interaction.kind, {"action": "done"}), "reward.ordinary.done"); assert_equal([ordinary_done.state, ordinary.level, ordinary.experience, ordinary_done.events.any(func(event: DomainEvent) -> bool: return event.kind == &"character_leveled")], [ScenarioRuntimeOperationResult.State.COMPLETED, 1, -900, false], "an ordinary negative VP balance receives its share without entering level-up progression"); var capped := _character(content, "reward.capped", "Capped", 100, -1); var capped_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [capped]), RealmzClock.new()); var capped_api := RealmzRuntimeApi.new(content, capped_state, RealmzRng.new(20), ScenarioActionState.new(), RealmzRules.new()); var capped_reward := capped_api.execute_classic(ClassicActionDefinition.new(0, 11, 11, 100, false, []), "reward.capped"); var capped_done := capped_api.resume_safe(capped_reward.continuation, InteractionResponse.from_data(capped_reward.interaction.request_id, capped_reward.interaction.kind, {"action": "done"}), "reward.capped.done"); assert_equal([capped_done.state, capped.level, capped.experience, capped_done.events.any(func(event: DomainEvent) -> bool: return event.kind == &"character_leveled"), capped_done.events.any(func(event: DomainEvent) -> bool: return event.kind == &"reward_threshold_corrected")], [ScenarioRuntimeOperationResult.State.COMPLETED, 1, -1, false, true], "a nonpositive next-level threshold records the invalid content and grants no repeat level"); var character := _character(content, "reward.leveler", "Leveler", 500, -1, 6)
	character.knowledge = 18
	character.judgment = 16
	character.vitality = 15
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [character]), RealmzClock.new())
	state.experience_multiplier = 2.5
	var rng := RealmzRng.new(23)
	var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new(), RealmzRules.new())
	var instructions: Array[ClassicActionDefinition] = [ClassicActionDefinition.new(0, 11, 11, 10_000, false, []), ClassicActionDefinition.new(1, 25, 25, 0, false, []), ClassicActionDefinition.new(2, 84, 84, 0, false, [])]
	var program := ScenarioProgramDefinition.new("reward.level-program", &"trigger", "reward.level", instructions)
	var definition := ScenarioDefinition.new([program], [])
	var vm := ScenarioVm.new()
	vm.configure(definition)
	assert_equal(vm.start_program(program.id, ScenarioExecutionContext.trigger(&"action", "ap.reward-level")).state, ScenarioVmResult.State.COMPLETED, "experience fixture starts through the ordinary VM")
	var treasure_stage := vm.run(api)
	assert_equal([treasure_stage.state, treasure_stage.interaction.kind, treasure_stage.interaction.body.to_data()["experienceShare"]], [ScenarioVmResult.State.WAITING, InteractionRequest.TREASURE_DISTRIBUTION, 25_000], "experience is awarded once with the selected party's Classic 250 percent setup multiplier before the empty treasure stage")
	var level_stage := vm.resume(InteractionResponse.from_data(treasure_stage.interaction.request_id, treasure_stage.interaction.kind, {"action": "done"}), api)
	assert_equal([level_stage.state, level_stage.interaction.kind, level_stage.interaction.body.to_data()["mode"], character.level, level_stage.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"character_leveled")[0].payload.get("experienceRemaining")], [ScenarioVmResult.State.WAITING, InteractionRequest.LEVEL_UP, "result", 2, 21_499], "positive residual experience produces the first staged level result with its carried-VP diagnostic")
	assert_equal(character.experience, 21_499, "the first result retains the balance needed to drain additional earned levels in the same reward")
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
	var wrong_level := restored_vm.resume(InteractionResponse.from_data(saved_vm.pending_request.request_id, InteractionRequest.LEVEL_UP, {"action": "continue", "characterId": "reward.someone-else"}), restored_api)
	assert_equal([wrong_level.error_code, restored_vm.pending_request().request_id], [&"invalid_interaction_response", saved_vm.pending_request.request_id], "a rejected level-result response preserves the issuing VM request for a corrected response")
	var spell_stage := restored_vm.resume(InteractionResponse.from_data(saved_vm.pending_request.request_id, InteractionRequest.LEVEL_UP, {"action": "continue", "characterId": character.id}), restored_api)
	var acknowledged_levels := 1
	while spell_stage.state == ScenarioVmResult.State.WAITING and spell_stage.interaction.kind == InteractionRequest.LEVEL_UP and spell_stage.interaction.body.to_data()["mode"] == "result":
		acknowledged_levels += 1
		spell_stage = restored_vm.resume(InteractionResponse.from_data(spell_stage.interaction.request_id, InteractionRequest.LEVEL_UP, {"action": "continue", "characterId": character.id}), restored_api)
	assert_true(spell_stage.state == ScenarioVmResult.State.WAITING and spell_stage.interaction.kind == InteractionRequest.LEVEL_UP and spell_stage.interaction.body.to_data()["mode"] == "spell-selection" and not spell_stage.interaction.body.to_data()["spells"].is_empty() and not String(spell_stage.interaction.body.to_data()["spells"][0]["description"]).is_empty(), "a qualifying caster advances to a dedicated spell-selection stage with the exact application spell description")
	assert_equal(acknowledged_levels, 4, "the same reward drains every earned level instead of deferring them to later one-point awards")
	var spell_boundary := ScenarioVmSnapshot.from_data(JSON.parse_string(JSON.stringify(restored_vm.snapshot().to_data())))
	assert_not_null(spell_boundary, "the spell-selection stage is independently serializable")
	var completed := restored_vm.resume(InteractionResponse.from_data(spell_stage.interaction.request_id, InteractionRequest.LEVEL_UP, {"action": "confirm-spells", "characterId": character.id, "spellIds": []}), restored_api)
	assert_equal([completed.state, saved_game.world.trigger_is_disabled("ap.reward-level"), completed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"classic_control_marker")], [ScenarioVmResult.State.COMPLETED, true, false], "a completed staged scenario reward reaches opcode 25, removes its issuing AP, and terminates before any later Encounter code")
	assert_equal([saved_game.party.character_by_id(character.id).level, saved_game.party.character_by_id(character.id).experience], [5, -23_001], "all earned levels survive the complete continuation with a negative balance toward the next level")


func _test_terminal_battle_rewards_once(content: RealmzContent) -> void:
	var battle: BattleDefinition = content.battle_by_id("classic.battle.0"); var character := _character(content, "reward.victor", "Victor", 5_000, -10_000_000); var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [character]), RealmzClock.new()); var rng := RealmzRng.new(31); var rules := RealmzRules.new(); var magical_loot: ItemDefinition = content.item_definitions().filter(func(item: ItemDefinition) -> bool: return item.magical)[0]
	var setup := rules.combat_flow.start_battle(state, content, battle, rng)
	assert_true(setup.ok, "terminal reward fixture starts a source-backed battle")
	if not setup.ok:
		return
	var defeated_hostiles := 0
	for monster: MonsterState in state.combat.monsters():
		if monster.traitor:
			if defeated_hostiles == 0: monster.set_loot_item_ids([magical_loot.id]); monster.mark_loot_magic_detected()
			monster.current_health = 0
			defeated_hostiles += 1
	state.combat.active_turn = null
	state.combat.pending_monster_attack = null
	state.combat.pending_reaction = null
	state.combat.completed = true
	state.combat.outcome = &"victory"
	state.last_battle_outcome = &"victory"
	var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new(), rules)
	var reward := api.begin_completed_battle_reward("battle.reward")
	assert_true(reward.state in [ScenarioRuntimeOperationResult.State.WAITING, ScenarioRuntimeOperationResult.State.COMPLETED], "victory transitions into the typed reward pipeline")
	assert_equal(reward.interaction.body.to_data()["items"].filter(func(row: Dictionary) -> bool: return row["definitionId"] == magical_loot.id and row["magical"]).size(), 1, "battle Discover Magic carries only the detected magical loot item into the Treasure presentation")
	var detected_continuation := ScenarioRuntimeContinuation.from_data(JSON.parse_string(JSON.stringify(reward.continuation.to_data()))); var detected_body := detected_continuation.body as ScenarioRuntimeContinuation.RewardBody; assert_equal(detected_body.state.magic_detected_item_ids().size(), 1, "per-item battle magic detection survives the terminal reward continuation boundary")
	var guard := 2_000
	while reward.state == ScenarioRuntimeOperationResult.State.WAITING and guard > 0:
		var response := _reward_response(reward.interaction)
		var serialized_data: Dictionary = JSON.parse_string(JSON.stringify(reward.continuation.to_data()))
		var serialized := ScenarioRuntimeContinuation.from_data(serialized_data)
		var serialized_body := serialized.body as ScenarioRuntimeContinuation.RewardBody if serialized != null else null
		assert_not_null(serialized_body, "every terminal reward interaction retains a valid serialized continuation")
		assert_not_null(serialized_body.state, "every terminal reward interaction retains typed reward state")
		reward = api.resume_classic(serialized, response, reward.interaction.request_id + ".next")
		guard -= 1
	assert_true(guard > 0, "terminal reward completion stays within the bounded interaction count")
	assert_equal([reward.state, state.combat, state.last_battle_outcome], [ScenarioRuntimeOperationResult.State.COMPLETED, null, &"victory"], "victory completes reward ownership and releases the terminal battle exactly once")
	var money_draws := rng.trace().filter(func(entry: Dictionary) -> bool: return String(entry.get("tag", "")).begins_with("battle.reward.") and String(entry.get("tag", "")).contains(".money."))
	assert_equal(money_draws.size(), defeated_hostiles * 3, "each defeated hostile consumes Castle's three denomination draws, including zero-maximum money fields")
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
	var mode_ten_item := content.item_by_id(content.treasure_by_classic_id(0).item_ids()[0]); var mode_ten_character := _character(content, "reward.mode-ten", "Mode Ten", 500, 0); mode_ten_character.set_inventory([ItemInstance.new("mode-ten.stored", mode_ten_item.id, mode_ten_item.initial_charges)]); var mode_ten_party := PartyState.new(content.start_map_id, content.start_coordinate, [mode_ten_character]); mode_ten_party.pooled_wealth.gold = 40; assert_true(mode_ten_party.capture_equipment(), "mode 10 fixture captures the source-owned party equipment and wealth")
	var mode_ten_state := GameState.new(mode_ten_party, RealmzClock.new()); var mode_ten_rules := RealmzRules.new(); var mode_ten_saved := GameState.from_data(JSON.parse_string(JSON.stringify(mode_ten_state.to_data()))); assert_true(mode_ten_rules.combat_flow.start_battle(mode_ten_saved, content, battle, RealmzRng.new(29)).ok, "mode 10 escrow restores before its battle starts through the public combat boundary"); var defeated_character := mode_ten_saved.party.character_by_id(mode_ten_character.id); defeated_character.current_health = 0; defeated_character.conditions.set_value(ConditionRules.ANIMATED, -1); mode_ten_saved.combat.active_turn = null; mode_ten_saved.combat.pending_monster_attack = null; mode_ten_saved.combat.pending_reaction = null; mode_ten_saved.combat.invalidate_undo(); mode_ten_saved.combat.completed = true; mode_ten_saved.combat.outcome = &"defeat"; mode_ten_saved.last_battle_outcome = &"defeat"; var mode_ten_rng := RealmzRng.new(31); var mode_ten_api := RealmzRuntimeApi.new(content, mode_ten_saved, mode_ten_rng, ScenarioActionState.new(), mode_ten_rules); var mode_ten_caller := ScenarioBattleCaller.classic(2, false, 10, 0)
	var mode_ten_handoff := ScenarioRuntimeHandoff.party_defeat(battle.id, ScenarioRuntimeHandoff.CLASSIC_COMBAT, mode_ten_caller); assert_false(RealmzRuntimeApi.party_defeat_handoff_is_valid(content, mode_ten_saved, mode_ten_handoff), "mode 10 never enters the ordinary Party Death handoff"); var restarted := mode_ten_api.begin_completed_battle_reward("battle.mode-ten.defeat", mode_ten_caller); var restarted_character := mode_ten_saved.party.character_by_id(mode_ten_character.id); assert_equal([restarted.state, restarted.directive.kind, restarted_character.current_health, restarted_character.conditions.value(ConditionRules.ANIMATED), mode_ten_saved.party.equipment_storage_active, mode_ten_saved.combat, mode_ten_rng.snapshot().draw_count], [ScenarioRuntimeOperationResult.State.COMPLETED, ScenarioVmDirective.RESTART_CURRENT_PROGRAM, 1, 0, true, null, 0], "mode 10 total defeat bypasses Party Death, revives the party, retains escrow, consumes no RNG, and requests the exact caller restart")
	assert_equal([restarted.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"classic_battle_restart_requested").size(), restarted.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"battle_returned").size()], [1, 0], "the restarted defeat publishes one restart and no false terminal return")
	assert_equal(ScenarioVmDirective.from_data(JSON.parse_string(JSON.stringify(restarted.directive.to_data()))).kind, ScenarioVmDirective.RESTART_CURRENT_PROGRAM, "the mode 10 restart directive survives its strict wire boundary")
	var restore_character := _character(content, "reward.mode-ten-victory", "Mode Ten Victory", 500, 0); restore_character.set_inventory([ItemInstance.new("mode-ten.original", mode_ten_item.id, mode_ten_item.initial_charges)]); var restore_party := PartyState.new(content.start_map_id, content.start_coordinate, [restore_character]); restore_party.pooled_wealth.gold = 40; assert_true(restore_party.capture_equipment(), "mode 10 victory fixture captures the original equipment"); restore_character.set_inventory([ItemInstance.new("mode-ten.scenario", mode_ten_item.id, mode_ten_item.initial_charges)]); restore_party.pooled_wealth.gold = 5; var restore_state := GameState.new(restore_party, RealmzClock.new()); restore_state.combat = CombatState.new(battle.id); restore_state.combat.completed = true; restore_state.combat.outcome = &"victory"; restore_state.last_battle_outcome = &"victory"; var restore_rng := RealmzRng.new(31)
	var restored_mode_ten := RealmzRuntimeApi.new(content, restore_state, restore_rng, ScenarioActionState.new(), RealmzRules.new()).begin_completed_battle_reward("battle.mode-ten.victory", mode_ten_caller); assert_equal([restored_mode_ten.state, restore_character.inventory()[0].id, restore_party.storage()[0].id, restore_party.pooled_wealth.gold, restore_party.equipment_storage_active, restore_state.combat, restore_rng.snapshot().draw_count], [ScenarioRuntimeOperationResult.State.COMPLETED, "mode-ten.original", "mode-ten.scenario", 40, false, null, 0], "mode 10 victory restores only escrowed equipment and wealth, retains scenario gear as recovered storage, and returns without reward RNG"); assert_equal(restored_mode_ten.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"battle_returned").size(), 1, "mode 10 victory publishes one terminal return")
	assert_true(restored_mode_ten.events.any(func(event: DomainEvent) -> bool: return event.kind == &"equipment_restored" and event.payload.get("changed") == true), "the victory return exposes its source-owned equipment restoration")

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


func _test_battle_mode_five_and_incidental_rewards(content: RealmzContent) -> void:
	var source_battle := content.battle_by_id("classic.battle.0"); var opening_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [_character(content, "reward.mode-five-opening", "Opening", 5_000, -100_000)]), RealmzClock.new()); var opening := RealmzRuntimeApi.new(content, opening_state, RealmzRng.new(47), ScenarioActionState.new(), RealmzRules.new()).execute_classic(ClassicActionDefinition.new(0, 2, 2, source_battle.classic_id, false, [source_battle.classic_id, 0, 0, 0, 5]), "battle.mode-five.open"); var opening_body := opening.continuation.body as ScenarioRuntimeContinuation.CombatBody if opening.continuation != null else null; assert_equal(opening_body.caller.mode if opening_body != null else -1, 5, "opcode 2 preserves AOGM's fifth Extra Code word as the public battle caller mode")
	var loot := content.treasure_by_classic_id(0).item_ids()[0]; var flags: Array[int] = [1, 0, 0, 0, 0, 0, 0, 0]; var definition := MonsterDefinition.new("reward.incidental.monster", 9_001, "Incidental", 2, 0, 10, 0, 0, flags, [], [], [9, 8, 7], [], [loot], [], []); definition.can_summon = 0; definition.experience = 25; definition.traitor = true; definition.size = 0
	var battle := BattleDefinition.new("reward.incidental.battle", 9_001, [], 0, 0, 0, 0); var reward_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, content.scenario, [], [], [], content.race_definitions(), content.caste_definitions(), content.item_definitions(), content.spell_definitions(), [definition], [battle], [content.treasure_by_classic_id(0)], [], [], [], [], [], content.campaign_definition()); var results: Dictionary = {}
	for mode: int in [0, 5]:
		var character := _character(reward_content, "reward.mode-%d" % mode, "Mode %d" % mode, 5_000, -10_000_000); var party := PartyState.new(content.start_map_id, content.start_coordinate, [character]); var state := GameState.new(party, RealmzClock.new()); var tiles: Array[int] = []; tiles.resize(BattlefieldState.CELL_COUNT); tiles.fill(0); var field := BattlefieldState.new(content.start_map_id, tiles); assert_true(field.place_character(character.id, Vector2i(45, 45)), "mode %d reward fixture places its experience recipient" % mode)
		var monster := MonsterState.new("reward.mode-%d.monster" % mode, definition.id, definition.name, 0, 10, definition.hit_dice, definition.agility, definition.armor, definition.magic_resistance, 0, true); assert_true(field.place_monster(monster.id, Vector2i(47, 45), 0), "mode %d reward fixture places its defeated monster" % mode); var summoned := MonsterState.new("reward.mode-%d.summoned" % mode, definition.id, definition.name, 0, 10, definition.hit_dice, definition.agility, definition.armor, definition.magic_resistance, 0, true); summoned.summoned = true; assert_true(field.place_monster(summoned.id, Vector2i(48, 45), 0), "mode %d reward fixture places a defeated summon" % mode); state.combat = CombatState.new(battle.id, [monster, summoned], 0, field); state.combat.completed = true; state.combat.outcome = &"victory"; state.last_battle_outcome = &"victory"
		var rng := ScriptedRng.new([32_767, 32_767, 32_767, 0, 0]); var api := RealmzRuntimeApi.new(reward_content, state, rng, ScenarioActionState.new(), RealmzRules.new()); var reward := api.begin_completed_battle_reward("battle.mode-%d" % mode, ScenarioBattleCaller.classic(2, false, mode, 0)); var payload := reward.interaction.body.to_data(); var item_ids: Array = payload["items"].map(func(row: Dictionary) -> String: return row["definitionId"]); results[mode] = {"experience": payload["experienceShare"], "itemIds": item_ids, "wealth": party.pooled_wealth.to_data(), "tags": rng.trace().map(func(row: Dictionary) -> String: return row["tag"])}
		if mode == 5:
			var restored_state := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data()))); var restored_continuation := ScenarioRuntimeContinuation.from_data(JSON.parse_string(JSON.stringify(reward.continuation.to_data()))); var restored_rng := RealmzRng.new(1); assert_true(restored_rng.restore(rng.snapshot()), "mode 5 reward restores its exact post-construction RNG boundary"); var restored_api := RealmzRuntimeApi.new(reward_content, restored_state, restored_rng, ScenarioActionState.new(), RealmzRules.new()); var guard := 10
			while reward.state == ScenarioRuntimeOperationResult.State.WAITING and guard > 0:
				reward = restored_api.resume_classic(restored_continuation, _reward_response(reward.interaction), reward.interaction.request_id + ".next"); restored_continuation = reward.continuation; guard -= 1
			assert_equal([reward.state, restored_state.combat, guard > 0], [ScenarioRuntimeOperationResult.State.COMPLETED, null, true], "mode 5 incidental treasure and experience survive canonical save/restore and return once")
	assert_equal([results[0]["wealth"], results[5]["wealth"]], [{"gold": 9, "gems": 8, "jewelry": 7}, {"gold": 0, "gems": 0, "jewelry": 0}], "mode 5 consumes the three source money draws but discards their values")
	assert_true(results[0]["itemIds"].has(loot) and not results[5]["itemIds"].has(loot), "mode 5 discards authored monster loot while the ordinary battle retains it"); assert_equal([results[0]["itemIds"].count("classic.item.806"), results[0]["itemIds"].count("classic.item.877"), results[5]["itemIds"].count("classic.item.806"), results[5]["itemIds"].count("classic.item.877")], [1, 1, 1, 1], "source-eligible parchment and ration checks remain active in ordinary and experience-only booty")
	assert_equal([results[0]["experience"], results[5]["experience"]], [400, 400], "ordinary and mode 5 rewards exclude summoned actors from the fixture's scaled battle experience"); assert_equal(results[5]["tags"], ["battle.reward.reward.mode-5.monster.money.0", "battle.reward.reward.mode-5.monster.money.1", "battle.reward.reward.mode-5.monster.money.2", "battle.reward.reward.mode-5.monster.parchment", "battle.reward.reward.mode-5.monster.rations"], "summoned actors consume no money, parchment, or ration reward draws")


func _test_opcode_48_bonus_reward_chain(content: RealmzContent) -> void:
	var source_battle := content.battle_by_id("classic.battle.0")
	if source_battle == null:
		return
	var bonus_content := _content_with_bonus_treasure(content, source_battle); var battle := bonus_content.battle_by_id(source_battle.id); var bonus_treasure := bonus_content.treasure_by_classic_id(1); var opening_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [_character(content, "reward.opcode-48-opening", "Opening", 5_000, -100_000)]), RealmzClock.new()); opening_state.set_selected_character_ids([opening_state.party.characters()[0].id]); var opening_api := RealmzRuntimeApi.new(bonus_content, opening_state, RealmzRng.new(47), ScenarioActionState.new(), RealmzRules.new())
	var action := ClassicActionDefinition.new(0, 48, 48, battle.classic_id, false, [battle.classic_id, 0, 0, 0, bonus_treasure.classic_id])
	var opened := opening_api.execute_classic(action, "battle.opcode-48.open")
	var combat_body := opened.continuation.body as ScenarioRuntimeContinuation.CombatBody if opened.continuation != null else null
	assert_not_null(combat_body, "opcode 48 starts through the ordinary typed combat continuation")
	assert_equal(combat_body.caller.mode if combat_body != null else -1, bonus_treasure.classic_id, "opcode 48 preserves Extra Code word five as its post-battle treasure identity")

	var character := _character(bonus_content, "reward.opcode-48", "Bonus", 5_000, -10_000_000)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [character]), RealmzClock.new())
	var rng := RealmzRng.new(53)
	var rules := RealmzRules.new()
	var setup := rules.combat_flow.start_battle(state, bonus_content, battle, rng)
	assert_true(setup.ok, "opcode 48 reward fixture starts a source-backed battle")
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
	var api := RealmzRuntimeApi.new(bonus_content, state, rng, ScenarioActionState.new(), rules)
	var caller := ScenarioBattleCaller.classic(48, false, bonus_treasure.classic_id, 0)
	var reward := api.begin_completed_battle_reward("battle.opcode-48.reward", caller)
	var event_kinds: Array[StringName] = []
	var guard := 2_000
	while guard > 0:
		for event: DomainEvent in reward.events:
			event_kinds.append(event.kind)
		if reward.state != ScenarioRuntimeOperationResult.State.WAITING:
			break
		var serialized := ScenarioRuntimeContinuation.from_data(JSON.parse_string(JSON.stringify(reward.continuation.to_data())))
		assert_not_null(serialized, "each opcode 48 reward stage survives canonical continuation serialization")
		reward = api.resume_classic(serialized, _reward_response(reward.interaction), reward.interaction.request_id + ".next")
		guard -= 1
	assert_true(guard > 0, "opcode 48 ordinary and fixed treasure stages complete within the bounded interaction count")
	assert_equal([reward.state, state.combat], [ScenarioRuntimeOperationResult.State.COMPLETED, null], "opcode 48 releases combat only after both reward workspaces complete")
	assert_equal(event_kinds.count(&"battle_bonus_reward_started"), 1, "opcode 48 opens its authored fixed treasure exactly once after ordinary booty")
	assert_equal(event_kinds.count(&"reward_completed"), 2, "opcode 48 commits ordinary and fixed treasure as two ordered reward stages")
	assert_equal(event_kinds.count(&"battle_returned"), 1, "opcode 48 returns to its issuing VM exactly once after the second reward")
	assert_true(event_kinds.find(&"battle_bonus_reward_started") > event_kinds.find(&"reward_completed") and event_kinds.find(&"battle_returned") > event_kinds.find(&"battle_bonus_reward_started"), "the fixed treasure stage remains between ordinary booty and terminal battle return")

	var defeat_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [_character(bonus_content, "reward.opcode-48-defeat", "Defeat", 5_000, -10_000_000)]), RealmzClock.new())
	var defeat_rng := RealmzRng.new(59)
	var defeat_setup := rules.combat_flow.start_battle(defeat_state, bonus_content, battle, defeat_rng)
	assert_true(defeat_setup.ok, "opcode 48 defeat characterization starts a source-backed battle")
	if defeat_setup.ok:
		defeat_state.combat.active_turn = null
		defeat_state.combat.pending_monster_attack = null
		defeat_state.combat.pending_reaction = null
		defeat_state.combat.completed = true
		defeat_state.combat.outcome = &"defeat"
		var defeat := RealmzRuntimeApi.new(bonus_content, defeat_state, defeat_rng, ScenarioActionState.new(), rules).begin_completed_battle_reward("battle.opcode-48.defeat", caller)
		var defeat_kinds: Array[StringName] = []
		for event: DomainEvent in defeat.events:
			defeat_kinds.append(event.kind)
		assert_equal([defeat.state, defeat_state.combat], [ScenarioRuntimeOperationResult.State.COMPLETED, null], "opcode 48 defeat returns without opening either victory reward workspace")
		assert_equal(defeat_kinds.count(&"battle_bonus_reward_started"), 0, "opcode 48 defeat cannot grant its fixed treasure")


func _content_with_bonus_treasure(content: RealmzContent, battle: BattleDefinition) -> RealmzContent:
	var monsters: Array[MonsterDefinition] = []
	var monster_ids: Dictionary = {}
	for slot: BattleMonsterSlotDefinition in battle.monster_slots():
		if monster_ids.has(slot.monster_id):
			continue
		monster_ids[slot.monster_id] = true
		monsters.append(content.monster_by_id(slot.monster_id))
	var base_treasure := content.treasure_by_classic_id(0)
	var treasures: Array[TreasureDefinition] = [base_treasure, TreasureDefinition.new("classic.treasure.1", 1, [base_treasure.item_ids()[0]], 321, 11)]
	var battles: Array[BattleDefinition] = [BattleDefinition.new(battle.id, battle.classic_id, battle.monster_slots(), battle.distance, 0, 0, battle.macro_id)]
	return RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, content.scenario, [], [], [], content.race_definitions(), content.caste_definitions(), content.item_definitions(), content.spell_definitions(), monsters, battles, treasures, [], [], [], [], [], content.campaign_definition())


func _test_corrupt_reward_boundaries(content: RealmzContent) -> void:
	var character := _character(content, "reward.corrupt", "Corrupt", 500, -100_000); var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [character]), RealmzClock.new()); var rng := RealmzRng.new(41); var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new(), RealmzRules.new())
	var opened := api.execute_safe("core.economy.grant-treasure", {"treasureId": "classic.treasure.0"}, "reward.corrupt.open"); var pooled_before := state.party.pooled_wealth.to_data()
	var fractional_transfer := api.resume_safe(opened.continuation, InteractionResponse.from_data(opened.interaction.request_id, opened.interaction.kind, {"action": "transfer", "direction": "to-character", "kind": "gold", "amount": 5.5, "characterId": character.id}), "reward.corrupt.transfer")
	assert_equal(fractional_transfer.error_code, &"invalid_interaction_response", "a non-integral transfer amount is rejected without coercion")
	assert_equal(state.party.pooled_wealth.to_data(), pooled_before, "a corrupt transfer leaves pooled wealth unchanged")
	var unknown_denomination := api.resume_safe(opened.continuation, InteractionResponse.from_data(opened.interaction.request_id, opened.interaction.kind, {"action": "transfer", "direction": "to-character", "kind": "silver", "amount": 1, "characterId": character.id}), "reward.corrupt.kind")
	assert_equal(unknown_denomination.error_code, &"invalid_interaction_response", "an unknown reward denomination fails explicitly")

	var battle: BattleDefinition = content.battle_by_id("classic.battle.0")
	var battle_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [_character(content, "reward.invalid-battle", "Invalid Battle", 500, 0)]), RealmzClock.new())
	var battle_rng := RealmzRng.new(43)
	var rules := RealmzRules.new()
	var setup := rules.combat_flow.start_battle(battle_state, content, battle, battle_rng)
	assert_true(setup.ok, "invalid-reward characterization begins from a valid battle")
	if not setup.ok:
		return
	for monster: MonsterState in battle_state.combat.monsters():
		if monster.traitor:
			monster.current_health = 0
	battle_state.combat.active_turn = null
	battle_state.combat.undo_state = null
	battle_state.combat.pending_monster_attack = null
	battle_state.combat.pending_reaction = null
	battle_state.combat.completed = true
	battle_state.combat.outcome = &"victory"
	var draws_before := battle_rng.snapshot().draw_count
	var invalid_bonus := RealmzRuntimeApi.new(content, battle_state, battle_rng, ScenarioActionState.new(), rules).begin_completed_battle_reward("battle.invalid-bonus", ScenarioBattleCaller.classic(48, false, 999, 0))
	assert_equal(invalid_bonus.error_code, &"unknown_treasure", "an unavailable opcode 48 bonus treasure fails before claiming reward ownership")
	assert_equal([battle_state.combat.rewards_started, battle_rng.snapshot().draw_count], [false, draws_before], "bonus treasure validation neither claims the one-shot stage nor consumes reward RNG")
	var corrupted_monster: MonsterState = null
	var original_definition_id := ""
	for monster: MonsterState in battle_state.combat.monsters():
		if monster.traitor:
			corrupted_monster = monster
			original_definition_id = monster.definition_id
			monster.definition_id = "classic.monster.unavailable"
			break
	var invalid_reward := RealmzRuntimeApi.new(content, battle_state, battle_rng, ScenarioActionState.new(), rules).begin_completed_battle_reward("battle.invalid-reward")
	assert_equal(invalid_reward.error_code, &"unknown_monster", "a malformed battle reward fails before committing its continuation")
	assert_equal([battle_state.combat.rewards_started, battle_rng.snapshot().draw_count], [false, draws_before], "battle reward validation neither claims the one-shot stage nor consumes reward RNG")

	corrupted_monster.definition_id = original_definition_id
	var reward_item: ItemDefinition = content.item_definitions()[0]
	assert_true(corrupted_monster.set_loot_item_ids([reward_item.id]), "post-validation rollback characterization fixes one source-valid loot item")
	var colliding_instance_id := "reward.item.%d" % (battle_state.instance_id_checkpoint() + 1)
	assert_true(battle_state.combat.queue_fumbled_item(ItemInstance.new(colliding_instance_id, reward_item.id, reward_item.initial_charges)), "post-validation rollback characterization queues a source-valid fumbled item")
	var state_before_construction_failure := battle_state.to_data()
	var rng_before_construction_failure := battle_rng.checkpoint()
	var failed_construction := RealmzRuntimeApi.new(content, battle_state, battle_rng, ScenarioActionState.new(), rules).begin_completed_battle_reward("battle.invalid-construction")
	assert_equal(failed_construction.error_code, &"invalid_reward", "an exact-instance collision characterizes a failure after reward ownership and RNG would otherwise advance")
	assert_equal(battle_state.to_data(), state_before_construction_failure, "failed battle reward construction restores ownership, instance IDs, wealth, experience, combat, and fumbled items atomically")
	assert_equal(battle_rng.checkpoint(), rng_before_construction_failure, "failed battle reward construction restores RNG state, draw count, trace, and scripted source position")


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
		if request.body.to_data().get("mode") == "result":
			return InteractionResponse.from_data(request.request_id, request.kind, {"action": "continue", "characterId": request.body.to_data()["characterId"]})
		return InteractionResponse.from_data(request.request_id, request.kind, {"action": "confirm-spells", "characterId": request.body.to_data()["characterId"], "spellIds": []})
	if request.body.to_data().get("mode") == "completion-confirmation":
		return InteractionResponse.from_data(request.request_id, request.kind, {"action": "confirm-completion"})
	var items: Variant = request.body.to_data().get("items", [])
	if items is Array and not items.is_empty():
		return InteractionResponse.from_data(request.request_id, request.kind, {"action": "discard", "instanceId": items[0]["instanceId"]})
	return InteractionResponse.from_data(request.request_id, request.kind, {"action": "done"})
