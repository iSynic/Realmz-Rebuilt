extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const AOGM_OPCODE_INVENTORY_PATH: String = "res://tests/fixtures/oracle/aogm-active-opcode-inventory.json"


func selected_case_arguments() -> Array:
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "Scenario VM fixture loads: %s" % loaded.error_message)
	return [loaded.content] if loaded.is_ok() else []


func run() -> void:
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "Scenario VM fixture loads: %s" % loaded.error_message)
	if not loaded.is_ok():
		return
	var content: RealmzContent = loaded.content
	_test_scenario_wire_contracts()
	_test_public_interaction_matrix(content)
	_test_public_classic_encounter_iterations(content)
	_test_public_thief_encounter(content)
	_test_public_session_resume(content)
	_test_public_vm_combat_auto(content)
	_test_public_continuation_matrix(content)
	_test_public_limits_and_errors(content)
	_test_public_application_transitions(content)
	_test_public_character_checks(content)
	_test_public_action_state(content)
	_test_aogm_dispatch_has_no_fallback(content)


func _test_scenario_wire_contracts() -> void:
	var branch := ScenarioVmDirective.branch_program("xap:7", true, ScenarioExecutionContext.trigger(&"", "ap.fixture"))
	var restored := ScenarioVmDirective.from_data(JSON.parse_string(JSON.stringify(branch.to_data())))
	assert_not_null(restored, "VM directive round-trips through its typed wire contract")
	assert_equal([restored.kind, restored.program_id, restored.gosub, restored.context.to_data()], [ScenarioVmDirective.BRANCH_PROGRAM, "xap:7", true, {"triggerId": "ap.fixture"}], "VM directive preserves branch and trigger state")
	var encounter_context := ScenarioExecutionContext.encounter(&"complex", 2, "", -1, &"choice", 0).set_encounter_attempt(3)
	var encounter_branch := ScenarioVmDirective.branch_encounter_result("complex:2:result:0", false, encounter_context, true)
	var restored_encounter_branch := ScenarioVmDirective.from_data(JSON.parse_string(JSON.stringify(encounter_branch.to_data())))
	assert_equal([restored_encounter_branch.kind, restored_encounter_branch.repeat_encounter, restored_encounter_branch.context.value("encounterAttempt")], [ScenarioVmDirective.BRANCH_ENCOUNTER_RESULT, true, 3], "encounter-result directive preserves its repeat boundary and attempt")
	for malformed: Dictionary in [
		{"kind": "finish", "extra": true},
		{"kind": "branch-xap", "targetId": "7", "gosub": false},
		{"kind": "branch-program", "programId": "", "gosub": false, "context": {}},
	]:
		assert_equal(ScenarioVmDirective.from_data(malformed), null, "VM directive rejects malformed or unknown fields")
	var context := ScenarioExecutionContext.encounter(&"complex", 0, "response.0", 0, &"thief", 0)
	context.set_application_hook(&"shop", "")
	context.set_combatant("monster.0", 0, false, true)
	context.set_thief_action(0, "character.0")
	var context_wire: Dictionary = JSON.parse_string(JSON.stringify(context.to_data()))
	var restored_context := ScenarioExecutionContext.from_data(context_wire)
	assert_not_null(restored_context, "execution context round-trips with zero and false values")
	assert_equal(JSON.parse_string(JSON.stringify(restored_context.to_data())), context_wire, "execution context preserves sparse declared fields")
	var unknown_context := context_wire.duplicate(true)
	unknown_context["unexpected"] = true
	assert_equal(ScenarioExecutionContext.from_data(unknown_context), null, "execution context rejects unknown fields")
	var caller := ScenarioBattleCaller.classic(2, false, 0, 0)
	var handoff := ScenarioRuntimeHandoff.party_defeat("classic.battle.0", ScenarioRuntimeHandoff.CLASSIC_COMBAT, caller)
	var body := SessionContinuation.CombatBody.new()
	body.battle_id = "classic.battle.0"
	body.actor_id = "character.1"
	body.mode = &"explicit"
	body.destination = Vector2i(-100_000, -100_000)
	var contracts: Array[Dictionary] = [
		{"name": "battle caller", "value": caller, "decode": ScenarioBattleCaller.from_data},
		{"name": "encounter continuation", "value": ScenarioRuntimeContinuation.encounter(ScenarioRuntimeContinuation.CLASSIC_SIMPLE_ENCOUNTER, 0, false, [0]), "decode": ScenarioRuntimeContinuation.from_data},
		{"name": "retreat continuation", "value": ScenarioRuntimeContinuation.combat_retreat(ScenarioRuntimeContinuation.CLASSIC_COMBAT_RETREAT, ScenarioRuntimeContinuation.CLASSIC_COMBAT, "classic.battle.0", caller, "character.1", &"explicit", Vector2i(-100_000, -100_000)), "decode": ScenarioRuntimeContinuation.from_data},
		{"name": "VM pending continuation", "value": ScenarioVmPendingContinuation.classic(ScenarioRuntimeContinuation.encounter(ScenarioRuntimeContinuation.CLASSIC_SIMPLE_ENCOUNTER, 0, false, [0])), "decode": ScenarioVmPendingContinuation.from_data},
		{"name": "runtime handoff", "value": handoff, "decode": ScenarioRuntimeHandoff.from_data},
		{"name": "VM handoff", "value": ScenarioVmHandoff.classic(handoff), "decode": ScenarioVmHandoff.from_data},
		{"name": "session retreat", "value": SessionContinuation.combat_state(&"combat-retreat-confirmation", body), "decode": SessionContinuation.from_data},
	]
	for contract: Dictionary in contracts:
		var wire: Dictionary = JSON.parse_string(JSON.stringify(contract.value.to_data()))
		var decoded: Variant = contract.decode.call(wire)
		assert_not_null(decoded, "%s round-trips" % contract.name)
		assert_equal(JSON.parse_string(JSON.stringify(decoded.to_data())), wire, "%s preserves its fields" % contract.name)
		var unknown := wire.duplicate(true)
		unknown["unexpected"] = true
		assert_equal(contract.decode.call(unknown), null, "%s rejects unknown fields" % contract.name)
	var snapshot := ScenarioVmSnapshot.new().to_data()
	snapshot["unexpected"] = true
	assert_equal(ScenarioVmSnapshot.from_data(snapshot), null, "VM snapshots reject unknown fields")


func _test_public_interaction_matrix(content: RealmzContent) -> void:
	var action_state := ScenarioActionState.new()
	var api := _runtime_api(content, action_state)
	var vm := ScenarioVm.new()
	vm.configure(content.scenario)
	assert_equal(vm.start_program("trigger:ap.fixture.encounter", ScenarioExecutionContext.calling(&"action")).state, ScenarioVmResult.State.COMPLETED, "Classic trigger starts through the public VM")
	var waiting := vm.run(api)
	assert_equal([waiting.state, waiting.interaction.kind], [ScenarioVmResult.State.WAITING, &"encounter_choice"], "Simple Encounter yields a typed choice")
	var saved := ScenarioVmSnapshot.from_data(vm.snapshot().to_data())
	assert_not_null(saved, "choice boundary serializes through the public VM snapshot")
	var restored := ScenarioVm.new()
	restored.configure(content.scenario)
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
	var text := api.execute_classic(ClassicActionDefinition.new(0, 1, 1, 1, false, []), "text.positive")
	assert_equal([text.state, text.interaction.kind, text.interaction.body.to_data().get("presentation")], [ScenarioRuntimeOperationResult.State.WAITING, &"acknowledge", "classic-textbox"], "positive message stages the dedicated Classic textbox")
	var wrong := api.resume_classic(text.continuation, InteractionResponse.from_data(text.interaction.request_id, &"yes_no", {"accepted": true}), "text.wrong")
	assert_equal(wrong.error_code, &"invalid_interaction_response", "text continuation rejects an unrelated response shape")
	var acknowledged := api.resume_classic(text.continuation, InteractionResponse.acknowledge(text.interaction), "text.resume")
	assert_equal(acknowledged.state, ScenarioRuntimeOperationResult.State.COMPLETED, "acknowledgement releases the message operation")
	var negative := api.execute_classic(ClassicActionDefinition.new(0, 1, 1, -1, false, []), "text.negative")
	assert_equal([negative.state, negative.events[0].payload.get("classicClick")], [ScenarioRuntimeOperationResult.State.COMPLETED, false], "negative message publishes without inventing a click boundary")


func _test_public_classic_encounter_iterations(content: RealmzContent) -> void:
	var simple_responses: Array[SimpleEncounterResponse] = [
		SimpleEncounterResponse.new("first", "First", "simple:0:result:0"),
		SimpleEncounterResponse.new("second", "Second", "simple:0:result:1"),
		SimpleEncounterResponse.new("third", "Third", "simple:0:result:2"),
	]
	var simple := SimpleEncounterDefinition.new(0, 1, simple_responses, true, 3, 0)
	var complex_texts: Array[String] = ["Wait", "", "", "", "", "", "", "", ""]
	var complex := ComplexEncounterDefinition.new(0, 1, 4, 0, [0, 0, 0, 0, 0, 0, 0, 0], [], [], [], [], true, false, 2, 0, 0, 0, complex_texts)
	var programs: Array[ScenarioProgramDefinition] = [
		ScenarioProgramDefinition.new("root.simple-loop", &"trigger", "simple-loop", [ClassicActionDefinition.new(0, 4, 4, 0, false, [])]),
		ScenarioProgramDefinition.new("simple:0:result:0", &"simple-encounter-result", "0", [ClassicActionDefinition.new(0, 35, 35, 1, false, [])]),
		ScenarioProgramDefinition.new("simple:0:result:1", &"simple-encounter-result", "1", [ClassicActionDefinition.new(0, 35, 35, 2, false, [])]),
		ScenarioProgramDefinition.new("simple:0:result:2", &"simple-encounter-result", "2", []),
		ScenarioProgramDefinition.new("root.complex-loop", &"trigger", "complex-loop", [ClassicActionDefinition.new(0, 5, 5, 0, false, [])]),
		ScenarioProgramDefinition.new("complex:0:result:0", &"complex-encounter-result", "0", []),
		ScenarioProgramDefinition.new("complex:0:result:1", &"complex-encounter-result", "1", []),
		ScenarioProgramDefinition.new("complex:0:result:2", &"complex-encounter-result", "2", [ClassicActionDefinition.new(0, 1, 1, 2, false, [])]),
		ScenarioProgramDefinition.new("complex:0:result:3", &"complex-encounter-result", "3", []),
	]
	var definition := ScenarioDefinition.new(programs, [])
	var iteration_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, definition, [MessageDefinition.new(1, "Choose."), MessageDefinition.new(2, "Time has expired.")], [], [simple], [], [], [], [], [], [], [], [], [complex])

	var simple_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("loop.hero", "Loop Hero", 10, 10)]), RealmzClock.new())
	var simple_rng := RealmzRng.for_oracle(17)
	var simple_vm := ScenarioVm.new()
	simple_vm.configure(definition)
	simple_vm.start_program("root.simple-loop", ScenarioExecutionContext.trigger(&"action", "ap.simple-loop"))
	var simple_api := RealmzRuntimeApi.new(iteration_content, simple_state, simple_rng, ScenarioActionState.new())
	var first_choice := simple_vm.run(simple_api)
	var second_choice := simple_vm.resume(InteractionResponse.from_data(first_choice.interaction.request_id, InteractionRequest.ENCOUNTER_CHOICE, {"index": 0}), simple_api)
	assert_equal([second_choice.state, second_choice.interaction.kind, second_choice.interaction.body.to_data().get("options", []).size(), simple_state.encounter_attempts(&"simple", 0)], [ScenarioVmResult.State.WAITING, InteractionRequest.ENCOUNTER_CHOICE, 2, 1], "Simple Encounter repeats after its result and removes the source-selected option")
	var simple_save := save_round_trip(SessionSnapshot.new(iteration_content.campaign_id, iteration_content.package_hash, iteration_content.rules_version, 1, simple_state, simple_rng.snapshot(), simple_vm.snapshot(), ScenarioActionState.new()))
	assert_not_null(simple_save, "repeating Simple Encounter crosses the save envelope")
	if simple_save != null:
		assert_true(SessionRestoreValidator.validate(iteration_content, simple_save).ok, "repeating Simple Encounter passes transactional restore validation")
		var restored_simple_state := GameState.from_data(simple_save.game_state.to_data())
		var restored_simple_rng := RealmzRng.for_oracle(1)
		assert_true(restored_simple_rng.restore(simple_save.rng_state), "repeating Simple Encounter restores its gameplay RNG")
		var restored_simple_vm := ScenarioVm.new()
		restored_simple_vm.configure(definition)
		assert_true(restored_simple_vm.restore(simple_save.scenario_vm), "repeating Simple Encounter restores its typed VM frame")
		var restored_simple_api := RealmzRuntimeApi.new(iteration_content, restored_simple_state, restored_simple_rng, simple_save.scenario_action_state)
		var third_choice := restored_simple_vm.resume(InteractionResponse.from_data(restored_simple_vm.pending_request().request_id, InteractionRequest.ENCOUNTER_CHOICE, {"index": 0}), restored_simple_api)
		assert_equal([third_choice.state, third_choice.interaction.body.to_data().get("options", []).size()], [ScenarioVmResult.State.WAITING, 1], "restored Simple Encounter continues with its second source option removed")
		var simple_done := restored_simple_vm.resume(InteractionResponse.from_data(third_choice.interaction.request_id, InteractionRequest.ENCOUNTER_CHOICE, {"index": 0}), restored_simple_api)
		assert_equal([simple_done.state, restored_simple_state.encounter_attempts(&"simple", 0)], [ScenarioVmResult.State.COMPLETED, 3], "Simple Encounter exits after the authored maximum number of selections")

	var complex_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("timeout.hero", "Timeout Hero", 10, 10)]), RealmzClock.new())
	var complex_rng := RealmzRng.for_oracle(23)
	var complex_vm := ScenarioVm.new()
	complex_vm.configure(definition)
	complex_vm.start_program("root.complex-loop", ScenarioExecutionContext.trigger(&"action", "ap.complex-loop"))
	var complex_api := RealmzRuntimeApi.new(iteration_content, complex_state, complex_rng, ScenarioActionState.new())
	var complex_choice := complex_vm.run(complex_api)
	var repeated_complex := complex_vm.resume(InteractionResponse.from_data(complex_choice.interaction.request_id, InteractionRequest.WORD_AND_ACTION, {"action": "choice", "slot": 0}), complex_api)
	assert_equal([repeated_complex.state, repeated_complex.interaction.kind, complex_state.encounter_attempts(&"complex", 0)], [ScenarioVmResult.State.WAITING, InteractionRequest.WORD_AND_ACTION, 1], "Complex Encounter repeats after a nonfinal fallback result")
	var complex_save := save_round_trip(SessionSnapshot.new(iteration_content.campaign_id, iteration_content.package_hash, iteration_content.rules_version, 1, complex_state, complex_rng.snapshot(), complex_vm.snapshot(), ScenarioActionState.new()))
	assert_not_null(complex_save, "repeating Complex Encounter crosses the save envelope")
	if complex_save != null:
		assert_true(SessionRestoreValidator.validate(iteration_content, complex_save).ok, "repeating Complex Encounter passes transactional restore validation")
		var restored_complex_state := GameState.from_data(complex_save.game_state.to_data())
		var restored_complex_rng := RealmzRng.for_oracle(1)
		assert_true(restored_complex_rng.restore(complex_save.rng_state), "repeating Complex Encounter restores its gameplay RNG")
		var restored_complex_vm := ScenarioVm.new()
		restored_complex_vm.configure(definition)
		assert_true(restored_complex_vm.restore(complex_save.scenario_vm), "repeating Complex Encounter restores its typed VM frame")
		var restored_complex_api := RealmzRuntimeApi.new(iteration_content, restored_complex_state, restored_complex_rng, complex_save.scenario_action_state)
		var timeout := restored_complex_vm.resume(InteractionResponse.from_data(restored_complex_vm.pending_request().request_id, InteractionRequest.WORD_AND_ACTION, {"action": "choice", "slot": 0}), restored_complex_api)
		assert_equal([timeout.state, timeout.interaction.kind, timeout.interaction.body.to_data().get("messageId"), restored_complex_state.encounter_attempts(&"complex", 0)], [ScenarioVmResult.State.WAITING, InteractionRequest.ACKNOWLEDGE, 2, 2], "final Complex fallback routes to Castle's authored timeout result")
		assert_equal(restored_complex_vm.resume(InteractionResponse.acknowledge(timeout.interaction), restored_complex_api).state, ScenarioVmResult.State.COMPLETED, "Complex timeout result exits the encounter loop")

	var cancelled_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("cancel.hero", "Cancel Hero", 10, 10)]), RealmzClock.new())
	var cancelled_vm := ScenarioVm.new()
	cancelled_vm.configure(definition)
	cancelled_vm.start_program("root.complex-loop", ScenarioExecutionContext.trigger(&"action", "ap.complex-cancel"))
	var cancelled_api := RealmzRuntimeApi.new(iteration_content, cancelled_state, RealmzRng.for_oracle(29), ScenarioActionState.new())
	var cancel_first := cancelled_vm.run(cancelled_api)
	var cancel_repeat := cancelled_vm.resume(InteractionResponse.from_data(cancel_first.interaction.request_id, InteractionRequest.WORD_AND_ACTION, {"action": "choice", "slot": 0}), cancelled_api)
	var cancelled := cancelled_vm.resume(InteractionResponse.from_data(cancel_repeat.interaction.request_id, InteractionRequest.WORD_AND_ACTION, {"action": "back"}), cancelled_api)
	assert_equal([cancelled.state, cancelled_state.encounter_attempts(&"complex", 0)], [ScenarioVmResult.State.COMPLETED, 1], "backing out exits a repeating Complex Encounter without consuming another attempt")


func _test_public_thief_encounter(content: RealmzContent) -> void:
	var character := CharacterState.new("thief.hero", "Locksmith", 12, 12)
	character.set_ability_value(7, 90)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [character]), RealmzClock.new())
	var rng := RealmzRng.for_oracle(7)
	var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new())
	var vm := ScenarioVm.new()
	vm.configure(content.scenario)
	assert_equal(vm.start_program("trigger:ap.fixture.complex", ScenarioExecutionContext.calling(&"action")).state, ScenarioVmResult.State.COMPLETED, "Complex Encounter fixture starts through the public VM")
	var complex := vm.run(api)
	var complex_actions: Array = complex.interaction.body.to_data().get("actions", []) if complex.interaction != null else []
	assert_equal([complex.state, complex.interaction.kind, complex_actions.filter(func(value: Dictionary) -> bool: return value.get("kind") == "thief").size()], [ScenarioVmResult.State.WAITING, InteractionRequest.WORD_AND_ACTION, 1], "Complex Encounter exposes one dedicated Thief action rather than eight host-authored shortcuts")
	var thief := vm.resume(InteractionResponse.from_data(complex.interaction.request_id, InteractionRequest.WORD_AND_ACTION, {"action": "thief"}), api)
	assert_equal([thief.state, thief.interaction.kind if thief.interaction != null else &""], [ScenarioVmResult.State.WAITING, InteractionRequest.THIEF_ENCOUNTER], "Thief opens its source-shaped character and action workspace")
	if thief.interaction == null:
		return
	var pick_lock := vm.resume(InteractionResponse.from_data(thief.interaction.request_id, InteractionRequest.THIEF_ENCOUNTER, {"action": "attempt", "characterId": character.id, "actionIndex": 2}), api)
	assert_equal([pick_lock.state, pick_lock.interaction.kind if pick_lock.interaction != null else &"", rng.snapshot().draw_count], [ScenarioVmResult.State.WAITING, InteractionRequest.PICK_LOCK, 0], "Pick Lock previews its timed tumbler sequence without advancing gameplay RNG")
	if pick_lock.interaction == null:
		return
	var lock_body := pick_lock.interaction.body as InteractionRequest.PickLockRequestBody
	assert_not_null(lock_body, "Pick Lock request uses its strict typed body")
	if lock_body == null:
		return
	assert_equal([lock_body.chance_percent, lock_body.time_limit_frames], [90, 210], "Disarm Trap reads Castle spec[7] and retains the final static countdown second")
	var saved := ScenarioVmSnapshot.from_data(JSON.parse_string(JSON.stringify(vm.snapshot().to_data())))
	assert_not_null(saved, "Pick Lock request and issuing continuation serialize at the modal boundary")
	if saved == null:
		return
	var envelope := SessionSnapshot.new(content.campaign_id, content.package_hash, content.rules_version, 1, state, rng.snapshot(), saved, ScenarioActionState.new())
	assert_true(SessionRestoreValidator.validate(content, envelope).ok, "Pick Lock pending state passes the complete transactional restore validator")
	var forged_wire := saved.to_data()
	forged_wire["pendingRequest"]["data"]["payload"]["frames"][0][0] = 208
	var forged_vm := ScenarioVmSnapshot.from_data(forged_wire)
	assert_not_null(forged_vm, "forged Pick Lock preview remains structurally valid wire data")
	if forged_vm != null:
		var forged_envelope := SessionSnapshot.new(content.campaign_id, content.package_hash, content.rules_version, 1, state, rng.snapshot(), forged_vm, ScenarioActionState.new())
		assert_false(SessionRestoreValidator.validate(content, forged_envelope).ok, "restore rejects a structurally valid Pick Lock preview that does not match authoritative RNG state")
	var restored_state := GameState.from_data(state.to_data())
	var restored_rng := RealmzRng.for_oracle(1)
	assert_true(restored_rng.restore(rng.snapshot()), "Pick Lock restores the source RNG position separately from presentation frames")
	var restored_api := RealmzRuntimeApi.new(content, restored_state, restored_rng, ScenarioActionState.new())
	var restored_vm := ScenarioVm.new()
	restored_vm.configure(content.scenario)
	assert_true(restored_vm.restore(saved), "Pick Lock restores through the public VM snapshot")
	var selected_frame := lock_body.frames.size() - 1
	var resolved := restored_vm.resume(InteractionResponse.from_data(saved.pending_request.request_id, InteractionRequest.PICK_LOCK, {"frameIndex": selected_frame}), restored_api)
	assert_equal([resolved.state, resolved.interaction.kind if resolved.interaction != null else &""], [ScenarioVmResult.State.WAITING, InteractionRequest.ACKNOWLEDGE], "the fixture's nonpositive thief text adds no click before entering the authored Complex result")
	assert_true(restored_rng.snapshot().draw_count > 0, "Committed Pick Lock replays the selected frame prefix through session-owned RNG")
	assert_equal(restored_state.party.character_by_id(character.id).experience, 600, "successful interactive thief action awards 300 experience per authored tumbler")
	var resolution: DomainEvent = null
	for event: DomainEvent in resolved.events:
		if event.kind == &"thief_action_resolved":
			resolution = event
			break
	assert_not_null(resolution, "Pick Lock publishes one source-ordered action result")
	if resolution != null:
		assert_equal([resolution.payload.get("succeeded"), resolution.payload.get("frameIndex"), resolution.payload.get("positions"), resolution.payload.get("classicClick")], [true, selected_frame, lock_body.frames[selected_frame], false], "committed result matches the selected frame and preserves the signed non-click text")
	var scout := CharacterState.new("thief.scout", "Scout", 12, 12)
	scout.set_ability_value(5, 100)
	var scout_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [scout]), RealmzClock.new())
	var scout_api := RealmzRuntimeApi.new(content, scout_state, RealmzRng.for_oracle(1), ScenarioActionState.new())
	var scout_vm := ScenarioVm.new()
	scout_vm.configure(content.scenario)
	assert_equal(scout_vm.start_program("trigger:ap.fixture.complex", ScenarioExecutionContext.calling(&"action")).state, ScenarioVmResult.State.COMPLETED, "non-lock thief proof starts through the same public VM")
	var scout_complex := scout_vm.run(scout_api)
	var scout_thief := scout_vm.resume(InteractionResponse.from_data(scout_complex.interaction.request_id, InteractionRequest.WORD_AND_ACTION, {"action": "thief"}), scout_api)
	scout_vm.resume(InteractionResponse.from_data(scout_thief.interaction.request_id, InteractionRequest.THIEF_ENCOUNTER, {"action": "attempt", "characterId": scout.id, "actionIndex": 0}), scout_api)
	assert_equal(scout_state.party.character_by_id(scout.id).experience, 0, "successful non-lock thief actions do not inherit Pick Lock experience")

	var source_complex := content.complex_encounter_by_id(0)
	var source_thief := content.thief_encounter_by_id(source_complex.thief_success) if source_complex != null else null
	assert_true(source_complex != null and source_thief != null, "Thief loop fixture provides its source definitions")
	if source_complex == null or source_thief == null:
		return
	var loop_texts := source_complex.action_labels()
	loop_texts.append(source_complex.expected_word())
	var loop_complex := ComplexEncounterDefinition.new(source_complex.id, source_complex.prompt_message_id, source_complex.action_result, source_complex.word_result, source_complex.groups(), source_complex.spell_ids(), source_complex.spell_results(), source_complex.item_ids(), source_complex.item_results(), source_complex.can_back_out, source_complex.thief, 2, source_complex.caste_success, source_complex.thief_success, source_complex.thief_fail, loop_texts)
	var loop_programs: Array[ScenarioProgramDefinition] = [ScenarioProgramDefinition.new("root.thief-loop", &"trigger", "thief-loop", [ClassicActionDefinition.new(0, 5, 5, loop_complex.id, false, [])])]
	for outcome_index: int in 4:
		loop_programs.append(ScenarioProgramDefinition.new("complex:%d:result:%d" % [loop_complex.id, outcome_index], &"complex-encounter-result", str(outcome_index), []))
	var loop_definition := ScenarioDefinition.new(loop_programs, [])
	var loop_messages: Array[MessageDefinition] = [content.message_by_id(absi(loop_complex.prompt_message_id))]
	var loop_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, loop_definition, loop_messages, [], [], [], [], [], [], [], [], [], [], [loop_complex], [source_thief])
	var loop_character := CharacterState.new("thief.loop", "Loop Thief", 12, 12)
	loop_character.set_ability_value(5, 100)
	loop_character.set_ability_value(6, 100)
	var loop_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [loop_character]), RealmzClock.new())
	var loop_rng := RealmzRng.for_oracle(31)
	var loop_vm := ScenarioVm.new()
	loop_vm.configure(loop_definition)
	loop_vm.start_program("root.thief-loop", ScenarioExecutionContext.trigger(&"action", "ap.thief-loop"))
	var loop_api := RealmzRuntimeApi.new(loop_content, loop_state, loop_rng, ScenarioActionState.new())
	var loop_complex_choice := loop_vm.run(loop_api)
	var loop_thief_choice := loop_vm.resume(InteractionResponse.from_data(loop_complex_choice.interaction.request_id, InteractionRequest.WORD_AND_ACTION, {"action": "thief"}), loop_api)
	var repeated_after_thief := loop_vm.resume(InteractionResponse.from_data(loop_thief_choice.interaction.request_id, InteractionRequest.THIEF_ENCOUNTER, {"action": "attempt", "characterId": loop_character.id, "actionIndex": 0}), loop_api)
	assert_equal([repeated_after_thief.state, repeated_after_thief.interaction.kind, loop_state.encounter_attempts(&"complex", loop_complex.id)], [ScenarioVmResult.State.WAITING, InteractionRequest.WORD_AND_ACTION, 1], "Thief result returns to its source Complex Encounter while selections remain")
	var loop_save := save_round_trip(SessionSnapshot.new(loop_content.campaign_id, loop_content.package_hash, loop_content.rules_version, 1, loop_state, loop_rng.snapshot(), loop_vm.snapshot(), ScenarioActionState.new()))
	assert_true(loop_save != null and SessionRestoreValidator.validate(loop_content, loop_save).ok, "repeating Thief result passes the complete save validator")
	if loop_save != null:
		var restored_loop_state := GameState.from_data(loop_save.game_state.to_data())
		var restored_loop_rng := RealmzRng.for_oracle(1)
		restored_loop_rng.restore(loop_save.rng_state)
		var restored_loop_vm := ScenarioVm.new()
		restored_loop_vm.configure(loop_definition)
		assert_true(restored_loop_vm.restore(loop_save.scenario_vm), "repeating Thief result restores its VM attempt")
		var restored_loop_api := RealmzRuntimeApi.new(loop_content, restored_loop_state, restored_loop_rng, loop_save.scenario_action_state)
		var restored_thief_choice := restored_loop_vm.resume(InteractionResponse.from_data(restored_loop_vm.pending_request().request_id, InteractionRequest.WORD_AND_ACTION, {"action": "thief"}), restored_loop_api)
		var finished_thief := restored_loop_vm.resume(InteractionResponse.from_data(restored_thief_choice.interaction.request_id, InteractionRequest.THIEF_ENCOUNTER, {"action": "attempt", "characterId": loop_character.id, "actionIndex": 1}), restored_loop_api)
		assert_equal([finished_thief.state, restored_loop_state.encounter_attempts(&"complex", loop_complex.id)], [ScenarioVmResult.State.COMPLETED, 2], "restored Thief result exits after the final Complex selection")


func _test_public_session_resume(content: RealmzContent) -> void:
	var session := GameSession.new()
	session.start(content, 1)
	_begin_fixture_adventure(session, content)
	_restore_fixture_position(session, content, "land:1", Vector2i(0, 1))
	var waiting := session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
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
	var battle := content.battle_by_id("classic.battle.0")
	assert_not_null(battle, "VM Auto fixture provides a Classic battle")
	if battle == null:
		return
	var original_scenario := content.scenario
	var battle_action := ClassicActionDefinition.new(0, 48, 48, battle.classic_id, false, [battle.classic_id, 0, 0, 0, 0])
	var program := ScenarioProgramDefinition.new("fixture.vm-combat-auto", &"application-hook", "start-game", [battle_action])
	content.scenario = ScenarioDefinition.new([program], [], ScenarioApplicationHooks.new(program.id, "", "", "", ""))
	var sixth_id := "fixture.vm-auto.6"
	var inactive_session := _vm_combat_auto_session(content, 1)
	var active_session := _vm_combat_auto_session(content, 12)
	assert_true(inactive_session != null and active_session != null, "public VM combat fixture provides inactive and active sixth-member turns")
	if inactive_session == null or active_session == null:
		content.scenario = original_scenario
		return
	assert_equal([inactive_session.view().combat_view.active_actor_id == sixth_id, active_session.view().combat_view.active_actor_id == sixth_id], [false, true], "fixed fixture seeds cover inactive and active sixth-member turns")
	for member: CharacterView in active_session.view().party_members:
		if member.id != sixth_id: active_session.submit_intent(PlayerIntent.set_combat_auto(member.id, true))
	_assert_vm_combat_auto_round_trip(content, inactive_session, sixth_id, "inactive")
	_assert_vm_combat_auto_round_trip(content, active_session, sixth_id, "active")
	content.scenario = original_scenario


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
	var moved := aged.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal(moved.interaction.kind, InteractionRequest.AGE_UPDATE, "age update yields before destination AP work")
	var held := save_round_trip(aged.snapshot())
	assert_not_null(held, "nested age and post-move continuation is saveable")
	if held != null:
		var resumed := GameSession.new()
		assert_equal(resumed.restore(content, held).state, SessionStep.State.COMPLETED, "nested continuation restores")
		var encounter := resumed.respond(InteractionResponse.age_update(resumed.view().pending_interaction))
		assert_equal(encounter.interaction.kind, InteractionRequest.ENCOUNTER_CHOICE, "age acknowledgement resumes destination trigger discovery")
	var keep_definition := ScenarioDefinition.new([ScenarioProgramDefinition.new("keep", &"trigger", "keep", [ClassicActionDefinition.new(0, 24, 24, 0, false, [])])], [])
	var keep_vm := ScenarioVm.new()
	keep_vm.configure(keep_definition)
	keep_vm.start_program("keep", ScenarioExecutionContext.trigger(&"action", "ap.fixture.keep"))
	var keep := keep_vm.run(_runtime_api(content, ScenarioActionState.new()))
	assert_equal([keep.state, _event_has(keep.events, &"action_point_kept")], [ScenarioVmResult.State.COMPLETED, true], "opcode 24 returns the Keep Codes result through the VM")
	var transfer_definition := ScenarioDefinition.new([
		ScenarioProgramDefinition.new("root", &"trigger", "root", [ClassicActionDefinition.new(0, 39, 39, 0, false, [])]),
		ScenarioProgramDefinition.new("xap:0", &"extra-action-point", "0", [ClassicActionDefinition.new(0, 25, 25, 0, false, []), ClassicActionDefinition.new(1, 111, 111, 0, false, [])]),
	], [])
	var transfer_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("context", "Context", 1, 1)]), RealmzClock.new())
	var transfer_vm := ScenarioVm.new()
	transfer_vm.configure(transfer_definition)
	transfer_vm.start_program("root", ScenarioExecutionContext.trigger(&"action", "ap.fixture.message", content.start_map_id))
	var transferred := transfer_vm.run(RealmzRuntimeApi.new(content, transfer_state, RealmzRng.new(1), ScenarioActionState.new()))
	assert_equal(transferred.state, ScenarioVmResult.State.COMPLETED, "opcode 39 returns through the transferred XAP")
	assert_true(transfer_state.world.trigger_is_disabled("ap.fixture.message"), "opcode 25 retains the issuing AP origin")


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
	var unknown := ScenarioDefinition.new([ScenarioProgramDefinition.new("root", &"trigger", "root", [ClassicActionDefinition.new(0, 999, 999, 0, false, [])])], [])
	var unknown_vm := ScenarioVm.new()
	unknown_vm.configure(unknown)
	unknown_vm.start_program("root", ScenarioExecutionContext.calling(&"action"))
	assert_equal(unknown_vm.run(_runtime_api(content, ScenarioActionState.new())).error_code, &"unsupported_classic_opcode", "unknown opcodes never fall through to dynamic GDScript")


func _test_public_application_transitions(content: RealmzContent) -> void:
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var map := content.world.player_map_by_classic_id(1)
	assert_not_null(map, "fixture exposes a source-backed player map")
	if map == null:
		return
	var acquired := api.execute_classic(ClassicActionDefinition.new(0, 29, 29, 1, false, []), "map.acquire")
	assert_equal([acquired.state, state.world.has_map(map.id)], [ScenarioRuntimeOperationResult.State.COMPLETED, true], "opcode 29 acquires a stable player-map identity")
	var shown := api.execute_classic(ClassicActionDefinition.new(0, 29, 29, -1, false, []), "map.show")
	assert_equal([shown.state, shown.interaction.kind, shown.interaction.body.to_data().get("playerMapId")], [ScenarioRuntimeOperationResult.State.WAITING, &"acknowledge", map.id], "negative opcode 29 stages the player-map presentation")
	var forged := api.resume_classic(shown.continuation, InteractionResponse.from_data(shown.interaction.request_id, &"acknowledge", {"accepted": true}), "map.forged")
	assert_equal(forged.error_code, &"invalid_interaction_response", "player-map acknowledgement rejects forged fields")
	var resumed := api.resume_classic(shown.continuation, InteractionResponse.acknowledge(shown.interaction), "map.resume")
	assert_equal(resumed.state, ScenarioRuntimeOperationResult.State.COMPLETED, "player-map acknowledgement resumes its issuing operation")
	var unavailable := api.execute_classic(ClassicActionDefinition.new(0, 29, 29, 19, false, []), "map.unknown")
	assert_equal(unavailable.error_code, &"unknown_player_map", "unknown player-map identities fail explicitly")


func _test_public_character_checks(content: RealmzContent) -> void:
	var first := CharacterState.new("ability.first", "First", 10, 10)
	var second := CharacterState.new("ability.second", "Second", 10, 10)
	first.set_ability_value(5, 40)
	second.set_ability_value(5, 5)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [first, second]), RealmzClock.new())
	var rng := ScriptedRng.new([0, 13_107, 26_214, 1_311, 16_057, 30_802])
	var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new())
	var missing := api.execute_classic(ClassicActionDefinition.new(0, 31, 31, 0, false, [5, 0, 0, 12]), "ability.missing")
	assert_equal(missing.error_code, &"missing_extra_code", "opcode 31 rejects incomplete Extra Code rows")
	var waiting := api.execute_classic(ClassicActionDefinition.new(0, 31, 31, 0, false, [5, 0, 0, 12, 13]), "ability.pick")
	assert_equal([waiting.state, waiting.interaction.kind, waiting.interaction.body.to_data().get("eligible").size()], [ScenarioRuntimeOperationResult.State.WAITING, &"character_selection", 2], "opcode 31 yields a typed character picker")
	assert_equal(waiting.interaction.body.to_data()["eligible"][0], {"id": first.id, "name": first.name, "currentHealth": 10, "maximumHealth": 10}, "opcode 31 carries the living character facts rendered by the typed picker")
	var chosen := api.resume_classic(waiting.continuation, InteractionResponse.from_data(waiting.interaction.request_id, &"character_selection", {"characterIds": [first.id]}), "ability.resume")
	assert_equal([chosen.directive.target_id, state.selected_character_ids()], [12, [first.id]], "opcode 31 resumes through the selected character and authored branch")
	var third := CharacterState.new("ability.third", "Third", 10, 10)
	third.brawn = 22
	first.brawn = 2
	second.brawn = 12
	state.party.add_character(third)
	var filter_api := RealmzRuntimeApi.new(content, state, ScriptedRng.new([0, 13_107, 26_214]), ScenarioActionState.new())
	var filtered := filter_api.execute_classic(ClassicActionDefinition.new(0, 30, 30, 0, false, [0, 0, 2, 1, 0]), "ability.filter")
	assert_equal(filtered.value, [first.id, second.id, third.id], "opcode 30 evaluates the iterated characters through the public API")


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


func _begin_fixture_adventure(session: GameSession, content: RealmzContent) -> void:
	var races := content.race_definitions()
	var castes := content.caste_definitions()
	assert_false(races.is_empty() or castes.is_empty(), "fixture has playable race and caste data")
	if races.is_empty() or castes.is_empty():
		return
	var character := CharacterState.new("fixture.party.member", "Fixture Hero", 10, 10)
	character.race_id = races[0].id
	character.caste_id = castes[0].id
	var imported := session.submit_intent(PlayerIntent.import_vault_character(character.id, "1".repeat(64), character, "fixture", content.package_hash))
	assert_equal(imported.state, SessionStep.State.COMPLETED, "fixture imports a deterministic party member")
	var started := session.submit_intent(PlayerIntent.begin_adventure())
	if content.scenario.application_hook_program_id(ScenarioApplicationHooks.START_GAME).is_empty():
		assert_equal(started.state, SessionStep.State.COMPLETED, "fixture begins without a Start Game interaction")
	else:
		assert_equal(started.state, SessionStep.State.WAITING_FOR_INTERACTION, "fixture reaches the Start Game interaction")
		assert_equal(session.respond(InteractionResponse.acknowledge(started.interaction)).state, SessionStep.State.COMPLETED, "fixture completes its Start Game interaction")


func _vm_combat_auto_session(content: RealmzContent, seed: int) -> GameSession:
	var races := content.race_definitions(); var castes := content.caste_definitions()
	if races.is_empty() or castes.is_empty(): return null
	var session := GameSession.new(); session.start(content, seed)
	for character_index: int in 6:
		var character := CharacterState.new("fixture.vm-auto.%d" % (character_index + 1), "VM Auto Hero %d" % (character_index + 1), 100, 100); character.race_id = races[0].id; character.caste_id = castes[0].id
		var imported := session.submit_intent(PlayerIntent.import_vault_character(character.id, "1".repeat(64), character, "fixture", content.package_hash))
		if imported.state != SessionStep.State.COMPLETED: return null
	var entered := session.submit_intent(PlayerIntent.begin_adventure())
	if entered.state != SessionStep.State.WAITING_FOR_INTERACTION or entered.interaction == null or entered.interaction.kind != InteractionRequest.COMBAT:
		return null
	if session.view().party_members.size() != 6 or session.view().combat_view == null:
		return null
	return session


func _assert_vm_combat_auto_round_trip(content: RealmzContent, session: GameSession, character_id: String, phase: String) -> void:
	var enabled := session.submit_intent(PlayerIntent.set_combat_auto(character_id, true))
	assert_equal([enabled.state, enabled.error_code, enabled.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, &"", InteractionRequest.COMBAT], "the %s sixth member enables persistent Auto through VM combat" % phase)
	assert_true(_event_has(enabled.events, &"combat_auto_changed"), "%s VM Auto publishes the committed change" % phase)
	var body := enabled.interaction.body as InteractionRequest.CombatRequestBody
	assert_true(body != null and body.auto_character_ids.has(character_id) and (phase != "active" or body.auto_character_ids.size() == 6), "the next %s VM combat request projects sixth-member Auto after one activation" % phase)
	var saved := save_round_trip(session.snapshot())
	assert_not_null(saved, "%s sixth-member Auto crosses the save envelope" % phase)
	if saved == null:
		return
	var restored := GameSession.new()
	assert_equal(restored.restore(content, saved).state, SessionStep.State.COMPLETED, "%s sixth-member Auto restores with its VM continuation" % phase)
	assert_true(restored.view().combat_view.auto_character_ids.has(character_id), "restored %s VM combat retains sixth-member Auto" % phase)
	var disabled_id := restored.view().combat_view.active_actor_id if phase == "active" else character_id
	var disabled := restored.submit_intent(PlayerIntent.set_combat_auto(disabled_id, false))
	assert_equal([disabled.state, disabled.error_code, disabled.interaction.kind, restored.view().combat_view.auto_character_ids.has(disabled_id)], [SessionStep.State.WAITING_FOR_INTERACTION, &"", InteractionRequest.COMBAT, false], "restored %s VM combat disables Auto at the next activation boundary" % phase)


func _restore_fixture_position(session: GameSession, content: RealmzContent, map_id: String, coordinate: Vector2i) -> void:
	var envelope := session.snapshot()
	envelope.game_state.party.map_id = map_id
	envelope.game_state.party.coordinate = coordinate
	assert_equal(session.restore(content, envelope).state, SessionStep.State.COMPLETED, "fixture position changes through validated restore")


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
	for race: RaceDefinition in content.race_definitions():
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
