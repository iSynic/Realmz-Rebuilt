extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func run() -> void:
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "Scenario VM fixture loads: %s" % loaded.error_message)
	if not loaded.is_ok():
		return
	_test_classic_encounter_action_xap_trace(loaded.content)
	_test_session_save_resume_boundary(loaded.content)
	_test_safe_choice_resume(loaded.content)
	_test_persistent_action_state(loaded.content)
	_test_classic_call_limit(loaded.content)
	_test_action_call_limit(loaded.content)
	_test_execution_step_limit(loaded.content)
	_test_unknown_opcode_failure(loaded.content)


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
	assert_equal(resumed.state, ScenarioVmResult.State.COMPLETED, "Encounter Result, Scenario Action, XAP, and CODE 111 complete as one VM trace")
	assert_equal(_message_texts(resumed.events), ["The encounter result begins.", "The reusable Scenario Action ran.", "The Extra Action Point returns through CODE 111."], "ordinary timeline order surrounds the reusable Scenario Action call")
	assert_true(_trace_has(restored.trace(), "call-action"), "VM trace records the Scenario Action frame")
	assert_true(_trace_has(restored.trace(), "classic-transfer"), "VM trace records the XAP transfer")
	assert_true(_trace_has(restored.trace(), "classic-return"), "VM trace records CODE 111 return")


func _test_session_save_resume_boundary(content: RealmzContent) -> void:
	var session := GameSession.new()
	session.start(content, 1)
	session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
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
	var completed := restored.respond(InteractionResponse.new(request.request_id, &"encounter_choice", {"index": 0}))
	assert_equal(completed.state, SessionStep.State.COMPLETED, "typed response resumes simulation without presentation mutation")
	assert_equal(_message_texts(completed.events), ["The encounter result begins.", "The reusable Scenario Action ran.", "The Extra Action Point returns through CODE 111."], "restored interaction follows the same action timeline")
	assert_equal(restored.snapshot().session_continuation, {}, "completed action timeline clears the serialized host continuation")


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
