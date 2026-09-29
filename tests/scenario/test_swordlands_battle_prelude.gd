extends RealmzTestCase


func run() -> void:
	var loaded := load_test_package("res://src/storage/packages/bundled_campaigns/scenario-trouble-in-the-sword-lands.realmz2")
	assert_true(loaded.is_ok(), "Trouble in the Sword Lands package loads for the reported AP")
	if not loaded.is_ok():
		return
	var content: RealmzContent = loaded.content
	_test_pit_party_loss(content)
	_test_locked_door_failure(content)
	var program := content.scenario.program_by_id("trigger:Data DD:18:7")
	var action: ClassicActionDefinition = program.instruction_at(3) if program != null else null
	assert_true(action != null and action.opcode == 2 and action.extra_code == [180, 180, 2221, 10136, 0], "land 18 AP 7 retains its authored battle row")
	if action == null:
		return
	assert_true(content.scenario_records.message_by_id(10136) == null and not content.has_media_resource("snd ", 2221), "the prelude message and sound really are absent")
	var party := PartyState.new("land:18", Vector2i(73, 22), [CharacterState.new("swordlands.hero", "Hero", 30, 30)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(7), ScenarioActionState.new(), RealmzRules.new())
	var result := api.execute_classic(action, "swordlands.land18.ap7.battle")
	assert_equal(result.state, ScenarioRuntimeOperationResult.State.WAITING, "missing optional prelude does not prevent battle 180 from starting")
	assert_true(state.combat != null and state.combat.battle_id == "classic.battle.180" and result.interaction != null and result.interaction.kind == &"combat_action", "reported AP enters an actionable battle")
	assert_true(not result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"message_shown" and event.payload.get("source") == "classic-battle"), "missing message is not fabricated")
	assert_true(result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 2221), "the authored sound identity reaches the nonblocking media resolver")
	var vm_party_members: Array[CharacterState] = []
	for index: int in range(6):
		vm_party_members.append(CharacterState.new("swordlands.vm.%d" % index, "Hero %d" % index, 1000, 1000))
	var vm_state := GameState.new(PartyState.new("land:18", Vector2i(73, 22), vm_party_members), RealmzClock.new())
	var vm_api := RealmzRuntimeApi.new(content, vm_state, RealmzRng.new(7), ScenarioActionState.new(), RealmzRules.new())
	var vm := ScenarioVm.new()
	vm.configure(content.scenario)
	vm.start_program(program.id, ScenarioExecutionContext.trigger(&"action-point", "Data DD:18:7", "land:18", Vector2i(73, 22), true))
	var ap_result := vm.run(vm_api)
	for step: int in range(4):
		if ap_result.state != ScenarioVmResult.State.WAITING or ap_result.interaction.kind != InteractionRequest.ACKNOWLEDGE:
			break
		ap_result = vm.resume(InteractionResponse.acknowledge(ap_result.interaction), vm_api)
	assert_true(ap_result.state == ScenarioVmResult.State.WAITING and ap_result.interaction != null and ap_result.interaction.kind == &"combat_action" and vm_state.combat != null and vm_state.combat.battle_id == "classic.battle.180", "the compiled AP itself reaches battle 180 after its authored narration (state %d, interaction %s, error %s)" % [ap_result.state, ap_result.interaction.kind if ap_result.interaction != null else "none", ap_result.error_message])


func _test_pit_party_loss(content: RealmzContent) -> void:
	var program := content.scenario.program_by_id("trigger:Data DD:8:82")
	assert_equal(program.instruction_at(5).extra_code, [2701, 7, -100, 1, 0], "Land 8 AP 82 retains its forced lethal spell")
	for searching: bool in [false, true]:
		var session := GameSession.new()
		assert_equal(session.start(content, 82).state, SessionStep.State.COMPLETED, "pit fixture starts")
		var members: Array[CharacterState] = []
		for index: int in range(6):
			var character := CharacterState.new("pit.hero.%d" % index, "Hero %d" % index, 30, 30)
			character.race_id = content.characters.race_definitions()[0].id
			character.caste_id = content.characters.caste_definitions()[0].id
			members.append(character)
		session._context.state.party = PartyState.new("land:8", Vector2i(65, 25), members)
		session._context.state.party_setup_completed = true
		if searching:
			session._context.state.party.conditions.set_value(ConditionRules.PARTY_SEARCHING, -1)
		var step := session.submit_intent(ExplorationIntents.move(Vector2i.UP))
		var events: Array[DomainEvent] = step.events.duplicate()
		for acknowledgement: int in range(4):
			if step.state != SessionStep.State.WAITING_FOR_INTERACTION or step.interaction.kind != InteractionRequest.ACKNOWLEDGE:
				break
			step = session.respond(InteractionResponse.acknowledge(step.interaction))
			events.append_array(step.events)
		assert_true(step.state != SessionStep.State.FAILED, "pit route completes without an execution failure: %s" % step.error_message)
		assert_equal(session.view().session_started, searching, "Search avoids the pit; without Search, total-party loss ends the adventure")
		assert_equal(events.any(func(event: DomainEvent) -> bool: return event.kind == &"session_ended"), not searching, "the pit publishes the ordinary session-ended event only on the lethal branch")
		assert_equal(members.all(func(character: CharacterState) -> bool: return character.current_health <= 0), not searching, "only the unprotected party dies")


func _test_locked_door_failure(content: RealmzContent) -> void:
	var session := GameSession.new()
	assert_equal(session.start(content, 89).state, SessionStep.State.COMPLETED, "door fixture starts")
	var character := CharacterState.new("door.hero", "Locksmith", 100, 100)
	character.race_id = content.characters.race_definitions()[0].id
	character.caste_id = content.characters.caste_definitions()[0].id
	character.set_ability_value(6, 120)
	character.set_ability_value(7, 50)
	character.set_ability_value(11, 50)
	session._context.state.party = PartyState.new("land:7", Vector2i(35, 51), [character])
	session._context.state.party_setup_completed = true
	session._context.state.party.conditions.set_value(ConditionRules.PARTY_SEARCHING, -1)
	var step := session.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	var events: Array[DomainEvent] = step.events.duplicate()
	var actions: Array[int] = [1, 2, 6]
	for response_index: int in range(16):
		if step.state != SessionStep.State.WAITING_FOR_INTERACTION:
			break
		var request := step.interaction
		var body: InteractionResponse.Body
		match request.kind:
			InteractionRequest.ACKNOWLEDGE:
				body = InteractionResponse.AcknowledgeBody.new()
			InteractionRequest.WORD_AND_ACTION:
				body = InteractionResponse.ComplexEncounterBody.new(&"thief")
			InteractionRequest.THIEF_ENCOUNTER:
				assert_false(actions.is_empty(), "door resolves after the three attempted thief actions")
				if actions.is_empty(): return
				body = InteractionResponse.ThiefEncounterBody.new(&"attempt", character.id, actions.pop_front())
			InteractionRequest.PICK_LOCK:
				body = InteractionResponse.PickLockBody.new(0)
			_:
				assert_true(false, "unexpected door interaction: %s" % request.kind)
				return
		step = session.respond(InteractionResponse.new(request.request_id, request.kind, body))
		events.append_array(step.events)
	assert_equal(step.state, SessionStep.State.COMPLETED, "failed pick completes the authored result: %s" % step.error_message)
	assert_equal(session.view().party_coordinate, Vector2i(35, 51), "failure pushes the party out of the door")
	assert_false(session._context.state.world.triggers.trigger_is_disabled("Data DD:7:89"), "failure does not unlock the door AP")
	assert_true(events.any(func(event: DomainEvent) -> bool: return event.kind == &"message_shown" and event.payload.get("messageId") == 1049), "Result 3 displays its valid failure message")
	assert_false(events.any(func(event: DomainEvent) -> bool: return event.kind == &"message_shown" and event.payload.get("messageId") == 10049), "the unavailable thief text is never fabricated")
	assert_true(character.current_health < 100, "the failed disarm still applies the trap damage")
	var retried := session.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	assert_true(retried.state == SessionStep.State.WAITING_FOR_INTERACTION and retried.interaction.kind == InteractionRequest.ACKNOWLEDGE and (retried.interaction.body as AcknowledgeRequestBody).message_id == 251, "attempting to cross again still enters the locked-door AP")
