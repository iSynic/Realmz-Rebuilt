extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const AOGM_OPCODE_INVENTORY_PATH: String = "res://tests/fixtures/oracle/aogm-active-opcode-inventory.json"


func run() -> void:
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "Scenario VM fixture loads: %s" % loaded.error_message)
	if not loaded.is_ok():
		return
	_test_classic_encounter_action_xap_trace(loaded.content)
	_test_classic_choice_labels_and_sound_wait(loaded.content)
	_test_session_save_resume_boundary(loaded.content)
	_test_age_update_precedes_post_move(loaded.content)
	_test_safe_choice_resume(loaded.content)
	_test_persistent_action_state(loaded.content)
	_test_classic_call_limit(loaded.content)
	_test_classic_transfer_keeps_trigger_context(loaded.content)
	_test_classic_keep_codes(loaded.content)
	_test_action_call_limit(loaded.content)
	_test_execution_step_limit(loaded.content)
	_test_unknown_opcode_failure(loaded.content)
	_test_classic_opcode_ownership()
	_test_gameplay_capabilities_and_battle_resume(loaded.content)
	_test_complex_encounter_save_resume(loaded.content)
	_test_equipment_storage_save_resume(loaded.content)
	_test_program_replacement_and_redirect(loaded.content)
	_test_scenario_spell_opcodes(loaded.content)
	_test_monster_aging_attack_continuations(loaded.content)
	_test_monster_status_attack_flow(loaded.content)
	_test_monster_resource_drain_flow(loaded.content)
	_test_monster_charm_and_affliction_flow(loaded.content)
	_test_combat_fumble_mutation(loaded.content)
	_test_classic_encounter_break(loaded.content)
	_test_classic_party_shift(loaded.content)
	_test_classic_game_time_mutation(loaded.content)
	_test_classic_game_time_branch(loaded.content)
	_test_classic_camping_availability(loaded.content)
	_test_classic_ally_branch(loaded.content)
	_test_classic_misc_branch(loaded.content)
	_test_classic_party_backup(loaded.content)
	_test_classic_map_darkness(loaded.content)
	_test_classic_teleport_and_recheck(loaded.content)
	_test_classic_quest_values(loaded.content)
	_test_registration_marker(loaded.content)
	_test_classic_party_mode(loaded.content)
	_test_scrolling_text_event(loaded.content)
	_test_classic_shop_configuration(loaded.content)
	_test_classic_priest_turning(loaded.content)
	_test_classic_experience_loss_and_drop(loaded.content)
	_test_classic_character_money_loss(loaded.content)
	_test_classic_battle_macro_controls(loaded.content)
	_test_classic_selected_character_alteration(loaded.content)
	_test_classic_combat_monster_alteration(loaded.content)
	_test_classic_ally_participation(loaded.content)
	_test_classic_bodycount_selection(loaded.content)
	_test_classic_spellcasting_flags(loaded.content)
	_test_classic_identity_selection(loaded.content)
	_test_classic_monster_route(loaded.content)
	_test_classic_random_items(loaded.content)
	_test_classic_selected_level_up(loaded.content)
	_test_classic_death_macro_revival(loaded.content)
	_test_automatic_monster_death_macro(loaded.content)
	_test_aogm_dispatch_has_no_fallback(loaded.content)
	_test_classic_shell_domain_route(loaded.content)


func _test_classic_encounter_action_xap_trace(content: RealmzContent) -> void:
	var action_state := ScenarioActionState.new()
	var api := _runtime_api(content, action_state)
	var vm := ScenarioVm.new()
	vm.configure(content.scenario)
	assert_equal(vm.start_program("trigger:ap.fixture.encounter", {"callingContext": "action"}).state, ScenarioVmResult.State.COMPLETED, "typed trigger program starts")
	var yielded := vm.run(api)
	assert_equal(yielded.state, ScenarioVmResult.State.WAITING, "negative Classic encounter opcode yields through the VM")
	assert_equal(yielded.interaction.kind, &"encounter_choice", "Simple Encounter exposes a typed interaction")
	assert_equal(yielded.interaction.payload["prompt"], "Will you follow the Scenario Action route?", "interaction carries compiled prompt text")
	var saved := ScenarioVmSnapshot.from_data(vm.snapshot().to_data())
	assert_not_null(saved, "VM continuation serializes at the interaction boundary")
	var restored := ScenarioVm.new()
	restored.configure(content.scenario)
	assert_true(restored.restore(saved), "VM continuation restores against the same immutable scenario")
	var resumed := restored.resume(InteractionResponse.new(saved.pending_request.request_id, &"encounter_choice", {"index": 0}), api)
	assert_equal(resumed.state, ScenarioVmResult.State.WAITING, "positive Classic result text pauses the VM at a serializable textbox")
	assert_equal(resumed.interaction.kind, &"acknowledge", "Classic result text requires an explicit acknowledgement")
	var message_texts := _message_texts(resumed.events)
	var action_text := restored.resume(InteractionResponse.new(resumed.interaction.request_id, &"acknowledge", {}), api)
	assert_equal(action_text.state, ScenarioVmResult.State.WAITING, "execution resumes through the Scenario Action and pauses at the positive XAP text")
	message_texts.append_array(_message_texts(action_text.events))
	var completed := restored.resume(InteractionResponse.new(action_text.interaction.request_id, &"acknowledge", {}), api)
	message_texts.append_array(_message_texts(completed.events))
	assert_equal(completed.state, ScenarioVmResult.State.COMPLETED, "the second textbox acknowledgement reaches CODE 111")
	assert_equal(message_texts, ["The encounter result begins.", "The reusable Scenario Action ran.", "The Extra Action Point returns through CODE 111."], "ordinary timeline order surrounds the reusable Scenario Action call")
	assert_true(_trace_has(restored.trace(), "call-action"), "VM trace records the Scenario Action frame")
	assert_true(_trace_has(restored.trace(), "classic-transfer"), "VM trace records the XAP transfer")
	assert_true(_trace_has(restored.trace(), "classic-return"), "VM trace records CODE 111 return")


func _test_classic_choice_labels_and_sound_wait(content: RealmzContent) -> void:
	var api := _runtime_api(content, ScenarioActionState.new())
	var default_choice := api.execute_classic(ClassicActionDefinition.new(0, 3, 3, 0, false, [1, 0, 0, 0, 2]), "request.default-choice")
	assert_equal(default_choice.state, ScenarioRuntimeOperationResult.State.WAITING, "Classic opcode 3 yields a typed yes/no request")
	assert_equal(default_choice.interaction.payload["yesLabel"], "Yes", "zero Classic option ID uses the standard Yes label")
	assert_equal(default_choice.interaction.payload["noLabel"], "No", "a zero first Classic option ID selects the complete standard Yes/No pair")
	var authored_choice := api.execute_classic(ClassicActionDefinition.new(0, 3, 3, 0, false, [1, 0, 0, 1, 2]), "request.authored-choice")
	assert_equal(authored_choice.state, ScenarioRuntimeOperationResult.State.WAITING, "authored Classic choice labels remain a serializable interaction")
	assert_equal(authored_choice.interaction.payload["yesLabel"], "Proceed", "Classic option IDs resolve through the Data OD option-label table")
	assert_equal(authored_choice.interaction.payload["noLabel"], "Turn back", "Classic option labels do not alias ordinary scenario messages")
	var blocking_sound := api.execute_classic(ClassicActionDefinition.new(0, 9, 9, -10001, false, []), "request.blocking-sound")
	assert_equal(blocking_sound.events[0].payload["soundId"], 10001, "Classic sound lookup uses the absolute resource ID")
	assert_true(blocking_sound.events[0].payload["waitForCompletion"], "negative Classic sound IDs preserve the blocking playback flag")
	var asynchronous_sound := api.execute_classic(ClassicActionDefinition.new(0, 9, 9, 10049, false, []), "request.asynchronous-sound")
	assert_equal(asynchronous_sound.events[0].payload["soundId"], 10049, "positive Classic sounds retain their resource identity")
	assert_false(asynchronous_sound.events[0].payload["waitForCompletion"], "positive Classic sound IDs preserve asynchronous playback")
	var positive_text := api.execute_classic(ClassicActionDefinition.new(0, 1, 1, 1, false, []), "request.positive-text")
	assert_equal(positive_text.state, ScenarioRuntimeOperationResult.State.WAITING, "positive Classic message IDs preserve textbox click pacing")
	assert_equal(positive_text.interaction.kind, &"acknowledge", "positive Classic text uses the typed acknowledgement ABI")
	assert_equal(positive_text.interaction.payload["presentation"], "classic-textbox", "presentation can select the dedicated Classic textbox without inspecting VM state")
	assert_equal(positive_text.events[0].payload["classicClick"], true, "the message event retains Castle's click evidence")
	var wrong_text_response := api.resume_classic(positive_text.continuation, InteractionResponse.new(positive_text.interaction.request_id, &"yes_no", {"accepted": true}), "request.positive-text.resume")
	assert_equal(wrong_text_response.error_code, &"invalid_interaction_response", "Classic textbox continuation rejects unrelated response shapes")
	var acknowledged_text := api.resume_classic(positive_text.continuation, InteractionResponse.new(positive_text.interaction.request_id, &"acknowledge", {}), "request.positive-text.resume")
	assert_equal(acknowledged_text.state, ScenarioRuntimeOperationResult.State.COMPLETED, "acknowledging a Classic textbox releases the issuing opcode")
	var negative_text := api.execute_classic(ClassicActionDefinition.new(0, 1, 1, -1, false, []), "request.negative-text")
	assert_equal(negative_text.state, ScenarioRuntimeOperationResult.State.COMPLETED, "negative Classic message IDs publish text without adding a click boundary")
	assert_false(negative_text.events[0].payload["classicClick"], "negative message events preserve Castle's no-click evidence")


func _test_session_save_resume_boundary(content: RealmzContent) -> void:
	var session := GameSession.new()
	session.start(content, 1)
	_begin_fixture_adventure(session, content)
	_restore_fixture_position(session, content, "land:1", Vector2i(0, 1))
	var waiting := session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal(waiting.state, SessionStep.State.WAITING_FOR_INTERACTION, "GameSession publishes the VM interaction after committing movement")
	assert_equal(session.view().party_coordinate, Vector2i(1, 1), "movement is committed before presentation chooses")
	var held := session.snapshot()
	assert_not_null(held, "pending player interaction is a committed save boundary")
	assert_not_null(held.scenario_vm.pending_request, "save aggregate owns the pending VM request")
	assert_equal(held.session_continuation["activeTriggerId"], "ap.fixture.encounter", "save aggregate owns host continuation after the VM returns")
	var saves := SaveRepository.new("user://realmz2-tests/phase3-vm-saves")
	assert_true(saves.save(content.campaign_id, "encounter", held), "pending VM save passes transactional verification: %s" % saves.last_error)
	var reloaded := saves.load(content.campaign_id, "encounter", content.package_hash)
	assert_not_null(reloaded, "pending VM save reloads from disk: %s" % saves.last_error)
	if reloaded == null:
		return
	var restored := GameSession.new()
	assert_equal(restored.restore(content, reloaded).state, SessionStep.State.COMPLETED, "GameSession restores the VM and post-move continuation transactionally")
	var request: InteractionRequest = restored.view().pending_interaction
	var result_text := restored.respond(InteractionResponse.new(request.request_id, &"encounter_choice", {"index": 0}))
	assert_equal(result_text.state, SessionStep.State.WAITING_FOR_INTERACTION, "encounter response reaches the result's committed Classic textbox boundary")
	var message_texts := _message_texts(result_text.events)
	var textbox_save := SaveEnvelope.from_data(restored.snapshot().to_data())
	assert_not_null(textbox_save, "Classic textbox continuation survives the complete save envelope")
	var textbox_restored := GameSession.new()
	assert_equal(textbox_restored.restore(content, textbox_save).state, SessionStep.State.COMPLETED, "GameSession restores a positive Classic textbox transactionally")
	var action_text := textbox_restored.respond(InteractionResponse.new(textbox_restored.view().pending_interaction.request_id, &"acknowledge", {}))
	assert_equal(action_text.state, SessionStep.State.WAITING_FOR_INTERACTION, "first acknowledgement advances to the later positive XAP textbox")
	message_texts.append_array(_message_texts(action_text.events))
	var completed := textbox_restored.respond(InteractionResponse.new(action_text.interaction.request_id, &"acknowledge", {}))
	message_texts.append_array(_message_texts(completed.events))
	assert_equal(completed.state, SessionStep.State.COMPLETED, "typed acknowledgements resume simulation without presentation mutation: %s %s" % [completed.error_code, completed.error_message])
	assert_equal(message_texts, ["The encounter result begins.", "The reusable Scenario Action ran.", "The Extra Action Point returns through CODE 111."], "restored interactions follow the same action timeline")
	assert_equal(textbox_restored.snapshot().session_continuation, {}, "completed action timeline clears the serialized host continuation")


func _test_age_update_precedes_post_move(content: RealmzContent) -> void:
	var source := GameSession.new()
	source.start(content, 1)
	_begin_fixture_adventure(source, content)
	_restore_fixture_position(source, content, "land:1", Vector2i(0, 1))
	var boundary := source.snapshot()
	var character := boundary.game_state.party.characters()[0]
	var race := _aging_race(content)
	character.race_id = race.id
	character.age_group = 1
	character.age_days = race.age_range(1).x * 365 - 1
	boundary.game_state.clock.advance_minutes(RealmzClock.MINUTES_PER_DAY - 1 - boundary.game_state.clock.total_minutes())
	var session := GameSession.new()
	assert_equal(session.restore(content, boundary).state, SessionStep.State.COMPLETED, "the pre-midnight AP fixture restores")
	var moved := session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal(moved.interaction.kind, InteractionRequest.AGE_UPDATE, "the Castle age dialog blocks before destination AP execution")
	assert_equal(session.snapshot().session_continuation["resumeKind"], "post-move", "the age dialog owns the unstarted post-move continuation")
	var held := SaveEnvelope.from_data(session.snapshot().to_data())
	assert_not_null(held, "the age-before-AP boundary serializes with its nested topology continuation")
	var restored := GameSession.new()
	assert_equal(restored.restore(content, held).state, SessionStep.State.COMPLETED, "the nested age/post-move continuation validates transactionally")
	var encounter := restored.respond(InteractionResponse.age_update(restored.view().pending_interaction))
	assert_equal(encounter.state, SessionStep.State.WAITING_FOR_INTERACTION, "acknowledging age resumes destination trigger discovery")
	assert_equal(encounter.interaction.kind, InteractionRequest.ENCOUNTER_CHOICE, "the original AP then reaches its ordinary encounter interaction")


func _test_classic_shell_domain_route(content: RealmzContent) -> void:
	var session := GameSession.new()
	session.start(content, 1)
	_begin_fixture_adventure(session, content)
	_restore_fixture_position(session, content, "land:1", Vector2i(0, 1))
	var encounter := session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal(encounter.interaction.kind, &"encounter_choice", "synthetic shell route enters the ordinary Simple Encounter picker")
	assert_not_null(SaveEnvelope.from_data(session.snapshot().to_data()), "encounter picker is a serializable committed boundary")
	var resolved_encounter := session.respond(InteractionResponse.new(encounter.interaction.request_id, &"encounter_choice", {"index": 0}))
	while resolved_encounter.state == SessionStep.State.WAITING_FOR_INTERACTION and resolved_encounter.interaction.kind == &"acknowledge":
		resolved_encounter = session.respond(InteractionResponse.new(resolved_encounter.interaction.request_id, &"acknowledge", {}))
	assert_equal(resolved_encounter.state, SessionStep.State.COMPLETED, "synthetic encounter result and Scenario Action return before the next domain")

	var battle := session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal(battle.interaction.kind, &"combat_action", "battle AP enters the typed combat presenter contract")
	assert_not_null(SaveEnvelope.from_data(session.snapshot().to_data()), "combat interaction and VM continuation serialize together")
	var combat_steps: int = 0
	while session.view().pending_interaction != null and combat_steps < 32:
		var request := session.view().pending_interaction
		var targets: Array = request.payload.get("targets", [])
		var payload := {"actorId": String(request.payload.get("actorId", "")), "action": "defend", "targetId": ""}
		if not targets.is_empty():
			payload = {"actorId": String(request.payload.get("actorId", "")), "action": "attack", "targetId": String(targets[0].get("id", ""))}
		session.respond(InteractionResponse.new(request.request_id, &"combat_action", payload))
		combat_steps += 1
	assert_true(combat_steps < 32, "synthetic battle reaches a committed outcome without presentation-driven advancement")
	assert_true(session.view().pending_interaction == null, "combat completion clears only its genuine interaction boundary")

	var shop := session.submit_intent(PlayerIntent.move(Vector2i.DOWN))
	assert_equal(shop.interaction.kind, &"shop_action", "shop AP exposes typed stock, party, and leave actions")
	assert_true(shop.interaction.payload.get("stock") is Array and shop.interaction.payload.get("characters") is Array, "shop request carries detached purchase and sale read models")
	assert_not_null(SaveEnvelope.from_data(session.snapshot().to_data()), "shop interaction serializes through the same VM frame")
	assert_equal(session.respond(InteractionResponse.new(shop.interaction.request_id, &"shop_action", {"action": "leave"})).state, SessionStep.State.COMPLETED, "leaving the shop resumes and completes the AP")

	var temple := session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_equal(temple.interaction.kind, &"temple_action", "temple AP exposes a typed service request")
	assert_true(temple.interaction.payload.get("characters") is Array, "temple request is presentation-ready without core access")
	assert_equal(session.respond(InteractionResponse.new(temple.interaction.request_id, &"temple_action", {"action": "leave"})).state, SessionStep.State.COMPLETED, "leaving the temple resumes the AP")

	var bank := session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_equal(bank.interaction.kind, &"bank_action", "bank AP exposes typed carried and deposited wealth")
	assert_true(bank.interaction.payload.has("carriedGold") and bank.interaction.payload.has("bankedGold"), "bank presenter receives only detached wealth values")
	assert_not_null(SaveEnvelope.from_data(session.snapshot().to_data()), "bank interaction is a committed save boundary")
	assert_equal(session.respond(InteractionResponse.new(bank.interaction.request_id, &"bank_action", {"action": "leave", "amount": 0})).state, SessionStep.State.COMPLETED, "leaving the bank resumes the AP")


func _test_complex_encounter_save_resume(content: RealmzContent) -> void:
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("test", "Test", 5, 5)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var vm := ScenarioVm.new()
	vm.configure(content.scenario)
	assert_equal(vm.start_program("trigger:ap.fixture.complex", {"callingContext": "action"}).state, ScenarioVmResult.State.COMPLETED, "Complex Encounter trigger starts through the ordinary VM")
	var waiting := vm.run(api)
	assert_equal(waiting.state, ScenarioVmResult.State.WAITING, "Classic opcode 5 yields a typed Complex Encounter")
	assert_equal(waiting.interaction.kind, &"complex_encounter", "Complex Encounter uses one serializable interaction contract")
	var saved := ScenarioVmSnapshot.from_data(vm.snapshot().to_data())
	var restored := ScenarioVm.new()
	restored.configure(content.scenario)
	assert_true(restored.restore(saved), "Complex Encounter continuation survives JSON-shaped save restoration")
	var result_text := restored.resume(InteractionResponse.new(waiting.interaction.request_id, &"complex_encounter", {"action": "choice", "slot": 0}), api)
	assert_equal(result_text.state, ScenarioVmResult.State.WAITING, "Complex response branches to the result's positive Classic textbox: %s" % result_text.error_message)
	assert_equal(_message_texts(result_text.events), ["The encounter result begins."], "Complex result executes through the same action timeline as APs and Simple Encounters")
	var completed := restored.resume(InteractionResponse.new(result_text.interaction.request_id, &"acknowledge", {}), api)
	assert_equal(completed.state, ScenarioVmResult.State.COMPLETED, "acknowledging Complex result text completes the result program")
	assert_equal(state.encounter_attempts(&"complex", 0), 1, "Complex resolution commits attempt state inside GameSession data")


func _test_safe_choice_resume(content: RealmzContent) -> void:
	var choice := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.OPERATION)
	choice.capability = "core.presentation.choice"
	choice.result_target = "selected"
	choice.set_arguments({"prompt": _literal("Choose safely"), "options": _array([_literal("One"), _literal("Two")])})
	var finish := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.RETURN)
	finish.value = _variable(&"local", "selected")
	var remember := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.SET_VALUE)
	remember.scope = &"persistent"
	remember.name = "selected"
	remember.value = _variable(&"local", "selected")
	var action := _action("scenario.test.choose", &"int", [choice, remember, finish], ["core.presentation.choice"])
	var call := CallScenarioActionInstruction.new(action.id)
	var definition := ScenarioDefinition.new([ScenarioProgramDefinition.new("root", &"trigger", "root", [call])], [action])
	var action_state := ScenarioActionState.new()
	var api := _runtime_api(content, action_state)
	var vm := ScenarioVm.new()
	vm.configure(definition)
	vm.start_program("root", {"callingContext": "action"})
	var waiting := vm.run(api)
	assert_equal(waiting.state, ScenarioVmResult.State.WAITING, "Safe Scenario Action can yield a typed choice")
	assert_equal(waiting.interaction.kind, &"scenario_choice", "Safe choice uses its own typed request contract")
	var restored := ScenarioVm.new()
	restored.configure(definition)
	assert_true(restored.restore(ScenarioVmSnapshot.from_data(vm.snapshot().to_data())), "Safe Action frame and local continuation restore")
	var completed := restored.resume(InteractionResponse.new(waiting.interaction.request_id, &"scenario_choice", {"index": 1}), api)
	assert_equal(completed.state, ScenarioVmResult.State.COMPLETED, "Safe Action resumes through the issuing frame")
	assert_equal(action_state.read("campaign", action.id, "selected"), 1, "typed choice result resumes into the issuing Safe Action frame")


func _test_persistent_action_state(content: RealmzContent) -> void:
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
	var action_state := ScenarioActionState.new()
	var vm := ScenarioVm.new()
	vm.configure(definition)
	vm.start_program("root", {"callingContext": "action"})
	var completed := vm.run(_runtime_api(content, action_state))
	assert_equal(completed.state, ScenarioVmResult.State.COMPLETED, "persistent Safe Action completes")
	assert_equal(action_state.read("campaign", action.id, "visits"), 42, "persistent write is namespaced to the Scenario Action")
	assert_equal(action_state.read("campaign", action.id, "mirror"), 42, "persistent Safe variable reads through the session-owned action state")
	var parsed_state: Variant = JSON.parse_string(JSON.stringify(action_state.to_data()))
	var restored_state := ScenarioActionState.from_data(parsed_state)
	assert_true(restored_state.read("campaign", action.id, "visits") is int, "tagged Scenario Action state preserves integer type through JSON")


func _test_classic_call_limit(content: RealmzContent) -> void:
	var encounter_action := ClassicActionDefinition.new(0, -4, 4, 0, true, [])
	var programs: Array[ScenarioProgramDefinition] = [
		ScenarioProgramDefinition.new("root", &"trigger", "root", [encounter_action]),
		ScenarioProgramDefinition.new("recursive", &"simple-encounter-result", "0", [encounter_action]),
	]
	var definition := ScenarioDefinition.new(programs, [])
	var encounter := SimpleEncounterDefinition.new(0, 1, [SimpleEncounterResponse.new("continue", "Continue", "recursive")], false, 0, 0)
	var recursive_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, definition, [MessageDefinition.new(1, "Continue?")], [], [encounter])
	var action_state := ScenarioActionState.new()
	var vm := ScenarioVm.new()
	vm.configure(definition)
	vm.start_program("root", {"callingContext": "action"})
	var result := vm.run(_runtime_api(recursive_content, action_state))
	for _index: int in range(21):
		if result.state != ScenarioVmResult.State.WAITING:
			break
		result = vm.resume(InteractionResponse.new(result.interaction.request_id, &"encounter_choice", {"index": 0}), _runtime_api(recursive_content, action_state))
	assert_equal(result.error_code, &"classic_gosub_limit", "Classic GOSUB stack fails explicitly beyond 20 frames")


func _test_classic_transfer_keeps_trigger_context(content: RealmzContent) -> void:
	var programs: Array[ScenarioProgramDefinition] = [
		ScenarioProgramDefinition.new("root", &"trigger", "root", [ClassicActionDefinition.new(0, 39, 39, 0, false, [])]),
		ScenarioProgramDefinition.new("xap:0", &"extra-action-point", "0", [ClassicActionDefinition.new(0, 25, 25, 0, false, []), ClassicActionDefinition.new(1, 111, 111, 0, false, [])]),
	]
	var definition := ScenarioDefinition.new(programs, [])
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("context", "Context", 1, 1)])
	var state := GameState.new(party, RealmzClock.new())
	var vm := ScenarioVm.new()
	vm.configure(definition)
	vm.start_program("root", {"callingContext": "action", "triggerId": "ap.fixture.message", "mapId": content.start_map_id})
	var result := vm.run(RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new()))
	assert_equal(result.state, ScenarioVmResult.State.COMPLETED, "Classic opcode 39 completes through the transferred XAP")
	assert_true(state.world.trigger_is_disabled("ap.fixture.message"), "Classic transfer retains Action Point origin context for opcode 25")


func _test_classic_keep_codes(content: RealmzContent) -> void:
	var keep := ClassicActionDefinition.new(0, 24, 24, 0, false, [])
	var definition := ScenarioDefinition.new([ScenarioProgramDefinition.new("root", &"trigger", "root", [keep])], [])
	var vm := ScenarioVm.new()
	vm.configure(definition)
	vm.start_program("root", {"callingContext": "action", "triggerId": "ap.fixture.keep"})
	var result := vm.run(_runtime_api(content, ScenarioActionState.new()))
	assert_equal(result.state, ScenarioVmResult.State.COMPLETED, "Classic opcode 24 finishes the active AP timeline")
	assert_true(_event_has(result.events, &"action_point_kept"), "Classic opcode 24 carries the Keep Codes exception back to the session")


func _test_action_call_limit(content: RealmzContent) -> void:
	var recurse := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.CALL_ACTION)
	recurse.action_id = "scenario.test.recurse"
	var action := _action(recurse.action_id, &"void", [recurse])
	var definition := ScenarioDefinition.new([ScenarioProgramDefinition.new("root", &"trigger", "root", [CallScenarioActionInstruction.new(action.id)])], [action])
	var vm := ScenarioVm.new()
	vm.configure(definition)
	vm.start_program("root", {"callingContext": "action"})
	var result := vm.run(_runtime_api(content, ScenarioActionState.new()))
	assert_equal(result.error_code, &"scenario_action_call_limit", "Safe Scenario Action stack fails explicitly beyond 32 frames")


func _test_execution_step_limit(content: RealmzContent) -> void:
	assert_equal(ScenarioVm.EXECUTION_STEP_LIMIT, 65536, "production Scenario VM budget remains locked")
	var jump := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.JUMP)
	jump.target = 0
	var action := _action("scenario.test.loop", &"void", [jump])
	var definition := ScenarioDefinition.new([ScenarioProgramDefinition.new("root", &"trigger", "root", [CallScenarioActionInstruction.new(action.id)])], [action])
	var vm := ScenarioVm.new()
	vm.configure(definition, 64)
	vm.start_program("root", {"callingContext": "action"})
	var result := vm.run(_runtime_api(content, ScenarioActionState.new()))
	assert_equal(result.error_code, &"scenario_step_limit", "Scenario execution uses the same explicit guard at a reduced test budget")


func _test_unknown_opcode_failure(content: RealmzContent) -> void:
	var unsupported := ClassicActionDefinition.new(0, 999, 999, 0, false, [])
	var definition := ScenarioDefinition.new([ScenarioProgramDefinition.new("root", &"trigger", "root", [unsupported])], [])
	var vm := ScenarioVm.new()
	vm.configure(definition)
	vm.start_program("root", {"callingContext": "action"})
	var result := vm.run(_runtime_api(content, ScenarioActionState.new()))
	assert_equal(result.error_code, &"unsupported_classic_opcode", "unowned Classic opcode fails instead of falling through to GDScript")


func _test_classic_opcode_ownership() -> void:
	var file := FileAccess.open(AOGM_OPCODE_INVENTORY_PATH, FileAccess.READ)
	assert_not_null(file, "AOGM active-opcode inventory is available as bounded evidence")
	if file == null:
		return
	var inventory: Variant = JSON.parse_string(file.get_as_text())
	assert_true(inventory is Dictionary, "AOGM active-opcode inventory is valid JSON")
	if not inventory is Dictionary:
		return
	assert_equal(inventory.get("sourceSha256"), "23e5a33dcf06e020d9efdde12ff1b5a85a97d42d732b9bc1bfb464f4fa1f7ce0", "AOGM inventory is tied to its local source fixture hash")
	var observed: Array[int] = []
	for value: Variant in inventory.get("activeNormalizedOpcodes", []):
		observed.append(int(value))
	assert_equal(observed, ClassicOpcodeCatalog.AOGM_ACTIVE_OPCODES, "runtime readiness uses the audited active opcode set")
	for opcode: int in observed:
		assert_true(ClassicOpcodeCatalog.is_owned(opcode), "AOGM Classic opcode %d has one explicit domain owner" % opcode)
		assert_true(ClassicOpcodeCatalog.is_executable(opcode), "AOGM Classic opcode %d passes package readiness with an executable owner" % opcode)
	assert_equal(ClassicOpcodeCatalog.normalize(-121), 121, "negative Classic opcodes normalize as GOSUB calls")
	assert_equal(ClassicOpcodeCatalog.normalize(-23), -23, "Classic dungeon random-rectangle opcode keeps its signed identity")
	assert_equal(ClassicOpcodeCatalog.normalize(-14), -14, "Classic inverse character picker keeps its signed identity")


func _test_gameplay_capabilities_and_battle_resume(content: RealmzContent) -> void:
	var character := CharacterState.new("character.rules-host", "Rules Host", 100, 100)
	character.maximum_load = 500
	character.agility = 30
	character.to_hit = 100
	character.damage_bonus = 30
	character.luck = 1
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [character])
	var ally_definition := content.monster_by_classic_id(1)
	assert_not_null(ally_definition, "battle fixture contains an ally-capable Classic monster")
	var ally := MonsterState.new("ally.battle-participant", ally_definition.id, "Battle Ally", 20, 20, 1, 1, 0, 0, 0, false)
	party.add_ally(ally)
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new(), RealmzRules.new())
	var item := api.execute_safe("core.inventory.grant-item", {"characterId": character.id, "itemId": "classic.item.901", "identified": true}, "request.item")
	assert_equal(item.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Safe Scenario Action grants a definition-backed item through the session API")
	assert_equal(character.inventory().size(), 1, "grant-item mutates the direct Realmz inventory model")
	var treasure := api.execute_safe("core.economy.grant-treasure", {"treasureId": "classic.treasure.0"}, "request.treasure")
	assert_equal(treasure.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Safe Scenario Action grants deterministic treasure through the fixed rules")
	assert_equal(party.pooled_wealth.gold, 25, "treasure wealth is session-owned")
	var camped := api.execute_safe("core.party.camp", {}, "request.camp")
	assert_equal(camped.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Safe Scenario Action camps through the same clock rules as player intent")
	assert_equal(state.clock.total_minutes(), 480, "Scenario Action camping advances the Realmz clock")

	var program := ScenarioProgramDefinition.new("root", &"trigger", "root", [ClassicActionDefinition.new(0, 2, 2, 0, false, [])])
	var definition := ScenarioDefinition.new([program], [])
	var vm := ScenarioVm.new()
	vm.configure(definition)
	vm.start_program("root", {"callingContext": "action"})
	var waiting := vm.run(api)
	assert_equal(waiting.state, ScenarioVmResult.State.WAITING, "Classic battle opcode yields a typed combat action instead of delegating simulation to presentation")
	assert_equal(waiting.interaction.kind, &"combat_action", "battle continuation uses the shared typed host boundary")
	assert_not_null(state.combat.monster_by_id(ally.id), "unsuspended party allies enter the shared combat roster")
	assert_equal(party.allies().size(), 0, "Classic battle setup consumes participating held-over allies")
	var saved := ScenarioVmSnapshot.from_data(vm.snapshot().to_data())
	var restored := ScenarioVm.new()
	restored.configure(definition)
	assert_true(restored.restore(saved), "active battle VM continuation serializes at the player turn")
	var target_id: String = waiting.interaction.payload["targets"][0]["id"]
	var completed := restored.resume(InteractionResponse.new(waiting.interaction.request_id, &"combat_action", {"actorId": character.id, "action": "attack", "targetId": target_id}), api)
	var battle_events: Array[DomainEvent] = []
	battle_events.assign(completed.events)
	if completed.state == ScenarioVmResult.State.WAITING and completed.interaction.kind == &"ally_selection":
		completed = restored.resume(InteractionResponse.new(completed.interaction.request_id, &"ally_selection", {"selectedIds": completed.interaction.payload["selectedIds"]}), api)
	assert_equal(completed.state, ScenarioVmResult.State.COMPLETED, "typed combat response resolves inside the restored session VM")
	assert_equal(state.last_battle_outcome, &"victory", "battle completion and outcome remain in GameState")
	assert_true(_event_has(battle_events, &"battle_completed"), "battle completion is published as a domain event")
	var extra_code_battle := api.execute_classic(ClassicActionDefinition.new(0, 2, 2, 70, false, [0, 0, 0, 0, 0]), "request.extra-code-battle")
	assert_equal(extra_code_battle.state, ScenarioRuntimeOperationResult.State.WAITING, "Classic battle opcode accepts an authored Extra Code row")
	assert_equal(_event_classic_id(extra_code_battle.events, &"battle_started"), 0, "Classic battle opcode resolves the battle ID from Extra Code slot zero")
	var round_trip := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(round_trip, "rules, combat, quest, and instance state remain saveable after battle")
	assert_equal(round_trip.to_data(), state.to_data(), "post-battle session state round-trips exactly")


func _test_equipment_storage_save_resume(content: RealmzContent) -> void:
	var character := CharacterState.new("character.storage", "Storage Test", 10, 10)
	character.maximum_load = 500
	character.money.gold = 7
	character.carried_load = 7
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [character])
	party.pooled_wealth.gold = 11
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var granted := api.execute_safe("core.inventory.grant-item", {"characterId": character.id, "itemId": "classic.item.901", "identified": true}, "request.storage-item")
	assert_equal(granted.state, ScenarioRuntimeOperationResult.State.COMPLETED, "equipment storage fixture grants a weighted item")
	var stored_item_id: String = character.inventory()[0].id
	var capture := api.execute_classic(ClassicActionDefinition.new(0, 36, 36, 1, false, []), "request.capture")
	assert_equal(capture.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 36 captures equipment and wealth")
	assert_true(party.equipment_storage_active, "captured equipment state is explicit")
	assert_equal(character.inventory().size(), 0, "capture removes character equipment")
	assert_equal(character.carried_load, 0, "capture clears the character load")
	assert_equal(party.pooled_wealth.gold, 0, "capture stores pooled and character wealth together")
	var saved := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(saved, "captured equipment state survives save parsing")
	if saved == null:
		return
	var restored_character := saved.party.character_by_id(character.id)
	var restored_api := RealmzRuntimeApi.new(content, saved, RealmzRng.new(1), ScenarioActionState.new())
	var extra := restored_api.execute_safe("core.inventory.grant-item", {"characterId": character.id, "itemId": "classic.item.901", "identified": false}, "request.extra-item")
	assert_equal(extra.state, ScenarioRuntimeOperationResult.State.COMPLETED, "items found while equipment is captured remain mutable state")
	var restore := restored_api.execute_classic(ClassicActionDefinition.new(0, 36, 36, 0, false, []), "request.restore")
	assert_equal(restore.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 36 restores captured equipment")
	assert_false(saved.party.equipment_storage_active, "restore closes the equipment-storage interval")
	assert_equal(restored_character.inventory().size(), 1, "restore reinstates the exact captured inventory")
	assert_equal(restored_character.inventory()[0].id, stored_item_id, "captured item identity survives save and restore")
	assert_equal(saved.party.storage().size(), 1, "items acquired during capture move to party storage")
	assert_equal(saved.party.pooled_wealth.gold, 18, "restore returns all captured wealth to the party pool")
	assert_true(restored_character.carried_load > 0, "restore recalculates load from immutable item definitions")


func _test_program_replacement_and_redirect(content: RealmzContent) -> void:
	var source := ScenarioProgramDefinition.new("simple:4:result:2", &"simple-encounter-result", "4:2", [ClassicActionDefinition.new(0, 1, 1, 901, false, [])])
	var replacement := ScenarioProgramDefinition.new("xap:7", &"xap", "7", [ClassicActionDefinition.new(0, 1, 1, 902, false, [])])
	var origin := ScenarioProgramDefinition.new("trigger:origin", &"trigger", "origin", [ClassicActionDefinition.new(0, 8, 8, 1, false, [])])
	var target := ScenarioProgramDefinition.new("trigger:target", &"trigger", "target", [ClassicActionDefinition.new(0, 1, 1, 903, false, [])])
	var definition := ScenarioDefinition.new([source, replacement, origin, target], [])
	var map_id := content.start_map_id
	var triggers: Array[TriggerDefinition] = [
		TriggerDefinition.new("origin", origin.id, map_id, content.start_coordinate, true, 100, null, 0),
		TriggerDefinition.new("target", target.id, map_id, content.start_coordinate, true, 100, null, 1),
	]
	var direct := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, map_id, content.start_coordinate, content.world, definition, [MessageDefinition.new(901, "Original result"), MessageDefinition.new(902, "Replacement XAP"), MessageDefinition.new(903, "Redirected Action Point")], triggers)
	var state := GameState.new(PartyState.new(map_id, content.start_coordinate, [CharacterState.new("program-test", "Program Test", 1, 1)]), RealmzClock.new())
	var api := RealmzRuntimeApi.new(direct, state, RealmzRng.new(1), ScenarioActionState.new())
	var replace_action := ClassicActionDefinition.new(0, 7, 7, 0, false, [-1, 4, 7, 0, 2])
	var replaced := api.execute_classic(replace_action, "request.replace")
	assert_equal(replaced.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 7 installs a session-owned program replacement")
	var vm := ScenarioVm.new()
	vm.configure(definition)
	vm.start_program(source.id, {"callingContext": "encounter"})
	var result := vm.run(api)
	assert_equal(_message_texts(result.events), ["Replacement XAP"], "program replacement resolves once when a new frame begins")
	assert_true(_trace_has(vm.trace(), "program-override"), "program replacement is explicit in the VM trace")
	var saved := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(saved, "program replacement survives the central save aggregate")
	if saved == null:
		return
	var restored_vm := ScenarioVm.new()
	restored_vm.configure(definition)
	restored_vm.start_program(source.id, {"callingContext": "encounter"})
	var restored_result := restored_vm.run(RealmzRuntimeApi.new(direct, saved, RealmzRng.new(1), ScenarioActionState.new()))
	assert_equal(_message_texts(restored_result.events), ["Replacement XAP"], "restored program replacement resolves identically")
	var redirect_vm := ScenarioVm.new()
	redirect_vm.configure(definition)
	redirect_vm.start_program(origin.id, {"callingContext": "action", "triggerId": "origin", "mapId": map_id})
	var redirected := redirect_vm.run(api)
	assert_equal(_message_texts(redirected.events), ["Redirected Action Point"], "Classic opcode 8 transfers execution to another Action Point record")


func _test_scenario_spell_opcodes(content: RealmzContent) -> void:
	var first := CharacterState.new("spell.first", "First", 20, 20)
	var second := CharacterState.new("spell.second", "Second", 20, 20)
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [first, second])
	var state := GameState.new(party, RealmzClock.new())
	state.set_selected_character_ids([first.id])
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var selected := api.execute_classic(ClassicActionDefinition.new(0, 17, 17, 0, false, [5101, 1, 0, 1]), "request.selected-spell")
	assert_equal(selected.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 17 applies a packed spell to selected characters")
	assert_true(first.current_health < 20, "selected scenario spell mutates its target inside the session")
	assert_equal(second.current_health, 20, "selected scenario spell does not mutate unselected characters")
	var before_first := first.current_health
	var entire_party := api.execute_classic(ClassicActionDefinition.new(0, 18, 18, 0, false, [5101, 1, 0, 1]), "request.party-spell")
	assert_equal(entire_party.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 18 applies a packed spell to the whole party")
	assert_true(first.current_health < before_first and second.current_health < 20, "party scenario spell resolves each target through fixed rules")
	assert_equal(entire_party.events.size(), 2, "scenario spell publishes one ordered observation per target")
	var unknown := api.execute_classic(ClassicActionDefinition.new(0, 18, 18, 0, false, [9999, 1, 0, 1]), "request.unknown-spell")
	assert_equal(unknown.error_code, &"unknown_spell", "unknown packed spells fail explicitly")

	var race := _aging_race(content)
	var caste := content.caste_definitions()[0]
	var aging_spell := SpellDefinition.new("classic.spell.5999", 5999, "Aging Haste")
	aging_spell.special = 24
	var aging_instructions: Array[Variant] = [
		ClassicActionDefinition.new(0, 17, 17, 0, false, [5999, 1, 0, 1]),
		ClassicActionDefinition.new(1, 1, 1, 909, false, []),
	]
	var aging_program := ScenarioProgramDefinition.new("test.age-update", &"trigger", "test.age-update", aging_instructions)
	var aging_scenario := ScenarioDefinition.new([aging_program], [])
	var aging_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, aging_scenario, [MessageDefinition.new(909, "The spell timeline continues.")], [], [], [race], [caste], [], [aging_spell])
	var aging_character := CharacterState.new("spell.aging", "Aging Spell Target", 20, 20)
	aging_character.race_id = race.id
	aging_character.caste_id = caste.id
	aging_character.age_group = 1
	aging_character.age_days = race.age_range(1).x * 365 - 1
	var aging_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [aging_character]), RealmzClock.new())
	aging_state.set_selected_character_ids([aging_character.id])
	var aging_api := RealmzRuntimeApi.new(aging_content, aging_state, RealmzRng.new(1), ScenarioActionState.new())
	var aging_vm := ScenarioVm.new()
	aging_vm.configure(aging_scenario)
	aging_vm.start_program(aging_program.id, {"callingContext": "action"})
	var age_dialog := aging_vm.run(aging_api)
	assert_equal(age_dialog.state, ScenarioVmResult.State.WAITING, "an age-changing scenario spell blocks its issuing VM frame")
	assert_equal(age_dialog.interaction.kind, InteractionRequest.AGE_UPDATE, "the spell uses the dedicated Classic age-update contract")
	assert_true(age_dialog.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 3002), "the spell dialog requests Castle sound 3002")
	var aging_snapshot := ScenarioVmSnapshot.from_data(aging_vm.snapshot().to_data())
	assert_not_null(aging_snapshot, "the age-changing spell continuation serializes")
	var restored_aging_vm := ScenarioVm.new()
	restored_aging_vm.configure(aging_scenario)
	assert_true(restored_aging_vm.restore(aging_snapshot), "the age-changing spell continuation restores")
	var after_age := restored_aging_vm.resume(InteractionResponse.age_update(aging_snapshot.pending_request), aging_api)
	assert_equal(after_age.state, ScenarioVmResult.State.WAITING, "acknowledging age resumes the original spell timeline")
	assert_equal(after_age.interaction.kind, InteractionRequest.ACKNOWLEDGE, "the instruction after the spell now owns the next interaction")
	assert_equal(restored_aging_vm.resume(InteractionResponse.acknowledge(after_age.interaction), aging_api).state, ScenarioVmResult.State.COMPLETED, "the resumed spell timeline completes normally")


func _test_combat_fumble_mutation(content: RealmzContent) -> void:
	var character := CharacterState.new("fumble.character", "Fumbler", 10, 10)
	character.maximum_load = 500
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [character])
	var state := GameState.new(party, RealmzClock.new())
	var combat := CombatState.new("classic.battle.0")
	combat.set_turn_order([character.id])
	state.combat = combat
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var granted := api.execute_safe("core.inventory.grant-item", {"characterId": character.id, "itemId": "classic.item.6", "identified": true}, "request.fumble-item")
	assert_equal(granted.state, ScenarioRuntimeOperationResult.State.COMPLETED, "fumble fixture grants a Classic melee weapon")
	var instance: ItemInstance = character.inventory()[0]
	instance.charges = 7
	assert_true(RealmzRules.new().inventory.equip(character, instance.id, content.item_by_id(instance.definition_id)), "fumble fixture equips the item")
	combat.begin_active_turn()
	var premature := api.execute_classic(ClassicActionDefinition.new(0, 122, 122, 0, false, [1, -641]), "request.premature-fumble", {"combatantId": character.id})
	assert_equal(character.inventory().size(), 1, "opcode 122 cannot fumble an item before the active turn has made a physical attack")
	assert_false(_event_has(premature.events, &"message_shown") or _event_has(premature.events, &"sound_requested"), "the outer physical guard suppresses authored fumble text and sound with the mutation")
	combat.active_turn.physical_action_committed = true
	var fumbled := api.execute_classic(ClassicActionDefinition.new(0, 122, 122, 0, false, [1, 0]), "request.fumble", {"combatantId": character.id})
	assert_equal(fumbled.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 122 resolves inside active combat")
	assert_equal(character.inventory().size(), 0, "fumble removes the equipped item from the combatant")
	assert_equal(party.storage().size(), 0, "fumble does not bypass battle recovery through general party storage")
	assert_equal(combat.fumbled_items().size(), 1, "fumbled item remains in the bounded battle recovery queue")
	assert_equal([combat.fumbled_items()[0].definition_id, combat.fumbled_items()[0].charges], ["classic.item.6", 7], "FD-COMBAT-005 preserves the exact runtime item and remaining charges")
	assert_true(_event_has(fumbled.events, &"combatant_fumbled"), "fumble mutation publishes its outcome")
	var monster := MonsterState.new("fumble.monster", "classic.monster.1", "Armed Monster", 10, 10, 1)
	monster.weapon_id = "classic.item.6"
	var monster_combat := CombatState.new("classic.battle.0", [monster])
	monster_combat.set_turn_order([monster.id])
	state.combat = monster_combat
	monster_combat.begin_active_turn().physical_action_committed = true
	var unreachable_monster := api.execute_classic(ClassicActionDefinition.new(0, 122, 122, 0, false, [1, -641]), "request.monster-fumble", {"combatantId": monster.id})
	assert_equal(monster.weapon_id, "classic.item.6", "opcode 122 preserves Castle's outer initiative guard and cannot disarm a monster")
	assert_false(_event_has(unreachable_monster.events, &"message_shown") or _event_has(unreachable_monster.events, &"sound_requested"), "the unreachable monster branch cannot publish authored opcode 122 media")
	assert_true(unreachable_monster.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_fumble_skipped" and event.payload.get("reason") == "not-party-actor"), "opcode 122 reports the source-settled party-only guard")


func _test_classic_party_shift(content: RealmzContent) -> void:
	var dungeon := content.world.map_by_type_and_index(&"dungeon", 0)
	assert_not_null(dungeon, "party-shift fixture has a normalized dungeon topology")
	if dungeon == null:
		return
	var character := CharacterState.new("shift.character", "Shifter", 10, 10)
	var party := PartyState.new(dungeon.id, Vector2i(1, 1), [character])
	var state := GameState.new(party, RealmzClock.new())
	var fixed_rng := RealmzRng.new(1)
	var api := RealmzRuntimeApi.new(content, state, fixed_rng, ScenarioActionState.new())
	var fixed := api.execute_classic(ClassicActionDefinition.new(0, 61, 61, 0, false, [0, 1, -1, 0, 0]), "request.fixed-shift")
	assert_equal(fixed.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 61 applies authored X/Y offsets on the current map")
	assert_equal(party.coordinate, Vector2i(2, 0), "fixed party shift uses Extra Code X then Y without changing maps")
	assert_equal(fixed_rng.snapshot().draw_count, 0, "fixed party shift consumes no gameplay randomness")
	assert_true(state.world.was_visited(dungeon.id, Vector2i(2, 0)), "shifted destination becomes visible session state")
	assert_true(_event_has(fixed.events, &"party_shifted"), "party shift publishes a detached presentation observation")

	party.coordinate = Vector2i(1, 1)
	var random_rng := ScriptedRng.new([-32_767, 0, 0, 32_767])
	var random_api := RealmzRuntimeApi.new(content, state, random_rng, ScenarioActionState.new())
	var random := random_api.execute_classic(ClassicActionDefinition.new(0, 61, 61, 0, false, [0, 1, 1, 1, 0]), "request.random-shift")
	assert_equal(random.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 61 supports Castle's random signed-offset mode")
	assert_equal(party.coordinate, Vector2i(0, 2), "random party shift consumes sign then inclusive magnitude for each axis")
	assert_equal(random_rng.snapshot().draw_count, 4, "random party shift preserves Castle's four-draw order")
	assert_equal(random_rng.trace()[0]["tag"], "classic.opcode61.x-sign", "party-shift trace labels the first sign draw")
	assert_equal(random_rng.trace()[3]["tag"], "classic.opcode61.y-magnitude", "party-shift trace labels the final magnitude draw")

	party.coordinate = Vector2i.ZERO
	var rejected := api.execute_classic(ClassicActionDefinition.new(0, 61, 61, 0, false, [0, -1, 0, 0, 0]), "request.out-of-bounds-shift")
	assert_equal(rejected.error_code, &"shift_out_of_bounds", "party shift rejects a destination absent from authoritative topology")
	assert_equal(party.coordinate, Vector2i.ZERO, "rejected party shift leaves session location untouched")


func _test_classic_encounter_break(content: RealmzContent) -> void:
	var stop := ClassicActionDefinition.new(0, 34, 34, 0, false, [])
	var unreachable := ClassicActionDefinition.new(1, 1, 1, 901, false, [])
	var definition := ScenarioDefinition.new([ScenarioProgramDefinition.new("encounter-break", &"complex-encounter-result", "test", [stop, unreachable])], [])
	var vm := ScenarioVm.new()
	vm.configure(definition)
	vm.start_program("encounter-break", {"callingContext": "encounter"})
	var result := vm.run(_runtime_api(content, ScenarioActionState.new()))
	assert_equal(result.state, ScenarioVmResult.State.COMPLETED, "Classic opcode 34 ends the issuing encounter-result frame")
	assert_true(_event_has(result.events, &"encounter_loop_finished"), "encounter break publishes an explicit observation")
	assert_equal(_message_texts(result.events), [], "encounter break does not execute later result slots")


func _test_classic_game_time_mutation(content: RealmzContent) -> void:
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("clock.character", "Clock", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var offset := api.execute_classic(ClassicActionDefinition.new(0, 63, 63, 0, false, [2, 1, 2, 30, 0]), "request.offset-clock")
	assert_equal(offset.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 63 offsets the session-owned game clock")
	assert_equal(state.clock.total_minutes(), 1_590, "clock offset combines days, hours, and minutes without wall-clock access")
	assert_equal(state.clock.day(), 2, "clock offset preserves the runtime's one-based Realmz day")
	var absolute := api.execute_classic(ClassicActionDefinition.new(0, 63, 63, 0, false, [1, -1, 7, 15, 0]), "request.set-clock")
	assert_equal(absolute.state, ScenarioRuntimeOperationResult.State.COMPLETED, "absolute clock mode accepts Castle's -1 preserve sentinel")
	assert_equal(state.clock.total_minutes(), 1_875, "absolute clock mutation preserves the current day and replaces hour/minute")
	var rejected := api.execute_classic(ClassicActionDefinition.new(0, 63, 63, 0, false, [2, -10, 0, 0, 0]), "request.invalid-clock")
	assert_equal(rejected.error_code, &"invalid_game_time", "clock mutation fails explicitly before time zero")
	assert_equal(state.clock.total_minutes(), 1_875, "rejected clock mutation leaves session time untouched")


func _test_classic_game_time_branch(content: RealmzContent) -> void:
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("time-branch.character", "Time Branch", 10, 10)])
	var state := GameState.new(party, RealmzClock.new(8 * 60 + 30))
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var action := ClassicActionDefinition.new(0, 64, 64, 0, true, [-1, 8, 59, 11, 12])
	var early := api.execute_classic(action, "request.time-early")
	assert_equal(early.directive.get("targetId"), 11, "Classic opcode 64 takes the before-or-equal game-time branch")
	assert_true(early.directive.get("gosub"), "game-time branch preserves Classic GOSUB identity")
	state.clock.set_total_minutes(9 * 60)
	var late := api.execute_classic(action, "request.time-late")
	assert_equal(late.directive.get("targetId"), 12, "Classic opcode 64 takes the after-time branch")
	assert_true(_event_has(late.events, &"game_time_branch_checked"), "game-time branch publishes the observed day/hour comparison")


func _test_classic_camping_availability(content: RealmzContent) -> void:
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("camp.character", "Camp", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var disabled := api.execute_classic(ClassicActionDefinition.new(0, 66, 66, 1, false, []), "request.disable-camp")
	assert_false(state.camping_allowed, "Classic opcode 66 ID 1 disables camping")
	assert_true(_event_has(disabled.events, &"camping_availability_changed"), "camping availability change is presentation-observable")
	api.execute_classic(ClassicActionDefinition.new(0, 66, 66, 0, false, []), "request.enable-camp")
	assert_true(state.camping_allowed, "Classic opcode 66 ID 0 enables camping")


func _test_classic_ally_branch(content: RealmzContent) -> void:
	var monster := content.monster_by_classic_id(1)
	assert_not_null(monster, "ally-branch fixture contains a Classic monster identity")
	if monster == null:
		return
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("ally.character", "Ally Test", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var action := ClassicActionDefinition.new(0, 87, 87, 0, true, [1, 0, 1, 7, 0])
	var absent := api.execute_classic(action, "request.ally-absent")
	assert_equal(absent.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 87 can continue when an ally is absent")
	assert_true(absent.directive.is_empty(), "absent ally behavior one does not invent a branch")
	party.add_ally(MonsterState.new("ally.instance", monster.id, monster.name, 5, 5))
	var present := api.execute_classic(action, "request.ally-present")
	assert_equal(present.directive.get("kind"), "branch-xap", "present ally branches through the ordinary Classic VM directive")
	assert_equal(present.directive.get("targetId"), 7, "ally branch keeps its authored XAP target")
	assert_true(present.directive.get("gosub"), "negative ally opcode retains Classic GOSUB behavior")
	assert_true(_event_has(present.events, &"ally_branch_checked"), "ally branch publishes the tested identity and result")


func _test_classic_misc_branch(content: RealmzContent) -> void:
	var character := CharacterState.new("misc.character", "Misc Test", 10, 10)
	character.level = 5
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [character])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var level_branch := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, true, [7, 3, 0, 8, 0]), "request.misc-level")
	assert_equal(level_branch.directive.get("kind"), "branch-xap", "Classic opcode 86 branches on total party level")
	assert_equal(level_branch.directive.get("targetId"), 8, "miscellaneous branch uses its matched target")
	var boat_branch := api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [3, 0, 0, 9, 0]), "request.misc-boat")
	assert_true(boat_branch.directive.is_empty(), "boat test continues while the party is not in a boat")
	state.party_in_boat = true
	boat_branch = api.execute_classic(ClassicActionDefinition.new(0, 86, 86, 0, false, [3, 0, 0, 9, 0]), "request.misc-boat-present")
	assert_equal(boat_branch.directive.get("targetId"), 9, "boat status is session-owned branch state")
	var round_trip := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(round_trip, "boat and camping branch state remains inside the save aggregate")
	assert_true(round_trip.party_in_boat and not round_trip.party_camping, "miscellaneous status flags restore exactly")


func _test_classic_party_backup(content: RealmzContent) -> void:
	var map := content.world.map_by_id(content.start_map_id)
	var source := content.start_coordinate
	var direction := Vector2i(-1, -1)
	assert_not_null(map.topology.cell_at(source - direction), "party-backup fixture has a previous land cell")
	if map.topology.cell_at(source - direction) == null:
		return
	var party := PartyState.new(map.id, source, [CharacterState.new("backup.character", "Backup", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	state.last_move_direction = direction
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var backed_up := api.execute_classic(ClassicActionDefinition.new(0, 101, 101, 0, false, []), "request.backup")
	assert_equal(backed_up.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 101 reverses the last land movement direction")
	assert_equal(party.coordinate, source - direction, "party backup mutates only the session-owned location")
	assert_true(_event_has(backed_up.events, &"party_backed_up"), "party backup publishes its source and destination")
	var round_trip := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(round_trip, "last movement direction survives the central save aggregate")
	assert_equal(round_trip.last_move_direction, direction, "restored backup direction is exact")


func _test_classic_map_darkness(content: RealmzContent) -> void:
	var map := content.world.map_by_id(content.start_map_id)
	var party := PartyState.new(map.id, content.start_coordinate, [CharacterState.new("dark.character", "Dark", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var changed := api.execute_classic(ClassicActionDefinition.new(0, 106, 106, 0, false, [2, 0, 0, 0, 0]), "request.dark")
	assert_true(state.world.map_is_dark(map), "Classic opcode 106 stores current-map darkness as a world overlay")
	assert_true(_event_has(changed.events, &"map_darkness_changed"), "map darkness change is presentation-observable")
	var round_trip := WorldState.from_data(JSON.parse_string(JSON.stringify(state.world.to_data())))
	assert_not_null(round_trip, "map darkness overlay serializes with the authoritative world state")
	assert_true(round_trip.map_is_dark(map), "restored map darkness overrides immutable map metadata")
	var unchanged := api.execute_classic(ClassicActionDefinition.new(0, 106, 106, 0, false, [2, 1, 0, 0, 0]), "request.dark-unchanged")
	assert_equal(unchanged.directive.get("kind"), "finish", "opcode 106 can discontinue the issuing script when darkness already matches")


func _test_classic_teleport_and_recheck(content: RealmzContent) -> void:
	var map := content.world.map_by_id(content.start_map_id)
	var target := content.start_coordinate
	for cell: MapCell in map.topology.cells():
		if cell.coordinate != content.start_coordinate:
			target = cell.coordinate
			break
	assert_true(target != content.start_coordinate, "teleport fixture has a second authoritative cell")
	var party := PartyState.new(map.id, content.start_coordinate, [CharacterState.new("teleport.character", "Teleport", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var action := ClassicActionDefinition.new(0, 20, 20, 0, false, [-1, target.x, target.y, 77, 1])
	var teleported := api.execute_classic(action, "request.teleport")
	assert_equal(teleported.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 20 teleports within the current map using Castle's -1 preserve sentinel")
	assert_equal(party.coordinate, target, "teleport mutates the session-owned party location")
	assert_true(_event_has(teleported.events, &"sound_requested"), "opcode 20 publishes its authored post-teleport sound")
	assert_equal(_message_texts(teleported.events), ["The Realmz 2.0 fixture is deterministic."], "opcode 20 displays its authored post-teleport message")
	assert_equal(teleported.directive.get("kind"), "finish", "opcode 20 ends the current script before destination AP activation")
	assert_true(_event_has(teleported.events, &"destination_trigger_recheck_requested"), "opcode 20 requests destination trigger discovery through GameSession")


func _test_classic_quest_values(content: RealmzContent) -> void:
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("quest.character", "Quest", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var adjusted := api.execute_classic(ClassicActionDefinition.new(0, 76, 76, 0, false, [13, 150, 0, 0, 0]), "request.quest-adjust")
	assert_equal(adjusted.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 76 adjusts a session-owned quest value")
	assert_equal(state.quest_value(13), 127, "quest adjustment preserves Castle's signed-byte clamp")
	var matched := api.execute_classic(ClassicActionDefinition.new(0, 77, 77, 0, true, [13, 100, 0, 7, 8]), "request.quest-branch")
	assert_equal(matched.directive.get("targetId"), 8, "Classic opcode 77 branches when quest value reaches its threshold")
	assert_true(matched.directive.get("gosub"), "quest-value branch preserves Classic GOSUB identity")
	state.set_quest_value(13, 10)
	var missing := api.execute_classic(ClassicActionDefinition.new(0, 77, 77, 0, false, [13, 100, 0, 7, 8]), "request.quest-branch-low")
	assert_equal(missing.directive.get("targetId"), 7, "quest-value branch uses its below-threshold target")


func _test_registration_marker(content: RealmzContent) -> void:
	var api := _runtime_api(content, ScenarioActionState.new())
	var registration := api.execute_classic(ClassicActionDefinition.new(0, 98, 98, 1, false, []), "request.registration")
	assert_equal(registration.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Castle's open-source opcode 98 path performs no registration gate")
	assert_true(_event_has(registration.events, &"classic_control_marker"), "registration no-op remains explicit in the domain trace")


func _test_classic_party_mode(content: RealmzContent) -> void:
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("mode.character", "Mode", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var requires_boat := api.execute_classic(ClassicActionDefinition.new(0, 103, 103, 0, false, [1, 0, 0, 0, 0]), "request.require-boat")
	assert_equal(requires_boat.directive.get("kind"), "finish", "Classic opcode 103 ends the script when required boat state is absent")
	var enter_boat := api.execute_classic(ClassicActionDefinition.new(0, 103, 103, 0, false, [0, 0, 1, 0, 0]), "request.enter-boat")
	assert_true(state.party_in_boat, "Classic opcode 103 can place the party in a boat")
	assert_true(enter_boat.directive.is_empty(), "party-mode mutation continues when no status check fails")
	var excludes_boat := api.execute_classic(ClassicActionDefinition.new(0, 103, 103, 0, false, [2, 0, 0, 0, 0]), "request.exclude-boat")
	assert_equal(excludes_boat.directive.get("kind"), "finish", "Classic opcode 103 can require the party to be outside a boat")


func _test_scrolling_text_event(content: RealmzContent) -> void:
	var api := _runtime_api(content, ScenarioActionState.new())
	var result := api.execute_classic(ClassicActionDefinition.new(0, 62, 62, -1, false, []), "request.scrolling-text")
	assert_equal(result.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 62 emits scrolling text without making animation a simulation boundary")
	assert_true(_event_has(result.events, &"scrolling_text_requested"), "scrolling text crosses the host boundary as a presentation event")


func _test_classic_shop_configuration(content: RealmzContent) -> void:
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("shop-config.character", "Shop Config", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var configured := api.execute_classic(ClassicActionDefinition.new(0, 73, 73, 0, false, [0, 1, 799, 800, 970]), "request.configure-shop")
	assert_equal(configured.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 73 configures a shop without forcing presentation")
	assert_equal(state.active_shop_id, "classic.shop.0", "configured shop identity is session-owned")
	assert_equal(state.shop_accept_ranges(), [1, 799, 800, 970], "shop sale restrictions preserve both authored ranges")
	var round_trip := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(round_trip, "active shop and restrictions serialize in the central save aggregate")
	assert_equal(round_trip.shop_accept_ranges(), state.shop_accept_ranges(), "restored shop restrictions are exact")


func _test_classic_priest_turning(content: RealmzContent) -> void:
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("turning.character", "Turning", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var disabled := api.execute_classic(ClassicActionDefinition.new(0, 82, 82, 0, false, []), "request.turning-off")
	assert_false(state.priest_turning_allowed, "Classic opcode 82 disables priest turning in session state")
	assert_true(_event_has(disabled.events, &"priest_turning_availability_changed"), "turning availability publishes an explicit domain event")
	var enabled := api.execute_classic(ClassicActionDefinition.new(0, 83, 83, 0, false, []), "request.turning-on")
	assert_true(state.priest_turning_allowed, "Classic opcode 83 restores priest turning")
	assert_true(_event_has(enabled.events, &"message_shown"), "Castle's turning feedback crosses the presentation boundary as an event")
	var round_trip := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(round_trip, "priest-turning availability serializes in the central save aggregate")
	assert_true(round_trip.priest_turning_allowed, "restored turning availability is exact")


func _test_classic_experience_loss_and_drop(content: RealmzContent) -> void:
	var first := CharacterState.new("penalty.first", "First", 10, 10)
	var second := CharacterState.new("penalty.second", "Second", 10, 10)
	first.experience = 100
	second.experience = 100
	first.carried_load = 12
	first.set_inventory([ItemInstance.new("penalty.item", "item.fixture.sword", 0, true, true)])
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [first, second])
	var state := GameState.new(party, RealmzClock.new())
	state.set_selected_character_ids([second.id])
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	api.execute_classic(ClassicActionDefinition.new(0, 90, 90, 0, false, [30, 1, 0, 0, 0]), "request.take-victory")
	assert_equal(first.experience, 100, "Classic opcode 90 selected mode leaves unselected characters unchanged")
	assert_equal(second.experience, 70, "Classic opcode 90 removes authored experience from selected characters")
	var dropped := api.execute_classic(ClassicActionDefinition.new(0, 91, 91, 0, false, []), "request.drop-equipment")
	assert_equal(first.inventory().size(), 0, "Classic opcode 91 removes every carried item")
	assert_equal(first.carried_load, 0, "dropping all equipment clears carried load")
	assert_true(_event_has(dropped.events, &"party_equipment_dropped"), "bulk equipment loss is explicit in the domain trace")


func _test_classic_character_money_loss(content: RealmzContent) -> void:
	var first := CharacterState.new("money.first", "First", 10, 10)
	var second := CharacterState.new("money.second", "Second", 10, 10)
	first.money.jewelry = 2
	second.money.jewelry = 3
	first.carried_load = 30
	second.carried_load = 45
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [first, second])
	var state := GameState.new(party, RealmzClock.new())
	state.set_selected_character_ids([second.id])
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var cleared := api.execute_classic(ClassicActionDefinition.new(0, 60, 60, 0, false, [3, 1, 0, 0, 0]), "request.clear-money")
	assert_equal(first.money.jewelry, 2, "Classic opcode 60 selected mode preserves unselected character wealth")
	assert_equal(second.money.jewelry, 0, "Classic opcode 60 clears the selected authored wealth kind")
	assert_equal(second.carried_load, 0, "jewelry removal preserves Castle's fifteen-load-units convention")
	assert_equal(cleared.value, 3, "wealth-loss result reports the removed quantity")


func _test_classic_battle_macro_controls(content: RealmzContent) -> void:
	var definition := content.monster_by_classic_id(1)
	assert_not_null(definition, "battle-macro fixture contains a Classic monster identity")
	if definition == null:
		return
	var character := CharacterState.new("macro.character", "Macro", 10, 10)
	var monster := MonsterState.new("macro.monster", definition.id, definition.name, 5, 5)
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [character])
	var state := GameState.new(party, RealmzClock.new())
	state.combat = CombatState.new("classic.battle.0", [monster], -9)
	state.combat.round_number = 2
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var round_branch := api.execute_classic(ClassicActionDefinition.new(0, 126, 126, 0, false, [0, 1, 0, 11, 0]), "request.round-macro")
	assert_equal(round_branch.directive.get("targetId"), 11, "Classic opcode 126 branches to the authored battle macro on its matching completed round")
	assert_equal(state.combat.macro_id, 0, "single-use battle macro clears its mutable session-owned hook")
	var present := api.execute_classic(ClassicActionDefinition.new(0, 127, 127, 1, false, []), "request.monster-present")
	assert_true(present.directive.is_empty(), "Classic opcode 127 continues while its living monster identity is present")
	monster.current_health = 0
	var absent := api.execute_classic(ClassicActionDefinition.new(0, 127, 127, 1, false, []), "request.monster-absent")
	assert_equal(absent.directive.get("kind"), "finish", "monster-presence failure ends the active battle macro")
	var round_trip := CombatState.from_data(JSON.parse_string(JSON.stringify(state.combat.to_data())))
	assert_not_null(round_trip, "mutable battle macro identity serializes with combat state")
	assert_equal(round_trip.macro_id, state.combat.macro_id, "restored battle macro identity is exact")


func _test_classic_selected_character_alteration(content: RealmzContent) -> void:
	var first := CharacterState.new("alter.first", "First", 10, 10)
	var second := CharacterState.new("alter.second", "Second", 10, 10)
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [first, second])
	var state := GameState.new(party, RealmzClock.new())
	state.set_selected_character_ids([second.id])
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	api.execute_classic(ClassicActionDefinition.new(0, 108, 108, 0, false, [7, -20, 0, 0, 0]), "request.alter-stamina")
	assert_equal(first.maximum_health, 10, "Classic opcode 108 leaves unselected characters unchanged")
	assert_equal(second.maximum_health, 2, "selected stamina alteration preserves Castle's minimum of two")
	assert_equal(second.current_health, 2, "direct model remains valid when maximum stamina drops below current stamina")
	api.execute_classic(ClassicActionDefinition.new(0, 108, 108, 0, false, [1, 3, 0, 0, 0]), "request.alter-attacks")
	assert_equal(second.attack_bonus, 3, "attacks-per-round bonus is represented independently from the character's base attacks")
	var round_trip := CharacterState.from_data(JSON.parse_string(JSON.stringify(second.to_data())))
	assert_not_null(round_trip, "new Classic character alteration fields serialize in the central save aggregate")
	assert_equal(round_trip.attack_bonus, second.attack_bonus, "restored attack bonus is exact")


func _test_classic_combat_monster_alteration(content: RealmzContent) -> void:
	var definition := content.monster_by_classic_id(1)
	assert_not_null(definition, "combat-alteration fixture contains a Classic monster identity")
	if definition == null:
		return
	var monster := MonsterState.new("alter.monster", definition.id, definition.name, 5, 5)
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("alter.monster.character", "Alter", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	state.combat = CombatState.new("classic.battle.0", [monster])
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var altered := api.execute_classic(ClassicActionDefinition.new(0, 120, 120, 0, false, [2, 1, 1, -1, 0]), "request.alter-monster")
	assert_false(monster.traitor, "Classic opcode 120 can convert an authored combat monster to the party side")
	assert_equal(altered.value, 1, "combat monster alteration respects its authored count")
	monster.icon_id = 27
	var round_trip := MonsterState.from_data(JSON.parse_string(JSON.stringify(monster.to_data())))
	assert_not_null(round_trip, "mutable combat icon identity serializes with monster state")
	assert_equal(round_trip.icon_id, 27, "restored combat icon identity is exact")


func _test_classic_ally_participation(content: RealmzContent) -> void:
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("suspend.character", "Suspend", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var suspended := api.execute_classic(ClassicActionDefinition.new(0, 105, 105, 1, false, []), "request.suspend-allies")
	assert_true(state.allies_suspended, "Classic opcode 105 suspends ally battle participation in session state")
	assert_true(_event_has(suspended.events, &"ally_participation_changed"), "ally participation change is explicit in the domain trace")
	var round_trip := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(round_trip, "ally participation state serializes in the central save aggregate")
	assert_true(round_trip.allies_suspended, "restored ally participation state is exact")


func _test_classic_bodycount_selection(content: RealmzContent) -> void:
	var definition := content.monster_by_classic_id(1)
	assert_not_null(definition, "body-count fixture contains a Classic ally definition")
	if definition == null:
		return
	var original_can_summon := definition.can_summon
	definition.can_summon = 1
	var survivor := MonsterState.new("bodycount.survivor", definition.id, "Survivor", 9, 12, 1, 1, 0, 0, 0, false)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("bodycount.character", "Body Count", 10, 10)]), RealmzClock.new())
	state.combat = CombatState.new("classic.battle.0", [survivor])
	state.combat.completed = true
	state.combat.outcome = &"victory"
	var flow := RealmzRules.new().combat_flow
	var payload := flow.ally_selection_payload(state, content)
	assert_equal(payload.get("selectedIds"), [survivor.id], "Classic body-count defaults surviving eligible allies to selected")
	var selected := flow.apply_ally_selection(state, content, payload.get("selectedIds", []))
	assert_true(selected.ok, "typed post-battle selection retains a surviving ally")
	assert_equal(state.party.allies()[0].id, survivor.id, "selected combat survivor returns to the held-over party")
	definition.can_summon = -1
	state.party.set_allies([])
	var mandatory := flow.apply_ally_selection(state, content, [])
	assert_false(mandatory.ok, "scenario-mandatory Classic allies cannot be left behind")
	assert_equal(mandatory.error_code, &"required_ally_missing", "mandatory ally rejection is explicit")
	definition.can_summon = original_can_summon


func _test_classic_spellcasting_flags(content: RealmzContent) -> void:
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("casting.character", "Casting", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var changed := api.execute_classic(ClassicActionDefinition.new(0, 69, 69, 1, false, [1, 0, 1, 0, 0]), "request.casting-flags")
	assert_true(state.character_spellcasting and not state.monster_spellcasting and state.spell_charging, "Classic opcode 69 owns all three authored spellcasting flags")
	assert_true(_event_has(changed.events, &"spellcasting_flags_changed"), "spellcasting flag changes are explicit in the domain trace")
	var round_trip := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(round_trip, "spellcasting flags serialize in the central save aggregate")
	assert_true(round_trip.character_spellcasting and round_trip.spell_charging, "restored spellcasting flags are exact")


func _test_classic_identity_selection(content: RealmzContent) -> void:
	var first := CharacterState.new("identity.first", "First", 10, 10)
	var second := CharacterState.new("identity.second", "Second", 0, 10)
	first.race_id = "classic.race.0"
	second.race_id = "classic.race.0"
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [first, second])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var selected := api.execute_classic(ClassicActionDefinition.new(0, 50, 50, 0, false, [0, 0, 0, 0, 1]), "request.select-race")
	assert_equal(selected.value, [first.id], "Classic opcode 50 selects matching living characters by direct Realmz race identity")
	assert_equal(state.selected_character_ids(), [first.id], "identity selection updates the shared selected-character set used by later opcodes")


func _test_classic_monster_route(content: RealmzContent) -> void:
	var definition := content.monster_by_classic_id(1)
	assert_not_null(definition, "route fixture contains a Classic monster identity")
	if definition == null:
		return
	var monster := MonsterState.new("route.monster", definition.id, definition.name, 5, 5)
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("route.character", "Route", 10, 10)])
	var state := GameState.new(party, RealmzClock.new())
	state.combat = CombatState.new("classic.battle.0", [monster])
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var routed := api.execute_classic(ClassicActionDefinition.new(0, 123, 123, 0, false, [1, 0, 0, 0, 0]), "request.route")
	assert_equal(routed.value, 1, "Classic opcode 123 routes every matching monster on the macro source's side")
	assert_equal(monster.conditions.value(ConditionRules.RUNS_AWAY), -1, "routed monster receives Castle's persistent run-away condition")
	assert_equal(monster.surrender_percent, 50, "routed monster receives Castle's fifty-percent surrender override")


func _test_classic_random_items(content: RealmzContent) -> void:
	var character := CharacterState.new("random-item.character", "Random Item", 10, 10)
	character.maximum_load = 1_000
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [character])
	var state := GameState.new(party, RealmzClock.new())
	var rng := ScriptedRng.new([0, 0])
	var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new())
	var granted := api.execute_classic(ClassicActionDefinition.new(0, 65, 65, 0, false, [-1, 901, 901, 0, 0]), "request.random-item")
	assert_equal(granted.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 65 grants source-defined random items through inventory rules")
	assert_equal(character.inventory().size(), 1, "random item becomes a direct Realmz item instance")
	assert_equal(rng.snapshot().draw_count, 2, "random item count and inclusive item range each consume one session RNG draw")


func _test_classic_selected_level_up(content: RealmzContent) -> void:
	var character := CharacterState.new("level.character", "Level", 10, 10)
	character.race_id = "classic.race.0"
	character.caste_id = "classic.caste.0"
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [character])
	var state := GameState.new(party, RealmzClock.new())
	state.set_selected_character_ids([character.id])
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var leveled := api.execute_classic(ClassicActionDefinition.new(0, 102, 102, 0, false, []), "request.level-selected")
	assert_equal(leveled.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 102 levels picked characters through fixed character rules")
	assert_equal(character.level, 2, "selected character advances exactly one level")
	assert_equal(character.experience, 1, "forced level-up preserves Castle's explicit experience marker")


func _test_classic_death_macro_revival(content: RealmzContent) -> void:
	var character := CharacterState.new("revive.character", "Revive", 0, 10)
	character.conditions.set_value(ConditionRules.ANIMATED, -1)
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [character])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var revived := api.execute_classic(ClassicActionDefinition.new(0, 119, 119, 0, false, []), "request.revive-party")
	assert_equal(character.current_health, 1, "Classic opcode 119 revives a defeated party at one stamina")
	assert_equal(character.conditions.value(ConditionRules.ANIMATED), 0, "party revival clears animated death state")
	assert_equal(revived.directive.get("kind"), "finish", "whole-party revival exits its death macro as Castle does")


func _test_automatic_monster_death_macro(content: RealmzContent) -> void:
	var monster_definition := content.monster_by_classic_id(1)
	var battle := content.battle_by_classic_id(0)
	assert_not_null(monster_definition, "automatic death-macro fixture contains a Classic monster")
	assert_not_null(battle, "automatic death-macro fixture contains a Classic battle")
	if monster_definition == null or battle == null:
		return
	var original_death_macro := monster_definition.death_macro
	monster_definition.death_macro = 321
	var programs: Array[ScenarioProgramDefinition] = [
		ScenarioProgramDefinition.new("root", &"trigger", "root", [ClassicActionDefinition.new(0, 2, 2, 0, false, [])]),
		ScenarioProgramDefinition.new("xap:321", &"extra-action-point", "321", [ClassicActionDefinition.new(0, 119, 119, 0, false, [])]),
	]
	var messages: Array[MessageDefinition] = [MessageDefinition.new(1, "Before battle"), MessageDefinition.new(4, "After battle")]
	var direct := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, ScenarioDefinition.new(programs, []), messages, [], [], [], [], [], [], [monster_definition], [battle])
	var character := CharacterState.new("death-macro.attacker", "Death Macro Attacker", 100, 100)
	character.agility = 100
	character.to_hit = 100
	character.damage_bonus = 100
	character.luck = 1
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [character]), RealmzClock.new())
	var vm := ScenarioVm.new()
	vm.configure(direct.scenario)
	vm.start_program("root", {"callingContext": "action"})
	var api := RealmzRuntimeApi.new(direct, state, RealmzRng.new(1), ScenarioActionState.new())
	var waiting := vm.run(api)
	assert_equal(waiting.state, ScenarioVmResult.State.WAITING, "death-macro battle reaches the player combat boundary: %s %s" % [waiting.error_code, waiting.error_message])
	if waiting.state != ScenarioVmResult.State.WAITING:
		monster_definition.death_macro = original_death_macro
		return
	var target_id: String = waiting.interaction.payload["targets"][0]["id"]
	var completed := vm.resume(InteractionResponse.new(waiting.interaction.request_id, &"combat_action", {"actorId": character.id, "action": "attack", "targetId": target_id}), api)
	var macro_events: Array[DomainEvent] = []
	macro_events.assign(completed.events)
	assert_true(_event_has(macro_events, &"monster_death_macro_started"), "automatic death macro publishes its start")
	assert_true(_event_has(macro_events, &"monster_revived"), "opcode 119 receives the defeated combatant context")
	assert_true(_event_has(macro_events, &"monster_death_macro_completed"), "automatic death macro publishes its completion")
	if completed.state == ScenarioVmResult.State.WAITING and completed.interaction.kind == &"ally_selection":
		completed = vm.resume(InteractionResponse.new(completed.interaction.request_id, &"ally_selection", {"selectedIds": completed.interaction.payload["selectedIds"]}), api)
	assert_equal(completed.state, ScenarioVmResult.State.COMPLETED, "defeating a macro-bearing monster runs its XAP before battle completion")
	var revived := state.combat.monster_by_id(target_id)
	assert_equal(revived.current_health, 1, "death macro can revive its owning monster")
	assert_false(revived.traitor, "Classic death-macro completion moves the monster off the enemy side")
	assert_equal(state.last_battle_outcome, &"victory", "battle resolution runs after the death macro commits")

	var yielding_programs: Array[ScenarioProgramDefinition] = [
		ScenarioProgramDefinition.new("xap:321", &"extra-action-point", "321", [
			ClassicActionDefinition.new(0, 14, 14, 1, false, []),
			ClassicActionDefinition.new(1, 119, 119, 0, false, []),
		]),
	]
	var yielding_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, ScenarioDefinition.new(yielding_programs, []), messages, [], [], content.race_definitions(), content.caste_definitions(), [], [], [monster_definition], [battle])
	var session := GameSession.new()
	session.start(yielding_content, 1)
	_begin_fixture_adventure(session, yielding_content)
	var session_character: CharacterState = session._state.party.characters()[0]
	session_character.agility = 100
	session_character.to_hit = 100
	session_character.damage_bonus = 100
	session_character.luck = 1
	var battle_started := session._rules.combat_flow.start_battle(session._state, yielding_content, battle, session._rng)
	assert_true(battle_started.ok, "direct session death-macro fixture starts a battle")
	var session_target: MonsterState = session._state.combat.monsters()[0]
	var yielded := session.submit_intent(PlayerIntent.combat_action(&"attack", session_character.id, session_target.id))
	assert_equal(yielded.state, SessionStep.State.WAITING_FOR_INTERACTION, "direct session death macro can yield a typed interaction")
	assert_equal(yielded.interaction.kind, &"character_selection", "death-macro interaction crosses the normal session host boundary")
	var held := session.snapshot()
	assert_not_null(held, "pending direct-session death macro is a committed save boundary")
	var restored := GameSession.new()
	assert_equal(restored.restore(yielding_content, held).state, SessionStep.State.COMPLETED, "direct-session death macro restores transactionally")
	var restored_request := restored.view().pending_interaction
	var resumed := restored.respond(InteractionResponse.new(restored_request.request_id, &"character_selection", {"characterIds": [session_character.id]}))
	assert_true(_event_has(resumed.events, &"monster_death_macro_completed"), "restored direct-session death macro completes before battle resolution")
	if resumed.state == SessionStep.State.WAITING_FOR_INTERACTION and resumed.interaction.kind == &"ally_selection":
		var ally_boundary := SaveEnvelope.from_data(restored.snapshot().to_data())
		assert_not_null(ally_boundary, "post-battle ally selection is a committed save boundary")
		resumed = restored.respond(InteractionResponse.new(resumed.interaction.request_id, &"ally_selection", {"selectedIds": resumed.interaction.payload["selectedIds"]}))
	assert_equal(resumed.state, SessionStep.State.COMPLETED, "restored death-macro interaction resumes through GameSession")
	assert_equal(restored._state.last_battle_outcome, &"victory", "restored direct-session battle resolves after its death macro")
	monster_definition.death_macro = original_death_macro


func _test_monster_aging_attack_continuations(content: RealmzContent) -> void:
	var race := _aging_race(content)
	var castes := content.caste_definitions()
	assert_not_null(race, "monster-aging fixture has adjacent Classic age bands")
	assert_false(castes.is_empty(), "monster-aging fixture has a caste for live age changes")
	if race == null or castes.is_empty():
		return
	var caste: CasteDefinition = castes[0]
	var hit_dice := maxi(1, ceili(100.0 / float(race.max_age)))
	var zero8: Array[int] = []
	zero8.resize(8)
	zero8.fill(0)
	var zero6: Array[int] = []
	zero6.resize(6)
	zero6.fill(0)
	var zero3: Array[int] = []
	zero3.resize(3)
	zero3.fill(0)
	var attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 17), MonsterAttackDefinition.new(2, 2)]
	var monster_definition := MonsterDefinition.new("monster.age-special", 917, "Age Special", hit_dice, 0, 100, 0, 0, zero8, zero8, zero6, zero3, [], [], attacks)
	monster_definition.damage_bonus = 6
	monster_definition.traitor = true
	var aging_weapon := ItemDefinition.new("classic.item.917", 917, "Aging Weapon")
	aging_weapon.item_type = 2
	aging_weapon.vs_small = 1
	aging_weapon.special_1 = -10
	aging_weapon.special_2 = 0
	aging_weapon.special_3 = ConditionRules.POISONED + 20
	aging_weapon.special_5 = 2
	monster_definition.weapon_id = aging_weapon.id
	var battle := BattleDefinition.new("battle.age-special", 917, [BattleMonsterSlotDefinition.new(Vector2i.ZERO, monster_definition.id, false)])
	var programs: Array[ScenarioProgramDefinition] = [ScenarioProgramDefinition.new("root", &"trigger", "root", [ClassicActionDefinition.new(0, 2, 2, battle.classic_id, false, []), ClassicActionDefinition.new(1, 111, 111, 0, false, [])])]
	var aging_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, ScenarioDefinition.new(programs, []), [], [], [], [race], [caste], [aging_weapon], [], [monster_definition], [battle])
	var character := CharacterState.new("character.age-special", "Age Target", 100, 100)
	character.race_id = race.id
	character.caste_id = caste.id
	character.age_days = race.age_range(0).y * 365 + 364
	character.age_group = 1
	character.agility = 1
	character.set_save_value_raw(7, 50)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [character]), RealmzClock.new())
	state.party.conditions.set_value(ConditionRules.PARTY_DRAGON_HIDE, 1)
	var scripted_values: Array[int] = []
	# The fixture's landlook-zero field has one non-base 3 by 3 build; every
	# other interior base cell consumes a no-rubble check before formation.
	for _draw: int in 86 * 86 - 9:
		scripted_values.append(32_767)
	for _draw: int in hit_dice + 14:
		scripted_values.append(0)
	scripted_values.append(32_767)
	var runtime_rng := ScriptedRng.new(scripted_values)
	var api := RealmzRuntimeApi.new(aging_content, state, runtime_rng, ScenarioActionState.new())
	var vm := ScenarioVm.new()
	vm.configure(aging_content.scenario)
	vm.start_program("root", {"callingContext": "action"})
	var aged := vm.run(api)
	assert_equal(aged.state, ScenarioVmResult.State.WAITING, "scenario combat pauses at the monster-caused age update")
	assert_equal(aged.interaction.kind, InteractionRequest.AGE_UPDATE, "monster aging uses the ordinary typed age-update ABI")
	assert_equal(vm.snapshot().pending_continuation.get("runtime", {}).get("kind"), "classic-combat-age-updates", "the age dialog owns the issuing Classic combat continuation")
	assert_true(_event_has(aged.events, &"combat_monster_special_resolved") and _event_has(aged.events, &"character_age_changed"), "combat publishes the source-backed special and live-age transition")
	assert_false(_event_has(aged.events, &"combat_attack_resolved"), "ordinary damage waits behind Castle's age dialog")
	assert_equal(character.current_health, 100, "the pre-acknowledgement combat save retains pending physical damage")
	assert_equal(character.conditions.value(ConditionRules.POISONED), 0, "a monster weapon condition waits behind the same age-update boundary as physical damage")
	assert_equal(state.combat.active_turn.attack_index, 1, "the age-update boundary records the already-issued first attack row")
	var restored_state := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	var restored_vm_snapshot := ScenarioVmSnapshot.from_data(JSON.parse_string(JSON.stringify(vm.snapshot().to_data())))
	var restored_rng := RealmzRng.new()
	assert_true(restored_rng.restore(runtime_rng.snapshot()), "scenario combat aging restores its exact RNG draw boundary")
	var restored_api := RealmzRuntimeApi.new(aging_content, restored_state, restored_rng, ScenarioActionState.new())
	var restored_vm := ScenarioVm.new()
	restored_vm.configure(aging_content.scenario)
	assert_true(restored_vm.restore(restored_vm_snapshot), "scenario VM restores the nested combat age-update continuation")
	var resumed := restored_vm.resume(InteractionResponse.new(aged.interaction.request_id, InteractionRequest.AGE_UPDATE, {}), restored_api)
	assert_equal(resumed.state, ScenarioVmResult.State.WAITING, "acknowledging restored monster aging returns to the exact battle")
	assert_equal(resumed.interaction.kind, &"combat_action", "scenario battle resumes at the next player action")
	assert_true(_event_has(resumed.events, &"character_age_update_acknowledged"), "the restored scenario continuation records the acknowledgement")
	assert_true(_event_has(resumed.events, &"combat_attack_resolved"), "scenario acknowledgement commits the deferred ordinary hit")
	var scenario_attack_events := resumed.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved")
	assert_equal(scenario_attack_events.map(func(event: DomainEvent) -> int: return int(event.payload.get("attackIndex"))), [0, 1], "scenario restore commits the deferred row once and resumes the next authored row")
	assert_equal(scenario_attack_events.map(func(event: DomainEvent) -> int: return int(event.payload.get("damage"))), [2, 2], "each restored row independently applies the carried weapon and Dragon Hide reduction")
	var scenario_dragon_sound_index := _event_index_with_payload(resumed.events, &"sound_requested", "soundId", 694)
	assert_true(scenario_dragon_sound_index >= 0 and scenario_dragon_sound_index < _event_index(resumed.events, &"combat_attack_resolved"), "restored scenario combat plays Castle's asynchronous Dragon Hide feedback before deferred damage")
	assert_equal(restored_state.party.character_by_id(character.id).current_health, 96, "restored scenario combat applies the pending and remaining Dragon Hide-reduced rows exactly once each")
	assert_equal(restored_state.party.character_by_id(character.id).conditions.value(ConditionRules.POISONED), 4, "restored scenario combat applies the monster weapon condition once for each resolved attack row")

	var session := GameSession.new()
	session.start(aging_content, 1)
	session._state.party = PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.from_data(character.to_data())])
	session._state.party.conditions.set_value(ConditionRules.PARTY_DRAGON_HIDE, 1)
	session._state.party_setup_completed = true
	var session_character: CharacterState = session._state.party.characters()[0]
	session_character.age_days = race.age_range(0).y * 365 + 364
	session_character.age_group = 1
	session_character.current_health = 100
	var session_monster := MonsterState.new("monster.age-special.session", monster_definition.id, monster_definition.name, 10, 10, hit_dice, 100)
	session_monster.weapon_id = aging_weapon.id
	session._state.combat = CombatState.new(battle.id, [session_monster])
	session._state.combat.set_turn_order([session_character.id, session_monster.id])
	session._rng = ScriptedRng.new([0, 0, 0, 0, 0, 0, 0, 0, 32_767])
	var session_aged := session.submit_intent(PlayerIntent.combat_action(&"defend", session_character.id, ""))
	assert_equal(session_aged.state, SessionStep.State.WAITING_FOR_INTERACTION, "direct session combat pauses at the monster-caused age update")
	assert_equal(session_aged.interaction.kind, InteractionRequest.AGE_UPDATE, "direct combat exposes the same typed age update")
	assert_equal(session_character.current_health, 100, "direct combat also saves before ordinary physical damage")
	assert_equal(session_character.conditions.value(ConditionRules.POISONED), 0, "direct combat saves before its pending weapon condition")
	assert_equal(session._state.combat.active_turn.attack_index, 1, "direct combat persists the issued attack cursor at the age boundary")
	var boundary := SaveEnvelope.from_data(session.snapshot().to_data())
	assert_not_null(boundary, "monster-caused age update is a complete central save boundary")
	var restored_session := GameSession.new()
	assert_equal(restored_session.restore(aging_content, boundary).state, SessionStep.State.COMPLETED, "direct monster-aging continuation restores transactionally")
	var restored_request := restored_session.view().pending_interaction
	var session_resumed := restored_session.respond(InteractionResponse.new(restored_request.request_id, InteractionRequest.AGE_UPDATE, {}))
	assert_equal(session_resumed.state, SessionStep.State.COMPLETED, "acknowledging restored direct monster aging resumes combat")
	assert_equal(restored_session._state.combat.active_actor_id(), session_character.id, "direct combat resumes at the exact next actor")
	assert_equal(restored_session._state.party.character_by_id(session_character.id).age_group, 2, "the committed age band survives direct-session restore")
	var direct_dragon_sound_index := _event_index_with_payload(session_resumed.events, &"sound_requested", "soundId", 694)
	assert_true(direct_dragon_sound_index >= 0 and direct_dragon_sound_index < _event_index(session_resumed.events, &"combat_attack_resolved"), "the direct save continuation retains Dragon Hide's asynchronous sound ordering")
	var direct_attack_events := session_resumed.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved")
	assert_equal(direct_attack_events.map(func(event: DomainEvent) -> int: return int(event.payload.get("attackIndex"))), [0, 1], "the direct restore commits the pending row once and resumes the remaining authored row")
	assert_equal(direct_attack_events.map(func(event: DomainEvent) -> int: return int(event.payload.get("damage"))), [2, 2], "the direct restore independently resolves both carried-weapon rows")
	assert_equal(restored_session._state.party.character_by_id(session_character.id).current_health, 96, "the restored direct continuation applies the pending and remaining rows exactly once each")
	assert_equal(restored_session._state.party.character_by_id(session_character.id).conditions.value(ConditionRules.POISONED), 4, "the restored direct continuation applies the weapon condition once to the pending row and once to the remaining row")


func _test_monster_status_attack_flow(content: RealmzContent) -> void:
	var attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 6)]
	var zero8: Array[int] = []
	zero8.resize(8)
	zero8.fill(0)
	var zero6: Array[int] = []
	zero6.resize(6)
	zero6.fill(0)
	var zero3: Array[int] = []
	zero3.resize(3)
	zero3.fill(0)
	var definition := MonsterDefinition.new("monster.status-flow", 906, "Status Monster", 4, 0, 100, 0, 0, zero8, zero8, zero6, zero3, [], [], attacks)
	definition.traitor = true
	var battle := BattleDefinition.new("battle.status-flow", 906, [BattleMonsterSlotDefinition.new(Vector2i.ZERO, definition.id, false)])
	var status_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, content.scenario, [], [], [], content.race_definitions(), content.caste_definitions(), content.item_definitions(), content.spell_definitions(), [definition], [battle])
	var character := CharacterState.new("character.status-flow", "Status Target", 20, 20)
	character.set_save_value_raw(4, 0)
	var session := GameSession.new()
	session.start(status_content, 1)
	session._state.party = PartyState.new(content.start_map_id, content.start_coordinate, [character])
	session._state.party_setup_completed = true
	var monster := MonsterState.new("monster.status-flow.instance", definition.id, definition.name, 10, 10, 4, 100)
	session._state.combat = CombatState.new(battle.id, [monster])
	session._state.combat.set_turn_order([character.id, monster.id])
	session._rng = ScriptedRng.new([0, 0, 0, 0, 0, 0, 0, 32_767, 32_767])
	var resolved := session.submit_intent(PlayerIntent.combat_action(&"defend", character.id, ""))
	assert_equal(resolved.state, SessionStep.State.COMPLETED, "monster status attacks commit without inventing a player interaction")
	assert_equal(character.conditions.value(ConditionRules.POISONED), 4, "the direct session owns the resulting status mutation")
	var special_index := _event_index(resolved.events, &"combat_monster_special_resolved")
	var sound_index := _event_index(resolved.events, &"sound_requested")
	var damage_index := _event_index(resolved.events, &"combat_attack_resolved")
	assert_true(special_index >= 0 and sound_index > special_index and damage_index > sound_index, "combat publishes status, asynchronous sound, and physical damage in Castle order")
	assert_equal(resolved.events[special_index].payload.get("conditionIndex"), ConditionRules.POISONED, "the status event exposes the source-owned condition identity")
	assert_equal([resolved.events[sound_index].payload.get("soundId"), resolved.events[sound_index].payload.get("waitForCompletion")], [630, false], "party status feedback requests Castle sound 630 asynchronously")
	var boundary := SaveEnvelope.from_data(session.snapshot().to_data())
	assert_not_null(boundary, "a committed status attack produces a complete central save boundary")
	var restored := GameSession.new()
	assert_equal(restored.restore(status_content, boundary).state, SessionStep.State.COMPLETED, "status-mutated combat state restores transactionally")
	assert_equal(restored._state.party.character_by_id(character.id).conditions.value(ConditionRules.POISONED), 4, "restored combat retains the exact status duration")


func _test_monster_resource_drain_flow(content: RealmzContent) -> void:
	var attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 8)]
	var zero8: Array[int] = []
	zero8.resize(8)
	zero8.fill(0)
	var zero6: Array[int] = []
	zero6.resize(6)
	zero6.fill(0)
	var zero3: Array[int] = []
	zero3.resize(3)
	zero3.fill(0)
	var definition := MonsterDefinition.new("monster.resource-flow", 908, "Spell Drainer", 4, 0, 100, 0, 0, zero8, zero8, zero6, zero3, [], [], attacks)
	definition.traitor = true
	definition.spell_points = 2
	var battle := BattleDefinition.new("battle.resource-flow", 908, [BattleMonsterSlotDefinition.new(Vector2i.ZERO, definition.id, false)])
	var resource_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, content.scenario, [], [], [], content.race_definitions(), content.caste_definitions(), content.item_definitions(), content.spell_definitions(), [definition], [battle])
	var character := CharacterState.new("character.resource-flow", "Spell Target", 20, 20)
	character.maximum_spell_points = 20
	character.spell_points = 20
	character.set_save_value_raw(6, 0)
	var session := GameSession.new()
	session.start(resource_content, 1)
	session._state.party = PartyState.new(content.start_map_id, content.start_coordinate, [character])
	session._state.party_setup_completed = true
	var monster := MonsterState.new("monster.resource-flow.instance", definition.id, definition.name, 10, 10, 4, 100, 0, 0, 2)
	session._state.combat = CombatState.new(battle.id, [monster])
	session._state.combat.set_turn_order([character.id, monster.id])
	session._rng = ScriptedRng.new([0, 0, 0, 0, 0, 0, 0, 32_767, 32_767])
	var resolved := session.submit_intent(PlayerIntent.combat_action(&"defend", character.id, ""))
	assert_equal(resolved.state, SessionStep.State.COMPLETED, "monster resource drains commit without inventing a player interaction")
	assert_equal([character.spell_points, monster.spell_points, monster.maximum_spell_points], [8, 14, 2], "the direct session owns both sides of Castle's uncapped spell-point transfer")
	var special_index := _event_index(resolved.events, &"combat_monster_special_resolved")
	var damage_index := _event_index(resolved.events, &"combat_attack_resolved")
	assert_true(special_index >= 0 and damage_index > special_index, "combat publishes the resource transfer before ordinary physical damage feedback")
	assert_equal([resolved.events[special_index].payload.get("resource"), resolved.events[special_index].payload.get("amount"), resolved.events[special_index].payload.get("targetBefore"), resolved.events[special_index].payload.get("targetAfter"), resolved.events[special_index].payload.get("actorAfter")], ["spell_points", 12, 20, 8, 14], "the typed special event exposes the complete source-owned transfer")
	assert_equal(_event_index(resolved.events, &"sound_requested"), -1, "spell-point drain does not invent an experience-drain sound")
	var boundary := SaveEnvelope.from_data(session.snapshot().to_data())
	assert_not_null(boundary, "a committed resource drain produces a complete central save boundary")
	var restored := GameSession.new()
	assert_equal(restored.restore(resource_content, boundary).state, SessionStep.State.COMPLETED, "resource-drained combat state restores transactionally")
	assert_equal([restored._state.party.character_by_id(character.id).spell_points, restored._state.combat.monster_by_id(monster.id).spell_points, restored._state.combat.monster_by_id(monster.id).maximum_spell_points], [8, 14, 2], "restore retains both sides of an above-maximum spell transfer")

	var experience_attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 9)]
	var experience_definition := MonsterDefinition.new("monster.experience-flow", 909, "Experience Drainer", 4, 0, 100, 0, 0, zero8, zero8, zero6, zero3, [], [], experience_attacks)
	experience_definition.traitor = true
	var experience_battle := BattleDefinition.new("battle.experience-flow", 909, [BattleMonsterSlotDefinition.new(Vector2i.ZERO, experience_definition.id, false)])
	var experience_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, content.scenario, [], [], [], content.race_definitions(), content.caste_definitions(), content.item_definitions(), content.spell_definitions(), [experience_definition], [experience_battle])
	var experience_character := CharacterState.new("character.experience-flow", "Experience Target", 20, 20)
	experience_character.experience = 100
	experience_character.set_save_value_raw(5, 0)
	var experience_session := GameSession.new()
	experience_session.start(experience_content, 1)
	experience_session._state.party = PartyState.new(content.start_map_id, content.start_coordinate, [experience_character])
	experience_session._state.party_setup_completed = true
	var experience_monster := MonsterState.new("monster.experience-flow.instance", experience_definition.id, experience_definition.name, 10, 20, 4, 100)
	experience_session._state.combat = CombatState.new(experience_battle.id, [experience_monster])
	experience_session._state.combat.set_turn_order([experience_character.id, experience_monster.id])
	experience_session._rng = ScriptedRng.new([0, 0, 0, 0, 0, 0, 0, 32_767, 32_767])
	var experience_resolved := experience_session.submit_intent(PlayerIntent.combat_action(&"defend", experience_character.id, ""))
	assert_equal(experience_character.experience, -300, "the direct session subtracts Castle experience rather than altering a Remake-style level balance")
	var experience_special_index := _event_index(experience_resolved.events, &"combat_monster_special_resolved")
	var experience_sound_index := _event_index(experience_resolved.events, &"sound_requested")
	var experience_damage_index := _event_index(experience_resolved.events, &"combat_attack_resolved")
	assert_true(experience_special_index >= 0 and experience_sound_index > experience_special_index and experience_damage_index > experience_sound_index, "experience drain publishes result, asynchronous Castle sound, and physical damage in source order")
	assert_equal([experience_resolved.events[experience_special_index].payload.get("resource"), experience_resolved.events[experience_special_index].payload.get("amount"), experience_resolved.events[experience_sound_index].payload.get("soundId"), experience_resolved.events[experience_sound_index].payload.get("waitForCompletion")], ["experience", 400, 630, false], "experience-drain events expose the typed loss and Castle sound contract")
	var experience_boundary := SaveEnvelope.from_data(experience_session.snapshot().to_data())
	assert_not_null(experience_boundary, "negative experience after combat is a complete central save boundary")
	var restored_experience_session := GameSession.new()
	assert_equal(restored_experience_session.restore(experience_content, experience_boundary).state, SessionStep.State.COMPLETED, "experience-drained combat state restores transactionally")
	assert_equal(restored_experience_session._state.party.character_by_id(experience_character.id).experience, -300, "whole-session restore preserves the exact drained experience")


func _test_monster_charm_and_affliction_flow(content: RealmzContent) -> void:
	var zero8: Array[int] = []
	zero8.resize(8)
	zero8.fill(0)
	var zero6: Array[int] = []
	zero6.resize(6)
	zero6.fill(0)
	var zero3: Array[int] = []
	zero3.resize(3)
	zero3.fill(0)
	var attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 10)]
	var definition := MonsterDefinition.new("monster.charm-flow", 910, "Charmer", 4, 0, 100, 0, 0, zero8, zero8, zero6, zero3, [], [], attacks)
	definition.traitor = true
	var battle := BattleDefinition.new("battle.charm-flow", 910, [BattleMonsterSlotDefinition.new(Vector2i.ZERO, definition.id, false)])
	var charm_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, content.start_map_id, content.start_coordinate, content.world, content.scenario, [], [], [], content.race_definitions(), content.caste_definitions(), content.item_definitions(), content.spell_definitions(), [definition], [battle])
	var loyal := CharacterState.new("character.charm-flow.loyal", "Loyal", 20, 20)
	loyal.luck = 1
	loyal.hand_to_hand = 1
	var victim := CharacterState.new("character.charm-flow.victim", "Victim", 20, 20)
	victim.luck = 1
	victim.hand_to_hand = 1
	victim.set_save_value_raw(0, 0)
	var monster := MonsterState.new("monster.charm-flow.instance", definition.id, definition.name, 20, 20, 4, 100)
	var session := GameSession.new()
	session.start(charm_content, 1)
	session._state.party = PartyState.new(content.start_map_id, content.start_coordinate, [loyal, victim])
	session._state.party_setup_completed = true
	session._state.combat = CombatState.new(battle.id, [monster])
	session._state.combat.set_turn_order([loyal.id, monster.id, victim.id])
	session._rng = ScriptedRng.new([32_767, 32_767, 32_767, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	var resolved := session.submit_intent(PlayerIntent.combat_action(&"defend", loyal.id, ""))
	assert_equal(resolved.state, SessionStep.State.COMPLETED, "charm and the resulting charmed turn require no fabricated player interaction")
	assert_true(victim.traitor, "the session owns the charmed party allegiance while battle remains active")
	assert_equal(loyal.current_health, 19, "the charmed character automatically attacks a living combatant of the opposite allegiance")
	var special_index := _event_index(resolved.events, &"combat_monster_special_resolved")
	assert_true(special_index >= 0, "battle flow publishes the typed charm result")
	assert_equal([resolved.events[special_index].payload.get("allegianceBefore"), resolved.events[special_index].payload.get("allegianceAfter")], [false, true], "the charm event exposes its exact allegiance transition")
	var automatic_index := -1
	for index: int in resolved.events.size():
		if resolved.events[index].kind == &"combat_attack_resolved" and resolved.events[index].payload.get("actorId") == victim.id:
			automatic_index = index
			assert_true(resolved.events[index].payload.get("automatic", false), "a charmed party turn is explicitly marked automatic")
			assert_equal(resolved.events[index].payload.get("targetId"), loyal.id, "charmed targeting excludes combatants sharing the attacker's allegiance")
	assert_true(automatic_index > special_index, "the charmed actor proceeds only after the charm attack commits")
	assert_equal(session._state.combat.active_actor_id(), loyal.id, "automatic charm processing returns control to the next loyal party actor")

	var boundary := SaveEnvelope.from_data(session.snapshot().to_data())
	assert_not_null(boundary, "an active charm allegiance and next-turn cursor form a complete save boundary")
	var restored := GameSession.new()
	assert_equal(restored.restore(charm_content, boundary).state, SessionStep.State.COMPLETED, "charmed combat restores transactionally")
	assert_true(restored._state.party.character_by_id(victim.id).traitor, "restore retains battle-scoped party allegiance")
	restored._state.combat.monster_by_id(monster.id).current_health = 0
	var unresolved := restored._rules.combat_flow.continue_after_monster_death_macro(restored._state, charm_content, restored._rng)
	assert_false(unresolved.completed, "a living charmed party member remains an enemy after the original hostile monster falls")
	var restored_view := restored.view()
	assert_equal(restored_view.combat_view.character_targets.map(func(target: CharacterView) -> String: return target.id), [victim.id], "the detached combat view exposes the living charmed character as a hostile target")
	restored._state.party.character_by_id(victim.id).conditions.set_value(ConditionRules.HELPLESS, -1)
	var completed := restored._rules.combat_flow.submit_action(restored._state, charm_content, loyal.id, &"attack", victim.id, restored._rng)
	assert_true(completed.completed and restored._state.combat.outcome == &"victory", "a loyal actor can defeat a charmed party combatant through the ordinary allegiance-aware attack contract")
	assert_false(restored._state.party.character_by_id(victim.id).traitor, "battle cleanup restores every party character's base allegiance")
	assert_true(_event_has(completed.events, &"combat_allegiance_restored"), "allegiance cleanup is presentation-observable")


func _test_aogm_dispatch_has_no_fallback(content: RealmzContent) -> void:
	for opcode: int in ClassicOpcodeCatalog.AOGM_ACTIVE_OPCODES:
		if opcode == 39:
			continue
		var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("dispatch.character", "Dispatch", 10, 10)])
		var api := RealmzRuntimeApi.new(content, GameState.new(party, RealmzClock.new()), RealmzRng.new(1), ScenarioActionState.new())
		var action := ClassicActionDefinition.new(0, opcode, opcode, 0, false, [0, 0, 0, 0, 0])
		var operation := api.execute_classic(action, "request.dispatch", {"callingContext": "action"})
		assert_true(operation != null and operation.error_code != &"unsupported_classic_opcode", "AOGM opcode %d dispatches to its declared runtime owner" % opcode)


func _begin_fixture_adventure(session: GameSession, content: RealmzContent) -> void:
	var races := content.race_definitions()
	var castes := content.caste_definitions()
	assert_false(races.is_empty() or castes.is_empty(), "playable scenario fixture provides one race and class")
	if races.is_empty() or castes.is_empty():
		return
	var character := CharacterState.new("fixture.party.member", "Fixture Hero", 10, 10)
	character.race_id = races[0].id
	character.caste_id = castes[0].id
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(character.id, "1".repeat(64), character.to_data(), "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "scenario fixture imports a deterministic party member")
	assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "scenario fixture explicitly completes party setup")


func _restore_fixture_position(session: GameSession, content: RealmzContent, map_id: String, coordinate: Vector2i) -> void:
	var envelope := session.snapshot()
	envelope.game_state.party.map_id = map_id
	envelope.game_state.party.coordinate = coordinate
	assert_equal(session.restore(content, envelope).state, SessionStep.State.COMPLETED, "scenario route position changes through the validated save boundary")


func _runtime_api(content: RealmzContent, action_state: ScenarioActionState) -> RealmzRuntimeApi:
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("test", "Test", 1, 1)])
	return RealmzRuntimeApi.new(content, GameState.new(party, RealmzClock.new()), RealmzRng.new(1), action_state)


func _aging_race(content: RealmzContent) -> RaceDefinition:
	for race: RaceDefinition in content.race_definitions():
		if race.max_age > 0 and race.age_range(1).x == race.age_range(0).y + 1:
			return race
	return null


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


func _array(values: Array[SafeExpressionDefinition]) -> SafeExpressionDefinition:
	var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.ARRAY)
	expression.set_values(values)
	return expression


func _message_texts(events: Array[DomainEvent]) -> Array[String]:
	var result: Array[String] = []
	for event: DomainEvent in events:
		if event.kind == &"message_shown":
			result.append(event.payload["text"])
	return result


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


func _event_index(events: Array[DomainEvent], kind: StringName) -> int:
	for index: int in events.size():
		if events[index].kind == kind:
			return index
	return -1


func _event_index_with_payload(events: Array[DomainEvent], kind: StringName, field: String, value: Variant) -> int:
	for index: int in events.size():
		if events[index].kind == kind and events[index].payload.get(field) == value:
			return index
	return -1


func _event_classic_id(events: Array[DomainEvent], kind: StringName) -> int:
	for event: DomainEvent in events:
		if event.kind == kind:
			return int(event.payload.get("classicId", -1))
	return -1
