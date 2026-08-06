extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const AOGM_OPCODE_INVENTORY_PATH: String = "res://tests/fixtures/oracle/aogm-active-opcode-inventory.json"


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
	_test_classic_transfer_keeps_trigger_context(loaded.content)
	_test_action_call_limit(loaded.content)
	_test_execution_step_limit(loaded.content)
	_test_unknown_opcode_failure(loaded.content)
	_test_classic_opcode_ownership()
	_test_gameplay_capabilities_and_battle_resume(loaded.content)
	_test_complex_encounter_save_resume(loaded.content)
	_test_equipment_storage_save_resume(loaded.content)
	_test_program_replacement_and_redirect(loaded.content)
	_test_scenario_spell_opcodes(loaded.content)
	_test_combat_fumble_mutation(loaded.content)
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
	assert_equal(completed.state, SessionStep.State.COMPLETED, "typed response resumes simulation without presentation mutation: %s %s" % [completed.error_code, completed.error_message])
	assert_equal(_message_texts(completed.events), ["The encounter result begins.", "The reusable Scenario Action ran.", "The Extra Action Point returns through CODE 111."], "restored interaction follows the same action timeline")
	assert_equal(restored.snapshot().session_continuation, {}, "completed action timeline clears the serialized host continuation")


func _test_classic_shell_domain_route(content: RealmzContent) -> void:
	var session := GameSession.new()
	session.start(content, 1)
	session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	var encounter := session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal(encounter.interaction.kind, &"encounter_choice", "synthetic shell route enters the ordinary Simple Encounter picker")
	assert_not_null(SaveEnvelope.from_data(session.snapshot().to_data()), "encounter picker is a serializable committed boundary")
	var resolved_encounter := session.respond(InteractionResponse.new(encounter.interaction.request_id, &"encounter_choice", {"index": 0}))
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
	var completed := restored.resume(InteractionResponse.new(waiting.interaction.request_id, &"complex_encounter", {"action": "choice", "slot": 0}), api)
	assert_equal(completed.state, ScenarioVmResult.State.COMPLETED, "Complex response branches to its compiled result program: %s" % completed.error_message)
	assert_equal(_message_texts(completed.events), ["The encounter result begins."], "Complex result executes through the same action timeline as APs and Simple Encounters")
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
	var saved := ScenarioVmSnapshot.from_data(vm.snapshot().to_data())
	var restored := ScenarioVm.new()
	restored.configure(definition)
	assert_true(restored.restore(saved), "active battle VM continuation serializes at the player turn")
	var target_id: String = waiting.interaction.payload["targets"][0]["id"]
	var completed := restored.resume(InteractionResponse.new(waiting.interaction.request_id, &"combat_action", {"actorId": character.id, "action": "attack", "targetId": target_id}), api)
	assert_equal(completed.state, ScenarioVmResult.State.COMPLETED, "typed combat response resolves inside the restored session VM")
	assert_equal(state.last_battle_outcome, &"victory", "battle completion and outcome remain in GameState")
	assert_true(_event_has(completed.events, &"battle_completed"), "battle completion is published as a domain event")
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


func _test_combat_fumble_mutation(content: RealmzContent) -> void:
	var character := CharacterState.new("fumble.character", "Fumbler", 10, 10)
	character.maximum_load = 500
	var party := PartyState.new(content.start_map_id, content.start_coordinate, [character])
	var state := GameState.new(party, RealmzClock.new())
	var combat := CombatState.new("classic.battle.0")
	combat.set_turn_order([character.id])
	state.combat = combat
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new())
	var granted := api.execute_safe("core.inventory.grant-item", {"characterId": character.id, "itemId": "classic.item.901", "identified": true}, "request.fumble-item")
	assert_equal(granted.state, ScenarioRuntimeOperationResult.State.COMPLETED, "fumble fixture grants a weapon-like item")
	var instance: ItemInstance = character.inventory()[0]
	assert_true(RealmzRules.new().inventory.equip(character, instance.id, content.item_by_id(instance.definition_id)), "fumble fixture equips the item")
	var fumbled := api.execute_classic(ClassicActionDefinition.new(0, 122, 122, 0, false, [1, 0]), "request.fumble", {"combatantId": character.id})
	assert_equal(fumbled.state, ScenarioRuntimeOperationResult.State.COMPLETED, "Classic opcode 122 resolves inside active combat")
	assert_equal(character.inventory().size(), 0, "fumble removes the equipped item from the combatant")
	assert_equal(party.storage().size(), 1, "fumbled item remains recoverable in session-owned party storage")
	assert_true(_event_has(fumbled.events, &"combatant_fumbled"), "fumble mutation publishes its outcome")


func _test_aogm_dispatch_has_no_fallback(content: RealmzContent) -> void:
	for opcode: int in ClassicOpcodeCatalog.AOGM_ACTIVE_OPCODES:
		if opcode == 39:
			continue
		var party := PartyState.new(content.start_map_id, content.start_coordinate, [CharacterState.new("dispatch.character", "Dispatch", 10, 10)])
		var api := RealmzRuntimeApi.new(content, GameState.new(party, RealmzClock.new()), RealmzRng.new(1), ScenarioActionState.new())
		var action := ClassicActionDefinition.new(0, opcode, opcode, 0, false, [0, 0, 0, 0, 0])
		var operation := api.execute_classic(action, "request.dispatch", {"callingContext": "action"})
		assert_true(operation != null and operation.error_code != &"unsupported_classic_opcode", "AOGM opcode %d dispatches to its declared runtime owner" % opcode)


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


func _event_has(events: Array[DomainEvent], kind: StringName) -> bool:
	for event: DomainEvent in events:
		if event.kind == kind:
			return true
	return false


func _event_classic_id(events: Array[DomainEvent], kind: StringName) -> int:
	for event: DomainEvent in events:
		if event.kind == kind:
			return int(event.payload.get("classicId", -1))
	return -1
