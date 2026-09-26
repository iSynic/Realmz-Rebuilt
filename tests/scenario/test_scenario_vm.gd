extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const AOGM_OPCODE_INVENTORY_PATH: String = "res://tests/fixtures/oracle/aogm-active-opcode-inventory.json"


func selected_case_arguments() -> Array:
	var loaded := load_test_package(FIXTURE_PATH); return [loaded.content] if loaded.is_ok() else []


func run() -> void:
	var loaded := load_test_package(FIXTURE_PATH)
	if not loaded.is_ok():
		return
	var content: RealmzContent = loaded.content
	_test_scenario_wire_contracts()
	_test_public_interaction_matrix(content)
	_test_public_classic_choice_control_flow(content); _test_half_truth_complex_spell_class()
	_test_public_classic_difficulty_branch(content); _test_opcode_59_current_cell(content); _test_public_classic_encounter_iterations(content)
	_test_public_encounter_teleport_handoff(content)
	_test_public_thief_encounter(content); _test_public_session_resume(content)
	_test_public_vm_combat_auto(content); _test_opcode_56_defeat_return(content); _test_public_classic_forced_victory(content); _test_public_classic_combat_spawn(content); _test_public_classic_combat_mutation(content); _test_opcode_127_roster_presence(content)
	_test_public_vm_repeated_combat_item(content)
	_test_public_continuation_matrix(content)
	_test_public_limits_and_errors(content)
	_test_public_application_transitions(content); _test_public_shop_money(content); _test_public_world_state_opcodes(content); _test_half_truth_random_water_branch(); _test_public_opcode_61_land_shift(content)
	_test_public_character_checks(content)
	_test_scripted_party_defeat(content)
	_test_corrected_character_selection_opcodes(content)
	_test_corrected_fatigue_opcode(content)
	_test_corrected_take_experience_opcode(content)
	_test_opcode_7_program_replacement_modes(content)
	_test_opcode_13_trigger_mutation_modes(content)
	_test_public_action_state(content); _test_aogm_dispatch_has_no_fallback(content); _test_classic_opcode_2_legacy_battle_record(content); _test_package_backed_macro_spells(); _test_repaired_branch_and_opcode_variants(content); _test_state_and_progression_branch_opcodes(content)


func _test_scenario_wire_contracts() -> void:
	_test_scenario_runtime_continuation_contracts()
	_test_session_continuation_contracts()
	var branch := ScenarioVmDirective.branch_program_at("xap:7", true, ScenarioExecutionContext.trigger(&"", "ap.fixture"), 3); var restored := ScenarioVmDirective.from_data(JSON.parse_string(JSON.stringify(branch.to_data())))
	assert_not_null(restored, "VM directive round-trips through its typed wire contract"); assert_equal([restored.kind, restored.program_id, restored.gosub, restored.entry_cursor, ScenarioExecutionContextCodec.encode(restored.context)], [ScenarioVmDirective.BRANCH_PROGRAM, "xap:7", true, 3, {"triggerId": "ap.fixture"}], "VM directive preserves branch cursor and trigger state")
	var encounter_context := ScenarioExecutionContext.encounter(&"complex", 2, "", -1, &"choice", 0).set_encounter_attempt(3); var encounter_branch := ScenarioVmDirective.branch_encounter_result("complex:2:result:0", false, encounter_context, true); var restored_encounter_branch := ScenarioVmDirective.from_data(JSON.parse_string(JSON.stringify(encounter_branch.to_data()))); var enter_encounter := ScenarioVmDirective.from_data(JSON.parse_string(JSON.stringify(ScenarioVmDirective.enter_encounter(&"simple", 7, true).to_data()))); assert_equal([restored_encounter_branch.kind, restored_encounter_branch.repeat_encounter, restored_encounter_branch.context.value("encounterAttempt"), ScenarioVmDirective.from_data(ScenarioVmDirective.finish_timeline().to_data()).kind, ScenarioVmDirective.from_data(ScenarioVmDirective.resume_after_encounter().to_data()).kind, ScenarioVmDirective.from_data(ScenarioVmDirective.dropout().to_data()).kind, enter_encounter.kind, enter_encounter.encounter_kind, enter_encounter.target_id, enter_encounter.gosub], [ScenarioVmDirective.BRANCH_ENCOUNTER_RESULT, true, 3, ScenarioVmDirective.FINISH_TIMELINE, ScenarioVmDirective.RESUME_AFTER_ENCOUNTER, ScenarioVmDirective.DROPOUT, ScenarioVmDirective.ENTER_ENCOUNTER, &"simple", 7, true], "VM directives preserve encounter repetition, selected encounter entry, signed GOSUB, dropout, and both source-backed exits")
	for malformed: Dictionary in [
		{"kind": "finish", "extra": true}, {"kind": "branch-xap", "targetId": "7", "gosub": false}, {"kind": "branch-program", "programId": "", "gosub": false, "context": {}}, {"kind": "branch-program", "programId": "xap:7", "gosub": false, "context": {}, "unexpected": true},
	]:
		assert_equal(ScenarioVmDirective.from_data(malformed), null, "VM directive rejects malformed or unknown fields")
	var context := ScenarioExecutionContext.encounter(&"complex", 0, "response.0", 0, &"thief", 0)
	context.set_application_hook(&"shop", ""); context.set_combatant("monster.0", 0, false, true); context.set_thief_action(0, "character.0"); context.mark_program_transfer("trigger:source", "xap:49")
	var context_wire: Dictionary = JSON.parse_string(JSON.stringify(ScenarioExecutionContextCodec.encode(context))); var restored_context := ScenarioExecutionContextCodec.decode(context_wire)
	assert_not_null(restored_context, "execution context round-trips with zero and false values")
	assert_equal([JSON.parse_string(JSON.stringify(ScenarioExecutionContextCodec.encode(restored_context))), JSON.parse_string(JSON.stringify(ScenarioExecutionContextCodec.encode(context.copy())))], [context_wire, context_wire], "execution context preserves sparse declared fields through strict wire restoration and typed copying")
	var unknown_context := context_wire.duplicate(true); unknown_context["unexpected"] = true
	assert_equal(ScenarioExecutionContextCodec.decode(unknown_context), null, "execution context rejects unknown fields")
	var caller := ScenarioBattleCaller.classic(2, false, 0, 0); var handoff := ScenarioRuntimeHandoff.party_defeat("classic.battle.0", ScenarioRuntimeHandoff.CLASSIC_COMBAT, caller); var body := CombatContinuationBody.new(); body.battle_id = "classic.battle.0"; body.actor_id = "character.1"; body.mode = &"explicit"; body.destination = Vector2i(-100_000, -100_000); var collision_body := CombatContinuationBody.new(); collision_body.battle_id = body.battle_id; collision_body.actor_id = body.actor_id; collision_body.mode = &"friendly"; collision_body.destination = Vector2i(46, 45)
	var contracts: Array[Dictionary] = [
		{"name": "battle caller", "value": caller, "decode": ScenarioBattleCaller.from_data},
		{"name": "encounter continuation", "value": ScenarioInteractionContinuations.encounter(ScenarioRuntimeContinuation.CLASSIC_SIMPLE_ENCOUNTER, 0, false, [0]), "decode": ScenarioRuntimeContinuation.from_data},
		{"name": "retreat continuation", "value": ScenarioCombatContinuations.retreat(ScenarioRuntimeContinuation.CLASSIC_COMBAT_RETREAT, ScenarioRuntimeContinuation.CLASSIC_COMBAT, "classic.battle.0", caller, "character.1", &"explicit", Vector2i(-100_000, -100_000)), "decode": ScenarioRuntimeContinuation.from_data},
		{"name": "VM pending continuation", "value": ScenarioVmPendingContinuation.classic(ScenarioInteractionContinuations.encounter(ScenarioRuntimeContinuation.CLASSIC_SIMPLE_ENCOUNTER, 0, false, [0])), "decode": ScenarioVmPendingContinuation.from_data},
		{"name": "runtime handoff", "value": handoff, "decode": ScenarioRuntimeHandoff.from_data},
		{"name": "VM handoff", "value": ScenarioVmHandoff.classic(handoff), "decode": ScenarioVmHandoff.from_data},
		{"name": "session retreat", "value": CombatContinuations.retreat_confirmation(body), "decode": SessionContinuation.from_data},
		{"name": "session friendly collision", "value": CombatContinuations.friendly_collision(collision_body), "decode": SessionContinuation.from_data},
	]
	for contract: Dictionary in contracts:
		var wire: Dictionary = JSON.parse_string(JSON.stringify(contract.value.to_data())); var decoded: Variant = contract.decode.call(wire)
		assert_not_null(decoded, "%s round-trips" % contract.name)
		assert_equal(JSON.parse_string(JSON.stringify(decoded.to_data())), wire, "%s preserves its fields" % contract.name)
		var unknown := wire.duplicate(true); unknown["unexpected"] = true
		assert_equal(contract.decode.call(unknown), null, "%s rejects unknown fields" % contract.name)
	var combat_body := InteractionResponse.CombatBody.new(&"cast_spell", "character.1"); combat_body.spell_id = "classic.spell.58"; combat_body.target_coordinates.assign([Vector2i(44, 46), Vector2i(43, 46)]); var combat_wire: Dictionary = combat_body.to_data(); var combat_response := InteractionResponse.from_data("combat.sequence", InteractionRequest.COMBAT, combat_wire)
	assert_equal((combat_response.body as InteractionResponse.CombatBody).target_coordinates, [Vector2i(44, 46), Vector2i(43, 46)], "typed combat responses preserve ordered summon-space coordinates"); var ambiguous_combat: Dictionary = combat_wire.duplicate(true); ambiguous_combat["targetIds"] = ["monster.0"]; assert_equal(InteractionResponse.from_data("combat.ambiguous", InteractionRequest.COMBAT, ambiguous_combat).body, null, "typed combat responses reject mixed actor and coordinate target sequences")
	var snapshot := ScenarioVmSnapshot.new().to_data(); snapshot["unexpected"] = true
	assert_equal(ScenarioVmSnapshot.from_data(snapshot), null, "VM snapshots reject unknown fields")


func _test_scenario_runtime_continuation_contracts() -> void:
	var classic_caller := ScenarioBattleCaller.classic(2, false, 0, 0)
	var safe_caller := ScenarioBattleCaller.safe_continue()
	var age_update := AgeUpdateRequestBody.new()
	age_update.character_id = "character.1"; age_update.character_name = "Ari"; age_update.portrait_id = "portrait.1"; age_update.combat_icon_id = "icon.1"; age_update.race_id = "race.1"; age_update.race_name = "Human"; age_update.age_group_name = "Adult"; age_update.age_minimum_years = 18; age_update.age_maximum_years = 60; age_update.transition = 1; age_update.applied_age_group = 1; age_update.prompt = "Ari grows older."; age_update.presentation = &"classic-textbox"; age_update.sound_id = 1; age_update.source = &"test"
	var updates: Array[AgeUpdateRequestBody] = [age_update]
	var macro_vm := ScenarioVmSnapshot.new()
	var reward_state := ClassicRewardState.new(&"battle", "classic.battle.1", 0, WealthState.new())
	reward_state.battle_stage = ClassicRewardState.ORDINARY_BATTLE_STAGE
	var continuations: Array[ScenarioRuntimeContinuation] = [
		ScenarioInteractionContinuations.textbox(1),
		ScenarioInteractionContinuations.acknowledge(),
		ScenarioInteractionContinuations.player_map("classic.player-map.1"),
		ScenarioInteractionContinuations.safe_choice(2),
		ScenarioInteractionContinuations.classic_choice([1, 2, 3, 4, 5], false),
		ScenarioInteractionContinuations.encounter(ScenarioRuntimeContinuation.CLASSIC_SIMPLE_ENCOUNTER, 0, false, [0]),
		ScenarioInteractionContinuations.encounter(ScenarioRuntimeContinuation.CLASSIC_COMPLEX_ENCOUNTER, 0, true),
		ScenarioInteractionContinuations.thief_encounter(0, false),
		ScenarioInteractionContinuations.pick_lock(0, false, 2, "character.1"),
		ScenarioInteractionContinuations.thief_resolution(0, false, 2, "character.1", &"action-message", true, false),
		ScenarioInteractionContinuations.character_selection(1, false, false),
		ScenarioInteractionContinuations.character_ability([1, 2, 3, 4, 5], false),
		ScenarioAgeContinuations.updates(ScenarioRuntimeContinuation.CLASSIC_AGE_UPDATES, updates, 1, {"accepted": true}, ScenarioVmDirective.finish_timeline()),
		ScenarioAgeContinuations.updates(ScenarioRuntimeContinuation.SAFE_AGE_UPDATES, updates, 1, null, null),
		ScenarioServiceContinuations.shop("classic.shop.1", [1, 2, 3, 4]),
		ScenarioServiceContinuations.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE, 100, true, "character.1"),
		ScenarioServiceContinuations.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE_EXIT, 100, false, "character.1"),
		ScenarioServiceContinuations.banking(),
		ScenarioCombatContinuations.battle(ScenarioRuntimeContinuation.CLASSIC_COMBAT, "classic.battle.1", classic_caller),
		ScenarioCombatContinuations.battle(ScenarioRuntimeContinuation.SAFE_COMBAT, "safe.battle.1", safe_caller),
		ScenarioCombatContinuations.retreat(ScenarioRuntimeContinuation.CLASSIC_COMBAT_RETREAT, ScenarioRuntimeContinuation.CLASSIC_COMBAT, "classic.battle.1", classic_caller, "character.1", &"explicit", Vector2i(-100_000, -100_000)),
		ScenarioCombatContinuations.retreat(ScenarioRuntimeContinuation.SAFE_COMBAT_RETREAT, ScenarioRuntimeContinuation.SAFE_COMBAT, "safe.battle.1", safe_caller, "character.1", &"edge", Vector2i(4, 5)),
		ScenarioCombatContinuations.age_updates(ScenarioRuntimeContinuation.CLASSIC_COMBAT_AGE, ScenarioRuntimeContinuation.CLASSIC_COMBAT, "classic.battle.1", classic_caller, updates, 1, 1),
		ScenarioCombatContinuations.age_updates(ScenarioRuntimeContinuation.SAFE_COMBAT_AGE, ScenarioRuntimeContinuation.SAFE_COMBAT, "safe.battle.1", safe_caller, updates, 1, 1),
		ScenarioCombatContinuations.macro(ScenarioRuntimeContinuation.CLASSIC_COMBAT_MACRO, ScenarioRuntimeContinuation.CLASSIC_COMBAT, "classic.battle.1", classic_caller, "xap:1", macro_vm),
		ScenarioCombatContinuations.macro(ScenarioRuntimeContinuation.SAFE_COMBAT_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT, "safe.battle.1", safe_caller, "scenario.action.1", macro_vm),
		ScenarioCombatContinuations.macro(ScenarioRuntimeContinuation.CLASSIC_COMBAT_DEATH_MACRO, ScenarioRuntimeContinuation.CLASSIC_COMBAT, "classic.battle.1", classic_caller, "xap:1", macro_vm, "monster.1", false),
		ScenarioCombatContinuations.macro(ScenarioRuntimeContinuation.SAFE_COMBAT_DEATH_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT, "safe.battle.1", safe_caller, "scenario.action.1", macro_vm, "monster.1"),
		ScenarioCombatContinuations.opcode_death_macro("classic.battle.1", "monster.1", "xap:1", ["monster.2"], macro_vm),
		ScenarioCombatContinuations.terminal(ScenarioRuntimeContinuation.CLASSIC_COMBAT_ALLY, ScenarioRuntimeContinuation.CLASSIC_COMBAT, "classic.battle.1", classic_caller),
		ScenarioCombatContinuations.terminal(ScenarioRuntimeContinuation.SAFE_COMBAT_ALLY, ScenarioRuntimeContinuation.SAFE_COMBAT, "safe.battle.1", safe_caller),
		ScenarioCombatContinuations.terminal(ScenarioRuntimeContinuation.CLASSIC_COMBAT_FUMBLE, ScenarioRuntimeContinuation.CLASSIC_COMBAT, "classic.battle.1", classic_caller),
		ScenarioCombatContinuations.terminal(ScenarioRuntimeContinuation.SAFE_COMBAT_FUMBLE, ScenarioRuntimeContinuation.SAFE_COMBAT, "safe.battle.1", safe_caller),
		ScenarioRewardContinuations.reward(reward_state),
	]
	var kinds: Dictionary = {}
	for continuation: ScenarioRuntimeContinuation in continuations:
		var wire: Dictionary = JSON.parse_string(JSON.stringify(continuation.to_data()))
		var restored := ScenarioRuntimeContinuation.from_data(wire)
		assert_not_null(restored, "%s runtime continuation round-trips" % continuation.kind)
		assert_equal(JSON.parse_string(JSON.stringify(restored.to_data())), wire, "%s runtime continuation preserves its exact wire payload" % continuation.kind)
		kinds[continuation.kind] = true
		var unknown_data := wire.duplicate(true); unknown_data["data"]["unexpected"] = true
		assert_equal(ScenarioRuntimeContinuation.from_data(unknown_data), null, "%s runtime continuation rejects unknown payload fields" % continuation.kind)
	assert_equal([continuations.size(), kinds.size()], [34, 34], "the scenario runtime continuation contract covers every stable kind exactly once")
	assert_equal(ScenarioRuntimeContinuation.from_data(ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_TEXTBOX, ScenarioServiceContinuations.banking().body).to_data()), null, "runtime continuation decoding rejects a mismatched payload family")


func _test_session_continuation_contracts() -> void:
	var post_clock := ExplorationContinuationBody.new()
	post_clock.map_id = "land:0"; post_clock.coordinate = Vector2i(12, 34); post_clock.timed_day = 2; post_clock.timed_check_coordinate = Vector2i(-1, -1); post_clock.random_region_index = -1; post_clock.resume_kind = &"completed"
	var post_move := ExplorationContinuationBody.new()
	post_move.map_id = "land:0"; post_move.coordinate = Vector2i(13, 34); post_move.trigger_index = 0; post_move.random_region_index = -1
	var boat := BoatContinuationBody.new()
	boat.action = &"board"; boat.source_map_id = "land:0"; boat.source_coordinate = Vector2i(12, 34); boat.target_map_id = "land:0"; boat.target_coordinate = Vector2i(13, 34); boat.direction = Vector2i.RIGHT
	var application := ScenarioApplicationContinuationBody.new()
	application.hook = ScenarioApplicationHooks.START_GAME; application.program_id = "xap:1"; application.resume_kind = &"begin-adventure"
	var item_target := TargetingContinuationBody.new()
	item_target.character_id = "character.1"; item_target.instance_id = "item.1"; item_target.spell_id = "classic.spell.1"; item_target.power = 1; item_target.target_count = 1; item_target.starting_charges = 2
	var spell_target := TargetingContinuationBody.new()
	spell_target.character_id = "character.1"; spell_target.spell_id = "classic.spell.1"; spell_target.power = 1; spell_target.target_count = 1; spell_target.starting_spell_points = 10
	var scroll_target := TargetingContinuationBody.new()
	scroll_target.character_id = "character.1"; scroll_target.spell_id = "classic.spell.1"; scroll_target.power = 1; scroll_target.target_count = 1; scroll_target.scroll_slot = 0
	var scroll_discard := TargetingContinuationBody.new()
	scroll_discard.character_id = "character.1"; scroll_discard.spell_id = "classic.spell.1"; scroll_discard.power = 1; scroll_discard.scroll_slot = 0
	var drop_item := TargetingContinuationBody.new()
	drop_item.character_id = "character.1"; drop_item.instance_id = "item.1"
	var item_xap := ItemXapContinuationBody.new()
	item_xap.character_id = "character.1"; item_xap.instance_id = "item.1"; item_xap.item_id = "classic.item.1"; item_xap.program_id = "xap:1"
	var age_update := AgeUpdateRequestBody.new()
	age_update.character_id = "character.1"; age_update.character_name = "Ari"; age_update.portrait_id = "portrait.1"; age_update.combat_icon_id = "icon.1"; age_update.race_id = "race.1"; age_update.race_name = "Human"; age_update.age_group_name = "Adult"; age_update.age_minimum_years = 18; age_update.age_maximum_years = 60; age_update.transition = 1; age_update.applied_age_group = 1; age_update.prompt = "Ari grows older."; age_update.presentation = &"classic-textbox"; age_update.sound_id = 1; age_update.source = &"test"
	var age := AgeContinuationBody.new()
	age.updates.append(age_update); age.index = 1; age.resume_kind = &"completed"
	var retreat := _session_combat_body("classic.battle.1")
	retreat.actor_id = "character.1"; retreat.mode = &"explicit"; retreat.destination = Vector2i(-100_000, -100_000)
	var collision := _session_combat_body("classic.battle.1")
	collision.actor_id = "character.1"; collision.mode = &"friendly"; collision.destination = Vector2i(4, 5)
	var death_macro := _session_combat_body("classic.battle.1")
	death_macro.combatant_id = "monster.1"; death_macro.program_id = "xap:2"
	var reward_state := ClassicRewardState.new(&"battle", "classic.battle.1", 0, WealthState.new())
	reward_state.battle_stage = ClassicRewardState.ORDINARY_BATTLE_STAGE
	var reward_runtime := ScenarioRewardContinuations.reward(reward_state)
	var continuations: Array[SessionContinuation] = [
		ExplorationContinuations.post_clock(post_clock), ExplorationContinuations.post_move(post_move), ExplorationContinuations.boat_choice(boat), ScenarioContinuations.application_hook(application),
		CharacterContinuations.spell_confirmation("character.1", 3), CharacterContinuations.vault_publication("character.1"),
		InventoryContinuations.item_target(item_target), MagicContinuations.field_spell_target(spell_target), MagicContinuations.scroll_target(scroll_target), MagicContinuations.scroll_discard(scroll_discard), InventoryContinuations.drop_confirmation(drop_item),
		InventoryContinuations.item_xap(item_xap), ServiceContinuations.interaction("bank.1", ScenarioServiceContinuations.banking()), ServiceContinuations.pooled_wealth_departure(&"warning", Vector2i.RIGHT), CharacterContinuations.age_updates(age),
		CombatContinuations.retreat_confirmation(retreat), CombatContinuations.friendly_collision(collision), CombatContinuations.death_macro(death_macro), CombatContinuations.ally_selection(_session_combat_body("classic.battle.1")), CombatContinuations.fumble_recovery(_session_combat_body("classic.battle.1")), CombatContinuations.reward("classic.battle.1", reward_runtime),
	]
	var kinds: Dictionary = {}
	for continuation: SessionContinuation in continuations:
		var wire: Dictionary = JSON.parse_string(JSON.stringify(continuation.to_data()))
		var restored := SessionContinuation.from_data(wire)
		assert_not_null(restored, "%s continuation round-trips" % continuation.kind)
		assert_equal(JSON.parse_string(JSON.stringify(restored.to_data())), wire, "%s continuation preserves its exact wire payload" % continuation.kind)
		kinds[continuation.kind] = true
		var unknown_data := wire.duplicate(true); unknown_data["data"]["unexpected"] = true
		assert_equal(SessionContinuation.from_data(unknown_data), null, "%s continuation rejects unknown payload fields" % continuation.kind)
	assert_equal([continuations.size(), kinds.size()], [21, 21], "the continuation contract covers every stable kind exactly once")
	assert_equal(SessionContinuation.from_data(SessionContinuation.new(&"post-clock", retreat).to_data()), null, "continuation decoding rejects a mismatched payload family")


func _session_combat_body(battle_id: String) -> CombatContinuationBody:
	var body := CombatContinuationBody.new()
	body.battle_id = battle_id
	return body


func _test_public_interaction_matrix(content: RealmzContent) -> void:
	var action_state := ScenarioActionState.new(); var api := _runtime_api(content, action_state); var vm := ScenarioVm.new(); vm.configure(content.scenario)
	assert_equal(vm.start_program("trigger:ap.fixture.encounter", ScenarioExecutionContext.calling(&"action")).state, ScenarioVmResult.State.COMPLETED, "Classic trigger starts through the public VM")
	var waiting := vm.run(api); assert_equal([waiting.state, waiting.interaction.kind], [ScenarioVmResult.State.WAITING, &"encounter_choice"], "Simple Encounter yields a typed choice"); var saved := ScenarioVmSnapshot.from_data(vm.snapshot().to_data())
	assert_not_null(saved, "choice boundary serializes through the public VM snapshot")
	var restored := ScenarioVm.new(); restored.configure(content.scenario)
	assert_true(restored.restore(saved), "choice boundary restores into the same program")
	var result_text := restored.resume(InteractionResponse.from_data(saved.pending_request.request_id, &"encounter_choice", {"index": 0}), api)
	assert_equal([result_text.state, result_text.interaction.kind], [ScenarioVmResult.State.WAITING, &"acknowledge"], "choice response reaches the staged Classic textbox")
	var action_text := restored.resume(InteractionResponse.acknowledge(result_text.interaction), api)
	assert_equal(action_text.state, ScenarioVmResult.State.WAITING, "Scenario Action returns through a second staged textbox")
	var completed := restored.resume(InteractionResponse.acknowledge(action_text.interaction), api)
	assert_equal(completed.state, ScenarioVmResult.State.COMPLETED, "CODE 111 completes the restored action timeline")
	for trace_name: String in ["call-action", "classic-transfer", "classic-return"]:
		assert_true(_trace_has(restored.trace(), trace_name), "VM trace records %s" % trace_name)
	var default_choice := api.execute_classic(ClassicActionDefinition.new(0, 3, 3, 0, false, [1, 0, 0, 0, 2]), "choice.default")
	var authored_choice := api.execute_classic(ClassicActionDefinition.new(0, 3, 3, 0, false, [1, 0, 0, 1, 2]), "choice.authored")
	assert_equal([default_choice.interaction.body.to_data().get("yesLabel"), default_choice.interaction.body.to_data().get("noLabel")], ["Yes", "No"], "zero option IDs use the standard Yes/No labels")
	assert_equal([authored_choice.interaction.body.to_data().get("yesLabel"), authored_choice.interaction.body.to_data().get("noLabel")], ["Proceed", "Turn back"], "authored option IDs use Data OD labels")
	var blocking_sound := api.execute_classic(ClassicActionDefinition.new(0, 9, 9, -10001, false, []), "sound.blocking")
	var asynchronous_sound := api.execute_classic(ClassicActionDefinition.new(0, 9, 9, 10049, false, []), "sound.async")
	assert_equal([blocking_sound.events[0].payload.get("soundId"), blocking_sound.events[0].payload.get("waitForCompletion")], [10001, true], "negative sound preserves absolute ID and synchronous metadata")
	assert_equal([asynchronous_sound.events[0].payload.get("soundId"), asynchronous_sound.events[0].payload.get("waitForCompletion")], [10049, false], "positive sound preserves asynchronous metadata")
	var click_boundary := api.execute_classic(ClassicActionDefinition.new(0, 26, 26, 0, false, []), "click.modal")
	assert_equal([click_boundary.state, click_boundary.interaction.kind, click_boundary.interaction.body.to_data(), click_boundary.events[0].kind, click_boundary.events[0].payload.get("soundId")], [ScenarioRuntimeOperationResult.State.WAITING, InteractionRequest.ACKNOWLEDGE, {"prompt": "Continue", "presentation": "classic-click-modal"}, &"sound_requested", 30005], "opcode 26 stages Castle's compact blocking click window and requests its stock cue exactly once")
	assert_equal(api.resume_classic(click_boundary.continuation, InteractionResponse.acknowledge(click_boundary.interaction), "click.modal.resume").state, ScenarioRuntimeOperationResult.State.COMPLETED, "the compact click acknowledgement releases opcode 26")
	var text := api.execute_classic(ClassicActionDefinition.new(0, 1, 1, 1, false, []), "text.positive"); assert_equal([text.state, text.interaction.kind, text.interaction.body.to_data().get("presentation")], [ScenarioRuntimeOperationResult.State.WAITING, &"acknowledge", "classic-textbox"], "positive message stages the dedicated Classic textbox")
	var wrong := api.resume_classic(text.continuation, InteractionResponse.from_data(text.interaction.request_id, &"yes_no", {"accepted": true}), "text.wrong")
	assert_equal(wrong.error_code, &"invalid_interaction_response", "text continuation rejects an unrelated response shape")
	var acknowledged := api.resume_classic(text.continuation, InteractionResponse.acknowledge(text.interaction), "text.resume")
	assert_equal(acknowledged.state, ScenarioRuntimeOperationResult.State.COMPLETED, "acknowledgement releases the message operation")
	var negative := api.execute_classic(ClassicActionDefinition.new(0, 1, 1, -1, false, []), "text.negative"); assert_equal([negative.state, negative.events[0].payload.get("classicClick")], [ScenarioRuntimeOperationResult.State.COMPLETED, false], "negative message publishes without inventing a click boundary"); var scrolling := api.execute_classic(ClassicActionDefinition.new(0, 62, 62, -200, false, []), "text.scrolling"); assert_equal([scrolling.state, scrolling.interaction.kind, scrolling.interaction.body.to_data(), scrolling.events[0].payload.get("resourceType"), scrolling.events[0].payload.get("resourceId")], [ScenarioRuntimeOperationResult.State.WAITING, InteractionRequest.ACKNOWLEDGE, {"prompt": "", "presentation": "classic-scrolling-text", "resourceType": "TEXT", "resourceId": -200}, "TEXT", -200], "opcode 62 preserves its signed exact TEXT resource identity through a dedicated scrolling acknowledgement boundary instead of misreading Data SD2 messages"); assert_equal(api.resume_classic(scrolling.continuation, InteractionResponse.yes_no(InteractionRequest.yes_no(scrolling.interaction.request_id, "", "Yes", "No"), true), "text.scrolling-wrong").error_code, &"invalid_interaction_response", "scrolling text rejects an unrelated response shape"); var scrolling_program := ScenarioProgramDefinition.new("scrolling.fixture", &"trigger", "scrolling", [ClassicActionDefinition.new(0, 62, 62, -200, false, []), ClassicActionDefinition.new(1, 24, 24, 0, false, [])]); var scrolling_definition := ScenarioDefinition.new([scrolling_program], []); var scrolling_vm := ScenarioVm.new(); scrolling_vm.configure(scrolling_definition); scrolling_vm.start_program(scrolling_program.id, ScenarioExecutionContext.trigger(&"action", "ap.scrolling")); var scrolling_wait := scrolling_vm.run(api); var scrolling_snapshot := ScenarioVmSnapshot.from_data(scrolling_vm.snapshot().to_data()); var restored_scrolling_vm := ScenarioVm.new(); restored_scrolling_vm.configure(scrolling_definition); assert_true(scrolling_snapshot != null and restored_scrolling_vm.restore(scrolling_snapshot) and scrolling_snapshot.pending_request.body.to_data().get("resourceId") == -200, "opcode 62 restores its exact signed TEXT identity and continuation through the public VM snapshot"); var scrolling_complete := restored_scrolling_vm.resume(InteractionResponse.acknowledge(scrolling_wait.interaction), api); assert_true(scrolling_complete.state == ScenarioVmResult.State.COMPLETED and _event_has(scrolling_complete.events, &"action_point_kept"), "acknowledging restored scrolling text resumes the following authored opcode exactly once")
	var random_text := api.execute_classic(ClassicActionDefinition.new(0, 19, 19, 0, false, [1, 3, 0, 0, 0]), "text.random"); var inverted_rng := ScriptedRng.new([0, 0]); var inverted_api := RealmzRuntimeApi.new(content, GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("text.hero", "Hero", 10, 10)]), RealmzClock.new()), inverted_rng, ScenarioActionState.new()); var inverted_text := inverted_api.execute_classic(ClassicActionDefinition.new(0, 19, 19, 0, false, [1, 0, 0, 0, 0]), "text.inverted"); var random_program := ScenarioProgramDefinition.new("complex:0:result:3", &"complex-encounter-result", "3", [ClassicActionDefinition.new(0, 19, 19, 0, false, [1, 0, 0, 0, 0]), ClassicActionDefinition.new(1, 24, 24, 0, false, [])]); var random_vm := ScenarioVm.new(); random_vm.configure(ScenarioDefinition.new([random_program], [])); random_vm.start_program(random_program.id, ScenarioExecutionContext.encounter(&"complex", 0, "", -1, &"choice", 0)); var random_wait := random_vm.run(inverted_api); var random_saved := ScenarioVmSnapshot.from_data(random_vm.snapshot().to_data()); var random_restored := ScenarioVm.new(); random_restored.configure(ScenarioDefinition.new([random_program], [])); assert_true(random_saved != null and random_restored.restore(random_saved), "opcode 19 saves the selected Tutorial-shaped random textbox without another draw"); var random_done := random_restored.resume(InteractionResponse.acknowledge(random_wait.interaction), inverted_api); assert_equal([random_text.state, random_text.events[0].payload.get("messageId"), inverted_text.state, inverted_text.events[0].payload.get("messageId"), inverted_text.events[0].payload.get("classicClick"), random_wait.interaction.body.to_data().get("presentation"), random_done.state, _event_has(random_done.events, &"action_point_kept"), inverted_rng.snapshot().draw_count], [ScenarioRuntimeOperationResult.State.WAITING, 2, ScenarioRuntimeOperationResult.State.WAITING, 1, true, "classic-textbox", ScenarioVmResult.State.COMPLETED, true, 2], "opcode 19 preserves Castle's signed range and blocks the reversed Tutorial result until its selected text is acknowledged exactly once"); var locked_view := api.execute_classic(ClassicActionDefinition.new(0, 96, 96, 0, false, []), "view.lock"); var full_view := api.execute_classic(ClassicActionDefinition.new(0, 97, 97, 0, false, []), "view.full"); assert_equal([locked_view.value, locked_view.events[0].payload.get("multiview"), full_view.value, full_view.events[0].payload.get("multiview")], [false, false, true, true], "opcodes 96 and 97 persist Castle's locked-3D and full-map dungeon policy"); var display_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("display.hero", "Hero", 10, 10)]), RealmzClock.new()); var display_api := RealmzRuntimeApi.new(content, display_state, RealmzRng.new(71), ScenarioActionState.new()); var hidden := display_api.execute_classic(ClassicActionDefinition.new(0, 71, 71, 1, false, []), "display.xy"); var disabled := display_api.execute_classic(ClassicActionDefinition.new(0, 94, 94, 0, false, []), "display.compass-off"); var redundant := display_api.execute_classic(ClassicActionDefinition.new(0, 94, 94, 0, false, []), "display.compass-off-again"); var enabled := display_api.execute_classic(ClassicActionDefinition.new(0, 93, 93, 0, false, []), "display.compass-on"); var restored_display := GameState.from_data(JSON.parse_string(JSON.stringify(display_state.to_data()))); assert_true(hidden.value and not disabled.value and enabled.value and not disabled.events.any(func(event: DomainEvent) -> bool: return event.kind == &"message_shown") and redundant.events.any(func(event: DomainEvent) -> bool: return event.kind == &"message_shown" and event.payload.get("messageId") == 99) and restored_display != null and restored_display.xy_display_hidden and restored_display.compass_enabled and [hidden, disabled, enabled].all(func(result: ScenarioRuntimeOperationResult) -> bool: return result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"map_redraw_requested")), "opcodes 71, 93, and 94 persist display state, refresh presentation, and warn only on a redundant compass transition"); var malformed_display := display_state.to_data(); malformed_display["compassEnabled"] = 1; assert_equal(GameState.from_data(malformed_display), null, "display-state saves reject non-boolean flags")


func _test_public_classic_choice_control_flow(content: RealmzContent) -> void:
	for choice_case: Dictionary in [{"id": "backout", "mode": 0, "event": &"classic_choice_backout_requested"}, {"id": "stop", "mode": 4, "event": &"classic_choice_timeline_stopped"}]:
		var program := ScenarioProgramDefinition.new("choice.%s" % choice_case.id, &"trigger", choice_case.id, [ClassicActionDefinition.new(0, 3, 3, 0, false, [0, int(choice_case.mode), 0, 0, 0]), ClassicActionDefinition.new(1, 24, 24, 0, false, [])]); var vm := ScenarioVm.new(); vm.configure(ScenarioDefinition.new([program], [])); assert_equal(vm.start_program(program.id, ScenarioExecutionContext.trigger(&"action", "ap.%s" % choice_case.id)).state, ScenarioVmResult.State.COMPLETED, "%s Choice fixture starts" % choice_case.id)
		var api := _runtime_api(content, ScenarioActionState.new()); var waiting := vm.run(api); assert_equal([waiting.state, waiting.interaction.kind], [ScenarioVmResult.State.WAITING, InteractionRequest.YES_NO], "%s Choice yields the typed response boundary" % choice_case.id); var selected := vm.resume(InteractionResponse.yes_no(waiting.interaction, true), api)
		assert_equal(selected.state, ScenarioVmResult.State.COMPLETED, "%s Choice selection ends the issuing timeline" % choice_case.id); assert_true(_event_has(selected.events, choice_case.event), "%s Choice publishes its explicit session operation" % choice_case.id); assert_false(_event_has(selected.events, &"action_point_kept") or _event_has(selected.events, &"encounter_option_elimination_requested"), "%s Choice cannot execute the following slot or invent an encounter mutation" % choice_case.id)
		var continued_vm := ScenarioVm.new(); continued_vm.configure(ScenarioDefinition.new([program], [])); continued_vm.start_program(program.id, ScenarioExecutionContext.trigger(&"action", "ap.%s" % choice_case.id)); var continued_wait := continued_vm.run(api); var continued := continued_vm.resume(InteractionResponse.yes_no(continued_wait.interaction, false), api); assert_true(_event_has(continued.events, &"action_point_kept"), "%s Choice leaves the unselected branch on the following authored slot" % choice_case.id)


func _test_half_truth_complex_spell_class() -> void:
	var loaded := load_test_package("res://src/storage/packages/bundled_campaigns/scenario-half-truth.realmz2"); var content: RealmzContent = loaded.content; var encounter := content.scenario_records.complex_encounter_by_id(10); assert_true(encounter != null and encounter.spell_ids()[0] == 3 and encounter.spell_results()[0] == 1, "Half Truth Complex Encounter 10 preserves its Electrical class-to-result-one response"); var cases: Array[Array] = [_half_truth_complex_spell_case(content, 3205), _half_truth_complex_spell_case(content, 3105), _half_truth_complex_spell_case(content, 3103), _half_truth_complex_spell_case(content, 1109)]; assert_equal(cases.map(func(entry: Array) -> Array: return entry.slice(0, 2)), [["Electric Pulse", 3], ["Lightning Strike", 3], ["Electrical Protection", 8], ["Open Lock", 8]], "Half Truth resolves the live submitted spell IDs through their stock spell-class records"); assert_equal(cases.map(func(entry: Array) -> int: return entry[2]), [1, 1, 4, 4], "Half Truth routes class-three electrical attacks to result one while non-class-three spells take fallback result four")


func _half_truth_complex_spell_case(content: RealmzContent, classic_spell_id: int) -> Array:
	var spell := content.magic.spell_by_classic_id(classic_spell_id); var character := CharacterState.new("half-truth.caster.%d" % classic_spell_id, "Caster", 10, 10); character.set_known_spells([spell.id]); var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [character]), RealmzClock.new()); var rng := RealmzRng.for_oracle(10); var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new()); var opened := api.execute_classic(ClassicActionDefinition.new(0, 5, 5, 10, false, []), "half-truth.complex-10"); var resolved := api.resume_classic(opened.continuation, InteractionResponse.from_data(opened.interaction.request_id, opened.interaction.kind, {"action": "spell", "classicSpellId": classic_spell_id, "characterId": character.id}), "half-truth.complex-10.spell"); assert_equal(rng.snapshot().draw_count, 0, "Complex Encounter spell-class routing consumes no gameplay RNG"); return [spell.name, spell.spell_class, int(resolved.value)]


func _test_public_classic_difficulty_branch(content: RealmzContent) -> void:
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("difficulty.hero", "Hero", 10, 10)]), RealmzClock.new()); state.difficulty = 1; state.last_move_direction = Vector2i.RIGHT; var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(58), ScenarioActionState.new()); var direct := api.execute_classic(ClassicActionDefinition.new(0, 58, 58, 0, false, [1, 1, 0, 321, 7]), "difficulty.xap", ScenarioExecutionContext.trigger(&"action", "ap.fixture")); var missed := api.execute_classic(ClassicActionDefinition.new(0, 58, 58, 0, false, [2, 1, 0, 321, 0]), "difficulty.miss"); assert_equal([direct.directive.kind, direct.directive.target_id, missed.value, (missed.events[0] as DomainEvent).payload.get("matched")], [ScenarioVmDirective.BRANCH_XAP, 321, false, false], "opcode 58 compares Castle's signed difficulty directly and branches to the selected XAP only on a match"); var tile_defect := api.execute_classic(ClassicActionDefinition.new(0, 59, 59, 0, false, [32_767, 1, 0, 321, 0]), "tile-defect.xap", ScenarioExecutionContext.trigger(&"action", "ap.fixture")); assert_true(tile_defect.directive.kind == ScenarioVmDirective.BRANCH_XAP and tile_defect.directive.target_id == 321 and tile_defect.events.any(func(event: DomainEvent) -> bool: return event.kind == &"faced_tile_branch_checked" and event.payload.get("expectedTile") == 32_767 and event.payload.get("sourceDefect") == "comparison-omitted"), "opcode 59 reproduces Castle's unconditional branch after faced-tile marker normalization instead of correcting the omitted comparison")
	var simple_source := ScenarioProgramDefinition.new("simple:2:result:0", &"simple-encounter-result", "0", [ClassicActionDefinition.new(0, -58, 58, 0, true, [1, 1, 1, 2, 1]), ClassicActionDefinition.new(1, 24, 24, 0, false, [])]); var simple_target := ScenarioProgramDefinition.new("simple:2:result:2", &"simple-encounter-result", "2", [ClassicActionDefinition.new(0, 1, 1, -1, false, []), ClassicActionDefinition.new(1, 1, 1, 2, false, []), ClassicActionDefinition.new(2, 111, 111, 0, false, [])]); var simple_vm := ScenarioVm.new(); simple_vm.configure(ScenarioDefinition.new([simple_source, simple_target], [])); simple_vm.start_program(simple_source.id, ScenarioExecutionContext.encounter(&"simple", 2, "response", 0)); var waiting := simple_vm.run(api); var saved := ScenarioVmSnapshot.from_data(simple_vm.snapshot().to_data()); var restored := ScenarioVm.new(); restored.configure(ScenarioDefinition.new([simple_source, simple_target], [])); assert_true(saved != null and restored.restore(saved), "opcode 58 saves its exact within-encounter target cursor and GOSUB frame"); var returned := restored.resume(InteractionResponse.acknowledge(waiting.interaction), api); assert_true(waiting.state == ScenarioVmResult.State.WAITING and waiting.interaction.body.to_data().get("messageId") == 2 and returned.state == ScenarioVmResult.State.COMPLETED and _event_has(returned.events, &"action_point_kept"), "opcode 58 skips earlier result code, resumes after the saved target, and returns to the signed caller"); var tile_source := ScenarioProgramDefinition.new("simple:2:result:0", &"simple-encounter-result", "0", [ClassicActionDefinition.new(0, -59, 59, 0, true, [32_767, 1, 1, 2, 1]), ClassicActionDefinition.new(1, 24, 24, 0, false, [])]); var tile_vm := ScenarioVm.new(); tile_vm.configure(ScenarioDefinition.new([tile_source, simple_target], [])); tile_vm.start_program(tile_source.id, ScenarioExecutionContext.encounter(&"simple", 2, "response", 0)); var tile_wait := tile_vm.run(api); var tile_snapshot := ScenarioVmSnapshot.from_data(tile_vm.snapshot().to_data()); var restored_tile_vm := ScenarioVm.new(); restored_tile_vm.configure(ScenarioDefinition.new([tile_source, simple_target], [])); assert_true(tile_wait.state == ScenarioVmResult.State.WAITING and tile_wait.interaction.body.to_data().get("messageId") == 2 and tile_snapshot != null and restored_tile_vm.restore(tile_snapshot) and restored_tile_vm.resume(InteractionResponse.acknowledge(tile_wait.interaction), api).state == ScenarioVmResult.State.COMPLETED, "opcode 59 reuses the exact saveable GOSUB result-program cursor without executing an earlier result slot")
	var complex_source := ScenarioProgramDefinition.new("complex:0:result:0", &"complex-encounter-result", "0", [ClassicActionDefinition.new(0, 58, 58, 0, false, [1, 1, 2, 3, 1]), ClassicActionDefinition.new(1, 84, 84, 700, false, [])]); var complex_target := ScenarioProgramDefinition.new("complex:0:result:3", &"complex-encounter-result", "3", [ClassicActionDefinition.new(0, 84, 84, 701, false, []), ClassicActionDefinition.new(1, 24, 24, 0, false, [])]); var complex_vm := ScenarioVm.new(); complex_vm.configure(ScenarioDefinition.new([complex_source, complex_target], [])); complex_vm.start_program(complex_source.id, ScenarioExecutionContext.encounter(&"complex", 0, "", -1, &"choice", 0)); var complex_result := complex_vm.run(api); assert_true(complex_result.state == ScenarioVmResult.State.COMPLETED and _event_has(complex_result.events, &"action_point_kept") and not complex_result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"classic_control_marker"), "opcode 58 replaces a Complex result at its authored cursor without running skipped target or abandoned source code")
	var kept := api.execute_classic(ClassicActionDefinition.new(0, 58, 58, 0, false, [1, 2, 0, 0, 0]), "difficulty.keep", ScenarioExecutionContext.trigger(&"action", "ap.keep")); var erased := api.execute_classic(ClassicActionDefinition.new(0, 58, 58, 0, false, [1, -2, 0, 0, 0]), "difficulty.erase", ScenarioExecutionContext.trigger(&"action", "ap.erase")); assert_true(kept.directive.kind == ScenarioVmDirective.FINISH_TIMELINE and _event_has(kept.events, &"action_point_kept") and erased.directive.kind == ScenarioVmDirective.FINISH_TIMELINE and state.world.triggers.trigger_is_disabled("ap.erase"), "opcode 58 preserves Castle's matched keep and erase exits without consuming RNG")


func _test_public_classic_encounter_iterations(content: RealmzContent) -> void:
	var simple_responses: Array[SimpleEncounterResponse] = [
		SimpleEncounterResponse.new("first", "First", "simple:0:result:0"), SimpleEncounterResponse.new("second", "Second", "simple:0:result:1"), SimpleEncounterResponse.new("third", "Third", "simple:0:result:2"),
	]
	var simple := SimpleEncounterDefinition.new(0, 0, simple_responses, true, 3, 0); var keep_simple := SimpleEncounterDefinition.new(1, 1, [SimpleEncounterResponse.new("keep", "Keep", "simple:1:result:0")], false, 99, 0); var break_simple := SimpleEncounterDefinition.new(2, 1, [SimpleEncounterResponse.new("break", "Break", "simple:2:result:0")], false, 99, 0); var replace_simple := SimpleEncounterDefinition.new(3, 1, [SimpleEncounterResponse.new("replace", "Replace", "simple:3:result:0")], false, 1, 0); var complex_texts: Array[String] = ["Knock", "Set fire", "", "", "", "", "", "", ""]
	var complex := ComplexEncounterDefinition.new(0, 0, 3, 0, [0, 1, 0, 0, 0, 0, 0, 0], [], [], [], [], true, false, 2, 0, 0, 0, complex_texts)
	var programs: Array[ScenarioProgramDefinition] = [
		ScenarioProgramDefinition.new("root.simple-loop", &"trigger", "simple-loop", [ClassicActionDefinition.new(0, 4, 4, 0, false, [])]), ScenarioProgramDefinition.new("simple:0:result:0", &"simple-encounter-result", "0", [ClassicActionDefinition.new(0, 35, 35, 1, false, [])]), ScenarioProgramDefinition.new("simple:0:result:1", &"simple-encounter-result", "1", [ClassicActionDefinition.new(0, 35, 35, 2, false, [])]), ScenarioProgramDefinition.new("simple:0:result:2", &"simple-encounter-result", "2", []),
		ScenarioProgramDefinition.new("root.simple-keep", &"trigger", "simple-keep", [ClassicActionDefinition.new(0, 39, 39, 325, false, [])]), ScenarioProgramDefinition.new("simple:1:result:0", &"simple-encounter-result", "0", [ClassicActionDefinition.new(0, 24, 24, 0, false, [])]), ScenarioProgramDefinition.new("xap:325", &"extra-action-point", "325", [ClassicActionDefinition.new(0, 4, 4, 1, false, []), ClassicActionDefinition.new(1, 24, 24, 0, false, [])]), ScenarioProgramDefinition.new("root.simple-break", &"trigger", "simple-break", [ClassicActionDefinition.new(0, 4, 4, 2, false, []), ClassicActionDefinition.new(1, 84, 84, 2, false, []), ClassicActionDefinition.new(2, 24, 24, 0, false, [])]), ScenarioProgramDefinition.new("simple:2:result:0", &"simple-encounter-result", "0", [ClassicActionDefinition.new(0, 34, 34, 0, false, [])]),
		ScenarioProgramDefinition.new("root.complex-loop", &"trigger", "complex-loop", [ClassicActionDefinition.new(0, 5, 5, 0, false, [])]), ScenarioProgramDefinition.new("complex:0:result:0", &"complex-encounter-result", "0", []), ScenarioProgramDefinition.new("complex:0:result:1", &"complex-encounter-result", "1", []), ScenarioProgramDefinition.new("complex:0:result:2", &"complex-encounter-result", "2", [ClassicActionDefinition.new(0, 1, 1, 2, false, [])]), ScenarioProgramDefinition.new("complex:0:result:3", &"complex-encounter-result", "3", []), ScenarioProgramDefinition.new("root.random-encounter", &"trigger", "random-encounter", [ClassicActionDefinition.new(0, -85, 85, 0, true, [1, 0, 0, 10001, 2]), ClassicActionDefinition.new(1, 84, 84, 85, false, [])]), ScenarioProgramDefinition.new("root.random-replace", &"trigger", "random-replace", [ClassicActionDefinition.new(0, 85, 85, 0, false, [1, 3, 3, 0, 0]), ClassicActionDefinition.new(1, 84, 84, 85, false, [])]), ScenarioProgramDefinition.new("simple:3:result:0", &"simple-encounter-result", "0", []), ScenarioProgramDefinition.new("root.quest-break", &"trigger", "quest-break", [ClassicActionDefinition.new(0, -72, 72, 0, true, [4, 5, 0, 1, 2]), ClassicActionDefinition.new(1, 84, 84, 72, false, [])]),
	]
	var definition := ScenarioDefinition.new(programs, []); var charge_item := ItemDefinition.new("classic.item.500", 500, "Charge Key")
	var iteration_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, definition, [MessageDefinition.new(0, "Not an encounter prompt."), MessageDefinition.new(1, "Choose."), MessageDefinition.new(2, "Time has expired.")], [], [simple, keep_simple, break_simple, replace_simple], [], [], [charge_item], [], [], [], [], [], [complex])

	var simple_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("loop.hero", "Loop Hero", 10, 10)]), RealmzClock.new()); var simple_rng := RealmzRng.for_oracle(17); var simple_vm := ScenarioVm.new(); simple_vm.configure(definition); simple_vm.start_program("root.simple-loop", ScenarioExecutionContext.trigger(&"action", "ap.simple-loop")); var simple_api := RealmzRuntimeApi.new(iteration_content, simple_state, simple_rng, ScenarioActionState.new()); var branch_hero := simple_state.party.characters()[0]; branch_hero.spell_points = 12; branch_hero.maximum_spell_points = 12; branch_hero.set_inventory([ItemInstance.new("charge-key", charge_item.id, 5)]); simple_state.scenario_progress.set_selected_character_ids([branch_hero.id]); var charges_branch := simple_api.execute_classic(ClassicActionDefinition.new(0, 67, 67, 0, true, [500, 1, 5, 0, 2]), "branch.charges", ScenarioExecutionContext.trigger(&"action", "ap.charges")); simple_state.scenario_progress.set_quest_value(4, 1); simple_state.scenario_progress.set_quest_value(5, 1); var quest_branch := simple_api.execute_classic(ClassicActionDefinition.new(0, 72, 72, 0, true, [4, 5, 0, 2, 0]), "branch.quests"); var spell_branch := simple_api.execute_classic(ClassicActionDefinition.new(0, 75, 75, 0, true, [1, 7, 1, 0, 325]), "branch.spell"); var spell_keep := simple_api.execute_classic(ClassicActionDefinition.new(0, 75, 75, 0, false, [1, 99, 1, 0, 325]), "branch.spell-keep", ScenarioExecutionContext.trigger(&"action", "ap.spell-keep")); assert_true(charges_branch.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and charges_branch.directive.encounter_kind == &"simple" and charges_branch.directive.target_id == 0 and quest_branch.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and quest_branch.directive.encounter_kind == &"complex" and spell_branch.directive.kind == ScenarioVmDirective.BRANCH_XAP and spell_branch.directive.target_id == 325 and spell_keep.directive.kind == ScenarioVmDirective.FINISH_TIMELINE and _event_has(spell_keep.events, &"action_point_kept"), "opcodes 67, 72, and 75 branch on summed charges, an inclusive all-set quest range, and eligible spell points while retaining Keep Codes on spell-point failure")
	var remote_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("remote.hero", "Remote Hero", 10, 10)]), RealmzClock.new()); var remote_api := RealmzRuntimeApi.new(iteration_content, remote_state, RealmzRng.for_oracle(13), ScenarioActionState.new()); var eliminated := remote_api.execute_classic(ClassicActionDefinition.new(0, 41, 41, 0, false, [0, 2, 0, 0, 0]), "encounter.eliminate-remote"); var reduced := remote_api.execute_classic(ClassicActionDefinition.new(0, 4, 4, 0, false, []), "encounter.open-reduced"); var result_branch := remote_api.execute_classic(ClassicActionDefinition.new(0, 38, 38, 0, false, [500, 2, 1, 3, 0]), "encounter.result-branch", ScenarioExecutionContext.encounter(&"simple", 0)); assert_equal([eliminated.state, remote_state.scenario_progress.encounters.simple_option_is_eliminated(0, 1), reduced.interaction.body.to_data().get("options", []).map(func(option: Dictionary) -> String: return option["id"]), reduced.events[0].payload.get("soundId"), reduced.events[0].payload.get("reducedSoundEligible"), result_branch.directive.program_id, result_branch.directive.entry_cursor], [ScenarioRuntimeOperationResult.State.COMPLETED, true, ["first", "third"], 20005, true, "simple:0:result:3", 0], "Simple Encounters request Castle cue 20005, opcode 38 branches within the active result table, and opcode 41 persistently eliminates one exact one-based option")
	var first_choice := simple_vm.run(simple_api); var second_choice := simple_vm.resume(InteractionResponse.from_data(first_choice.interaction.request_id, InteractionRequest.ENCOUNTER_CHOICE, {"index": 0}), simple_api)
	assert_equal([second_choice.state, second_choice.interaction.kind, second_choice.interaction.body.prompt_text(), second_choice.interaction.body.to_data().get("options", []).size(), simple_state.scenario_progress.encounters.attempts(&"simple", 0), _event_has(second_choice.events, &"sound_requested"), simple_vm.snapshot().pending_continuation.runtime.body.wire_payload().get("reopenResult")], [ScenarioVmResult.State.WAITING, InteractionRequest.ENCOUNTER_CHOICE, "", 2, 1, false, true], "Opcode 35 reopens the zero-prompt Simple Encounter immediately without repeating the opening cue and saves its distinct result-replacement continuation")
	var simple_save := save_round_trip(SessionSnapshot.new(iteration_content.campaign_id, iteration_content.package_hash, iteration_content.rules_version, 1, simple_state, simple_rng.snapshot(), simple_vm.snapshot(), ScenarioActionState.new()))
	assert_not_null(simple_save, "repeating Simple Encounter crosses the save envelope")
	if simple_save != null:
		assert_true(SessionRestoreValidator.validate(iteration_content, simple_save).ok, "repeating Simple Encounter passes transactional restore validation")
		var restored_simple_state := GameState.from_data(simple_save.game_state.to_data()); var restored_simple_rng := RealmzRng.for_oracle(1)
		assert_true(restored_simple_rng.restore(simple_save.rng_state), "repeating Simple Encounter restores its gameplay RNG")
		var restored_simple_vm := ScenarioVm.new(); restored_simple_vm.configure(definition)
		assert_true(restored_simple_vm.restore(simple_save.scenario_vm), "repeating Simple Encounter restores its typed VM frame")
		var restored_simple_api := RealmzRuntimeApi.new(iteration_content, restored_simple_state, restored_simple_rng, simple_save.scenario_action_state)
		var third_choice := restored_simple_vm.resume(InteractionResponse.from_data(restored_simple_vm.pending_request().request_id, InteractionRequest.ENCOUNTER_CHOICE, {"index": 0}), restored_simple_api)
		assert_equal([third_choice.state, third_choice.interaction.body.to_data().get("options", []).size()], [ScenarioVmResult.State.WAITING, 1], "restored Simple Encounter continues with its second source option removed")
		var fourth_choice := restored_simple_vm.resume(InteractionResponse.from_data(third_choice.interaction.request_id, InteractionRequest.ENCOUNTER_CHOICE, {"index": 0}), restored_simple_api)
		assert_equal([fourth_choice.state, restored_simple_state.scenario_progress.encounters.attempts(&"simple", 0), _event_has(third_choice.events, &"sound_requested"), _event_has(fourth_choice.events, &"sound_requested"), restored_simple_vm.snapshot().pending_continuation.runtime.body.wire_payload().get("encounterAttempt")], [ScenarioVmResult.State.WAITING, 3, false, true, 1], "Two opcode-35 reopens preserve the repetition counter; only the completed result consumes one authored iteration and repeats its cue")
		var fifth_choice := restored_simple_vm.resume(InteractionResponse.from_data(fourth_choice.interaction.request_id, InteractionRequest.ENCOUNTER_CHOICE, {"index": 0}), restored_simple_api); var simple_done := restored_simple_vm.resume(InteractionResponse.from_data(fifth_choice.interaction.request_id, InteractionRequest.ENCOUNTER_CHOICE, {"index": 0}), restored_simple_api); assert_equal([fifth_choice.state, simple_done.state, restored_simple_state.scenario_progress.encounters.attempts(&"simple", 0), restored_simple_rng.snapshot().draw_count], [ScenarioVmResult.State.WAITING, ScenarioVmResult.State.COMPLETED, 5, 0], "Simple Encounter exhausts three ordinary iterations plus two forced reopens without consuming RNG")
	for exit_case: Dictionary in [{"program": "root.simple-keep", "marker": false, "message": "Keep Codes ends the complete repeated encounter timeline through a transferred XAP"}, {"program": "root.simple-break", "marker": true, "message": "Break Encounter unwinds its result and resumes after the issuing encounter"}]:
		var exit_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("exit.hero", "Exit Hero", 10, 10)]), RealmzClock.new()); var exit_vm := ScenarioVm.new(); exit_vm.configure(definition); exit_vm.start_program(exit_case.program, ScenarioExecutionContext.trigger(&"action", "ap.%s" % exit_case.program)); var exit_api := RealmzRuntimeApi.new(iteration_content, exit_state, RealmzRng.for_oracle(19), ScenarioActionState.new()); var exit_choice := exit_vm.run(exit_api); var exited := exit_vm.resume(InteractionResponse.from_data(exit_choice.interaction.request_id, InteractionRequest.ENCOUNTER_CHOICE, {"index": 0}), exit_api)
		assert_equal([exited.state, exited.interaction, _event_has(exited.events, &"action_point_kept"), _event_has(exited.events, &"classic_control_marker"), exit_state.scenario_progress.encounters.program_id(exit_case.program)], [ScenarioVmResult.State.COMPLETED, null, true, exit_case.marker, exit_case.program], exit_case.message + "; Keep Codes does not persist a transient program transfer")
	var random_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("random.hero", "Random Hero", 10, 10)]), RealmzClock.new()); var random_rng := RealmzRng.for_oracle(85); var random_vm := ScenarioVm.new(); random_vm.configure(definition); random_vm.start_program("root.random-encounter", ScenarioExecutionContext.trigger(&"action", "ap.random")); var random_api := RealmzRuntimeApi.new(iteration_content, random_state, random_rng, ScenarioActionState.new()); var random_choice := random_vm.run(random_api); var repeated_random := random_vm.resume(InteractionResponse.from_data(random_choice.interaction.request_id, InteractionRequest.ENCOUNTER_CHOICE, {"index": 0}), random_api); var random_snapshot := ScenarioVmSnapshot.from_data(JSON.parse_string(JSON.stringify(random_vm.snapshot().to_data()))); var restored_random_vm := ScenarioVm.new(); restored_random_vm.configure(definition); assert_true(random_choice.state == ScenarioVmResult.State.WAITING and random_choice.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 10001) and random_choice.events.any(func(event: DomainEvent) -> bool: return event.kind == &"message_shown" and event.payload.get("messageId") == 2) and repeated_random.state == ScenarioVmResult.State.WAITING and random_rng.snapshot().draw_count == 1 and random_snapshot != null and random_snapshot.frames.any(func(frame: ScenarioFrame) -> bool: return frame.kind == ScenarioFrame.ENCOUNTER and frame.definition_id == "simple:0" and frame.counts_as_classic_call) and restored_random_vm.restore(random_snapshot), "opcode 85 emits optional sound/text, consumes one inclusive draw, and preserves its chosen GOSUB encounter across repetition and VM serialization"); var cancelled_random := restored_random_vm.resume(InteractionResponse.from_data(restored_random_vm.pending_request().request_id, InteractionRequest.ENCOUNTER_CHOICE, {"cancelled": true}), random_api); assert_true(cancelled_random.state == ScenarioVmResult.State.COMPLETED and not _event_has(cancelled_random.events, &"classic_control_marker") and random_rng.snapshot().draw_count == 1, "Back exits opcode 85's entire invocation, including its signed GOSUB caller, without selecting or drawing again"); var quest_break_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("quest.hero", "Quest Hero", 10, 10)]), RealmzClock.new()); quest_break_state.scenario_progress.set_quest_value(4, 1); quest_break_state.scenario_progress.set_quest_value(5, 1); var quest_break_vm := ScenarioVm.new(); quest_break_vm.configure(definition); quest_break_vm.start_program("root.quest-break", ScenarioExecutionContext.trigger(&"action", "ap.quest-break")); var quest_break_api := RealmzRuntimeApi.new(iteration_content, quest_break_state, RealmzRng.for_oracle(72), ScenarioActionState.new()); var quest_break_choice := quest_break_vm.run(quest_break_api); var quest_broken := quest_break_vm.resume(InteractionResponse.from_data(quest_break_choice.interaction.request_id, InteractionRequest.ENCOUNTER_CHOICE, {"index": 0}), quest_break_api); assert_true(quest_broken.state == ScenarioVmResult.State.COMPLETED and _event_has(quest_broken.events, &"classic_control_marker"), "opcode 34 unwinds a branched encounter origin and resumes after opcode 72 exactly once")
	var random_save := save_round_trip(SessionSnapshot.new(iteration_content.campaign_id, iteration_content.package_hash, iteration_content.rules_version, 1, random_state, random_rng.snapshot(), random_snapshot, ScenarioActionState.new())); assert_true(random_save != null and SessionRestoreValidator.validate(iteration_content, random_save).ok, "opcode 85's selected encounter continuation passes complete transactional restore validation"); var replace_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("replace.hero", "Replace Hero", 10, 10)]), RealmzClock.new()); var replace_vm := ScenarioVm.new(); replace_vm.configure(definition); replace_vm.start_program("root.random-replace"); var replace_api := RealmzRuntimeApi.new(iteration_content, replace_state, RealmzRng.for_oracle(851), ScenarioActionState.new()); var replace_choice := replace_vm.run(replace_api); var replace_done := replace_vm.resume(InteractionResponse.from_data(replace_choice.interaction.request_id, InteractionRequest.ENCOUNTER_CHOICE, {"index": 0}), replace_api); assert_true(replace_done.state == ScenarioVmResult.State.COMPLETED and not _event_has(replace_done.events, &"classic_control_marker"), "opcode 85 without GOSUB replaces its caller and exits after the selected encounter's final result")

	var complex_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("timeout.hero", "Timeout Hero", 10, 10)]), RealmzClock.new()); var complex_rng := RealmzRng.for_oracle(23); var complex_vm := ScenarioVm.new(); complex_vm.configure(definition); complex_vm.start_program("root.complex-loop", ScenarioExecutionContext.trigger(&"action", "ap.complex-loop")); var complex_api := RealmzRuntimeApi.new(iteration_content, complex_state, complex_rng, ScenarioActionState.new()); var eliminated_complex_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("eliminated.hero", "Eliminated Hero", 10, 10)]), RealmzClock.new()); var eliminated_complex_api := RealmzRuntimeApi.new(iteration_content, eliminated_complex_state, RealmzRng.for_oracle(44), ScenarioActionState.new()); var eliminated_complex := eliminated_complex_api.execute_classic(ClassicActionDefinition.new(0, 44, 44, 4, false, []), "complex.eliminate", ScenarioExecutionContext.encounter(&"complex", 0)); var restored_eliminated_state := GameState.from_data(JSON.parse_string(JSON.stringify(eliminated_complex_state.to_data()))); var eliminated_complex_vm := ScenarioVm.new(); eliminated_complex_vm.configure(definition); eliminated_complex_vm.start_program("root.complex-loop", ScenarioExecutionContext.trigger(&"action", "ap.complex-eliminated")); var restored_eliminated_api := RealmzRuntimeApi.new(iteration_content, restored_eliminated_state, RealmzRng.for_oracle(44), ScenarioActionState.new()); var eliminated_choice := eliminated_complex_vm.run(restored_eliminated_api); var eliminated_done := eliminated_complex_vm.resume(InteractionResponse.from_data(eliminated_choice.interaction.request_id, InteractionRequest.WORD_AND_ACTION, {"action": "choice", "slots": [0]}), restored_eliminated_api); assert_true(eliminated.state == ScenarioRuntimeOperationResult.State.COMPLETED and restored_eliminated_state.scenario_progress.encounters.complex_result_is_eliminated(0, 3) and eliminated_done.state == ScenarioVmResult.State.COMPLETED and _event_has(eliminated_done.events, &"action_point_kept") and restored_eliminated_state.scenario_progress.encounters.attempts(&"complex", 0) == 1, "opcode 44 saves one current Complex result override and later executes its slot-seven Keep Codes equivalent without mutating the package program"); var exact_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("exact.hero", "Exact Hero", 10, 10)]), RealmzClock.new()); var exact_vm := ScenarioVm.new(); exact_vm.configure(definition); exact_vm.start_program("root.complex-loop"); var exact_api := RealmzRuntimeApi.new(iteration_content, exact_state, RealmzRng.for_oracle(24), ScenarioActionState.new()); var exact_choice := exact_vm.run(exact_api); var exact_result := exact_vm.resume(InteractionResponse.from_data(exact_choice.interaction.request_id, InteractionRequest.WORD_AND_ACTION, {"action": "choice", "slots": [1]}), exact_api); assert_true(exact_result.state == ScenarioVmResult.State.WAITING and exact_result.interaction.kind == InteractionRequest.ACKNOWLEDGE and exact_result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"complex_action_set_selected" and event.payload.get("exactMatch")), "Complex Actions submit Castle's complete toggle set and only the exact authored group selects its success result"); var complex_choice := complex_vm.run(complex_api); var repeated_complex := complex_vm.resume(InteractionResponse.from_data(complex_choice.interaction.request_id, InteractionRequest.WORD_AND_ACTION, {"action": "choice", "slots": [0]}), complex_api); assert_equal([repeated_complex.state, repeated_complex.interaction.kind, repeated_complex.interaction.body.prompt_text(), complex_state.scenario_progress.encounters.attempts(&"complex", 0)], [ScenarioVmResult.State.WAITING, InteractionRequest.WORD_AND_ACTION, "", 1], "Zero-prompt Complex Encounter ignores message zero while a same-sized nonmatching Complex Action set falls through and repeats like COB's Knock response")
	var complex_save := save_round_trip(SessionSnapshot.new(iteration_content.campaign_id, iteration_content.package_hash, iteration_content.rules_version, 1, complex_state, complex_rng.snapshot(), complex_vm.snapshot(), ScenarioActionState.new()))
	assert_not_null(complex_save, "repeating Complex Encounter crosses the save envelope")
	if complex_save != null:
		assert_true(SessionRestoreValidator.validate(iteration_content, complex_save).ok, "repeating Complex Encounter passes transactional restore validation")
		var restored_complex_state := GameState.from_data(complex_save.game_state.to_data()); var restored_complex_rng := RealmzRng.for_oracle(1)
		assert_true(restored_complex_rng.restore(complex_save.rng_state), "repeating Complex Encounter restores its gameplay RNG")
		var restored_complex_vm := ScenarioVm.new(); restored_complex_vm.configure(definition)
		assert_true(restored_complex_vm.restore(complex_save.scenario_vm), "repeating Complex Encounter restores its typed VM frame")
		var restored_complex_api := RealmzRuntimeApi.new(iteration_content, restored_complex_state, restored_complex_rng, complex_save.scenario_action_state)
		var timeout := restored_complex_vm.resume(InteractionResponse.from_data(restored_complex_vm.pending_request().request_id, InteractionRequest.WORD_AND_ACTION, {"action": "choice", "slots": [0]}), restored_complex_api)
		assert_equal([timeout.state, timeout.interaction.kind, timeout.interaction.body.to_data().get("messageId"), restored_complex_state.scenario_progress.encounters.attempts(&"complex", 0)], [ScenarioVmResult.State.WAITING, InteractionRequest.ACKNOWLEDGE, 2, 2], "final Complex fallback routes to Castle's authored timeout result")
		assert_equal(restored_complex_vm.resume(InteractionResponse.acknowledge(timeout.interaction), restored_complex_api).state, ScenarioVmResult.State.COMPLETED, "Complex timeout result exits the encounter loop")

	var cancel_programs: Array[ScenarioProgramDefinition] = programs.filter(func(program: ScenarioProgramDefinition) -> bool: return program.id != "complex:0:result:3"); cancel_programs.append(ScenarioProgramDefinition.new("complex:0:result:3", &"complex-encounter-result", "3", [ClassicActionDefinition.new(0, 5, 5, 0, false, [])])); var cancel_definition := ScenarioDefinition.new(cancel_programs, [])
	var cancelled_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("cancel.hero", "Cancel Hero", 10, 10)]), RealmzClock.new()); var cancelled_vm := ScenarioVm.new(); cancelled_vm.configure(cancel_definition); cancelled_vm.start_program("root.complex-loop", ScenarioExecutionContext.trigger(&"action", "ap.complex-cancel"))
	var cancelled_rng := RealmzRng.for_oracle(29); var cancelled_api := RealmzRuntimeApi.new(iteration_content, cancelled_state, cancelled_rng, ScenarioActionState.new()); var cancel_first := cancelled_vm.run(cancelled_api); var cancel_repeat := cancelled_vm.resume(InteractionResponse.from_data(cancel_first.interaction.request_id, InteractionRequest.WORD_AND_ACTION, {"action": "choice", "slots": [0]}), cancelled_api)
	var cancel_snapshot := ScenarioVmSnapshot.from_data(JSON.parse_string(JSON.stringify(cancelled_vm.snapshot().to_data()))); var restored_cancel_vm := ScenarioVm.new(); restored_cancel_vm.configure(cancel_definition); assert_true(cancel_repeat.state == ScenarioVmResult.State.WAITING and cancel_snapshot.frames.size() == 2 and restored_cancel_vm.restore(cancel_snapshot), "authored nested repetition retains both encounter frames across VM restoration")
	var cancelled := restored_cancel_vm.resume(InteractionResponse.from_data(restored_cancel_vm.pending_request().request_id, InteractionRequest.WORD_AND_ACTION, {"action": "back"}), cancelled_api)
	assert_equal([cancelled.state, cancelled.interaction, cancelled_state.scenario_progress.encounters.attempts(&"complex", 0), cancelled_rng.snapshot().draw_count, restored_cancel_vm.snapshot().frames.size()], [ScenarioVmResult.State.COMPLETED, null, 1, 0, 0], "Back exits the complete restored nested encounter timeline without another attempt or RNG draw")


func _test_public_encounter_teleport_handoff(content: RealmzContent) -> void:
	var encounter := SimpleEncounterDefinition.new(0, 0, [SimpleEncounterResponse.new("leave", "Leave", "simple:0:result:0")], false, 99, 0)
	var programs: Array[ScenarioProgramDefinition] = [
		ScenarioProgramDefinition.new("direct", &"trigger", "direct", [ClassicActionDefinition.new(0, 4, 4, 0, false, []), ClassicActionDefinition.new(1, 84, 84, 1, false, [])]),
		ScenarioProgramDefinition.new("branched", &"trigger", "branched", [ClassicActionDefinition.new(0, -85, 85, 0, true, [1, 0, 0, 0, 0]), ClassicActionDefinition.new(1, 84, 84, 2, false, [])]),
		ScenarioProgramDefinition.new("simple:0:result:0", &"simple-encounter-result", "0", [ClassicActionDefinition.new(0, 39, 39, 1, false, [])]),
		ScenarioProgramDefinition.new("xap:1", &"extra-action-point", "1", [ClassicActionDefinition.new(0, 20, 20, 0, false, [0, 1, 0, 0, 0]), ClassicActionDefinition.new(1, 84, 84, 3, false, [])]),
	]
	var definition := ScenarioDefinition.new(programs, [])
	var fixture := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, "land:0", Vector2i.ZERO, content.world, definition, [], [], [encounter])
	for root_id: String in ["direct", "branched"]:
		var state := GameState.new(PartyState.new("land:0", Vector2i.ZERO, []), RealmzClock.new())
		var rng := RealmzRng.for_oracle(20)
		var api := RealmzRuntimeApi.new(fixture, state, rng, ScenarioActionState.new())
		var vm := ScenarioVm.new()
		vm.configure(definition)
		vm.start_program(root_id)
		var prompt := vm.run(api)
		assert_equal(prompt.state, ScenarioVmResult.State.WAITING, "Teleport fixture reaches its repeating encounter through " + root_id)
		var restored := ScenarioVm.new()
		restored.configure(definition)
		assert_true(restored.restore(ScenarioVmSnapshot.from_data(JSON.parse_string(JSON.stringify(vm.snapshot().to_data())))), "Pending teleport choice restores its caller frames")
		var draws_before := rng.snapshot().draw_count
		var result := restored.resume(InteractionResponse.from_data(prompt.interaction.request_id, InteractionRequest.ENCOUNTER_CHOICE, {"index": 0}), api)
		assert_equal([result.state, result.interaction, restored.snapshot().frames.size(), state.party.coordinate, state.scenario_progress.encounters.attempts(&"simple", 0), rng.snapshot().draw_count], [ScenarioVmResult.State.COMPLETED, null, 0, Vector2i(1, 0), 1, draws_before], "Destination handoff closes the restored encounter and every caller without another choice or RNG draw")
		assert_equal(result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"destination_trigger_recheck_requested").size(), 1, "Teleport requests its destination Action Point exactly once")
		assert_false(_event_has(result.events, &"classic_control_marker"), "Neither a later XAP slot nor the enclosing caller resumes after destination handoff")


func _test_public_thief_encounter(content: RealmzContent) -> void:
	var character := CharacterState.new("thief.hero", "Locksmith", 12, 12); character.set_ability_value(7, 90)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [character]), RealmzClock.new()); var rng := RealmzRng.for_oracle(7); var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new()); var vm := ScenarioVm.new(); vm.configure(content.scenario)
	assert_equal(vm.start_program("trigger:ap.fixture.complex", ScenarioExecutionContext.calling(&"action")).state, ScenarioVmResult.State.COMPLETED, "Complex Encounter fixture starts through the public VM")
	var complex := vm.run(api)
	var complex_actions: Array = complex.interaction.body.to_data().get("actions", []) if complex.interaction != null else []
	assert_equal([complex.state, complex.interaction.kind, complex_actions.filter(func(value: Dictionary) -> bool: return value.get("kind") == "thief").size()], [ScenarioVmResult.State.WAITING, InteractionRequest.WORD_AND_ACTION, 1], "Complex Encounter exposes one dedicated Thief action rather than eight host-authored shortcuts")
	var thief := vm.resume(InteractionResponse.from_data(complex.interaction.request_id, InteractionRequest.WORD_AND_ACTION, {"action": "thief"}), api)
	assert_equal([thief.state, thief.interaction.kind if thief.interaction != null else &""], [ScenarioVmResult.State.WAITING, InteractionRequest.THIEF_ENCOUNTER], "Thief opens its source-shaped character and action workspace")
	if thief.interaction == null: return
	var pick_lock := vm.resume(InteractionResponse.from_data(thief.interaction.request_id, InteractionRequest.THIEF_ENCOUNTER, {"action": "attempt", "characterId": character.id, "actionIndex": 2}), api)
	assert_equal([pick_lock.state, pick_lock.interaction.kind if pick_lock.interaction != null else &"", rng.snapshot().draw_count], [ScenarioVmResult.State.WAITING, InteractionRequest.PICK_LOCK, 0], "Pick Lock previews its timed tumbler sequence without advancing gameplay RNG")
	if pick_lock.interaction == null: return
	var lock_body := pick_lock.interaction.body as PickLockRequestBody
	assert_not_null(lock_body, "Pick Lock request uses its strict typed body")
	if lock_body == null: return
	assert_equal([lock_body.chance_percent, lock_body.time_limit_frames], [90, 210], "Disarm Trap reads Castle spec[7] and retains the final static countdown second")
	var saved := ScenarioVmSnapshot.from_data(JSON.parse_string(JSON.stringify(vm.snapshot().to_data())))
	assert_not_null(saved, "Pick Lock request and issuing continuation serialize at the modal boundary")
	if saved == null: return
	var envelope := SessionSnapshot.new(content.campaign_id, content.package_hash, content.rules_version, 1, state, rng.snapshot(), saved, ScenarioActionState.new())
	assert_true(SessionRestoreValidator.validate(content, envelope).ok, "Pick Lock pending state passes the complete transactional restore validator")
	var forged_wire := saved.to_data()
	forged_wire["pendingRequest"]["data"]["payload"]["frames"][0][0] = 208
	var forged_vm := ScenarioVmSnapshot.from_data(forged_wire)
	assert_not_null(forged_vm, "forged Pick Lock preview remains structurally valid wire data")
	if forged_vm != null:
		var forged_envelope := SessionSnapshot.new(content.campaign_id, content.package_hash, content.rules_version, 1, state, rng.snapshot(), forged_vm, ScenarioActionState.new())
		assert_false(SessionRestoreValidator.validate(content, forged_envelope).ok, "restore rejects a structurally valid Pick Lock preview that does not match authoritative RNG state")
	var restored_state := GameState.from_data(state.to_data()); var restored_rng := RealmzRng.for_oracle(1)
	assert_true(restored_rng.restore(rng.snapshot()), "Pick Lock restores the source RNG position separately from presentation frames")
	var restored_api := RealmzRuntimeApi.new(content, restored_state, restored_rng, ScenarioActionState.new()); var restored_vm := ScenarioVm.new(); restored_vm.configure(content.scenario)
	assert_true(restored_vm.restore(saved), "Pick Lock restores through the public VM snapshot")
	var selected_frame := lock_body.frames.size() - 1
	var resolved := restored_vm.resume(InteractionResponse.from_data(saved.pending_request.request_id, InteractionRequest.PICK_LOCK, {"frameIndex": selected_frame}), restored_api)
	assert_equal([resolved.state, resolved.interaction.kind if resolved.interaction != null else &""], [ScenarioVmResult.State.WAITING, InteractionRequest.ACKNOWLEDGE], "the fixture's nonpositive thief text adds no click before entering the authored Complex result")
	assert_true(restored_rng.snapshot().draw_count > 0, "Committed Pick Lock replays the selected frame prefix through session-owned RNG")
	assert_equal(restored_state.party.character_by_id(character.id).experience, 600, "successful interactive thief action awards 300 experience per authored tumbler")
	var resolution: DomainEvent = null
	for event: DomainEvent in resolved.events:
		if event.kind == &"thief_action_resolved": resolution = event; break
	assert_not_null(resolution, "Pick Lock publishes one source-ordered action result")
	if resolution != null:
		assert_equal([resolution.payload.get("succeeded"), resolution.payload.get("frameIndex"), resolution.payload.get("positions"), resolution.payload.get("classicClick")], [true, selected_frame, lock_body.frames[selected_frame], false], "committed result matches the selected frame and preserves the signed non-click text")
	var scout := CharacterState.new("thief.scout", "Scout", 12, 12); scout.set_ability_value(5, 100)
	var scout_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [scout]), RealmzClock.new()); var scout_api := RealmzRuntimeApi.new(content, scout_state, RealmzRng.for_oracle(1), ScenarioActionState.new()); var scout_vm := ScenarioVm.new(); scout_vm.configure(content.scenario); assert_equal(scout_vm.start_program("trigger:ap.fixture.complex", ScenarioExecutionContext.calling(&"action")).state, ScenarioVmResult.State.COMPLETED, "non-lock thief proof starts through the same public VM")
	var scout_complex := scout_vm.run(scout_api); var scout_thief := scout_vm.resume(InteractionResponse.from_data(scout_complex.interaction.request_id, InteractionRequest.WORD_AND_ACTION, {"action": "thief"}), scout_api)
	scout_vm.resume(InteractionResponse.from_data(scout_thief.interaction.request_id, InteractionRequest.THIEF_ENCOUNTER, {"action": "attempt", "characterId": scout.id, "actionIndex": 0}), scout_api)
	assert_equal(scout_state.party.character_by_id(scout.id).experience, 0, "successful non-lock thief actions do not inherit Pick Lock experience")

	var source_complex := content.scenario_records.complex_encounter_by_id(0); var source_thief := content.scenario_records.thief_encounter_by_id(source_complex.thief_success) if source_complex != null else null
	assert_true(source_complex != null and source_thief != null, "Thief loop fixture provides its source definitions"); if source_complex == null or source_thief == null: return
	var trap_spell := SpellDefinition.new("classic.spell.synthetic-thief-trap", 9901, "Synthetic Trap Stun"); trap_spell.duration_min = 1; trap_spell.duration_max = 1; trap_spell.damage_min = 2; trap_spell.damage_max = 2; trap_spell.damage_type = 8; trap_spell.cannot = 3; trap_spell.special = 2
	var trap_prompts := source_thief.prompts(); trap_prompts[0] = 0; trap_prompts[2] = 1; var trap_thief := ThiefEncounterDefinition.new(source_thief.id, source_thief.type_flags(), source_thief.modifiers(), source_thief.success_codes(), source_thief.failure_codes(), source_thief.success_text(), source_thief.failure_text(), source_thief.success_sounds(), source_thief.failure_sounds(), trap_spell.classic_id, 0, 0, source_thief.tumblers, trap_prompts, source_thief.prompt_sounds()); var trap_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, content.scenario, [content.scenario_records.message_by_id(absi(source_complex.prompt_message_id))], [], [], [], [], [], [trap_spell], [], [], [], [], [source_complex], [trap_thief])
	var trap_first := CharacterState.new("thief.trap-first", "Trap First", 12, 12); trap_first.set_ability_value(5, 1); var trap_second := CharacterState.new("thief.trap-second", "Trap Second", 12, 12); var trap_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [trap_first, trap_second]), RealmzClock.new()); var trap_rng := ScriptedRng.new([32_767, 0, 0]); var trap_api := RealmzRuntimeApi.new(trap_content, trap_state, trap_rng, ScenarioActionState.new()); var trap_vm := ScenarioVm.new(); trap_vm.configure(trap_content.scenario); trap_vm.start_program("trigger:ap.fixture.complex", ScenarioExecutionContext.calling(&"action"))
	var trap_complex := trap_vm.run(trap_api); var trap_menu := trap_vm.resume(InteractionResponse.from_data(trap_complex.interaction.request_id, InteractionRequest.WORD_AND_ACTION, {"action": "thief"}), trap_api); assert_equal(trap_menu.interaction.body.prompt_text(), "", "Zero-prompt Thief Encounter opens without a message-zero record or invented prompt"); var trap_warning := trap_vm.resume(InteractionResponse.from_data(trap_menu.interaction.request_id, InteractionRequest.THIEF_ENCOUNTER, {"action": "attempt", "characterId": trap_first.id, "actionIndex": 0}), trap_api); var trap_resolved := trap_vm.resume(InteractionResponse.acknowledge(trap_warning.interaction), trap_api); var trap_events := trap_resolved.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"thief_trap_spell_resolved")
	assert_equal([trap_resolved.state, trap_events.size(), trap_events.map(func(event: DomainEvent) -> String: return String(event.payload.get("characterId"))), trap_events.map(func(event: DomainEvent) -> int: return int(event.payload.get("damage"))), trap_first.current_health, trap_second.current_health, trap_first.conditions.value(ConditionRules.HELPLESS), trap_second.conditions.value(ConditionRules.HELPLESS), trap_rng.snapshot().draw_count], [ScenarioVmResult.State.WAITING, 2, [trap_first.id, trap_second.id], [2, 2], 10, 10, 1, 1, 3], "a sprung all-party Thief trap shares one source-ordered duration and damage roll, applies the authored spell through the generic scenario resolver, and publishes each stable target")
	var loop_texts := source_complex.action_labels(); loop_texts.append(source_complex.expected_word()); var loop_complex := ComplexEncounterDefinition.new(source_complex.id, source_complex.prompt_message_id, source_complex.action_result, source_complex.word_result, source_complex.groups(), source_complex.spell_ids(), source_complex.spell_results(), source_complex.item_ids(), source_complex.item_results(), source_complex.can_back_out, source_complex.thief, 2, source_complex.caste_success, source_complex.thief_success, source_complex.thief_fail, loop_texts)
	var loop_programs: Array[ScenarioProgramDefinition] = [ScenarioProgramDefinition.new("root.thief-loop", &"trigger", "thief-loop", [ClassicActionDefinition.new(0, 5, 5, loop_complex.id, false, [])])]
	for outcome_index: int in 4:
		loop_programs.append(ScenarioProgramDefinition.new("complex:%d:result:%d" % [loop_complex.id, outcome_index], &"complex-encounter-result", str(outcome_index), [ClassicActionDefinition.new(0, 84, 84, 0, false, [])]))
	var loop_definition := ScenarioDefinition.new(loop_programs, [])
	var loop_messages: Array[MessageDefinition] = [content.scenario_records.message_by_id(absi(loop_complex.prompt_message_id))]
	var loop_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, loop_definition, loop_messages, [], [], [], [], [], [], [], [], [], [], [loop_complex], [source_thief])
	var loop_character := CharacterState.new("thief.loop", "Loop Thief", 12, 12); loop_character.set_ability_value(5, 100); loop_character.set_ability_value(6, 100)
	var loop_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [loop_character]), RealmzClock.new()); var loop_rng := RealmzRng.for_oracle(31); var loop_vm := ScenarioVm.new(); loop_vm.configure(loop_definition); loop_vm.start_program("root.thief-loop", ScenarioExecutionContext.trigger(&"action", "ap.thief-loop"))
	var loop_api := RealmzRuntimeApi.new(loop_content, loop_state, loop_rng, ScenarioActionState.new())
	var loop_complex_choice := loop_vm.run(loop_api)
	var loop_thief_choice := loop_vm.resume(InteractionResponse.from_data(loop_complex_choice.interaction.request_id, InteractionRequest.WORD_AND_ACTION, {"action": "thief"}), loop_api)
	var repeated_after_thief := loop_vm.resume(InteractionResponse.from_data(loop_thief_choice.interaction.request_id, InteractionRequest.THIEF_ENCOUNTER, {"action": "attempt", "characterId": loop_character.id, "actionIndex": 0}), loop_api)
	assert_equal([repeated_after_thief.state, repeated_after_thief.interaction.kind, loop_state.scenario_progress.encounters.attempts(&"complex", loop_complex.id), loop_state.world.triggers.trigger_is_disabled("ap.thief-loop")], [ScenarioVmResult.State.WAITING, InteractionRequest.WORD_AND_ACTION, 1, false], "Thief result retains its issuing AP context while returning to the source Complex Encounter")
	var loop_save := save_round_trip(SessionSnapshot.new(loop_content.campaign_id, loop_content.package_hash, loop_content.rules_version, 1, loop_state, loop_rng.snapshot(), loop_vm.snapshot(), ScenarioActionState.new()))
	assert_true(loop_save != null and SessionRestoreValidator.validate(loop_content, loop_save).ok, "repeating Thief result passes the complete save validator")
	if loop_save != null:
		var restored_loop_state := GameState.from_data(loop_save.game_state.to_data()); var restored_loop_rng := RealmzRng.for_oracle(1); restored_loop_rng.restore(loop_save.rng_state); var restored_loop_vm := ScenarioVm.new(); restored_loop_vm.configure(loop_definition)
		assert_true(restored_loop_vm.restore(loop_save.scenario_vm), "repeating Thief result restores its VM attempt")
		var restored_loop_api := RealmzRuntimeApi.new(loop_content, restored_loop_state, restored_loop_rng, loop_save.scenario_action_state)
		var restored_thief_choice := restored_loop_vm.resume(InteractionResponse.from_data(restored_loop_vm.pending_request().request_id, InteractionRequest.WORD_AND_ACTION, {"action": "thief"}), restored_loop_api)
		var finished_thief := restored_loop_vm.resume(InteractionResponse.from_data(restored_thief_choice.interaction.request_id, InteractionRequest.THIEF_ENCOUNTER, {"action": "attempt", "characterId": loop_character.id, "actionIndex": 1}), restored_loop_api)
		assert_equal([finished_thief.state, restored_loop_state.scenario_progress.encounters.attempts(&"complex", loop_complex.id)], [ScenarioVmResult.State.COMPLETED, 2], "restored Thief result exits after the final Complex selection")


func _test_public_session_resume(content: RealmzContent) -> void:
	var session := GameSession.new()
	session.start(content, 1)
	_begin_fixture_adventure(session, content)
	_restore_fixture_position(session, content, "land:1", Vector2i(0, 1))
	var waiting := session.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	assert_equal([waiting.state, session.view().party_coordinate], [SessionStep.State.WAITING_FOR_INTERACTION, Vector2i(1, 1)], "movement commits before the public interaction response")
	var held := session.snapshot()
	assert_not_null(held.scenario_vm.pending_request, "the save aggregate owns the pending VM request")
	var round_trip := save_round_trip(held)
	assert_not_null(round_trip, "pending interaction crosses the save envelope")
	if round_trip == null:
		return
	var restored := GameSession.new()
	assert_equal(restored.restore(content, round_trip).state, SessionStep.State.COMPLETED, "GameSession restores the committed VM continuation")
	var request := restored.view().pending_interaction
	assert_equal(request.to_data(), held.scenario_vm.pending_request.to_data(), "restore preserves exact request identity and payload")
	var result := restored.respond(InteractionResponse.from_data(request.request_id, &"encounter_choice", {"index": 0}))
	assert_equal(result.state, SessionStep.State.WAITING_FOR_INTERACTION, "the response reaches the next public textbox boundary")
	var textbox_save := save_round_trip(restored.snapshot())
	assert_not_null(textbox_save, "the staged textbox is saveable")
	if textbox_save == null:
		return
	var textbox_restored := GameSession.new()
	assert_equal(textbox_restored.restore(content, textbox_save).state, SessionStep.State.COMPLETED, "the staged textbox restores transactionally")
	var completed := textbox_restored.respond(InteractionResponse.acknowledge(textbox_restored.view().pending_interaction))
	assert_equal(completed.state, SessionStep.State.WAITING_FOR_INTERACTION, "the first acknowledgement reaches the following XAP textbox")
	var final := textbox_restored.respond(InteractionResponse.acknowledge(textbox_restored.view().pending_interaction))
	assert_equal(final.state, SessionStep.State.COMPLETED, "the final acknowledgement resumes the issuing session frame")
	assert_equal(textbox_restored.snapshot().continuation, null, "completed VM work clears the session continuation exactly once")


func _test_public_vm_combat_auto(content: RealmzContent) -> void:
	var battle := content.combat.battle_by_id("classic.battle.0")
	assert_not_null(battle, "VM Auto fixture provides a Classic battle")
	if battle == null:
		return
	var original_scenario := content.scenario; var selective_first := CharacterState.new("fixture.selective.first", "Selective First", 1000, 1000); var selective_second := CharacterState.new("fixture.selective.second", "Selective Second", 1000, 1000); var selective_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [selective_first, selective_second]), RealmzClock.new()); selective_state.scenario_progress.set_selected_character_ids([selective_first.id]); var selective_api := RealmzRuntimeApi.new(content, selective_state, RealmzRng.new(48), ScenarioActionState.new(), RealmzRules.new()); var selective := selective_api.execute_classic(ClassicActionDefinition.new(0, 48, 48, battle.classic_id, false, [battle.classic_id, 0, 0, 0, 0]), "battle.selective"); var selective_saved := CombatState.from_data(JSON.parse_string(JSON.stringify(selective_state.combat.to_data()))); var selective_started: DomainEvent = selective.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"battle_started")[0] if selective.events.any(func(event: DomainEvent) -> bool: return event.kind == &"battle_started") else null; assert_equal([selective.state, selective_state.combat.battlefield.actors.has_actor(selective_first.id), selective_state.combat.battlefield.actors.has_actor(selective_second.id), selective_state.combat.turns.turn_order().has(selective_second.id), selective_started.payload.get("participantCharacterIds") if selective_started != null else [], selective_saved.battlefield.actors.has_actor(selective_first.id) if selective_saved != null else false, selective_saved.battlefield.actors.has_actor(selective_second.id) if selective_saved != null else true], [ScenarioRuntimeOperationResult.State.WAITING, true, false, false, [selective_first.id], true, false], "opcode 48 enters combat with only the stable selected subparty and preserves that boundary through save state"); selective_first.current_health = -10; selective_state.combat.battlefield.actors.remove_character(selective_first.id); selective_state.combat.completed = true; selective_state.combat.outcome = &"defeat"; var selective_defeat := selective_api.complete_debug_victory(selective.continuation, "battle.selective.defeat", []); assert_equal([selective_defeat.state, selective_state.combat, selective_second.current_health, selective_defeat.events.any(func(event: DomainEvent) -> bool: return event.kind == &"classic_notification_requested" and event.payload.get("text") == "There is nobody left to collect any treasure." and event.payload.get("soundId") == 6000), selective_defeat.events.any(func(event: DomainEvent) -> bool: return event.kind == &"battle_returned" and event.payload.get("participantCharacterIds") == [selective_first.id])], [ScenarioRuntimeOperationResult.State.COMPLETED, null, 1000, true, true], "opcode 48 selected-party defeat warns once, skips Party Death, and returns the untouched members who never entered combat")
	var battle_action := ClassicActionDefinition.new(0, 2, 2, battle.classic_id, false, [battle.classic_id, 0, 0, 0, 0])
	var program := ScenarioProgramDefinition.new("fixture.vm-combat-auto", &"application-hook", "start-game", [battle_action])
	content.scenario = ScenarioDefinition.new([program], [], ScenarioApplicationHooks.new(program.id, "", "", "", ""))
	var sixth_id := "fixture.vm-auto.6"
	var inactive_session := _vm_combat_auto_session(content, 1)
	var active_session := _vm_combat_auto_session(content, 3)
	assert_true(inactive_session != null and active_session != null, "public VM combat fixture provides inactive and active sixth-member turns")
	if inactive_session == null or active_session == null:
		content.scenario = original_scenario
		return
	assert_equal([inactive_session.view().combat_view.active_actor_id == sixth_id, active_session.view().combat_view.active_actor_id == sixth_id], [false, true], "fixed fixture seeds cover inactive and active sixth-member turns")
	for member: CharacterView in active_session.view().party_members:
		if member.id != sixth_id: active_session.submit_intent(CombatIntents.set_auto(member.id, true))
	_assert_vm_combat_auto_round_trip(content, inactive_session, sixth_id, "inactive")
	_assert_vm_combat_auto_round_trip(content, active_session, sixth_id, "active")
	content.scenario = original_scenario


func _test_opcode_56_defeat_return(content: RealmzContent) -> void:
	var battle := content.combat.battle_by_id("classic.battle.0")
	var land: MapDefinition = null
	var origin := Vector2i.ZERO
	var direction := Vector2i.ZERO
	for map_id: String in content.world.map_ids():
		var candidate := content.world.map_by_id(map_id)
		if candidate.level_type != &"land":
			continue
		for y: int in range(candidate.topology.height):
			for x: int in range(1, candidate.topology.width):
				if candidate.topology.cell_at(Vector2i(x, y)) != null and candidate.topology.cell_at(Vector2i(x - 1, y)) != null:
					land = candidate; origin = Vector2i(x, y); direction = Vector2i.RIGHT; break
			if land != null: break
		if land != null: break
	assert_true(battle != null and land != null, "opcode 56 defeat-return fixture has a battle and adjacent land cells")
	if battle == null or land == null: return
	var first := CharacterState.new("opcode56.first", "First", 1, 10); first.level = 3; first.experience = 12_345
	var second := CharacterState.new("opcode56.second", "Second", 1, 10); second.level = 7; second.experience = -500
	var state := GameState.new(PartyState.new(land.id, origin, [first, second]), RealmzClock.new()); state.combat = CombatState.new(battle.id); state.combat.completed = true; state.combat.outcome = &"defeat"
	var rng := RealmzRng.new(56); var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new(), RealmzRules.new()); var caller := ScenarioBattleCaller.classic(56, true, 0, -1); var handoff := ScenarioRuntimeHandoff.party_defeat(battle.id, ScenarioRuntimeHandoff.CLASSIC_COMBAT, caller)
	var before := state.to_data(); var rejected := api.complete_party_defeat_handoff(handoff)
	assert_equal([rejected.error_code, state.to_data(), rng.snapshot().draw_count], [&"missing_move_direction", before, 0], "opcode 56 rejects a missing land backup direction without state or RNG mutation")
	state.last_move_direction = direction
	var completed := api.complete_party_defeat_handoff(handoff); var kinds := completed.events.map(func(event: DomainEvent) -> StringName: return event.kind); var notices := completed.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"classic_notification_requested").map(func(event: DomainEvent) -> String: return event.payload.get("text", "")); var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_equal([completed.state, completed.directive.kind, first.experience, second.experience, state.party.coordinate, state.last_battle_outcome, state.combat, rng.snapshot().draw_count], [ScenarioRuntimeOperationResult.State.COMPLETED, ScenarioVmDirective.FINISH_TIMELINE, 6_345, -14_500, origin - direction, &"retreated", null, 0], "opcode 56 target -1 applies each level-scaled loss, backs one land step, returns from the timeline, and consumes no RNG")
	assert_equal([notices, kinds, completed.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested")[0].payload.get("soundId")], [["Having fled the battle, the enemy remains to challange you another time.", "You all loose victory points for this cowardly display."], [&"party_defeat_revived", &"classic_notification_requested", &"sound_requested", &"classic_notification_requested", &"party_backed_up", &"battle_returned"], 26260], "opcode 56 preserves Castle's stock warning wording and ordered defeat-return events")
	assert_true(restored != null and restored.party.coordinate == origin - direction and restored.party.character_by_id(second.id).experience == -14_500 and restored.last_battle_outcome == &"retreated", "opcode 56's completed defeat return survives the save-owned game-state boundary")


func _test_public_classic_forced_victory(content: RealmzContent) -> void:
	var battle := content.combat.battle_by_id("classic.battle.0"); var slots := battle.monster_slots() if battle != null else []; var definition := content.combat.monster_by_id(slots[0].monster_id) if not slots.is_empty() else null; assert_true(battle != null and definition != null, "opcode 100 fixture has source-backed battle content"); if battle == null or definition == null: return; var character := CharacterState.new("opcode100.hero", "Hero", 20, 20); var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [character]), RealmzClock.new()); var tiles: Array[int] = []; tiles.resize(BattlefieldGrid.CELL_COUNT); tiles.fill(0); var field := BattlefieldState.new(content.start_map_id, tiles); field.actors.place_character(character.id, Vector2i(45, 45)); var monster := MonsterState.new("opcode100.monster", definition.id, definition.name, 20, 20, definition.hit_dice, definition.agility, definition.armor, definition.magic_resistance, 0, true); field.actors.place_monster(monster.id, Vector2i(47, 45), 0); state.combat = CombatState.new(battle.id, [monster], -1, field); state.combat.set_turn_order([character.id, monster.id]); var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(100), ScenarioActionState.new(), RealmzRules.new()); var program := ScenarioProgramDefinition.new("xap:100", &"xap", "100", [ClassicActionDefinition.new(0, 100, 100, 0, false, []), ClassicActionDefinition.new(1, 1, 1, 1, false, [])]); var vm := ScenarioVm.new(); vm.configure(ScenarioDefinition.new([program], [])); vm.start_program(program.id, ScenarioExecutionContext.calling(&"battle-macro").set_battle(battle.id)); var result := vm.run(api); var restored := CombatState.from_data(JSON.parse_string(JSON.stringify(state.combat.to_data()))); var reward := api.begin_completed_battle_reward("opcode100.reward", ScenarioBattleCaller.classic(2, false, 0, 0)); var reward_event: DomainEvent = reward.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"battle_reward_constructed")[0] if reward.events.any(func(event: DomainEvent) -> bool: return event.kind == &"battle_reward_constructed") else null; assert_equal([result.state, result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"message_shown"), state.combat.outcome, monster.current_health, restored.classic_post_battle_sentinel if restored != null else -1, reward_event.payload.get("experienceOnly") if reward_event != null else false, reward_event.payload.get("wealth") if reward_event != null else {}], [ScenarioVmResult.State.COMPLETED, false, &"victory", 0, 8, true, {"gold": 0, "gems": 0, "jewelry": 0}], "opcode 100 ends its macro, forces victory, preserves Castle's slot-eight sentinel through save state, and enters ordinary experience-only rewards without running later macro code")


func _test_public_classic_combat_spawn(content: RealmzContent) -> void:
	var source_definition := MonsterDefinition.new("classic.monster.12", 12, "Summoner", 1, 4, 8, 0, 0, [], [], [], [], [], [], [])
	source_definition.size = 3; source_definition.traitor = true; source_definition.can_summon = -1
	var summoned_definition := MonsterDefinition.new("classic.monster.4", 4, "Minor Demon", 1, 4, 8, 0, 0, [], [], [], [], [], [], [])
	summoned_definition.size = 3; summoned_definition.traitor = true; summoned_definition.can_summon = -1
	var battle := BattleDefinition.new("battle.opcode124", 1240, [])
	var spawn_content := RealmzContent.new("opcode124", "1".repeat(64), "opcode124", content.rules_version, content.start_map_id, content.start_coordinate, content.world, ScenarioDefinition.new([], []), [], [], [], [], [], [], [], [source_definition, summoned_definition], [battle])
	var hero := CharacterState.new("opcode124.hero", "Hero", 20, 20)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [hero]), RealmzClock.new())
	var map := content.world.map_by_id(content.start_map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	assert_not_null(terrain_set, "opcode 124 fixture resolves the active map's battle terrain")
	if terrain_set == null:
		return
	var tiles: Array[int] = []
	tiles.resize(BattlefieldGrid.CELL_COUNT)
	tiles.fill(terrain_set.base_tile)
	var field := BattlefieldState.new(content.start_map_id, tiles)
	field.actors.place_character(hero.id, Vector2i(45, 45))
	var source := MonsterState.new("opcode124.source", source_definition.id, source_definition.name, 20, 20, 1, 8, 0, 0, 0, true)
	field.actors.place_monster(source.id, Vector2i(50, 50), source_definition.size)
	state.combat = CombatState.new(battle.id, [source], -1, field)
	state.combat.set_turn_order([hero.id, source.id])
	var api := RealmzRuntimeApi.new(spawn_content, state, RealmzRng.for_oracle(124), ScenarioActionState.new(), RealmzRules.new())
	var result := api.execute_classic(ClassicActionDefinition.new(0, 124, 124, 0, false, [0, 4, 1, 605, 0]), "combat.spawn", ScenarioExecutionContext.calling(&"battle-macro").set_battle(battle.id))
	var spawned_id: String = result.value[0] if result.value is Array and not result.value.is_empty() else ""
	var spawned := state.combat.roster.monster_by_id(spawned_id)
	var spawn_event: DomainEvent = result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_monsters_spawned")[0] if result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_monsters_spawned") else null
	assert_equal([result.state, spawned != null, spawned.traitor if spawned != null else false, field.actors.has_actor(spawned_id), field.actors.actor_position(spawned_id), state.combat.turns.turn_order().back(), spawn_event.payload.get("coordinates") if spawn_event != null else [], result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 605)], [ScenarioRuntimeOperationResult.State.COMPLETED, true, true, true, Vector2i(48, 48), spawned_id, [Vector2i(48, 48)], true], "opcode 124 places a battle-macro summon through Castle's expanding complete-footprint scan, appends its turn, and publishes its authored cue")
	assert_true(BattlefieldGrid.footprint_cells(field.actors.actor_position(spawned_id), summoned_definition.size).all(func(coordinate: Vector2i) -> bool: return field.actors.actor_at(coordinate) == spawned_id), "the summoned 2x2 monster owns every authoritative battlefield cell and therefore appears in combat presentation")
	var macro_spell := SpellDefinition.new("classic.spell.2301", 2301, "Confuse"); macro_spell.in_combat = true; macro_spell.target_type = 3; macro_spell.size = 7; macro_spell.special = 30; macro_spell.spell_class = 5; macro_spell.damage_type = 5; macro_spell.cost = 15; macro_spell.power_duration_min = 1; macro_spell.power_duration_max = 1
	var damage_spell := SpellDefinition.new("classic.spell.4606", 4606, "Macro Blast"); damage_spell.in_combat = true; damage_spell.target_type = 3; damage_spell.size = 7; damage_spell.spell_class = 8; damage_spell.damage_type = 8; damage_spell.damage_min = 40; damage_spell.damage_max = 40
	var field_spell := SpellDefinition.new("classic.spell.3209", 3209, "Noxious Cloud"); field_spell.in_combat = true; field_spell.target_type = 3; field_spell.size = 18; field_spell.queue_icon = 7; field_spell.special = 2; field_spell.spell_class = 4; field_spell.damage_type = 4; field_spell.power_duration_min = 1; field_spell.power_duration_max = 1
	spawn_content.magic = SpellCatalog.new([macro_spell, damage_spell, field_spell]); source.current_health = 0
	var macro_program := ScenarioProgramDefinition.new("xap:108", &"extra-action-point", "108", [ClassicActionDefinition.new(0, 17, 17, 388, false, [2301, 1, 0, 1]), ClassicActionDefinition.new(1, 84, 84, 0, false, [])]); var macro_vm := ScenarioVm.new(); macro_vm.configure(ScenarioDefinition.new([macro_program], [])); macro_vm.start_program(macro_program.id, ScenarioExecutionContext.calling(&"monster-death-macro").set_battle(battle.id).set_combatant(source.id)); var macro_result := macro_vm.run(api)
	assert_equal([macro_result.state, source.current_health, spawned.conditions.value(ConditionRules.CONFUSED), hero.conditions.value(ConditionRules.CONFUSED), state.combat.turns.active_actor_id(), hero.spell_points, macro_spell.cannot, _event_has(macro_result.events, &"classic_control_marker")], [ScenarioVmResult.State.COMPLETED, 0, 1, 0, hero.id, 0, 0, true], "opcode 17 in a death macro targets living footprints around the retained dead source without selected characters, resource cost, turn advance, catalog mutation, or lost following code")
	var field_program := ScenarioProgramDefinition.new("xap:110", &"extra-action-point", "110", [ClassicActionDefinition.new(0, 17, 17, 390, false, [3209, 1, 0, 1]), ClassicActionDefinition.new(1, 84, 84, 0, false, [])]); var field_vm := ScenarioVm.new(); field_vm.configure(ScenarioDefinition.new([field_program], [])); field_vm.start_program(field_program.id, ScenarioExecutionContext.calling(&"monster-death-macro").set_battle(battle.id).set_combatant(source.id)); var field_result := field_vm.run(api); var created_fields := field_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_persistent_field_created"); var retained_fields := state.combat.spell_runtime.persistent_fields()
	assert_equal([field_result.state, created_fields.size(), created_fields[0].payload.get("center") if not created_fields.is_empty() else [], created_fields[0].payload.get("shape") if not created_fields.is_empty() else -1, retained_fields.size(), retained_fields[0].caster_id if not retained_fields.is_empty() else "", retained_fields[0].center if not retained_fields.is_empty() else Vector2i.ZERO, _event_has(field_result.events, &"classic_control_marker")], [ScenarioVmResult.State.COMPLETED, 1, [50, 50], 18, 1, source.id, Vector2i(50, 50), true], "a source-authored queued opcode-17 area creates its persistent field at the retained macro source before continuing the issuing program")
	var damage_program := ScenarioProgramDefinition.new("xap:109", &"extra-action-point", "109", [ClassicActionDefinition.new(0, 17, 17, 389, false, [4606, 1, 0, 1]), ClassicActionDefinition.new(1, 84, 84, 0, false, [])]); var damage_vm := ScenarioVm.new(); damage_vm.configure(ScenarioDefinition.new([damage_program], [])); damage_vm.start_program(damage_program.id, ScenarioExecutionContext.calling(&"monster-death-macro").set_battle(battle.id).set_combatant(source.id)); var damage_result := damage_vm.run(api); var damage_events := damage_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")
	assert_equal([damage_result.state, spawned.current_health, field.actors.has_actor(spawned.id), damage_events.size(), damage_events[0].payload.get("damage") if not damage_events.is_empty() else 0, state.combat.turns.active_actor_id(), hero.spell_points, _event_has(damage_result.events, &"classic_control_marker")], [ScenarioVmResult.State.COMPLETED, -32, false, 1, 40, hero.id, 0, true], "a damaging opcode-17 death-macro area uses the retained source geometry, removes its defeated target, spends no active-character resources, and continues the issuing program")


func _test_public_classic_combat_mutation(content: RealmzContent) -> void:
	var macro_definition := MonsterDefinition.new("monster.opcode125.macro", 1, "Related", 1, 0, 1, 0, 0, [], [], [], [], [], [], [], [], 77); macro_definition.death_macro = 901; macro_definition.can_summon = -1; var plain_definition := MonsterDefinition.new("monster.opcode125.plain", 2, "Related", 1, 0, 1, 0, 0, [], [], [], [], [], [], [], [], 77); plain_definition.can_summon = -1; var other_definition := MonsterDefinition.new("monster.opcode125.other", 3, "Other", 1, 0, 1, 0, 0, [], [], [], [], [], [], [], [], 88); other_definition.can_summon = -1; var root := ScenarioProgramDefinition.new("xap:900", &"extra-action-point", "900", [ClassicActionDefinition.new(0, 125, 125, 0, false, [77, 2, 0, 0, 0]), ClassicActionDefinition.new(1, 125, 125, 0, false, [77, 1, 0, 0, 0]), ClassicActionDefinition.new(2, 125, 125, 0, false, [88, 0, 0, 0, 0]), ClassicActionDefinition.new(3, 84, 84, 125, false, [])]); var death := ScenarioProgramDefinition.new("xap:901", &"extra-action-point", "901", [ClassicActionDefinition.new(0, 1, 1, 1, false, []), ClassicActionDefinition.new(1, 119, 119, 0, false, [])]); var battle := BattleDefinition.new("battle.opcode125", 1250, []); var mutation_content := RealmzContent.new("opcode125", "1".repeat(64), "opcode125", content.rules_version, content.start_map_id, content.start_coordinate, content.world, ScenarioDefinition.new([root, death], []), [MessageDefinition.new(1, "Death macro")], [], [], [], [], [], [], [macro_definition, plain_definition, other_definition], [battle]); var hero := CharacterState.new("opcode125.hero", "Hero", 20, 20); var first := MonsterState.new("opcode125.first", macro_definition.id, macro_definition.name, 10, 10, 1, 1, 0, 0, 0, true); var second := MonsterState.new("opcode125.second", plain_definition.id, plain_definition.name, 10, 10, 1, 1, 0, 0, 0, true); var third := MonsterState.new("opcode125.third", plain_definition.id, plain_definition.name, 10, 10, 1, 1, 0, 0, 0, true); var loyal := MonsterState.new("opcode125.loyal", plain_definition.id, plain_definition.name, 10, 10, 1, 1, 0, 0, 0, false); var other := MonsterState.new("opcode125.other", other_definition.id, other_definition.name, 10, 10, 1, 1, 0, 0, 0, true); var tiles: Array[int] = []; tiles.resize(BattlefieldGrid.CELL_COUNT); tiles.fill(0); var field := BattlefieldState.new(content.start_map_id, tiles); field.actors.place_character(hero.id, Vector2i(45, 45)); field.actors.place_monster(first.id, Vector2i(46, 45), 0); field.actors.place_monster(second.id, Vector2i(47, 45), 0); field.actors.place_monster(third.id, Vector2i(48, 45), 0); field.actors.place_monster(loyal.id, Vector2i(49, 45), 0); field.actors.place_monster(other.id, Vector2i(50, 45), 0); var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [hero]), RealmzClock.new()); state.combat = CombatState.new(battle.id, [first, second, third, loyal, other], -1, field); state.combat.set_turn_order([hero.id, first.id, second.id, third.id, loyal.id, other.id]); var rng := RealmzRng.for_oracle(125); var api := RealmzRuntimeApi.new(mutation_content, state, rng, ScenarioActionState.new()); var vm := ScenarioVm.new(); vm.configure(mutation_content.scenario); vm.start_program(root.id, ScenarioExecutionContext.calling(&"battle-macro").set_battle(battle.id)); var waiting := vm.run(api); var saved_state := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data()))); var saved_vm := ScenarioVmSnapshot.from_data(JSON.parse_string(JSON.stringify(vm.snapshot().to_data()))); var restored_vm := ScenarioVm.new(); restored_vm.configure(mutation_content.scenario); assert_true(waiting.state == ScenarioVmResult.State.WAITING and waiting.interaction.kind == InteractionRequest.ACKNOWLEDGE and saved_state != null and saved_vm != null and restored_vm.restore(saved_vm) and saved_vm.pending_continuation.runtime.kind == ScenarioRuntimeContinuation.CLASSIC_OPCODE_DEATH_MACRO and rng.snapshot().draw_count == 0, "opcode 125 kills the first bounded stable-order matches and saves its ordinary death-macro continuation without RNG")
	var restored_api := RealmzRuntimeApi.new(mutation_content, saved_state, rng, ScenarioActionState.new()); var completed := restored_vm.resume(InteractionResponse.acknowledge(waiting.interaction), restored_api); var draws_before_reward := rng.snapshot().draw_count; var reward := restored_api.begin_completed_battle_reward("opcode125.reward", ScenarioBattleCaller.classic(2, false, 0, 0)); assert_equal([completed.state, saved_state.combat.completed, saved_state.combat.outcome, saved_state.combat.roster.monster_by_id(first.id).current_health, saved_state.combat.roster.monster_by_id(first.id).traitor, saved_state.combat.roster.monster_by_id(second.id).current_health, saved_state.combat.roster.monster_by_id(third.id).current_health, saved_state.combat.roster.monster_by_id(loyal.id).current_health, saved_state.combat.roster.monster_by_id(other.id).current_health, _event_has(completed.events, &"monster_death_macro_completed"), _event_has(completed.events, &"battle_completed"), _event_has(completed.events, &"classic_control_marker"), reward.state != ScenarioRuntimeOperationResult.State.FAILED, draws_before_reward], [ScenarioVmResult.State.COMPLETED, true, &"victory", 1, false, 0, 0, 10, 0, true, true, true, true, 0], "opcode 125 resumes the macro, preserves loyal filtering and zero-to-100 limits, uses Classic name identity, reaches ordinary terminal victory and rewards, and adds no opcode randomness")


func _test_opcode_127_roster_presence(content: RealmzContent) -> void:
	var definition := content.combat.monster_by_id(content.combat.battle_by_id("classic.battle.0").monster_slots()[0].monster_id)
	var prepared := _package_macro_battle(content, definition.classic_id)
	var api := RealmzRuntimeApi.new(content, prepared.state, RealmzRng.for_oracle(127), ScenarioActionState.new())
	var present := api.execute_classic(ClassicActionDefinition.new(0, 127, 127, definition.classic_id, false, []), "battle.presence")
	var absent := api.execute_classic(ClassicActionDefinition.new(0, 127, 127, 441, false, []), "battle.presence")
	assert_equal([present.state, present.value, absent.state, absent.value, absent.directive.kind, absent.events[0].payload.get("classicMonsterId"), absent.events[0].payload.get("present")], [ScenarioRuntimeOperationResult.State.COMPLETED, true, ScenarioRuntimeOperationResult.State.COMPLETED, false, ScenarioVmDirective.FINISH, 441, false], "opcode 127 checks the active roster by Classic identity; an absent source definition is a false test, not a VM failure")


func _test_public_vm_repeated_combat_item(content: RealmzContent) -> void:
	var base_battle := content.combat.battle_by_id("classic.battle.0"); var races := content.characters.race_definitions(); var castes := content.characters.caste_definitions()
	assert_true(base_battle != null and not races.is_empty() and not castes.is_empty(), "VM repeated-item fixture has battle and character definitions"); if base_battle == null or races.is_empty() or castes.is_empty(): return
	var selected_race: RaceDefinition = null; var selected_caste: CasteDefinition = null; var usable_low := 0; var usable_high := 0; var flask_spell := content.magic.spell_by_classic_id(4409)
	for race: RaceDefinition in races:
		for caste: CasteDefinition in castes:
			if not race.eligible_caste_ids.is_empty() and not race.eligible_caste_ids.has(caste.id): continue
			if not caste.eligible_race_ids.is_empty() and not caste.eligible_race_ids.has(race.id): continue
			var shared_low := race.item_category_mask_low & caste.item_category_mask_low; var shared_high := race.item_category_mask_high & caste.item_category_mask_high
			if shared_low != 0 or shared_high != 0:
				selected_race = race; selected_caste = caste; usable_low = shared_low; usable_high = shared_high
				break
		if selected_race != null: break
	assert_true(selected_race != null and selected_caste != null, "VM repeated-item fixture has a race/caste pair with a shared Classic item category"); assert_not_null(flask_spell, "VM item fixture has AOGM's exact application-owned Flask of Oil spell"); if selected_race == null or selected_caste == null or flask_spell == null: return
	var spell: SpellDefinition = null
	for candidate_spell: SpellDefinition in content.magic.definitions():
		if candidate_spell.target_type == 0 and candidate_spell.size == 0 and ClassicSpellDispositionRules.combat_item_disposition(candidate_spell) == ClassicSpellDispositionRules.DISPOSITION_EXECUTABLE:
			spell = candidate_spell; break
	assert_not_null(spell, "VM repeated-item fixture has a stock executable repeated-target spell"); if spell == null: return
	var item := ItemDefinition.new("item.vm-repeated-wand", 991, "Wild Forked Wand"); item.item_type = 21; item.initial_charges = 2; item.item_category_mask_low = usable_low; item.item_category_mask_high = usable_high; item.special_1 = 8; item.special_2 = spell.classic_id; var flask := ItemDefinition.new("classic.item.881", 881, "Flask of Oil"); flask.item_type = 15; flask.initial_charges = 5; flask.item_category_mask_low = usable_low; flask.item_category_mask_high = usable_high; flask.special_1 = -1; flask.special_2 = flask_spell.classic_id
	var monster_definitions: Array[MonsterDefinition] = []; var monster_ids: Dictionary = {}
	for slot: BattleMonsterSlotDefinition in base_battle.monster_slots():
		var definition := content.combat.monster_by_id(slot.monster_id)
		if definition != null and not monster_ids.has(definition.id):
			monster_ids[definition.id] = true; monster_definitions.append(definition)
	var battle := BattleDefinition.new("classic.battle.vm-repeated-item", 991, base_battle.monster_slots()); var battle_action := ClassicActionDefinition.new(0, 2, 2, battle.classic_id, false, [battle.classic_id, 0, 0, 0, 0])
	var program := ScenarioProgramDefinition.new("fixture.vm-repeated-item", &"application-hook", "start-game", [battle_action]); var scenario := ScenarioDefinition.new([program], [], ScenarioApplicationHooks.new(program.id, "", "", "", ""))
	var item_definitions := content.items.definitions(); item_definitions.append(item); item_definitions.append(flask); var spell_definitions := content.magic.definitions()
	var fixture := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, scenario, [], [], [], races, castes, item_definitions, spell_definitions, monster_definitions, [battle])
	var session: GameSession = null; var active_id := ""
	for seed: int in range(1, 33):
		var candidate := GameSession.new(); candidate.start(fixture, seed)
		var caster := CharacterState.new("fixture.vm-item.caster", "VM Item Caster", 30, 30); caster.race_id = selected_race.id; caster.caste_id = selected_caste.id; caster.normal_attacks = 4; caster.maximum_movement = 12; caster.movement = 12; caster.maximum_spell_points = 17; caster.spell_points = 17; caster.set_inventory([ItemInstance.new("instance.vm-repeated-wand.caster", item.id, 2, false, true), ItemInstance.new("instance.flask-oil.caster", flask.id, 5, false, true)])
		var ally := CharacterState.new("fixture.vm-item.ally", "VM Item Ally", 30, 30); ally.race_id = selected_race.id; ally.caste_id = selected_caste.id; ally.normal_attacks = 4; ally.maximum_movement = 12; ally.movement = 12; ally.maximum_spell_points = 17; ally.spell_points = 17; ally.set_inventory([ItemInstance.new("instance.vm-repeated-wand.ally", item.id, 2, false, true), ItemInstance.new("instance.flask-oil.ally", flask.id, 5, false, true)])
		var caster_import := candidate.submit_intent(PartyIntents.import_vault_character(caster.id, "1".repeat(64), caster, "fixture", fixture.package_hash)); if caster_import.state != SessionStep.State.COMPLETED: continue
		var ally_import := candidate.submit_intent(PartyIntents.import_vault_character(ally.id, "2".repeat(64), ally, "fixture", fixture.package_hash)); if ally_import.state != SessionStep.State.COMPLETED: continue
		var entered := candidate.submit_intent(PartyIntents.begin_adventure())
		if entered.state == SessionStep.State.WAITING_FOR_INTERACTION and entered.interaction != null and entered.interaction.kind == InteractionRequest.COMBAT:
			var combat_body := entered.interaction.body as CombatRequestBody
			if combat_body != null and combat_body.item_casts.any(func(cast: InteractionRequestValue.CastOption) -> bool: return cast.item_id == item.id):
				session = candidate; active_id = combat_body.actor_id; break
	assert_not_null(session, "VM repeated-item fixture reaches the caster's public combat request"); if session == null: return
	var request_before_restore := session.view().pending_interaction; var rng_before_restore := session.snapshot().rng_state.to_data(); var debug_restore_step := session.apply_debug_command(SessionDebugCommand.restore_party()); var request := session.view().pending_interaction; assert_equal([debug_restore_step.state, debug_restore_step.events.map(func(event: DomainEvent) -> StringName: return event.kind), request.request_id, session.snapshot().rng_state.to_data()], [SessionStep.State.COMPLETED, [&"debug_party_restored"], request_before_restore.request_id, rng_before_restore], "party restoration commits without consuming RNG or replacing the active scenario combat request"); var request_body := request.body as CombatRequestBody
	assert_true(request_body != null and request_body.item_casts.any(func(cast: InteractionRequestValue.CastOption) -> bool: return cast.item_id == item.id) and request_body.item_casts.any(func(cast: InteractionRequestValue.CastOption) -> bool: return cast.item_id == flask.id), "VM combat request exposes both the random-power item and AOGM Flask of Oil"); if request_body == null or request_body.item_casts.is_empty(): return
	var character_records := request_body.combatants.filter(func(combatant: InteractionRequestValue.Combatant) -> bool: return combatant.kind == &"character")
	var monster_records := request_body.combatants.filter(func(combatant: InteractionRequestValue.Combatant) -> bool: return combatant.kind == &"monster")
	assert_true(character_records.all(func(combatant: InteractionRequestValue.Combatant) -> bool: return combatant.items.any(func(row: String) -> bool: return row.contains("Wild Forked Wand")) and not combatant.attack_rows.is_empty()) and monster_records.all(func(combatant: InteractionRequestValue.Combatant) -> bool: return not combatant.attack_rows.is_empty()), "public combat inspection records carry player-visible inventory and authoritative attack rows for every battlefield side")
	var option: InteractionRequestValue.CastOption = null
	for cast: InteractionRequestValue.CastOption in request_body.item_casts:
		if cast.item_id == item.id: option = cast; break
	assert_not_null(option, "VM combat request retains the random charged-item identity"); if option == null: return
	assert_equal([option.target_mode, option.power, option.power_staged, option.target_candidates.size()], [&"random_power", 0, false, 0], "VM request requires the source power roll before exposing item targets"); var stage_body := InteractionResponse.CombatBody.new(&"use_item", active_id); stage_body.item_instance_id = option.item_instance_id; var staged_step := session.respond(InteractionResponse.from_data(request.request_id, InteractionRequest.COMBAT, stage_body.to_data())); var staged_event: DomainEvent = staged_step.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_item_power_staged")[0] if staged_step.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_item_power_staged") else null; var staged_request := session.view().pending_interaction; var staged_body := staged_request.body as CombatRequestBody; var staged_option: InteractionRequestValue.CastOption = staged_body.item_casts[0] if staged_body != null and not staged_body.item_casts.is_empty() else null; assert_true(staged_step.state == SessionStep.State.WAITING_FOR_INTERACTION and staged_event != null and staged_option != null, "VM response rolls power and rerenders the combat item target boundary"); if staged_event == null or staged_option == null: return
	var candidate_ids := staged_option.target_candidates.map(func(target: InteractionRequestValue.CombatTarget) -> String: return target.id); var monster_targets := staged_option.target_candidates.filter(func(target: InteractionRequestValue.CombatTarget) -> bool: return target.kind == &"monster"); var monster_target_id: String = "" if monster_targets.is_empty() else monster_targets[0].id; var party_target_id := "fixture.vm-item.ally" if active_id == "fixture.vm-item.caster" else "fixture.vm-item.caster"
	assert_equal([staged_option.target_mode, staged_option.power, staged_option.power_staged, staged_option.maximum_targets, candidate_ids.has(party_target_id), not monster_target_id.is_empty()], [&"sequence", int(staged_event.payload.get("power")), true, int(staged_event.payload.get("power")), true, true], "the rerendered VM request preserves the rolled power and rules-owned actor candidates"); var saved := save_round_trip(session.snapshot()); assert_not_null(saved, "the staged random-power target boundary is saveable before selection"); if saved == null or monster_target_id.is_empty(): return
	var forged := save_round_trip(saved); forged.game_state.combat.turns.active_turn.staged_item_power = 1 if staged_option.power != 1 else 2; assert_false(SessionRestoreValidator.validate(fixture, forged).ok, "restore rejects a staged power that no longer matches its authoritative VM target request"); var restored := GameSession.new(); var restore_step := restored.restore(fixture, saved); assert_equal(restore_step.state, SessionStep.State.COMPLETED, "the VM random-power combat request restores transactionally (%s)" % restore_step.error_message); if restore_step.state != SessionStep.State.COMPLETED: return
	var restored_request := restored.view().pending_interaction; var restored_body := restored_request.body as CombatRequestBody; var restored_option: InteractionRequestValue.CastOption = restored_body.item_casts[0] if restored_body != null and not restored_body.item_casts.is_empty() else null; assert_true(restored_option != null and restored_option.power == staged_option.power and restored_option.power_staged, "restore retains the authoritative rolled power in the typed VM request"); var response_body := InteractionResponse.CombatBody.new(&"use_item", active_id); response_body.item_instance_id = option.item_instance_id; response_body.target_ids.assign([monster_target_id])
	var committed := restored.respond(InteractionResponse.from_data(restored_request.request_id, InteractionRequest.COMBAT, response_body.to_data())); var resolved_events := committed.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved"); var restored_caster := restored.snapshot().game_state.party.character_by_id(active_id); assert_equal([committed.error_code, resolved_events.map(func(event: DomainEvent) -> String: return String(event.payload.get("selectedTargetId"))), restored_caster.inventory()[0].charges, restored_caster.spell_points], [&"", [monster_target_id], 1, 17], "the restored VM response commits the staged power, selected actor, one charge, and no caster spell points"); var flask_request := restored.view().pending_interaction; var flask_body := flask_request.body as CombatRequestBody; var flask_casts := flask_body.item_casts.filter(func(cast: InteractionRequestValue.CastOption) -> bool: return cast.item_id == flask.id) if flask_body != null else []; var flask_option: InteractionRequestValue.CastOption = null if flask_casts.is_empty() else flask_casts[0]; assert_not_null(flask_option, "the VM rerender keeps AOGM Flask of Oil available after another item cast"); if flask_option == null: return; var flask_monsters := flask_option.target_candidates.filter(func(target: InteractionRequestValue.CombatTarget) -> bool: return target.kind == &"monster"); if flask_monsters.is_empty(): return; var flask_target: InteractionRequestValue.CombatTarget = flask_monsters[0]; var flask_target_before := restored._context.state.combat.roster.monster_by_id(flask_target.id).current_health; var flask_response := InteractionResponse.CombatBody.new(&"use_item", active_id); flask_response.item_instance_id = flask_option.item_instance_id; flask_response.target_ids.assign([flask_target.id]); var flask_committed := restored.respond(InteractionResponse.from_data(flask_request.request_id, InteractionRequest.COMBAT, flask_response.to_data())); var flask_events := flask_committed.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved" and event.payload.get("spellId") == flask_spell.id); var flask_after := restored.snapshot().game_state; var flask_caster := flask_after.party.character_by_id(active_id); assert_equal([flask_committed.error_code, flask_events.size(), flask_caster.inventory()[1].charges, flask_caster.spell_points, flask_after.combat.roster.monster_by_id(flask_target.id).current_health], [&"", 1, 4, 17, flask_target_before - int(flask_events[0].payload.get("damage"))], "AOGM Flask of Oil resolves through the VM item request, spends one charge and no spell points, and commits its exact projectile damage"); var debug_victory := restored.apply_debug_command(SessionDebugCommand.win_battle()); var debug_view := restored.view(); assert_true(debug_victory.state != SessionStep.State.FAILED and debug_victory.events.any(func(event: DomainEvent) -> bool: return event.kind == &"battle_completed" and event.payload.get("outcome") == "victory") and (debug_view.pending_interaction == null or debug_view.pending_interaction.kind != InteractionRequest.COMBAT), "debug victory completes a scenario-owned combat request through its ordinary VM reward and return continuation")


func _test_public_continuation_matrix(content: RealmzContent) -> void:
	var age_source := GameSession.new()
	age_source.start(content, 1)
	_begin_fixture_adventure(age_source, content)
	_restore_fixture_position(age_source, content, "land:1", Vector2i(0, 1))
	var age_boundary := age_source.snapshot()
	var character := age_boundary.game_state.party.characters()[0]
	var race := _aging_race(content)
	if race == null:
		assert_true(false, "fixture provides an age-transition race")
		return
	character.race_id = race.id
	character.age_group = 1
	character.age_days = race.age_range(1).x * 365 - 1
	age_boundary.game_state.clock.advance_minutes(RealmzClock.MINUTES_PER_DAY - 1 - age_boundary.game_state.clock.total_minutes())
	var aged := GameSession.new()
	assert_equal(aged.restore(content, age_boundary).state, SessionStep.State.COMPLETED, "age boundary restores through public validation")
	var moved := aged.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	assert_equal(moved.interaction.kind, InteractionRequest.AGE_UPDATE, "age update yields before destination AP work")
	var held := save_round_trip(aged.snapshot())
	assert_not_null(held, "nested age and post-move continuation is saveable")
	if held != null:
		var resumed := GameSession.new()
		assert_equal(resumed.restore(content, held).state, SessionStep.State.COMPLETED, "nested continuation restores")
		var encounter := resumed.respond(InteractionResponse.age_update(resumed.view().pending_interaction))
		assert_equal(encounter.interaction.kind, InteractionRequest.ENCOUNTER_CHOICE, "age acknowledgement resumes destination trigger discovery")
	var transfer_definition := ScenarioDefinition.new([
		ScenarioProgramDefinition.new("root", &"trigger", "root", [ClassicActionDefinition.new(0, 39, 39, 13, false, [])]),
		ScenarioProgramDefinition.new("xap:13", &"extra-action-point", "13", [ClassicActionDefinition.new(0, 3, 3, 68, false, [0, 1, 17, 0, 0])]),
		ScenarioProgramDefinition.new("xap:17", &"extra-action-point", "17", [ClassicActionDefinition.new(0, 25, 25, 0, false, []), ClassicActionDefinition.new(1, 84, 84, 0, false, [])]),
	], [])
	var transfer_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("context", "Context", 1, 1)]), RealmzClock.new()); var transfer_vm := ScenarioVm.new()
	transfer_vm.configure(transfer_definition); transfer_vm.start_program("root", ScenarioExecutionContext.trigger(&"action", "ap.fixture.message", content.start_map_id))
	var transfer_api := RealmzRuntimeApi.new(content, transfer_state, RealmzRng.new(1), ScenarioActionState.new()); var transfer_choice := transfer_vm.run(transfer_api)
	var transferred := transfer_vm.resume(InteractionResponse.yes_no(transfer_choice.interaction, true), transfer_api)
	assert_equal([transfer_choice.state, transferred.state], [ScenarioVmResult.State.WAITING, ScenarioVmResult.State.COMPLETED], "opcode 39 and a resumed Choice reach the selected XAP")
	var source_less_vm := ScenarioVm.new(); source_less_vm.configure(transfer_definition); source_less_vm.start_program("xap:17"); var source_less := source_less_vm.run(RealmzRuntimeApi.new(content, transfer_state, RealmzRng.new(2), ScenarioActionState.new())); assert_true(transfer_state.world.triggers.trigger_is_disabled("ap.fixture.message") and not _event_has(transferred.events, &"classic_control_marker") and source_less.state == ScenarioVmResult.State.COMPLETED and not _event_has(source_less.events, &"trigger_disabled"), "opcode 25 retains the issuing AP origin through a transferred Choice, while a source-less XAP ends cleanly without inventing an AP removal")


func _test_public_limits_and_errors(content: RealmzContent) -> void:
	var recursive_action := ClassicActionDefinition.new(0, -4, 4, 0, true, [])
	var recursive_definition := ScenarioDefinition.new([
		ScenarioProgramDefinition.new("root", &"trigger", "root", [recursive_action]),
		ScenarioProgramDefinition.new("recursive", &"simple-encounter-result", "0", [recursive_action]),
	], [])
	var recursive_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, recursive_definition, [MessageDefinition.new(1, "Continue?")], [], [SimpleEncounterDefinition.new(0, 1, [SimpleEncounterResponse.new("continue", "Continue", "recursive")], false, 0, 0)])
	var classic_vm := ScenarioVm.new()
	classic_vm.configure(recursive_definition)
	classic_vm.start_program("root", ScenarioExecutionContext.calling(&"action"))
	var classic_result := classic_vm.run(_runtime_api(recursive_content, ScenarioActionState.new()))
	for _index: int in range(21):
		if classic_result.state != ScenarioVmResult.State.WAITING:
			break
		classic_result = classic_vm.resume(InteractionResponse.from_data(classic_result.interaction.request_id, &"encounter_choice", {"index": 0}), _runtime_api(recursive_content, ScenarioActionState.new()))
	assert_equal(classic_result.error_code, &"classic_gosub_limit", "Classic GOSUB depth fails explicitly at its public VM boundary")
	var safe_call := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.CALL_ACTION)
	safe_call.action_id = "scenario.test.recurse"
	var safe_action := _action(safe_call.action_id, &"void", [safe_call])
	var safe_definition := ScenarioDefinition.new([ScenarioProgramDefinition.new("root", &"trigger", "root", [CallScenarioActionInstruction.new(safe_action.id)])], [safe_action])
	var safe_vm := ScenarioVm.new()
	safe_vm.configure(safe_definition)
	safe_vm.start_program("root", ScenarioExecutionContext.calling(&"action"))
	assert_equal(safe_vm.run(_runtime_api(content, ScenarioActionState.new())).error_code, &"scenario_action_call_limit", "Safe Action depth fails explicitly")
	assert_equal(ScenarioVm.EXECUTION_STEP_LIMIT, 65536, "Scenario VM execution budget remains explicit")
	var jump := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.JUMP)
	jump.target = 0
	var loop_action := _action("scenario.test.loop", &"void", [jump])
	var loop_definition := ScenarioDefinition.new([ScenarioProgramDefinition.new("root", &"trigger", "root", [CallScenarioActionInstruction.new(loop_action.id)])], [loop_action])
	var loop_vm := ScenarioVm.new()
	loop_vm.configure(loop_definition, 64)
	loop_vm.start_program("root", ScenarioExecutionContext.calling(&"action"))
	assert_equal(loop_vm.run(_runtime_api(content, ScenarioActionState.new())).error_code, &"scenario_step_limit", "bounded Safe Action execution fails explicitly")
	var unknown := ScenarioDefinition.new([ScenarioProgramDefinition.new("root", &"trigger", "root", [ClassicActionDefinition.new(0, 999, 999, 0, false, [])])], []); var unknown_vm := ScenarioVm.new()
	unknown_vm.configure(unknown); unknown_vm.start_program("root", ScenarioExecutionContext.calling(&"action"))
	assert_equal(unknown_vm.run(_runtime_api(content, ScenarioActionState.new())).error_code, &"unsupported_classic_opcode", "unknown opcodes never fall through to dynamic GDScript")


func _test_public_shop_money(content: RealmzContent) -> void:
	var shopper := CharacterState.new("shop.money", "Shopper", 10, 10); shopper.race_id = content.characters.race_definitions()[0].id; shopper.caste_id = content.characters.caste_definitions()[0].id; shopper.money = WealthState.new(15, 2, 1); shopper.maximum_load = 10000; var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [shopper]), RealmzClock.new()); state.party.pooled_wealth = WealthState.new(115, 1, 0); var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(11), ScenarioActionState.new()); assert_equal(api.execute_classic(ClassicActionDefinition.new(0, 6, 6, 0, false, []), "shop.money.offer").state, ScenarioRuntimeOperationResult.State.COMPLETED, "shop is configured before its money interaction"); var opened := api.request_available_shop("shop.money.open"); var invalid := api.resume_classic(opened.continuation, InteractionResponse.new(opened.interaction.request_id, InteractionRequest.SHOP, InteractionResponse.ShopBody.new(&"to-character", shopper.id, "", "", "gold", 1)), "shop.money.invalid"); assert_equal([invalid.error_code, state.party.pooled_wealth.gold, shopper.money.gold], [&"invalid_money_increment", 115, 15], "forged Shop Swap amount fails before mutation"); var pooled := api.resume_classic(opened.continuation, InteractionResponse.new(opened.interaction.request_id, InteractionRequest.SHOP, InteractionResponse.ShopBody.new(&"pool")), "shop.money.pool"); assert_equal([pooled.state, state.party.pooled_wealth.to_data(), shopper.money.to_data(), pooled.events[0].kind], [ScenarioRuntimeOperationResult.State.WAITING, {"gold": 130, "gems": 3, "jewelry": 1}, {"gold": 0, "gems": 0, "jewelry": 0}, &"wealth_pooled"], "Shop Pool moves every denomination and reopens the same Shop"); var transfer_wire := {"action": "to-character", "characterId": shopper.id, "denomination": "gold", "amount": 5}; var transfer := api.resume_classic(pooled.continuation, InteractionResponse.from_data(pooled.interaction.request_id, InteractionRequest.SHOP, transfer_wire), "shop.money.swap"); assert_equal([transfer.state, state.party.pooled_wealth.gold, shopper.money.gold, transfer.events[0].kind], [ScenarioRuntimeOperationResult.State.WAITING, 125, 5, &"wealth_transferred"], "Shop Money Swap decodes its typed transfer and preserves Shop continuation"); var changed := api.resume_classic(transfer.continuation, InteractionResponse.new(transfer.interaction.request_id, InteractionRequest.SHOP, InteractionResponse.ShopBody.new(MoneyChangingRules.GOLD_TO_GEMS, "", "", "", "gold", 115)), "shop.money.change"); assert_equal([changed.state, state.party.pooled_wealth.gold, state.party.pooled_wealth.gems, changed.events[0].kind], [ScenarioRuntimeOperationResult.State.WAITING, 10, 4, &"wealth_changed"], "Shop Money Changing uses the exact Castle rate inside the Shop"); var shared := api.resume_classic(changed.continuation, InteractionResponse.new(changed.interaction.request_id, InteractionRequest.SHOP, InteractionResponse.ShopBody.new(&"share")), "shop.money.share"); assert_equal([shared.state, state.party.pooled_wealth.to_data(), shopper.money.to_data(), shared.events[0].kind], [ScenarioRuntimeOperationResult.State.WAITING, {"gold": 0, "gems": 0, "jewelry": 0}, {"gold": 15, "gems": 4, "jewelry": 1}, &"wealth_shared"], "Shop Share returns pooled wealth in Castle denomination order without leaving Shop")


func _test_public_application_transitions(content: RealmzContent) -> void:
	var shopper := CharacterState.new("shopper", "Shopper", 10, 10); shopper.portrait_id = "portrait.fixture"; var party := PartyState.new(content.start_map_id, content.start_coordinate, [shopper]); var state := GameState.new(party, RealmzClock.new()); var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var map := content.world.player_map_by_classic_id(1); var shop := content.economy.shop_by_id("classic.shop.0"); var shop_offer := api.execute_classic(ClassicActionDefinition.new(0, 6, 6, 0, false, []), "shop.offer"); var shop_result := api.request_available_shop("shop.open"); var shop_data := shop_result.interaction.body.to_data(); var unpaid := api.execute_classic(ClassicActionDefinition.new(0, 33, 33, 0, true, [5000, 0, 0, 7, 0]), "wealth.unpaid"); assert_equal([shop_offer.state, state.location_services.active_shop_id, shop_offer.events[0].kind, shop_offer.events[1].kind, shop_offer.events[1].payload.get("soundId"), shop_offer.events[1].payload.get("stopExisting"), shop_result.state, shop_data["stock"][0]["stockKey"], shop_data["stock"][0]["index"], shop_data["stock"][0]["category"], shop_data["stock"][0].has("description"), shop_data["characters"][0]["portraitId"], shop_data["characters"][0]["load"], unpaid.value, unpaid.events[1].payload, unpaid.directive.kind, unpaid.directive.target_id, unpaid.directive.gosub], [ScenarioRuntimeOperationResult.State.COMPLETED, shop.id, &"shop_available", &"sound_requested", 30005, true, ScenarioRuntimeOperationResult.State.WAITING, "base:817", 817, "supplies", true, shopper.portrait_id, 0, false, {"text": "The party does not have enough gold.", "soundId": 6000, "source": "classic-opcode-33"}, ScenarioVmDirective.BRANCH_XAP, 7, false], "Shop exposes its contextual source cue after silencing competing movement audio and sparse stock facts while failed opcode 33 requests Castle warning 50 with sound 6000 before its authored non-GOSUB XAP branch"); var first_stock := content.items.item_by_id(shop.item_ids()[0]); var saved_icon_id := first_stock.icon_id; first_stock.icon_id = 0; var iconless_shop := api.request_available_shop("shop.iconless"); first_stock.icon_id = saved_icon_id; assert_true(iconless_shop.state == ScenarioRuntimeOperationResult.State.WAITING and not iconless_shop.interaction.body.to_data()["stock"][0].has("iconId"), "a source-valid shop item without a CICN remains an actionable typed row instead of collapsing the interaction")
	var original_quantity := state.location_services.shop_quantity(shop, 0); var absent_mutation := api.execute_classic(ClassicActionDefinition.new(0, 51, 51, 0, false, [shop.classic_id, 2, 9999, 5, 0]), "shop.mutate.absent"); var stocked_mutation := api.execute_classic(ClassicActionDefinition.new(0, 51, 51, 0, false, [shop.classic_id, 0, first_stock.classic_id, 1, 0]), "shop.mutate.stocked")
	assert_equal([absent_mutation.state, absent_mutation.events[0].payload.get("stockIndex"), state.location_services.shop_inflation(shop), stocked_mutation.state, state.location_services.shop_quantity(shop, 0)], [ScenarioRuntimeOperationResult.State.COMPLETED, -1, shop.inflation_percent + 2, ScenarioRuntimeOperationResult.State.COMPLETED, original_quantity + 1], "opcode 51 applies inflation and ignores an unstocked item, then mutates matching native stock without failing the AP")
	var sold_item := content.items.item_by_classic_id(1); shopper.set_inventory([ItemInstance.new("shop.sold", sold_item.id, sold_item.initial_charges, false, true)]); var sold := api.resume_classic(shop_result.continuation, InteractionResponse.new(shop_result.interaction.request_id, InteractionRequest.SHOP, InteractionResponse.ShopBody.new(&"sell", shopper.id, "shop.sold")), "shop.sell"); var sold_data := sold.interaction.body.to_data(); var restored_shop_state := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data()))); restored_shop_state.party.character_by_id(shopper.id).portrait_id = ""; var valid_shop_snapshot := SessionSnapshot.new(content.campaign_id, content.package_hash, content.rules_version, 1, restored_shop_state, RealmzRng.new(2).snapshot()); var forged_shop_data := state.to_data(); forged_shop_data["shopBuybackSlots"][shop.id][sold_item.id] = 817; var forged_shop_state := GameState.from_data(forged_shop_data); forged_shop_state.party.character_by_id(shopper.id).portrait_id = ""; var forged_shop_snapshot := SessionSnapshot.new(content.campaign_id, content.package_hash, content.rules_version, 1, forged_shop_state, RealmzRng.new(2).snapshot()); assert_equal([sold.state, sold_data["stock"][0]["stockKey"], sold_data["stock"][0]["index"], sold_data["stock"][1]["stockKey"], state.location_services.shop_buyback_slot(shop.id, sold_item.id), restored_shop_state.location_services.shop_buyback_slot(shop.id, sold_item.id), shop.stock_slot(0), SessionRestoreValidator.validate(content, valid_shop_snapshot).ok, SessionRestoreValidator.validate(content, forged_shop_snapshot).ok], [ScenarioRuntimeOperationResult.State.WAITING, "buyback:%s" % sold_item.id, 0, "base:817", 0, 0, 817, true, false], "selling uses Castle's first empty slot in the item's native 200-slot band, projects in slot order, persists the assignment, rejects a colliding restored slot, and leaves package stock immutable")
	var outside_item := content.items.item_by_classic_id(206); shopper.set_inventory([ItemInstance.new("shop.inside", sold_item.id, sold_item.initial_charges, false, true), ItemInstance.new("shop.outside", outside_item.id, outside_item.initial_charges, false, true)]); var restricted_offer := api.execute_classic(ClassicActionDefinition.new(0, 73, 73, 0, false, [0, 1, 100, 0, 999]), "shop.restricted"); var restricted := api.request_available_shop("shop.restricted.open"); var restricted_inventory: Array = restricted.interaction.body.to_data()["characters"][0]["inventory"]
	assert_equal([restricted_offer.state, state.location_services.shop_accept_ranges(), restricted_inventory[0]["canSell"], restricted_inventory[0]["sellReason"], restricted_inventory[1]["canSell"], restricted_inventory[1]["sellReason"]], [ScenarioRuntimeOperationResult.State.COMPLETED, [1, 100, 0, 999], true, "", false, "This shop does not accept this item."], "opcode 73 treats one active authored acceptance range as a real restriction while retaining the disabled pair's unused high word")
	var union_offer := api.execute_classic(ClassicActionDefinition.new(0, 73, 73, 0, false, [0, 1, 1, 206, 206]), "shop.restricted.union"); var union_shop := api.request_available_shop("shop.restricted.union.open"); var union_inventory: Array = union_shop.interaction.body.to_data()["characters"][0]["inventory"]; assert_equal([union_offer.state, union_inventory[0]["canSell"], union_inventory[1]["canSell"]], [ScenarioRuntimeOperationResult.State.COMPLETED, true, true], "opcode 73 accepts the union of both active inclusive ranges through the public Shop request")
	assert_not_null(map, "fixture exposes a source-backed player map")
	if map == null: return
	var acquired := api.execute_classic(ClassicActionDefinition.new(0, 29, 29, 1, false, []), "map.acquire")
	assert_equal([acquired.state, state.world.exploration.has_map(map.id), acquired.events[0].payload.get("notificationText"), acquired.events[0].payload.get("notificationSoundId")], [ScenarioRuntimeOperationResult.State.COMPLETED, true, "You gain a map, to view the map use Maps/Notes in the Menu.", 30005], "positive opcode 29 acquires a stable player-map identity and preserves Castle's click notification contract")
	var shown := api.execute_classic(ClassicActionDefinition.new(0, 29, 29, -1, false, []), "map.show")
	assert_equal([shown.state, shown.interaction.kind, shown.interaction.body.to_data().get("playerMapId")], [ScenarioRuntimeOperationResult.State.WAITING, &"acknowledge", map.id], "negative opcode 29 stages the player-map presentation")
	var forged := api.resume_classic(shown.continuation, InteractionResponse.from_data(shown.interaction.request_id, &"acknowledge", {"accepted": true}), "map.forged")
	assert_equal(forged.error_code, &"invalid_interaction_response", "player-map acknowledgement rejects forged fields")
	var resumed := api.resume_classic(shown.continuation, InteractionResponse.acknowledge(shown.interaction), "map.resume")
	assert_equal(resumed.state, ScenarioRuntimeOperationResult.State.COMPLETED, "player-map acknowledgement resumes its issuing operation")
	var missing_party_marker: MediaAsset = null
	for asset: MediaAsset in content.media_assets:
		if asset.id == map.party_marker_asset_id:
			missing_party_marker = asset
			break
	assert_not_null(missing_party_marker, "fixture resolves the selected Player Map's exact party marker media")
	if missing_party_marker != null:
		content.media_assets.erase(missing_party_marker)
		var deferred_marker := api.execute_classic(ClassicActionDefinition.new(0, 29, 29, map.classic_id, false, []), "map.missing-marker")
		content.media_assets.append(missing_party_marker)
		assert_equal([deferred_marker.state, deferred_marker.error_code, deferred_marker.error_message], [ScenarioRuntimeOperationResult.State.FAILED, &"deferred_player_map_reference", "Classic opcode 29 Player Map %d requires unavailable party marker asset '%s'." % [map.classic_id, map.party_marker_asset_id]], "selected Player Map fails with its exact missing party marker before acquisition")
	var unavailable := api.execute_classic(ClassicActionDefinition.new(0, 29, 29, 19, false, []), "map.unknown"); assert_equal(unavailable.error_code, &"unknown_player_map", "unknown player-map identities fail explicitly"); var entered_dungeon := api.execute_classic(ClassicActionDefinition.new(0, 37, 37, 0, false, [0, 0, 0, 0, -2]), "dungeon.enter"); assert_equal([entered_dungeon.state, state.party.map_id, state.dungeon_heading, state.dungeon_multiview, entered_dungeon.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested")], [ScenarioRuntimeOperationResult.State.COMPLETED, "dungeon:0", 2, false, false], "opcode 37 treats signed Extra Code 4 as Castle heading and locked-view policy rather than a sound identity"); state.party.fatigue = 100; var exhausted := api.execute_classic(ClassicActionDefinition.new(0, 68, 68, 0, false, [1, 0, 0, 0, 0]), "fatigue.exhaust"); var rested := api.execute_classic(ClassicActionDefinition.new(0, 68, 68, 0, false, [2, 0, 0, 0, 0]), "fatigue.rest"); state.party.fatigue = 100; var fatigue := api.execute_classic(ClassicActionDefinition.new(0, 68, 68, 0, false, [3, 150, 0, 0, 0]), "fatigue.calculate"); var registration := api.execute_classic(ClassicActionDefinition.new(0, 84, 84, 0, false, [-1, -1, 0, 10105, 0]), "registration.scenario"); var heading_rng := ScriptedRng.new([0]); var heading_api := RealmzRuntimeApi.new(content, state, heading_rng, ScenarioActionState.new()); var fixed_heading := heading_api.execute_classic(ClassicActionDefinition.new(0, 95, 95, 1, false, []), "heading.fixed"); var random_heading := heading_api.execute_classic(ClassicActionDefinition.new(0, 95, 95, -1, false, []), "heading.random"); assert_equal([exhausted.value, rested.value, fatigue.value, state.party.fatigue, fatigue.events[0].payload, registration.state, registration.events[0].payload, fixed_heading.value, random_heading.value, heading_rng.snapshot().draw_count], [135, 4, 135, 135, {"previous": 100, "current": 135, "reason": "classic-opcode-68", "source": "classic"}, ScenarioRuntimeOperationResult.State.COMPLETED, {"opcode": 84, "operandId": 0}, 1, 1, 1], "opcodes 68, 84, and 95 preserve corrected fatigue, registration, fixed-heading, and one-draw random-heading paths")
	var land_map := content.world.map_by_id("land:0"); state.party.map_id = land_map.id; state.party.coordinate = Vector2i.ZERO; var open_teleport := api.execute_classic(ClassicActionDefinition.new(0, 20, 20, 0, false, [0, 3, 3, 0, 0]), "teleport.open"); var open_position := state.party.coordinate; var ap_teleport := api.execute_classic(ClassicActionDefinition.new(0, 20, 20, 0, false, [0, 1, 0, 0, 0]), "teleport.ap"); assert_equal([land_map.topology.cell_at(Vector2i(3, 3)).trigger_ids(), open_teleport.state, open_teleport.directive, _event_has(open_teleport.events, &"destination_trigger_recheck_requested"), open_position, land_map.topology.cell_at(Vector2i(1, 0)).trigger_ids().is_empty(), ap_teleport.directive.kind, _event_has(ap_teleport.events, &"destination_trigger_recheck_requested")], [[], ScenarioRuntimeOperationResult.State.COMPLETED, null, false, Vector2i(3, 3), false, ScenarioVmDirective.FINISH_TIMELINE, true], "opcode 20 continues the issuing timeline after an unmarked destination but replaces it with a bounded recheck when the destination carries a placed AP")


func _test_public_world_state_opcodes(content: RealmzContent) -> void:
	var state := GameState.new(PartyState.new("land:0", Vector2i(0, 1), [CharacterState.new("world.hero", "World Hero", 10, 10)]), RealmzClock.new()); state.last_move_direction = Vector2i.UP; var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new()); var faced := api.execute_classic(ClassicActionDefinition.new(0, 78, 78, 0, true, [7, 1, 0, 0, 0]), "world.forest"); var saved := api.execute_classic(ClassicActionDefinition.new(0, 70, 70, 0, false, [1, 0, 0, 0, 0]), "world.save"); state.party.map_id = "dungeon:0"; state.party.coordinate = Vector2i(4, 5); var restored_position := api.execute_classic(ClassicActionDefinition.new(0, 70, 70, 0, false, [2, 0, 0, 0, 0]), "world.restore"); state.party.map_id = "land:1"; state.party.coordinate = Vector2i.ZERO; var appearance := api.execute_classic(ClassicActionDefinition.new(0, 57, 57, 0, false, [0, 1, 0, 0, 0]), "world.appearance"); var land := content.world.map_by_id("land:0"); var region := land.random_region_by_index(1); var normalized_region := land.random_region_by_index(0); var authored_bounds := region.bounds; var before_geometry := state.to_data(); var altered := api.execute_classic(ClassicActionDefinition.new(0, 92, 92, 0, false, [0, 1, 0, -500, 0, 7, 7, 8, 8, 0]), "world.region"); var malformed := api.execute_classic(ClassicActionDefinition.new(0, 92, 92, 0, false, [0, 1, 0, 1, 9, 0, 0, 0, 0, 0]), "world.region.invalid"); var normalized := api.execute_classic(ClassicActionDefinition.new(0, 92, 92, 0, false, [-1, -1, 0, 100, 0, 1, 0, 0, 0, 0]), "world.region.classic-normalized"); var round_trip := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data()))); assert_equal([faced.state, faced.value, faced.events[0].payload.get("matched"), saved.state, restored_position.state, state.saved_party_map_id, appearance.state, state.world.topology.map_is_dark(land), content.world.battle_terrain_set_for_map(land, state.world).landlook], [ScenarioRuntimeOperationResult.State.COMPLETED, true, true, ScenarioRuntimeOperationResult.State.COMPLETED, ScenarioRuntimeOperationResult.State.COMPLETED, "land:0", ScenarioRuntimeOperationResult.State.COMPLETED, true, 0], "opcodes 57, 70, and 78 use semantic faced tiles, exact saved map context, and an offscreen save-owned appearance override"); assert_equal([altered.state, altered.error_code, altered.error_message, region.bounds, state.world.triggers.random_region(region).chance_ten_thousand, state.world.triggers.random_region_ids_at(land, Vector2i(2, 0)).has(region.id), state.world.triggers.random_region_ids_at(land, Vector2i(7, 8)).has(region.id), malformed.error_code, state.world.triggers.random_region(region).bounds_edges(), normalized.state, state.world.triggers.random_region(normalized_region).chance_ten_thousand, state.world.triggers.random_region(normalized_region).bounds_edges(), round_trip.world.triggers.random_region(region).bounds_edges(), round_trip.saved_party_coordinate], [ScenarioRuntimeOperationResult.State.COMPLETED, &"", "", authored_bounds, 9500, false, true, &"invalid_random_region_geometry", [7, 7, 8, 8], ScenarioRuntimeOperationResult.State.COMPLETED, normalized_region.chance_ten_thousand + 100, [1, 0, 0, 0], [7, 7, 8, 8], Vector2i(0, 1)], "opcode 92 changes one arbitrary offscreen rectangle without mutating package geometry, validates atomically, applies Castle's PC slot-zero fallback, and round-trips with opcode 70's exact bookmark"); assert_true(before_geometry != state.to_data() and altered.events.any(func(event: DomainEvent) -> bool: return event.kind == &"world_projection_invalidated" and event.payload.get("mapId") == "land:0"), "world mutations invalidate the affected projection while remaining deterministic save data"); assert_equal([state.world.triggers.has_random_region_at(land, Vector2i(2, 0)), state.world.triggers.has_random_region_at(land, Vector2i(7, 8)), round_trip.world.triggers.has_random_region_at(land, Vector2i(2, 0)), round_trip.world.triggers.has_random_region_at(land, Vector2i(7, 8))], [false, true, false, true], "the projection-oriented random-region membership query preserves effective overridden bounds before and after save restoration")


func _test_public_opcode_61_land_shift(content: RealmzContent) -> void:
	var map := content.world.map_by_id("land:0")
	var state := GameState.new(PartyState.new(map.id, Vector2i(2, map.topology.height - 5), [CharacterState.new("shift.hero", "Shift Hero", 10, 10)]), RealmzClock.new())
	var rng := ScriptedRng.new([32_767, 32_767, 0, 32_767])
	var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new())
	var shifted := api.execute_classic(ClassicActionDefinition.new(0, 61, 61, 0, false, [0, 10, 10, 1, 0]), "world.shift")
	var event := shifted.events[0]
	assert_equal([shifted.state, shifted.value, state.party.coordinate, rng.snapshot().draw_count], [ScenarioRuntimeOperationResult.State.COMPLETED, Vector2i(0, map.topology.height - 1), Vector2i(0, map.topology.height - 1), 4], "opcode 61 consumes Castle's two sign and two magnitude draws, then clamps a land shift through centerpict instead of failing")
	assert_equal([event.kind, event.payload.get("deltaX"), event.payload.get("deltaY"), event.payload.get("requestedDeltaX"), event.payload.get("requestedDeltaY"), event.payload.get("clamped"), state.world.exploration.was_visited(map.id, state.party.coordinate)], [&"party_shifted", -2, 4, -10, 10, true, true], "opcode 61 reports the committed boundary shift while retaining its requested random delta and visited destination")


func _test_public_character_checks(content: RealmzContent) -> void:
	var first := CharacterState.new("ability.first", "First", 10, 10); var second := CharacterState.new("ability.second", "Second", 10, 10)
	first.set_ability_value(5, 40); second.set_ability_value(5, 5)
	var goblin_shaman := MonsterDefinition.new("classic.monster.116", 116, "Goblin Shaman", 3, 0, 15, 10, 10, [], [], [], [], [], [], [])
	var tutorial_content := RealmzContent.new("scenario-tutorial", "1".repeat(64), "tutorial-opcode-89", content.rules_version, content.start_map_id, content.start_coordinate, content.world, ScenarioDefinition.new([], []), [], [], [], [], [], [], [], [goblin_shaman])
	var tutorial_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("tutorial.hero", "Tutorial Hero", 10, 10)]), RealmzClock.new())
	var tutorial_api := RealmzRuntimeApi.new(tutorial_content, tutorial_state, RealmzRng.new(89), ScenarioActionState.new())
	var corrected_ally := tutorial_api.execute_classic(ClassicActionDefinition.new(0, 89, 89, 149, false, []), "tutorial.ally-correction")
	var correction_event := corrected_ally.events[0]
	var unrelated_content := RealmzContent.new("scenario-unrelated", "2".repeat(64), "unrelated-opcode-89", content.rules_version, content.start_map_id, content.start_coordinate, content.world, ScenarioDefinition.new([], []), [], [], [], [], [], [], [], [goblin_shaman])
	var unrelated_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("unrelated.hero", "Unrelated Hero", 10, 10)]), RealmzClock.new())
	var unrelated_missing := RealmzRuntimeApi.new(unrelated_content, unrelated_state, RealmzRng.new(89), ScenarioActionState.new()).execute_classic(ClassicActionDefinition.new(0, 89, 89, 149, false, []), "unrelated.ally-missing")
	assert_equal([corrected_ally.state, tutorial_state.party.allies().size(), tutorial_state.party.allies()[0].definition_id, correction_event.payload.get("requestedClassicMonsterId"), correction_event.payload.get("resolvedClassicMonsterId"), unrelated_missing.error_code, unrelated_state.party.allies().size()], [ScenarioRuntimeOperationResult.State.COMPLETED, 1, goblin_shaman.id, 149, 116, &"unknown_monster", 0], "Tutorial's invalid opcode-89 record 149 resolves only to its source-backed Goblin Shaman 116 correction; unrelated missing targets still fail explicitly")
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [first, second]), RealmzClock.new())
	var rng := ScriptedRng.new([0, 13_107, 26_214, 1_311, 16_057, 30_802])
	var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new())
	var missing := api.execute_classic(ClassicActionDefinition.new(0, 31, 31, 0, false, [5, 0, 0, 12]), "ability.missing")
	assert_equal(missing.error_code, &"missing_extra_code", "opcode 31 rejects incomplete Extra Code rows")
	var waiting := api.execute_classic(ClassicActionDefinition.new(0, 31, 31, 0, false, [5, 0, 0, 12, 13]), "ability.pick")
	assert_equal([waiting.state, waiting.interaction.kind, waiting.interaction.body.to_data().get("eligible").size()], [ScenarioRuntimeOperationResult.State.WAITING, &"character_selection", 2], "opcode 31 yields a typed character picker")
	assert_equal(waiting.interaction.body.to_data()["eligible"][0], {"id": first.id, "name": first.name, "currentHealth": 10, "maximumHealth": 10}, "opcode 31 carries the living character facts rendered by the typed picker")
	var chosen := api.resume_classic(waiting.continuation, InteractionResponse.from_data(waiting.interaction.request_id, &"character_selection", {"characterIds": [first.id]}), "ability.resume")
	assert_equal([chosen.directive.target_id, state.scenario_progress.selected_character_ids()], [12, [first.id]], "opcode 31 resumes through the selected character and authored branch"); var forced_caste := content.characters.caste_definitions().filter(func(caste: CasteDefinition) -> bool: return caste.progression.victory_threshold(8) > 1)[0] as CasteDefinition; var forced_race := content.characters.race_definitions().filter(func(race: RaceDefinition) -> bool: return race.max_age > 0)[0] as RaceDefinition; var forced := CharacterState.new("level.forced", "Forced Level", 10, 10); forced.level = 9; forced.experience = -1; forced.race_id = forced_race.id; forced.caste_id = forced_caste.id; var forced_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [forced]), RealmzClock.new()); forced_state.experience_multiplier = 1.0; forced_state.scenario_progress.set_selected_character_ids([forced.id]); var forced_api := RealmzRuntimeApi.new(content, forced_state, RealmzRng.new(102), ScenarioActionState.new(), RealmzRules.new()); var forced_level: ScenarioRuntimeOperationResult = forced_api.execute_classic(ClassicActionDefinition.new(0, 102, 102, 0, false, []), "level.forced"); var forced_balance := 1 - forced_caste.progression.victory_threshold(8); var later_reward: ScenarioRuntimeOperationResult = forced_api.execute_classic(ClassicActionDefinition.new(0, 11, 11, 1, false, []), "level.later-battle"); var later_done: ScenarioRuntimeOperationResult = forced_api.resume_safe(later_reward.continuation, InteractionResponse.from_data(later_reward.interaction.request_id, later_reward.interaction.kind, {"action": "done"}), "level.later-battle.done"); assert_equal([forced_level.state, forced.level, forced.experience, forced_level.events[0].payload.get("experienceRemaining", {}).get(forced.id), later_done.events.any(func(event: DomainEvent) -> bool: return event.kind == &"character_leveled")], [ScenarioRuntimeOperationResult.State.COMPLETED, 10, forced_balance + 1, forced_balance, false], "opcode 102 subtracts Castle's current-level VP threshold before leveling so a later battle cannot level the same character again from a lingering positive balance"); var health_rng := ScriptedRng.new([0]); var health_api := RealmzRuntimeApi.new(content, state, health_rng, ScenarioActionState.new()); var harmed := health_api.execute_classic(ClassicActionDefinition.new(0, 15, 15, 0, false, [-1, 1, 1, 658, 0]), "health.selected"); assert_equal([first.current_health, health_rng.snapshot().draw_count, harmed.events.map(func(event: DomainEvent) -> StringName: return event.kind)], [9, 1, [&"sound_requested", &"character_effect_requested", &"party_health_changed"]], "opcode 15 applies selected health, sound, and exact eight-frame roster feedback in Castle order"); assert_equal(harmed.events[1].payload, {"characterId": first.id, "resourceType": "cicn", "firstResourceId": 12112, "frameCount": 8, "source": "classic-opcode-15"}, "opcode 15 identifies Castle spell-effect CICNs 12112 through 12119 without presentation inference")
	var third := CharacterState.new("ability.third", "Third", 10, 10); third.brawn = 22
	first.brawn = 2
	second.brawn = 12
	state.party.add_character(third)
	var filter_api := RealmzRuntimeApi.new(content, state, ScriptedRng.new([0, 13_107, 26_214]), ScenarioActionState.new())
	var filtered := filter_api.execute_classic(ClassicActionDefinition.new(0, 30, 30, 0, false, [0, 0, 2, 1, 0]), "ability.filter")
	assert_equal(filtered.value, [first.id, second.id, third.id], "opcode 30 evaluates the iterated characters through the public API")
	state.scenario_progress.set_selected_character_ids([first.id, second.id]); first.maximum_spell_points = 10; first.spell_points = 9; second.maximum_spell_points = 8; second.spell_points = 2; var spell_point_rng := ScriptedRng.new([0, 32_767, 16_384, 0, 0, 0]); var spell_point_api := RealmzRuntimeApi.new(content, state, spell_point_rng, ScenarioActionState.new()); var granted := spell_point_api.execute_classic(ClassicActionDefinition.new(0, 74, 74, 0, false, [2, 2, 4, 1, 0]), "spell-points.give"); var taken := spell_point_api.execute_classic(ClassicActionDefinition.new(0, 74, 74, 0, false, [-1, 1, 1, 0, 0]), "spell-points.take"); assert_equal([granted.state, first.spell_points, second.spell_points, taken.state, spell_point_rng.snapshot().draw_count, granted.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 2)], [ScenarioRuntimeOperationResult.State.COMPLETED, 9, 3, ScenarioRuntimeOperationResult.State.COMPLETED, 6, true], "opcode 74 rerolls per selected caster, applies only the final roll, clamps both bounds, preserves Castle's lower-bound sound identity, and consumes source-ordered RNG")
	var castes := content.characters.caste_definitions(); var fighter := castes.filter(func(caste: CasteDefinition) -> bool: return caste.classic_id == 1)[0] as CasteDefinition; var mage := castes.filter(func(caste: CasteDefinition) -> bool: return caste.classic_id == 6)[0] as CasteDefinition; first.caste_id = fighter.id; second.caste_id = mage.id; third.caste_id = mage.id; first.gender = 1; second.gender = 2; third.gender = 2; third.current_health = 0; var males := api.execute_classic(ClassicActionDefinition.new(0, 50, 50, 0, false, [1, 1, 0, 0, 1]), "identity.male"); var magical := api.execute_classic(ClassicActionDefinition.new(0, 53, 53, 0, false, [0, 2, 1, 0, 0]), "caste.magical"); var scenario_spell := content.magic.spell_by_classic_id(1404); var cast := api.execute_classic(ClassicActionDefinition.new(0, 17, 17, 0, false, [scenario_spell.classic_id, 1, 0, 1]), "spell.selected"); state.scenario_progress.set_selected_character_ids([first.id]); var second_slot_reject := api.execute_classic(ClassicActionDefinition.new(0, 55, 55, 0, true, [2, 1, 0, 12, 13]), "picked.wrong-slot"); state.scenario_progress.set_selected_character_ids([second.id]); var second_slot_accept := api.execute_classic(ClassicActionDefinition.new(0, 55, 55, 0, true, [2, 1, 0, 12, 13]), "picked.second-slot"); state.scenario_progress.set_selected_character_ids([first.id, second.id]); var conditioned := api.execute_classic(ClassicActionDefinition.new(0, 43, 43, 0, false, [1, 2, 3, 610, 0]), "condition.feedback"); var turning_off := api.execute_classic(ClassicActionDefinition.new(0, 82, 82, 0, false, []), "turning.off"); var turning_on := api.execute_classic(ClassicActionDefinition.new(0, 83, 83, 0, false, []), "turning.on"); state.scenario_progress.set_selected_character_ids([first.id]); var cleared := api.execute_classic(ClassicActionDefinition.new(0, 53, 53, 0, false, [1, 0, 2, 0, 0]), "caste.preselected"); assert_equal([males.value, magical.value, cast.events.slice(0, 3).map(func(event: DomainEvent) -> StringName: return event.kind), cast.events[0].payload.get("soundId"), cast.events[1].payload.get("firstResourceId"), second_slot_reject.directive.target_id, second_slot_accept.directive.target_id, second_slot_accept.directive.gosub, conditioned.events.map(func(event: DomainEvent) -> StringName: return event.kind), turning_off.events[1].payload.get("soundId"), turning_on.events[1].payload.get("soundId"), cleared.value, state.scenario_progress.selected_character_ids()], [[first.id], [second.id], [&"sound_requested", &"character_effect_requested", &"scenario_spell_applied"], 690, 12096, 13, 12, true, [&"sound_requested", &"character_effect_requested", &"sound_requested", &"character_effect_requested", &"condition_applied"], 10105, 20004, [], []], "opcodes 17, 43, 50, 53, 55, 82, and 83 preserve exact identity and living-caste selection, correct Castle's specific-pick slot alias, and retain source-ordered roster spell feedback and notification sounds")
	first.conditions.set_value(24, 2); state.scenario_progress.set_selected_character_ids([first.id]); var selected_condition := api.execute_classic(ClassicActionDefinition.new(0, 81, 81, 0, true, [24, -1, 999, 12, 13]), "condition.selected"); var whole_condition := api.execute_classic(ClassicActionDefinition.new(0, 81, 81, 0, false, [24, 0, 999, 12, 13]), "condition.whole"); var first_position := api.execute_classic(ClassicActionDefinition.new(0, 81, 81, 0, false, [24, 1, 999, 12, 13]), "condition.first-position"); assert_equal([selected_condition.directive.target_id, selected_condition.directive.gosub, whole_condition.directive.target_id, first_position.directive.target_id], [12, true, 13, 12], "opcode 81 requires every candidate to hold the condition, preserves GOSUB, maps authored position one to the top character, and ignores its unused message slot")
func _test_scripted_party_defeat(content: RealmzContent) -> void:
	var first := CharacterState.new("health.first", "First", 1, 1); var second := CharacterState.new("health.second", "Second", 1, 1); second.current_health = 0; var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [first, second]), RealmzClock.new()); var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(16), ScenarioActionState.new()); var program := ScenarioProgramDefinition.new("xap:1600", &"extra-action-point", "1600", [ClassicActionDefinition.new(0, 16, 16, 0, false, [-1, 1, 1, 0, 0]), ClassicActionDefinition.new(1, 24, 24, 0, false, [])]); var vm := ScenarioVm.new(); vm.configure(ScenarioDefinition.new([program], [])); vm.start_program(program.id, ScenarioExecutionContext.trigger(&"action", "health.ap")); var suspended := vm.run(api); assert_equal([suspended.state, first.current_health, second.current_health, suspended.handoff.runtime.source_kind, suspended.handoff.runtime.health_next_index], [ScenarioVmResult.State.SUSPENDED, 0, 0, ScenarioRuntimeHandoff.CLASSIC_HEALTH, 1], "opcode 16 suspends the VM at the first total scripted-party-loss boundary instead of consuming later targets"); var wire: Dictionary = JSON.parse_string(JSON.stringify(suspended.handoff.runtime.to_data())); var restored_handoff := ScenarioRuntimeHandoff.from_data(wire); assert_not_null(restored_handoff, "scripted defeat preserves the exact opcode, operands, targets, and cursor across a save boundary"); var duplicate_ids: Dictionary = wire.duplicate(true); duplicate_ids["data"]["targetIds"][1] = first.id; assert_equal(ScenarioRuntimeHandoff.from_data(duplicate_ids), null, "scripted defeat rejects duplicate target identities on restore"); first.current_health = 1; second.current_health = 1; var completed := api.complete_party_defeat_handoff(restored_handoff); var resumed := vm.resume_handoff(suspended.handoff, completed, api); assert_equal([completed.state, resumed.state, first.current_health, second.current_health, resumed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"action_point_kept")], [ScenarioRuntimeOperationResult.State.COMPLETED, ScenarioVmResult.State.COMPLETED, 1, 0, true], "revival resumes the suspended health operation and then runs the next authored AP instruction once")


func _test_corrected_character_selection_opcodes(content: RealmzContent) -> void:
	var characters: Array[CharacterState] = []
	for index: int in 6:
		characters.append(CharacterState.new("corrected.character.%d" % (index + 1), "Corrected %d" % (index + 1), 10, 10))
	characters[2].current_health = 0
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, characters), RealmzClock.new())
	var rng := ScriptedRng.new([0, 32_767, 0, 32_767, 0, 32_767])
	var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new())
	var selected_ids: Array[String] = [characters[1].id, characters[3].id]
	state.scenario_progress.set_selected_character_ids(selected_ids)
	var picked_exact := api.execute_classic(ClassicActionDefinition.new(0, 52, 52, 0, false, [8, 4, 2, 0, 0]), "misc.picked-exact")
	assert_equal([picked_exact.value, state.scenario_progress.selected_character_ids(), rng.snapshot().draw_count], [[characters[3].id], [characters[3].id], 0], "opcode 52 snapshots Picked Only and applies one-based exact-position selection without RNG")
	state.scenario_progress.set_selected_character_ids(selected_ids)
	var invalid_exact := api.execute_classic(ClassicActionDefinition.new(0, 52, 52, 0, false, [8, 0, 0, 0, 0]), "misc.invalid-exact")
	assert_equal([invalid_exact.error_code, state.scenario_progress.selected_character_ids(), rng.snapshot().draw_count], [&"invalid_party_position", selected_ids, 0], "opcode 52 rejects invalid exact positions atomically")
	var first_two_ids: Array[String] = [characters[0].id, characters[1].id]
	state.scenario_progress.set_selected_character_ids(first_two_ids)
	var picked_random := api.execute_classic(ClassicActionDefinition.new(0, 52, 52, 0, false, [3, 100, 2, 0, 0]), "misc.picked-random")
	assert_equal([picked_random.value, rng.snapshot().draw_count], [[characters[0].id, characters[1].id], 2], "opcode 52 draws only for the incoming Picked Only candidates")
	for position: int in 6:
		var positioned_id: Array[String] = [characters[position].id]
		state.scenario_progress.set_selected_character_ids(positioned_id)
		var positioned := api.execute_classic(ClassicActionDefinition.new(0, 55, 55, 0, true, [position + 1, 1, 0, 12, 13]), "picked.position.%d" % (position + 1))
		assert_equal([positioned.directive.target_id, positioned.directive.gosub], [12, true], "opcode 55 maps authored party position %d" % (position + 1))
	var first_three_ids: Array[String] = [characters[0].id, characters[1].id, characters[2].id]
	state.scenario_progress.set_selected_character_ids(first_three_ids)
	for threshold_case: Array in [[-2, 12], [-3, 12], [-4, 13], [25, 13]]:
		var threshold := api.execute_classic(ClassicActionDefinition.new(0, 55, 55, 0, false, [threshold_case[0], 1, 0, 12, 13]), "picked.threshold.%d" % threshold_case[0])
		assert_equal(threshold.directive.target_id, threshold_case[1], "opcode 55 applies documented threshold or safe unsupported-positive behavior for %d" % threshold_case[0])
	characters[0].conditions.set_value(24, 1); characters[5].conditions.set_value(24, 1)
	for position_case: Array in [[1, 12], [6, 12]]:
		var condition := api.execute_classic(ClassicActionDefinition.new(0, 81, 81, 0, false, [24, position_case[0], 0, 12, 13]), "condition.position.%d" % position_case[0])
		assert_equal(condition.directive.target_id, position_case[1], "opcode 81 maps authored one-based position %d" % position_case[0])
	var no_ids: Array[String] = []
	state.scenario_progress.set_selected_character_ids(no_ids)
	var empty_picked := api.execute_classic(ClassicActionDefinition.new(0, 81, 81, 0, false, [24, -1, 0, 12, 13]), "condition.empty-picked")
	var invalid_condition := api.execute_classic(ClassicActionDefinition.new(0, 81, 81, 0, false, [24, 7, 0, 12, 13]), "condition.invalid-position")
	assert_equal([empty_picked.directive.target_id, invalid_condition.error_code], [13, &"invalid_party_position"], "opcode 81 makes an empty picked set false and rejects unsupported positions")
	var short_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [characters[0]]), RealmzClock.new())
	var short_api := RealmzRuntimeApi.new(content, short_state, RealmzRng.new(1), ScenarioActionState.new())
	var missing_position := short_api.execute_classic(ClassicActionDefinition.new(0, 81, 81, 0, false, [24, 6, 0, 12, 13]), "condition.unoccupied-position")
	assert_equal(missing_position.directive.target_id, 13, "opcode 81 safely fails an unoccupied valid party position")
func _test_corrected_fatigue_opcode(content: RealmzContent) -> void:
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("fatigue.hero", "Fatigue Hero", 10, 10)]), RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	for fatigue_case: Array in [[1, 4], [20, 27], [25, 33], [50, 67], [100, 135], [150, 135], [0, 4], [-50, 4]]:
		state.party.fatigue = 135
		var result := api.execute_classic(ClassicActionDefinition.new(0, 68, 68, 0, false, [3, fatigue_case[0], 999, 0, 0]), "fatigue.percent.%d" % fatigue_case[0])
		assert_equal([result.value, state.party.fatigue], [fatigue_case[1], fatigue_case[1]], "opcode 68 applies ECode 2 percentage %d with bounded truncation" % fatigue_case[0])
	state.party.fatigue = 135
	api.execute_classic(ClassicActionDefinition.new(0, 68, 68, 0, false, [3, 25, -999, 0, 0]), "fatigue.save-round-trip")
	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_equal(restored.party.fatigue, 33, "corrected opcode 68 fatigue crosses the save-owned GameState boundary")
func _test_corrected_take_experience_opcode(content: RealmzContent) -> void:
	for action_slot: int in [0, 7]:
		var characters: Array[CharacterState] = [CharacterState.new("experience.first.%d" % action_slot, "First", 10, 10), CharacterState.new("experience.second.%d" % action_slot, "Second", 10, 10), CharacterState.new("experience.third.%d" % action_slot, "Third", 10, 10)]
		for character: CharacterState in characters:
			character.experience = 100
		var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, characters), RealmzClock.new())
		state.scenario_progress.set_selected_character_ids([characters[0].id, characters[2].id])
		var actions: Array[ClassicActionDefinition] = []
		for filler: int in action_slot:
			actions.append(ClassicActionDefinition.new(filler, 84, 84, filler, false, []))
		actions.append(ClassicActionDefinition.new(action_slot, 90, 90, 0, false, [10, 1, 0, 0, 0]))
		var program := ScenarioProgramDefinition.new("opcode90.slot.%d" % action_slot, &"trigger", "opcode90", actions); var vm := ScenarioVm.new(); vm.configure(ScenarioDefinition.new([program], [])); vm.start_program(program.id, ScenarioExecutionContext.trigger(&"action", "ap.opcode90.%d" % action_slot)); var result := vm.run(RealmzRuntimeApi.new(content, state, RealmzRng.new(90), ScenarioActionState.new()))
		assert_equal([result.state, characters.map(func(character: CharacterState) -> int: return character.experience), state.scenario_progress.selected_character_ids(), result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"experience_taken").map(func(event: DomainEvent) -> Variant: return event.payload.get("targetIds"))], [ScenarioVmResult.State.COMPLETED, [90, 100, 90], [characters[0].id, characters[2].id], [[characters[0].id, characters[2].id]]], "opcode 90 mode 1 uses each picked identity rather than the action-slot selection cell at source slot %d" % action_slot)
func _test_opcode_7_program_replacement_modes(content: RealmzContent) -> void:
	var map := content.world.map_by_id(content.start_map_id); var source := ScenarioProgramDefinition.new("xap:325", &"extra-action-point", "325", []); var simple := ScenarioProgramDefinition.new("simple:0:result:1", &"simple-encounter-result", "1", []); var complex := ScenarioProgramDefinition.new("complex:0:result:2", &"complex-encounter-result", "2", []); var ap_target := ScenarioProgramDefinition.new("trigger:replacement-target", &"trigger", "replacement-target", []); var root := ScenarioProgramDefinition.new("trigger:replacement-root", &"trigger", "replacement-root", [ClassicActionDefinition.new(0, 7, 7, 0, false, [-1, 0, 325, 0, 1]), ClassicActionDefinition.new(1, 7, 7, 0, false, [-2, 0, 325, 0, 2]), ClassicActionDefinition.new(2, 7, 7, 0, false, [map.level_index, 4, 325, 0, 0])]); var definition := ScenarioDefinition.new([root, source, simple, complex, ap_target], [])
	var trigger := TriggerDefinition.new("replacement-target", ap_target.id, map.id, Vector2i.ZERO, true, 100, null, 4); var replacement_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, definition, [], [trigger]); var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("replacement.hero", "Hero", 10, 10)]), RealmzClock.new()); var rng := RealmzRng.new(7); var api := RealmzRuntimeApi.new(replacement_content, state, rng, ScenarioActionState.new()); var vm := ScenarioVm.new(); vm.configure(definition); vm.start_program(root.id, ScenarioExecutionContext.trigger(&"action", root.id)); var result := vm.run(api)
	assert_equal([result.state, state.scenario_progress.encounters.program_id(simple.id), state.scenario_progress.encounters.program_id(complex.id), state.scenario_progress.encounters.program_id(ap_target.id), rng.snapshot().draw_count], [ScenarioVmResult.State.COMPLETED, source.id, source.id, source.id, 0], "opcode 7 maps -1 to Simple result, -2 to Complex result, and nonnegative map indexes to Action Point replacement")
	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data()))); var before_invalid := restored.to_data(); var invalid := RealmzRuntimeApi.new(replacement_content, restored, RealmzRng.new(7), ScenarioActionState.new()).execute_classic(ClassicActionDefinition.new(0, 7, 7, 0, false, [-3, 0, 325, 0, 0]), "replacement.invalid")
	assert_equal([invalid.error_code, restored.to_data()], [&"unknown_map", before_invalid], "opcode 7 preserves unknown negative imports as typed atomic failures rather than reinterpreting them")
func _test_opcode_13_trigger_mutation_modes(content: RealmzContent) -> void:
	var land := content.world.map_by_type_and_index(&"land", 0)
	var dungeon := content.world.map_by_type_and_index(&"dungeon", 0)
	assert_true(land != null and dungeon != null, "opcode 13 fixture has land and dungeon index zero")
	if land == null or dungeon == null:
		return
	var triggers: Array[TriggerDefinition] = [
		TriggerDefinition.new("opcode13.land.1", "", land.id, Vector2i.ZERO, true, 100, null, 1),
		TriggerDefinition.new("opcode13.land.2", "", land.id, Vector2i.ZERO, true, 100, null, 2),
		TriggerDefinition.new("opcode13.land.4", "", land.id, Vector2i.ZERO, true, 100, null, 4),
		TriggerDefinition.new("opcode13.dungeon.1", "", dungeon.id, Vector2i.ZERO, true, 100, null, 1),
		TriggerDefinition.new("opcode13.dungeon.2", "", dungeon.id, Vector2i.ZERO, true, 100, null, 2),
	]
	var fixture := RealmzContent.new("opcode13", "1".repeat(64), "opcode13", content.rules_version, land.id, Vector2i.ZERO, content.world, ScenarioDefinition.new([], []), [], triggers)
	var state := GameState.new(PartyState.new(land.id, Vector2i.ZERO, [CharacterState.new("opcode13.hero", "Hero", 10, 10)]), RealmzClock.new())
	var rng := RealmzRng.for_oracle(13)
	var api := RealmzRuntimeApi.new(fixture, state, rng, ScenarioActionState.new())
	var land_result := api.execute_classic(ClassicActionDefinition.new(0, 13, 13, 0, false, [0, 1, 25, 2, 4]), "opcode13.land")
	var dungeon_result := api.execute_classic(ClassicActionDefinition.new(0, 13, 13, 0, false, [0, 0, -1, -1, -2]), "opcode13.dungeon")
	var single_result := api.execute_classic(ClassicActionDefinition.new(0, 13, 13, 0, false, [0, 1, 75, 0, 99]), "opcode13.single")
	var saved := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_equal([land_result.value, dungeon_result.value, single_result.value], [["opcode13.land.1", "opcode13.land.2", "opcode13.land.4"], ["opcode13.dungeon.1", "opcode13.dungeon.2"], ["opcode13.land.1"]], "opcode 13 combines its optional single record with an inclusive land range, uses a negative range for dungeon records, and silently skips unplaced native rows")
	assert_equal([state.world.triggers.trigger_chance("opcode13.land.1", 100), state.world.triggers.trigger_chance("opcode13.land.2", 100), state.world.triggers.trigger_chance("opcode13.land.4", 100), state.world.triggers.trigger_chance("opcode13.dungeon.1", 100), state.world.triggers.trigger_is_disabled("opcode13.dungeon.2"), rng.snapshot().draw_count], [75, 25, 25, -1, true, 0], "opcode 13 stores clamped runtime chance overrides and canonical disablement without consuming RNG")
	assert_true(saved != null and saved.world.triggers.trigger_chance("opcode13.land.2", 100) == 25 and saved.world.triggers.trigger_is_disabled("opcode13.dungeon.1"), "opcode 13's land and dungeon overrides survive the public save-owned state codec")
	var before_invalid := state.to_data()
	var invalid := api.execute_classic(ClassicActionDefinition.new(0, 13, 13, 0, false, [99, 1, 50, 0, 0]), "opcode13.invalid")
	assert_equal([invalid.error_code, state.to_data(), rng.snapshot().draw_count], [&"unknown_map", before_invalid, 0], "an unavailable opcode 13 map rejects atomically without state or RNG mutation")
func _test_public_action_state(content: RealmzContent) -> void:
	var store := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.SET_VALUE)
	store.scope = &"persistent"
	store.name = "visits"
	store.value = _literal(42)
	var mirror := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.SET_VALUE)
	mirror.scope = &"persistent"
	mirror.name = "mirror"
	mirror.value = _variable(&"persistent", "visits")
	var finish := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.RETURN)
	finish.value = _variable(&"persistent", "visits")
	var action := _action("scenario.test.state", &"int", [store, mirror, finish])
	var definition := ScenarioDefinition.new([ScenarioProgramDefinition.new("root", &"trigger", "root", [CallScenarioActionInstruction.new(action.id)])], [action])
	var state := ScenarioActionState.new()
	var vm := ScenarioVm.new()
	vm.configure(definition)
	vm.start_program("root", ScenarioExecutionContext.calling(&"action"))
	assert_equal(vm.run(_runtime_api(content, state)).state, ScenarioVmResult.State.COMPLETED, "persistent Safe Action completes through the public VM")
	assert_equal([state.read("campaign", action.id, "visits"), state.read("campaign", action.id, "mirror")], [42, 42], "persistent variables remain namespaced to the Scenario Action")
	var restored := ScenarioActionState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_equal(restored.read("campaign", action.id, "visits"), 42, "persistent action state preserves integer values through JSON")
func _test_aogm_dispatch_has_no_fallback(content: RealmzContent) -> void:
	for opcode: int in ClassicOpcodeCatalog.AOGM_ACTIVE_OPCODES:
		if opcode == 39:
			continue
		var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("dispatch.character", "Dispatch", 10, 10)])
		var api := RealmzRuntimeApi.new(content, GameState.new(party, RealmzClock.new()), RealmzRng.new(1), ScenarioActionState.new())
		var action := ClassicActionDefinition.new(0, opcode, opcode, 0, false, [0, 0, 0, 0, 0])
		var operation := api.execute_classic(action, "request.dispatch", ScenarioExecutionContext.calling(&"action"))
		assert_true(operation != null and operation.error_code != &"unsupported_classic_opcode", "AOGM opcode %d has an explicit runtime owner" % opcode)
func _test_classic_opcode_2_legacy_battle_record(content: RealmzContent) -> void:
	var battle := content.combat.battle_by_id("classic.battle.0")
	assert_not_null(battle, "fixture provides battle 0")
	if battle == null:
		return
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("opcode2.hero", "Hero", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(2), ScenarioActionState.new(), RealmzRules.new())
	var positive := api.execute_classic(ClassicActionDefinition.new(0, 2, 2, battle.classic_id, false, [battle.classic_id, 0, -1, 30002, 0]), "battle.legacy-aogm")
	assert_equal(positive.state, ScenarioRuntimeOperationResult.State.WAITING, "legacy opcode 2 battle record starts battle without unknown_message failure")
	var sound_events := positive.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 30002 and event.payload.get("source") == "classic-battle")
	var message_events := positive.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"message_shown" and event.payload.get("source") == "classic-battle")
	assert_true(sound_events.size() == 1 and message_events.is_empty(), "legacy opcode 2 battle emits application sound word4 directly and no pre-battle message")
	assert_true(state.combat != null and state.combat.battle_id == battle.id, "legacy opcode 2 battle initializes active combat state")
	state.combat = null
	var positive_mode := api.execute_classic(ClassicActionDefinition.new(0, 2, 2, battle.classic_id, false, [battle.classic_id, 0, -1, 30001, 599]), "battle.legacy-mode")
	assert_equal(positive_mode.state, ScenarioRuntimeOperationResult.State.WAITING, "legacy opcode 2 battle with positive sound in 30000..30005 starts battle")
	assert_true(positive_mode.continuation != null and positive_mode.continuation.combat().caller.mode == 599, "legacy opcode 2 preserves outcome mode 599 in battle caller")
	var sound_mode_events := positive_mode.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 30001 and event.payload.get("source") == "classic-battle")
	assert_true(sound_mode_events.size() == 1, "word 4 sound projects directly")
	state.combat = null
	var negative_codes: Array = [[battle.classic_id, 0, -1, -30001, 0], [battle.classic_id, 1, -1, 30002, 0], [battle.classic_id, 0, 0, 30002, 0], [battle.classic_id, 0, -1, 29999, 0], [battle.classic_id, 0, -1, 30006, 0], [battle.classic_id, 0, -1, 30002]]
	for code: Array in negative_codes:
		var extra: Array[int] = []
		extra.assign(code)
		var result := api.execute_classic(ClassicActionDefinition.new(0, 2, 2, battle.classic_id, false, extra), "battle.neg-table")
		assert_equal(result.error_code, &"unknown_message", "opcode 2 nearby negative %s does not match legacy discriminator" % [code])
	state.scenario_progress.set_selected_character_ids([party.characters()[0].id])
	var wrong_opcode := api.execute_classic(ClassicActionDefinition.new(0, 48, 48, battle.classic_id, false, [battle.classic_id, 0, -1, 30002, 0]), "battle.neg-opcode")
	assert_equal(wrong_opcode.error_code, &"unknown_message", "opcode 48 does not match legacy opcode 2 discriminator")
func _test_package_backed_macro_spells() -> void:
	var clouds := load_test_package("res://src/storage/packages/bundled_campaigns/scenario-castle-in-the-clouds.realmz2"); var c := _package_macro_battle(clouds.content, 29); var c_rng := RealmzRng.for_oracle(273); var c_vm := ScenarioVm.new(); c_vm.configure(clouds.content.scenario); c_vm.start_program("xap:273", ScenarioExecutionContext.calling(&"monster-death-macro").set_battle(c.state.combat.battle_id).set_combatant(c.source.id)); var c_result := c_vm.run(RealmzRuntimeApi.new(clouds.content, c.state, c_rng, ScenarioActionState.new(), RealmzRules.new())); var c1: CharacterState = c.hero1; var c2: CharacterState = c.hero2; var c_los: CharacterState = c.hero_los; var c_range: CharacterState = c.hero_range; var c_ally: MonsterState = c.ally; var c_state: GameState = c.state
	assert_equal([c_result.state, c1.current_health < 30, c2.current_health, c_los.current_health, c_range.current_health, c_ally.current_health, c1.spell_points, c_state.combat.turns.active_actor_id(), _event_has(c_result.events, &"sound_requested"), _event_has(c_result.events, &"action_point_kept"), c_rng.snapshot().draw_count], [ScenarioVmResult.State.COMPLETED, true, 30, 30, 30, 20, 50, c1.id, true, true, 3], "Castle in the Clouds packaged xap:273 resolves Spell 3208 against the first legal hero with exact range, LOS, allegiance, resource, turn, continuation, and RNG outcomes")
	var trouble := load_test_package("res://src/storage/packages/bundled_campaigns/scenario-trouble-in-the-sword-lands.realmz2"); var t := _package_macro_battle(trouble.content, 222); var t_rng := RealmzRng.for_oracle(1605); var t_vm := ScenarioVm.new(); t_vm.configure(trouble.content.scenario); t_vm.start_program("xap:1605", ScenarioExecutionContext.calling(&"monster-death-macro").set_battle(t.state.combat.battle_id).set_combatant(t.source.id)); var t_result := t_vm.run(RealmzRuntimeApi.new(trouble.content, t.state, t_rng, ScenarioActionState.new(), RealmzRules.new())); var t1: CharacterState = t.hero1; var t2: CharacterState = t.hero2; var t_los: CharacterState = t.hero_los; var t_range: CharacterState = t.hero_range; var t_ally: MonsterState = t.ally; var t_resolutions := t_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")
	assert_equal([t_result.state, t1.current_health < 30, t2.current_health < 30, t_los.current_health, t_range.current_health, t_ally.current_health, t_resolutions.map(func(event: DomainEvent) -> String: return String(event.payload.get("targetId"))), _event_has(t_result.events, &"combat_fumble_skipped"), _event_has(t_result.events, &"action_point_kept"), t_rng.snapshot().draw_count], [ScenarioVmResult.State.COMPLETED, true, true, 30, 30, 20, [t1.id, t2.id], true, true, 6], "Trouble packaged xap:1605 resolves Spell 1108 in deterministic order, applies range and LOS, uses the active actor for opcode 122, continues, and retains its exact RNG position")
	var mithril := load_test_package("res://src/storage/packages/bundled_campaigns/scenario-mithril-vault.realmz2"); var m := _package_macro_battle(mithril.content, 14); var m_state: GameState = m.state; var m1: CharacterState = m.hero1; var m2: CharacterState = m.hero2; var ma1: MonsterState = m.ally; var podling: MonsterDefinition = m.monster_def; m1.conditions.set_value(ConditionRules.MAGIC_AURA, 5); m2.conditions.set_value(ConditionRules.MAGIC_AURA, 5); ma1.conditions.set_value(ConditionRules.MAGIC_AURA, 5); var ma2 := MonsterState.new("macro.ally2", podling.id, "Ally Two", 20, 20, 1, 1, 0, 0, 0, true); ma2.conditions.set_value(ConditionRules.MAGIC_AURA, 5); m_state.combat.roster.add_monster(ma2); m_state.combat.battlefield.actors.place_monster(ma2.id, Vector2i(52, 48), podling.size); var ma_los := MonsterState.new("macro.ally_los", podling.id, "Ally LOS", 20, 20, 1, 1, 0, 0, 0, true); ma_los.conditions.set_value(ConditionRules.MAGIC_AURA, 5); m_state.combat.roster.add_monster(ma_los); m_state.combat.battlefield.actors.place_monster(ma_los.id, Vector2i(50, 46), podling.size); var ma_range := MonsterState.new("macro.ally_range", podling.id, "Ally Range", 20, 20, 1, 1, 0, 0, 0, true); ma_range.conditions.set_value(ConditionRules.MAGIC_AURA, 5); m_state.combat.roster.add_monster(ma_range); m_state.combat.battlefield.actors.place_monster(ma_range.id, Vector2i(35, 36), podling.size); var m_rng := RealmzRng.for_oracle(9); var m_vm := ScenarioVm.new(); m_vm.configure(mithril.content.scenario); m_vm.start_program("xap:9", ScenarioExecutionContext.calling(&"monster-death-macro").set_battle(m.state.combat.battle_id).set_combatant(m.source.id)); var m_result := m_vm.run(RealmzRuntimeApi.new(mithril.content, m.state, m_rng, ScenarioActionState.new(), RealmzRules.new()))
	assert_equal([m_result.state, ma1.conditions.value(ConditionRules.MAGIC_AURA), ma2.conditions.value(ConditionRules.MAGIC_AURA), m1.conditions.value(ConditionRules.MAGIC_AURA), m2.conditions.value(ConditionRules.MAGIC_AURA), ma_los.conditions.value(ConditionRules.MAGIC_AURA), ma_range.conditions.value(ConditionRules.MAGIC_AURA), m_rng.snapshot().draw_count], [ScenarioVmResult.State.COMPLETED, 0, 0, 5, 5, 0, 5, 6], "Mithril packaged xap:9 resolves Spell 1304 against in-range allies, correctly ignores LOS for its negative range, skips heroes and out-of-range allies, and retains exact RNG position")
	var y := _package_macro_battle(mithril.content, 136); var y_rng := RealmzRng.for_oracle(393); var y_vm := ScenarioVm.new(); y_vm.configure(mithril.content.scenario); y_vm.start_program("xap:393", ScenarioExecutionContext.calling(&"monster-death-macro").set_battle(y.state.combat.battle_id).set_combatant(y.source.id)); var y_api := RealmzRuntimeApi.new(mithril.content, y.state, y_rng, ScenarioActionState.new(), RealmzRules.new()); var y_waiting := y_vm.run(y_api); var y_before := JSON.stringify(y.state.to_data()); var y_failed := y_vm.resume(InteractionResponse.acknowledge(y_waiting.interaction), y_api)
	assert_equal([y_waiting.state, y_waiting.interaction.kind, y_failed.state, y_failed.error_code, JSON.stringify(y.state.to_data()) == y_before, y_rng.snapshot().draw_count], [ScenarioVmResult.State.WAITING, InteractionRequest.ACKNOWLEDGE, ScenarioVmResult.State.FAILED, &"unsupported_macro_single_target", true, 0], "Mithril packaged xap:393 crosses its acknowledgement then rejects the unsafe single-target macro without state or RNG mutation")
	var g := _package_macro_battle(mithril.content, 92); var g_rng := RealmzRng.for_oracle(337); var g_vm := ScenarioVm.new(); g_vm.configure(mithril.content.scenario); g_vm.start_program("xap:337", ScenarioExecutionContext.calling(&"monster-death-macro").set_battle(g.state.combat.battle_id).set_combatant(g.source.id)); var g_api := RealmzRuntimeApi.new(mithril.content, g.state, g_rng, ScenarioActionState.new(), RealmzRules.new()); var g_waiting := g_vm.run(g_api); var g_before := JSON.stringify(g.state.to_data()); var g_failed := g_vm.resume(InteractionResponse.acknowledge(g_waiting.interaction), g_api)
	assert_equal([g_waiting.state, g_waiting.interaction.kind, g_failed.state, g_failed.error_code, JSON.stringify(g.state.to_data()) == g_before, g_rng.snapshot().draw_count], [ScenarioVmResult.State.WAITING, InteractionRequest.ACKNOWLEDGE, ScenarioVmResult.State.FAILED, &"unsupported_macro_ray", true, 0], "Mithril packaged xap:337 crosses its acknowledgement then rejects the unsafe ray macro without state or RNG mutation")
func _package_macro_battle(content: RealmzContent, monster_classic_id: int) -> Dictionary:
	var map := content.world.map_by_id(content.start_map_id); var terrain_set := content.world.battle_terrain_set_for_map(map, null); if terrain_set == null: terrain_set = content.world.battle_terrain_sets()[0]
	var blocking_tiles := range(0, 401).filter(func(tile_id: int) -> bool: return terrain_set.tile_by_id(tile_id) != null and terrain_set.tile_by_id(tile_id).blocks_los); var blocking_tile_id: int = blocking_tiles[0] if not blocking_tiles.is_empty() else -1; var tiles: Array[int] = []; tiles.resize(BattlefieldGrid.CELL_COUNT); tiles.fill(terrain_set.base_tile); var field := BattlefieldState.new(content.start_map_id, tiles); var hero1 := CharacterState.new("macro.hero1", "Hero One", 30, 30); hero1.spell_points = 50; var hero2 := CharacterState.new("macro.hero2", "Hero Two", 30, 30); hero2.spell_points = 50; var hero_los := CharacterState.new("macro.hero_los", "Hero LOS", 30, 30); var hero_range := CharacterState.new("macro.hero_range", "Hero Range", 30, 30); field.actors.place_character(hero1.id, Vector2i(48, 50)); field.actors.place_character(hero2.id, Vector2i(46, 50)); field.actors.place_character(hero_los.id, Vector2i(50, 45)); field.actors.place_character(hero_range.id, Vector2i(35, 35))
	if blocking_tile_id >= 0: field.terrain.set_tile(Vector2i(50, 48), blocking_tile_id)
	var monster_def := content.combat.monster_by_classic_id(monster_classic_id); var source := MonsterState.new("macro.source", monster_def.id, monster_def.name, 20, 20, 1, 1, 0, 0, 0, true); source.current_health = 0; field.actors.place_monster(source.id, Vector2i(50, 50), monster_def.size); var ally := MonsterState.new("macro.ally", monster_def.id, "Ally", 20, 20, 1, 1, 0, 0, 0, true); field.actors.place_monster(ally.id, Vector2i(52, 50), monster_def.size); var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [hero1, hero2, hero_los, hero_range]), RealmzClock.new()); state.combat = CombatState.new("battle.macro", [source, ally], -1, field); state.combat.set_turn_order([hero1.id, hero2.id, source.id, ally.id]); return {"state": state, "source": source, "ally": ally, "hero1": hero1, "hero2": hero2, "hero_los": hero_los, "hero_range": hero_range, "monster_def": monster_def}
func _begin_fixture_adventure(session: GameSession, content: RealmzContent) -> void:
	var races := content.characters.race_definitions()
	var castes := content.characters.caste_definitions()
	assert_false(races.is_empty() or castes.is_empty(), "fixture has playable race and caste data")
	if races.is_empty() or castes.is_empty():
		return
	var character := CharacterState.new("fixture.party.member", "Fixture Hero", 10, 10)
	character.race_id = races[0].id
	character.caste_id = castes[0].id
	var imported := session.submit_intent(PartyIntents.import_vault_character(character.id, "1".repeat(64), character, "fixture", content.package_hash))
	assert_equal(imported.state, SessionStep.State.COMPLETED, "fixture imports a deterministic party member")
	var started := session.submit_intent(PartyIntents.begin_adventure())
	if content.scenario.application_hook_program_id(ScenarioApplicationHooks.START_GAME).is_empty():
		assert_equal(started.state, SessionStep.State.COMPLETED, "fixture begins without a Start Game interaction")
	else:
		assert_equal(started.state, SessionStep.State.WAITING_FOR_INTERACTION, "fixture reaches the Start Game interaction")
		assert_equal(session.respond(InteractionResponse.acknowledge(started.interaction)).state, SessionStep.State.COMPLETED, "fixture completes its Start Game interaction")
func _vm_combat_auto_session(content: RealmzContent, seed: int) -> GameSession:
	var races := content.characters.race_definitions(); var castes := content.characters.caste_definitions()
	if races.is_empty() or castes.is_empty(): return null
	var session := GameSession.new(); session.start(content, seed)
	for character_index: int in 6:
		var character := CharacterState.new("fixture.vm-auto.%d" % (character_index + 1), "VM Auto Hero %d" % (character_index + 1), 100, 100); character.race_id = races[0].id; character.caste_id = castes[0].id
		var imported := session.submit_intent(PartyIntents.import_vault_character(character.id, "1".repeat(64), character, "fixture", content.package_hash))
		if imported.state != SessionStep.State.COMPLETED: return null
	var entered := session.submit_intent(PartyIntents.begin_adventure())
	if entered.state != SessionStep.State.WAITING_FOR_INTERACTION or entered.interaction == null or entered.interaction.kind != InteractionRequest.COMBAT:
		return null
	if session.view().party_members.size() != 6 or session.view().combat_view == null:
		return null
	return session
func _assert_vm_combat_auto_round_trip(content: RealmzContent, session: GameSession, character_id: String, phase: String) -> void:
	var enabled := session.submit_intent(CombatIntents.set_auto(character_id, true))
	assert_equal([enabled.state, enabled.error_code, enabled.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, &"", InteractionRequest.COMBAT], "the %s sixth member enables persistent Auto through VM combat" % phase)
	assert_true(_event_has(enabled.events, &"combat_auto_changed"), "%s VM Auto publishes the committed change" % phase)
	var body := enabled.interaction.body as CombatRequestBody
	assert_true(body != null and body.auto_character_ids.has(character_id) and (phase != "active" or body.auto_character_ids.size() == 6), "the next %s VM combat request projects sixth-member Auto after one activation" % phase)
	var saved := save_round_trip(session.snapshot())
	assert_not_null(saved, "%s sixth-member Auto crosses the save envelope" % phase)
	if saved == null:
		return
	var restored := GameSession.new()
	assert_equal(restored.restore(content, saved).state, SessionStep.State.COMPLETED, "%s sixth-member Auto restores with its VM continuation" % phase)
	assert_true(restored.view().combat_view.auto_character_ids.has(character_id), "restored %s VM combat retains sixth-member Auto" % phase)
	var disabled_id := restored.view().combat_view.active_actor_id if phase == "active" else character_id
	var disabled := restored.submit_intent(CombatIntents.set_auto(disabled_id, false))
	assert_equal([disabled.state, disabled.error_code, disabled.interaction.kind, restored.view().combat_view.auto_character_ids.has(disabled_id)], [SessionStep.State.WAITING_FOR_INTERACTION, &"", InteractionRequest.COMBAT, false], "restored %s VM combat disables Auto at the next activation boundary" % phase)
func _restore_fixture_position(session: GameSession, content: RealmzContent, map_id: String, coordinate: Vector2i) -> void:
	var envelope := session.snapshot()
	envelope.game_state.party.map_id = map_id
	envelope.game_state.party.coordinate = coordinate
	assert_equal(session.restore(content, envelope).state, SessionStep.State.COMPLETED, "fixture position changes through validated restore")


func _test_repaired_branch_and_opcode_variants(content: RealmzContent) -> void:
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("variant.hero", "Variant Hero", 10, 10)]), RealmzClock.new())
	state.difficulty = 1
	var rng := RealmzRng.for_oracle(42); var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new())
	var op84 := api.execute_classic(ClassicActionDefinition.new(0, 84, 84, 840, false, []), "op84")
	var op98 := api.execute_classic(ClassicActionDefinition.new(0, 98, 98, 980, false, []), "op98")
	assert_true(op84.state == ScenarioRuntimeOperationResult.State.COMPLETED and op84.events.any(func(e: DomainEvent) -> bool: return e.kind == &"classic_control_marker" and e.payload.get("opcode") == 84 and e.payload.get("operandId") == 840), "opcode 84 emits control marker without mutating simulation")
	assert_true(op98.state == ScenarioRuntimeOperationResult.State.COMPLETED and op98.events.any(func(e: DomainEvent) -> bool: return e.kind == &"classic_control_marker" and e.payload.get("opcode") == 98 and e.payload.get("operandId") == 980), "opcode 98 emits control marker without mutating simulation")
	var op42_gosub := api.execute_classic(ClassicActionDefinition.new(0, -42, 42, 0, true, [100, 1, 0, 55, 0]), "op42.gosub")
	var op42_keep := api.execute_classic(ClassicActionDefinition.new(0, 42, 42, 0, false, [100, 2, 0, 0, 0]), "op42.keep")
	var op42_erase := api.execute_classic(ClassicActionDefinition.new(0, 42, 42, 0, false, [100, -2, 0, 0, 0]), "op42.erase", ScenarioExecutionContext.trigger(&"action", "ap.erase_op42"))
	assert_true(op42_gosub.directive.kind == ScenarioVmDirective.BRANCH_XAP and op42_gosub.directive.target_id == 55 and op42_gosub.directive.gosub == true and op42_keep.directive.kind == ScenarioVmDirective.FINISH_TIMELINE and _event_has(op42_keep.events, &"action_point_kept") and op42_erase.directive.kind == ScenarioVmDirective.FINISH_TIMELINE and state.world.triggers.trigger_is_disabled("ap.erase_op42"), "opcode 42 preserves signed GOSUB, keep-codes, and erase-trigger modes")
	state.scenario_progress.set_quest_value(3, 5); state.party_in_boat = true
	var op77_simple := api.execute_classic(ClassicActionDefinition.new(0, 77, 77, 0, false, [3, 5, 1, 0, 10]), "op77.simple"); var op77_complex := api.execute_classic(ClassicActionDefinition.new(0, 77, 77, 0, false, [3, 5, 2, 0, 20]), "op77.complex")
	var op86_simple := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [3, 0, 1, 11, 0]), "op86.simple"); var op86_complex := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [3, 0, 2, 21, 0]), "op86.complex")
	assert_true(op77_simple.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and op77_simple.directive.encounter_kind == &"simple" and op77_simple.directive.target_id == 10 and op77_complex.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and op77_complex.directive.encounter_kind == &"complex" and op77_complex.directive.target_id == 20, "opcode 77 branches to Simple and Complex encounters")
	assert_true(op86_simple.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and op86_simple.directive.encounter_kind == &"simple" and op86_simple.directive.target_id == 11 and op86_complex.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and op86_complex.directive.encounter_kind == &"complex" and op86_complex.directive.target_id == 21, "opcode 86 branches to Simple and Complex encounters")
	var op76_simple := api.execute_classic(ClassicActionDefinition.new(0, 76, 76, 0, false, [4, 1, 2, 1, 12]), "op76.simple"); var op76_complex := api.execute_classic(ClassicActionDefinition.new(0, 76, 76, 0, false, [4, 1, 3, 1, 22]), "op76.complex")
	assert_true(op76_simple.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and op76_simple.directive.encounter_kind == &"simple" and op76_simple.directive.target_id == 12 and op76_complex.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and op76_complex.directive.encounter_kind == &"complex" and op76_complex.directive.target_id == 22, "opcode 76 auto-branches to Simple and Complex encounters")
	var item_def := content.items.item_by_classic_id(1)
	if item_def != null:
		state.party.characters()[0].set_inventory([ItemInstance.new("item.test", item_def.id, 1)])
		var op21_simple := api.execute_classic(ClassicActionDefinition.new(0, 21, 21, 0, false, [1, 1, 0, 13, 0]), "op21.simple"); var op21_complex := api.execute_classic(ClassicActionDefinition.new(0, 21, 21, 0, false, [1, 2, 0, 23, 0]), "op21.complex")
		assert_true(op21_simple.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and op21_simple.directive.encounter_kind == &"simple" and op21_simple.directive.target_id == 13 and op21_complex.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and op21_complex.directive.encounter_kind == &"complex" and op21_complex.directive.target_id == 23, "opcode 21 branches to Simple and Complex encounters")
	var op87_simple := api.execute_classic(ClassicActionDefinition.new(0, 87, 87, 0, false, [999, 1, 0, 0, 15]), "op87.simple"); var op87_complex := api.execute_classic(ClassicActionDefinition.new(0, 87, 87, 0, false, [999, 2, 0, 0, 25]), "op87.complex")
	assert_true(op87_simple.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and op87_simple.directive.encounter_kind == &"simple" and op87_simple.directive.target_id == 15 and op87_complex.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and op87_complex.directive.encounter_kind == &"complex" and op87_complex.directive.target_id == 25, "opcode 87 branches to Simple and Complex encounters")
	state.party.conditions.set_value(0, 10)
	var op40_m0 := api.execute_classic(ClassicActionDefinition.new(0, 40, 40, 0, false, [1, 0, 0, 0, 0]), "op40.m0")
	var op40_m0_inactive := api.execute_classic(ClassicActionDefinition.new(0, 40, 40, 0, false, [2, 0, 0, 1, 0]), "op40.m0.inactive")
	var op40_m1 := api.execute_classic(ClassicActionDefinition.new(0, -40, 40, 0, true, [1, 1, 41, 0, 0]), "op40.m1")
	var op40_m2 := api.execute_classic(ClassicActionDefinition.new(0, -40, 40, 0, true, [1, 2, 42, 0, 0]), "op40.m2")
	var op40_m3 := api.execute_classic(ClassicActionDefinition.new(0, -40, 40, 0, true, [1, 3, 43, 0, 0]), "op40.m3")
	assert_true(op40_m0.state == ScenarioRuntimeOperationResult.State.COMPLETED and op40_m0.value == true and op40_m0.directive.kind == ScenarioVmDirective.FINISH_TIMELINE and op40_m0.events.is_empty(), "opcode 40 mode 0 finishes timeline without Keep Codes")
	assert_true(op40_m0_inactive.state == ScenarioRuntimeOperationResult.State.COMPLETED and op40_m0_inactive.value == true and op40_m0_inactive.directive.kind == ScenarioVmDirective.FINISH_TIMELINE and op40_m0_inactive.events.is_empty(), "opcode 40 mode 0 with required-state 2 and inactive condition finishes timeline with true result")
	assert_true(op40_m1.directive.kind == ScenarioVmDirective.BRANCH_XAP and op40_m1.directive.target_id == 41 and op40_m1.directive.gosub == true, "opcode 40 mode 1 branches to XAP with signed GOSUB")
	assert_true(op40_m2.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and op40_m2.directive.encounter_kind == &"simple" and op40_m2.directive.target_id == 42 and op40_m2.directive.gosub == true, "opcode 40 mode 2 branches to Simple encounter with signed GOSUB")
	assert_true(op40_m3.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and op40_m3.directive.encounter_kind == &"complex" and op40_m3.directive.target_id == 43 and op40_m3.directive.gosub == true, "opcode 40 mode 3 branches to Complex encounter with signed GOSUB")
	var op40_program := ScenarioProgramDefinition.new("prog.op40_m0", &"trigger", "op40", [
		ClassicActionDefinition.new(0, 40, 40, 0, false, [1, 0, 0, 0, 0]),
		ClassicActionDefinition.new(1, 84, 84, 401, false, []),
	])
	var vm_op40 := ScenarioVm.new(); vm_op40.configure(ScenarioDefinition.new([op40_program], []))
	vm_op40.start_program(op40_program.id, ScenarioExecutionContext.trigger(&"action", "ap.op40_m0"))
	var res_op40 := vm_op40.run(api)
	assert_true(res_op40.state == ScenarioVmResult.State.COMPLETED and not res_op40.events.any(func(e: DomainEvent) -> bool: return e.kind == &"classic_control_marker" and e.payload.get("operandId") == 401) and not _event_has(res_op40.events, &"action_point_kept") and vm_op40.snapshot().halted, "opcode 40 mode 0 finishes timeline without executing following slot or emitting action_point_kept")
	var slot7_program := ScenarioProgramDefinition.new("prog.dropout_slot7", &"trigger", "slot7", [
		ClassicActionDefinition.new(0, 58, 58, 0, false, [1, 1, -1, 0, 0]),
		ClassicActionDefinition.new(1, 84, 84, 991, false, []),
		ClassicActionDefinition.new(2, 84, 84, 992, false, []),
		ClassicActionDefinition.new(3, 84, 84, 993, false, []),
		ClassicActionDefinition.new(4, 84, 84, 994, false, []),
		ClassicActionDefinition.new(5, 84, 84, 995, false, []),
		ClassicActionDefinition.new(6, 84, 84, 996, false, []),
		ClassicActionDefinition.new(7, 84, 84, 777, false, []),
	])
	var vm_slot7 := ScenarioVm.new(); vm_slot7.configure(ScenarioDefinition.new([slot7_program], []))
	vm_slot7.start_program(slot7_program.id, ScenarioExecutionContext.trigger(&"action", "ap.dropout_slot7"))
	var res_slot7 := vm_slot7.run(api)
	assert_true(res_slot7.state == ScenarioVmResult.State.COMPLETED and res_slot7.events.any(func(e: DomainEvent) -> bool: return e.kind == &"classic_control_marker" and e.payload.get("operandId") == 777) and not res_slot7.events.any(func(e: DomainEvent) -> bool: return e.kind == &"classic_control_marker" and e.payload.get("operandId") == 991), "destination mode -1 executes slot 7 and skips intermediate slots")
	var op33_program := ScenarioProgramDefinition.new("prog.op33_unpaid", &"trigger", "op33", [
		ClassicActionDefinition.new(0, 33, 33, 0, false, [50000, -1, 0, 0, 0]),
		ClassicActionDefinition.new(1, 84, 84, 991, false, []),
		ClassicActionDefinition.new(2, 84, 84, 992, false, []),
		ClassicActionDefinition.new(3, 84, 84, 993, false, []),
		ClassicActionDefinition.new(4, 84, 84, 994, false, []),
		ClassicActionDefinition.new(5, 84, 84, 995, false, []),
		ClassicActionDefinition.new(6, 84, 84, 996, false, []),
		ClassicActionDefinition.new(7, 84, 84, 337, false, []),
	])
	var vm_op33 := ScenarioVm.new(); vm_op33.configure(ScenarioDefinition.new([op33_program], []))
	vm_op33.start_program(op33_program.id, ScenarioExecutionContext.trigger(&"action", "ap.op33_unpaid"))
	var res_op33 := vm_op33.run(api)
	assert_true(res_op33.state == ScenarioVmResult.State.COMPLETED and res_op33.events.any(func(e: DomainEvent) -> bool: return e.kind == &"classic_control_marker" and e.payload.get("operandId") == 337) and not res_op33.events.any(func(e: DomainEvent) -> bool: return e.kind == &"classic_control_marker" and e.payload.get("operandId") == 991), "opcode 33 unpaid test mode -1 executes slot 7 and skips intermediate slots")
	var caller_prog := ScenarioProgramDefinition.new("prog.caller", &"trigger", "caller", [
		ClassicActionDefinition.new(0, -42, 42, 0, true, [100, 1, 0, 50, 0]),
		ClassicActionDefinition.new(1, 84, 84, 888, false, []),
	])
	var callee_prog := ScenarioProgramDefinition.new("xap:50", &"extra-action-point", "50", [
		ClassicActionDefinition.new(0, 58, 58, 0, false, [1, 1, 3, 0, 0]),
	])
	var vm_nested := ScenarioVm.new(); vm_nested.configure(ScenarioDefinition.new([caller_prog, callee_prog], []))
	vm_nested.start_program(caller_prog.id, ScenarioExecutionContext.trigger(&"action", "ap.nested_keep"))
	var res_nested := vm_nested.run(api)
	assert_true(res_nested.state == ScenarioVmResult.State.COMPLETED and _event_has(res_nested.events, &"action_point_kept") and not res_nested.events.any(func(e: DomainEvent) -> bool: return e.kind == &"classic_control_marker" and e.payload.get("operandId") == 888) and vm_nested.snapshot().halted, "destination mode 3 Keep Codes finishes the entire timeline from a nested GOSUB call without returning to the caller frame"); var opcode44_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("opcode44.hero", "Opcode 44 Hero", 10, 10)]), RealmzClock.new()); var opcode44_api := RealmzRuntimeApi.new(content, opcode44_state, RealmzRng.for_oracle(44), ScenarioActionState.new()); var opcode44_without_loaded := opcode44_api.execute_classic(ClassicActionDefinition.new(0, 44, 44, 4, false, []), "opcode44.simple.without-complex", ScenarioExecutionContext.encounter(&"simple", 0)); assert_true(opcode44_without_loaded.state == ScenarioRuntimeOperationResult.State.COMPLETED and opcode44_without_loaded.events.any(func(event: DomainEvent) -> bool: return event.kind == &"classic_global_complex_result_mutation" and not event.payload.get("loadedComplexEncounter") and not event.payload.get("mutatedLoadedRecord")) and not opcode44_state.scenario_progress.encounters.complex_result_is_eliminated(0, 3), "opcode 44 in a Simple result completes without mutating an unloaded Castle Complex record"); var opcode44_loaded := opcode44_api.request_classic_encounter(&"complex", 0, "opcode44.load-complex", ScenarioExecutionContext.trigger(&"action", "ap.opcode44.load-complex")); var opcode44_with_loaded := opcode44_api.execute_classic(ClassicActionDefinition.new(0, 44, 44, 4, false, []), "opcode44.simple.with-complex", ScenarioExecutionContext.encounter(&"simple", 0)); assert_true(opcode44_loaded.state == ScenarioRuntimeOperationResult.State.WAITING and opcode44_with_loaded.state == ScenarioRuntimeOperationResult.State.COMPLETED and opcode44_with_loaded.events.any(func(event: DomainEvent) -> bool: return event.kind == &"classic_global_complex_result_mutation" and event.payload.get("loadedComplexEncounter") and event.payload.get("mutatedLoadedRecord") and event.payload.get("encounterId") == 0) and opcode44_state.scenario_progress.encounters.complex_result_is_eliminated(0, 3), "opcode 44 in a Simple result mutates the last Castle-loaded Complex record")


func _test_state_and_progression_branch_opcodes(content: RealmzContent) -> void:
	var races := content.characters.race_definitions(); var castes := content.characters.caste_definitions()
	var hero1 := CharacterState.new("c.b1", "Hero One", 20, 20); hero1.race_id = races[0].id; hero1.caste_id = castes[0].id; hero1.gender = 1; hero1.level = 5
	var hero2 := CharacterState.new("c.b2", "Hero Two", 20, 20); hero2.race_id = races[min(1, races.size() - 1)].id; hero2.caste_id = castes[min(1, castes.size() - 1)].id; hero2.gender = 2; hero2.level = 7
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [hero1, hero2]), RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.for_oracle(1), ScenarioActionState.new())
	var op30_short := api.execute_classic(ClassicActionDefinition.new(0, 30, 30, 0, false, [1, 0, 0, 1]), "op30.short")
	assert_true(op30_short.state == ScenarioRuntimeOperationResult.State.FAILED and op30_short.error_code == &"missing_extra_code", "opcode 30 rejects row with fewer than five extra codes")
	state.scenario_progress.set_quest_value(10, 0)
	var op46_u_branch := api.execute_classic(ClassicActionDefinition.new(0, 46, 46, 0, false, [10, 0, 0, 375, 0]), "op46.u.b")
	state.scenario_progress.set_quest_value(10, 1)
	var op46_u_fall := api.execute_classic(ClassicActionDefinition.new(0, 46, 46, 0, false, [10, 0, 0, 375, 0]), "op46.u.f")
	var op46_s_branch := api.execute_classic(ClassicActionDefinition.new(0, 46, 46, 0, false, [10, 1, 0, 375, 0]), "op46.s.b")
	var op46_force := api.execute_classic(ClassicActionDefinition.new(0, 46, 46, 0, false, [10, 2, 0, 375, 0]), "op46.force")
	state.scenario_progress.set_quest_value(4, 1)
	var op46_gosub := api.execute_classic(ClassicActionDefinition.new(0, -46, 46, 0, true, [4, 1, 0, 206, 0]), "op46.gosub")
	var op46_drop := api.execute_classic(ClassicActionDefinition.new(0, 46, 46, 0, false, [10, 2, -1, 0, 0]), "op46.drop")
	var op46_keep := api.execute_classic(ClassicActionDefinition.new(0, 46, 46, 0, false, [10, 2, 3, 0, 0]), "op46.keep")
	var simp_ctx := ScenarioExecutionContext.encounter(&"simple", 5, "", -1, &"choice", 0)
	var comp_ctx := ScenarioExecutionContext.encounter(&"complex", 6, "", -1, &"choice", 0)
	var op46_simp := api.execute_classic(ClassicActionDefinition.new(0, 46, 46, 0, false, [10, 2, 1, 2, 3]), "op46.simp", simp_ctx)
	var op46_comp := api.execute_classic(ClassicActionDefinition.new(0, 46, 46, 0, false, [10, 2, 2, 1, 4]), "op46.comp", comp_ctx)
	var op46_wrath := api.execute_classic(ClassicActionDefinition.new(0, 46, 46, 0, false, [274, 274, 304, 30003, 420]), "op46.wrath489")
	var op46_bad_mode := api.execute_classic(ClassicActionDefinition.new(0, 46, 46, 0, false, [10, 2, 9, 0, 0]), "op46.bad_mode")
	var op46_short := api.execute_classic(ClassicActionDefinition.new(0, 46, 46, 0, false, [10, 2]), "op46.short")
	assert_true(op46_u_branch.directive.kind == ScenarioVmDirective.BRANCH_XAP and op46_u_branch.directive.target_id == 375 and op46_u_fall.directive == null and op46_u_fall.value == false and op46_s_branch.directive.kind == ScenarioVmDirective.BRANCH_XAP and op46_force.directive.kind == ScenarioVmDirective.BRANCH_XAP and op46_gosub.directive.gosub == true and op46_gosub.directive.target_id == 206, "opcode 46 evaluates condition selectors 0, 1, 2 and signed GOSUB")
	assert_true(op46_drop.directive.kind == ScenarioVmDirective.DROPOUT and op46_keep.directive.kind == ScenarioVmDirective.FINISH_TIMELINE and _event_has(op46_keep.events, &"action_point_kept") and op46_simp.directive.kind == ScenarioVmDirective.BRANCH_PROGRAM and op46_simp.directive.program_id == "simple:5:result:2" and op46_comp.directive.kind == ScenarioVmDirective.BRANCH_PROGRAM and op46_comp.directive.program_id == "complex:6:result:1", "opcode 46 handles dropout, keep-codes, and simple/complex encounter result branch modes")
	assert_true(op46_wrath.state == ScenarioRuntimeOperationResult.State.COMPLETED and op46_wrath.value == false and op46_bad_mode.error_code == &"unsupported_branch_mode" and op46_short.error_code == &"missing_extra_code", "opcode 46 safely completes out-of-bounds rows and types invalid modes/lengths")
	state.scenario_progress.set_quest_value(16, 1); state.scenario_progress.set_quest_value(17, 1)
	var op72_all_set := api.execute_classic(ClassicActionDefinition.new(0, 72, 72, 0, false, [16, 17, 0, 0, 899]), "op72.all")
	state.scenario_progress.set_quest_value(17, 0)
	var op72_part_set := api.execute_classic(ClassicActionDefinition.new(0, 72, 72, 0, false, [16, 17, 0, 0, 899]), "op72.part")
	var op72_inverted := api.execute_classic(ClassicActionDefinition.new(0, 72, 72, 0, false, [20, 10, 0, 0, 899]), "op72.inv")
	var op72_simp := api.execute_classic(ClassicActionDefinition.new(0, -72, 72, 0, true, [16, 16, 0, 1, 15]), "op72.simp")
	var op72_comp := api.execute_classic(ClassicActionDefinition.new(0, 72, 72, 0, false, [16, 16, 0, 2, 25]), "op72.comp")
	var op72_bad_rng := api.execute_classic(ClassicActionDefinition.new(0, 72, 72, 0, false, [-1, 10, 0, 0, 899]), "op72.bad")
	var op72_short := api.execute_classic(ClassicActionDefinition.new(0, 72, 72, 0, false, [16, 17]), "op72.short")
	assert_true(op72_all_set.directive.kind == ScenarioVmDirective.BRANCH_XAP and op72_all_set.directive.target_id == 899 and op72_part_set.directive == null and op72_part_set.value == false and op72_inverted.directive.kind == ScenarioVmDirective.BRANCH_XAP and op72_simp.directive.kind == ScenarioVmDirective.ENTER_ENCOUNTER and op72_simp.directive.encounter_kind == &"simple" and op72_simp.directive.gosub == true and op72_comp.directive.encounter_kind == &"complex", "opcode 72 evaluates all-set, fallthrough, inverted-range vacuous truth, and destination modes")
	assert_true(op72_bad_rng.error_code == &"invalid_quest_range" and op72_short.error_code == &"missing_extra_code", "opcode 72 types invalid quest range and short extra code")
	state.scenario_progress.set_quest_value(8, 5)
	var op77_true := api.execute_classic(ClassicActionDefinition.new(0, -77, 77, 0, true, [8, 3, 0, 0, 383]), "op77.t")
	var op77_dual_f := api.execute_classic(ClassicActionDefinition.new(0, 77, 77, 0, false, [8, 10, 0, 100, 200]), "op77.df")
	var op77_dual_t := api.execute_classic(ClassicActionDefinition.new(0, 77, 77, 0, false, [8, 5, 0, 100, 200]), "op77.dt")
	var op77_zero_t := api.execute_classic(ClassicActionDefinition.new(0, 77, 77, 0, false, [8, 5, 0, 100, 0]), "op77.zt")
	var op77_zero_f := api.execute_classic(ClassicActionDefinition.new(0, 77, 77, 0, false, [8, 10, 0, 0, 200]), "op77.zf")
	var op77_simp := api.execute_classic(ClassicActionDefinition.new(0, 77, 77, 0, false, [8, 5, 1, 0, 50]), "op77.simp")
	var op77_comp := api.execute_classic(ClassicActionDefinition.new(0, 77, 77, 0, false, [8, 5, 2, 0, 60]), "op77.comp")
	var op77_bad_q := api.execute_classic(ClassicActionDefinition.new(0, 77, 77, 0, false, [100, 5, 0, 0, 1]), "op77.bad")
	var op77_short := api.execute_classic(ClassicActionDefinition.new(0, 77, 77, 0, false, [8, 5]), "op77.short")
	assert_true(op77_true.directive.kind == ScenarioVmDirective.BRANCH_XAP and op77_true.directive.target_id == 383 and op77_true.directive.gosub == true and op77_dual_f.directive.target_id == 100 and op77_dual_t.directive.target_id == 200 and op77_zero_t.directive == null and op77_zero_t.value == true and op77_zero_f.directive == null and op77_zero_f.value == false and op77_simp.directive.target_id == 50 and op77_comp.directive.target_id == 60, "opcode 77 evaluates threshold, signed GOSUB, dual targets, encounter targets, and zero-target fallthrough")
	assert_true(op77_bad_q.error_code == &"invalid_quest" and op77_short.error_code == &"missing_extra_code", "opcode 77 types invalid quest index and short extra code")
	state.scenario_progress.set_selected_character_ids([hero1.id])
	var c1_classic: int = castes[0].classic_id; var c2_classic: int = castes[min(1, castes.size() - 1)].classic_id
	var op86_caste_t := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [0, c1_classic, 0, 796, 0]), "op86.c.t")
	var op86_caste_sel_t := api.execute_classic(ClassicActionDefinition.new(0, -86, 86, 0, true, [0, -c1_classic, 0, 796, 0]), "op86.c.st")
	var op86_caste_sel_f := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [0, -c2_classic, 0, 796, 0]), "op86.c.sf")
	var op86_race_war := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [1, 12, 0, 2816, 0]), "op86.war2815")
	var op86_gen_t := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [2, 1, 0, 10, 20]), "op86.g.t")
	var op86_gen_f := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [2, 99, 0, 10, 20]), "op86.g.f")
	state.party_in_boat = true; var op86_boat := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [3, 0, 0, 1998, 0]), "op86.boat")
	state.party_camping = true; var op86_camp := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [4, 0, 0, 1999, 0]), "op86.camp")
	var c_class: int = castes[0].caste_class
	var op86_cclass_t := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [5, c_class, 0, 50, 0]), "op86.cc.t")
	var op86_cclass_sel_f := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [5, -999, 0, 50, 0]), "op86.cc.sf")
	var desc_race: RaceDefinition = null; var desc_bit := 1; var absent_bit := 1
	for r: RaceDefinition in races:
		if r.descriptor_flags != 0:
			desc_race = r
			for b: int in range(1, 33):
				if (r.descriptor_flags & (1 << (b - 1))) != 0 and desc_bit == 1:
					desc_bit = b
				elif (r.descriptor_flags & (1 << (b - 1))) == 0 and absent_bit == 1:
					absent_bit = b
			break
	if desc_race != null:
		hero1.race_id = desc_race.id
	var op86_desc_t := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [6, desc_bit, 0, 60, 0]), "op86.d.t")
	var op86_desc_f := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [6, absent_bit, 0, 60, 0]), "op86.d.f")
	var op86_tot_lvl_t := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [7, 10, 0, 70, 0]), "op86.tl.t")
	var op86_tot_lvl_f := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [7, 15, 0, 70, 0]), "op86.tl.f")
	var op86_sel_lvl_t := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [8, 4, 0, 80, 0]), "op86.sl.t")
	var op86_sel_lvl_f := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [8, 6, 0, 80, 0]), "op86.sl.f")
	var op86_simp := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [3, 0, 1, 11, 0]), "op86.s")
	var op86_comp := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [3, 0, 2, 21, 0]), "op86.c")
	var op86_bad_kind := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [9, 0, 0, 0, 0]), "op86.bad_kind")
	var op86_bad_desc := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [6, 33, 0, 0, 0]), "op86.bad_desc")
	var op86_short := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [0, 1]), "op86.short")
	assert_true(op86_caste_t.directive.target_id == 796 and op86_caste_sel_t.directive.target_id == 796 and op86_caste_sel_t.directive.gosub == true and op86_caste_sel_f.directive == null and op86_race_war.directive == null and op86_gen_t.directive.target_id == 10 and op86_gen_f.directive.target_id == 20, "opcode 86 matches caste, race, gender, negative selected expectations, and target routing")
	assert_true(op86_boat.directive.target_id == 1998 and op86_camp.directive.target_id == 1999 and op86_cclass_t.directive.target_id == 50 and op86_cclass_sel_f.directive == null and (desc_race == null or (op86_desc_t.directive.target_id == 60 and op86_desc_f.directive == null)), "opcode 86 evaluates boat, camp, caste class, and race descriptor bits")
	assert_true(op86_tot_lvl_t.directive.target_id == 70 and op86_tot_lvl_f.directive == null and op86_sel_lvl_t.directive.target_id == 80 and op86_sel_lvl_f.directive == null and op86_simp.directive.target_id == 11 and op86_comp.directive.target_id == 21, "opcode 86 evaluates party/selected level sums and simple/complex encounter destinations")
	assert_true(op86_bad_kind.error_code == &"invalid_misc_branch" and op86_bad_desc.error_code == &"invalid_race_descriptor" and op86_short.error_code == &"missing_extra_code", "opcode 86 types invalid test kinds, out-of-range descriptors, and short rows")


func _runtime_api(content: RealmzContent, action_state: ScenarioActionState) -> RealmzRuntimeApi:
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("test", "Test", 1, 1)])
	return RealmzRuntimeApi.new(content, GameState.new(party, RealmzClock.new()), RealmzRng.new(1), action_state)
func _action(id: String, return_type: StringName, instructions: Array[SafeInstructionDefinition], capabilities: Array[String] = []) -> ScenarioActionDefinition:
	return ScenarioActionDefinition.new(id, id, "test", &"public", &"test", 1, 1, 1, [], return_type, [&"action"], capabilities, &"safe", SafeProgramDefinition.new(instructions))
func _literal(value: Variant) -> SafeExpressionDefinition:
	var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.LITERAL)
	expression.value = value
	return expression


func _variable(scope: StringName, name: String) -> SafeExpressionDefinition:
	var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.VARIABLE)
	expression.scope = scope
	expression.name = name
	return expression


func _aging_race(content: RealmzContent) -> RaceDefinition:
	for race: RaceDefinition in content.characters.race_definitions():
		if race.max_age > 0 and race.age_range(1).x == race.age_range(0).y + 1:
			return race
	return null


func _trace_has(trace: Array[Dictionary], event_name: String) -> bool:
	for entry: Dictionary in trace:
		if entry.get("event") == event_name:
			return true
	return false


func _event_has(events: Array[DomainEvent], kind: StringName) -> bool:
	for event: DomainEvent in events:
		if event.kind == kind:
			return true
	return false


func _test_half_truth_random_water_branch() -> void:
	var loaded := load_test_package("res://src/storage/packages/bundled_campaigns/scenario-half-truth.realmz2")
	if not loaded.is_ok():
		return
	var content: RealmzContent = loaded.content
	var state := GameState.new(PartyState.new("land:1", Vector2i(80, 4), [CharacterState.new("half-truth.water.hero", "Water Hero", 10, 10)]), RealmzClock.new())
	state.last_move_direction = Vector2i.UP
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(108), ScenarioActionState.new())
	var program := content.scenario.program_by_id("xap:108")
	assert_not_null(program, "Half Truth exposes the authored random-region water check")
	if program == null:
		return
	var action := program.instruction_at(0) as ClassicActionDefinition
	assert_not_null(action, "Half Truth random-region water check retains its Classic action")
	if action == null:
		return
	var result := api.execute_classic(action, "half-truth.xap-108")
	var checked := result.events[0] as DomainEvent if not result.events.is_empty() else null
	assert_equal([action.opcode, action.extra_code, result.state, result.value, result.directive, checked.payload.get("x") if checked != null else -1, checked.payload.get("y") if checked != null else -1], [78, [7, 182, 0, 109, 0], ScenarioRuntimeOperationResult.State.COMPLETED, true, null, 80, 4], "Half Truth's repeated water check reads the party's current cell, so a safe tile does not branch to the freezing-water XAP when the previous movement direction points at a neighboring wall")


func _test_opcode_59_current_cell(content: RealmzContent) -> void:
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("tile.hero", "Tile Hero", 10, 10)]), RealmzClock.new())
	state.last_move_direction = Vector2i.RIGHT
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(59), ScenarioActionState.new())
	var result := api.execute_classic(ClassicActionDefinition.new(0, 59, 59, 0, false, [32_767, 1, 0, 321, 0]), "tile-defect.coordinate")
	var checked := result.events[0] as DomainEvent if not result.events.is_empty() else null
	assert_equal([checked.payload.get("x") if checked != null else -1, checked.payload.get("y") if checked != null else -1], [state.party.coordinate.x, state.party.coordinate.y], "opcode 59 preserves Castle's current-cell coordinate while retaining its unconditional source-defect branch")
