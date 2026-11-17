extends RealmzTestCase

## Castle's click-to-continue text before a scripted fight: the instruction's own message,
## then the chosen battle's before-message, then the battle (issue 45).

const WAR := "res://src/storage/packages/bundled_campaigns/scenario-war-in-the-sword-lands.realmz2"


func run() -> void:
	var loaded := load_test_package(WAR)
	if not loaded.is_ok():
		return
	_test_instruction(loaded.content)
	_test_session(loaded.content)


func _party(prefix: String, content: RealmzContent) -> Array[CharacterState]:
	var members: Array[CharacterState] = []
	for index: int in range(6):
		var character := CharacterState.new("%s.%d" % [prefix, index], "Hero %d" % index, 1000, 1000)
		character.race_id = content.characters.race_definitions()[0].id
		character.caste_id = content.characters.caste_definitions()[0].id
		members.append(character)
	return members


func _shown(events: Array[DomainEvent], message_id: int) -> int:
	return events.filter(func(event: DomainEvent) -> bool: return event.kind == &"message_shown" and event.payload.get("messageId") == message_id).size()


func _test_instruction(content: RealmzContent) -> void:
	var program := content.scenario.program_by_id("xap:13")
	var action: ClassicActionDefinition = program.instruction_at(1) if program != null else null
	assert_true(action != null and action.opcode == 56 and action.extra_code == [92, 92, 1064, 210, 22], "XAP 13 retains its authored pursuit battle row")
	if action == null:
		return
	var battle := content.combat.battle_by_classic_id(92)
	assert_true(battle != null and battle.message_before_id == 78 and content.scenario_records.message_by_id(22).text.contains("Sharranth"), "battle 92 has its own before-message and message 22 is the pursuit text")
	var state := GameState.new(PartyState.new("land:0", Vector2i(1, 72), _party("prelude", content)), RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(7), ScenarioActionState.new(), RealmzRules.new())
	var first := api.execute_classic(action, "prelude.1")
	var first_body := first.continuation.body as ScenarioBattlePreludeBody if first.continuation != null else null
	assert_true(first.state == ScenarioRuntimeOperationResult.State.WAITING and first.interaction != null and first.interaction.kind == InteractionRequest.ACKNOWLEDGE and state.combat == null, "the instruction's message waits for a click before any battle exists")
	assert_true(first_body != null and first_body.stage == ScenarioBattlePreludeBody.INSTRUCTION and first_body.message_id == 22 and _shown(first.events, 22) == 1 and JSON.stringify(first.interaction.to_data()).contains("Sharranth"), "the wait shows message 22 once and carries it in the request")
	assert_true(first.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 210), "the authored sound still plays with the message")
	if first_body == null:
		return
	var wire: Dictionary = JSON.parse_string(JSON.stringify(first.continuation.to_data()))
	var restored := ScenarioRuntimeContinuation.from_data(wire)
	var round_trip: bool = restored != null and JSON.parse_string(JSON.stringify(restored.to_data())) == wire
	assert_true(round_trip, "the suspended instruction round-trips through its saved form")
	assert_true(api.resume_classic(first.continuation, InteractionResponse.yes_no(first.interaction, true), "prelude.x").state != ScenarioRuntimeOperationResult.State.WAITING and state.combat == null, "only an acknowledgement continues past the message")
	var noted := InteractionResponse.acknowledge(first.interaction)
	(noted.body as InteractionResponse.AcknowledgeBody).take_note = true
	var second := api.resume_classic(restored, noted, "prelude.2")
	var second_body := second.continuation.body as ScenarioBattlePreludeBody if second.continuation != null else null
	assert_true(second.state == ScenarioRuntimeOperationResult.State.WAITING and second.interaction != null and second.interaction.kind == InteractionRequest.ACKNOWLEDGE and state.combat == null, "the battle's before-message waits for its own click")
	assert_true(second_body != null and second_body.stage == ScenarioBattlePreludeBody.BATTLE and second_body.battle_number == 92 and second_body.message_id == 78 and _shown(second.events, 78) == 1, "the second wait names battle 92 and shows message 78")
	assert_true(state.scenario_progress.journal_message_is_recorded(22), "taking a note records the acknowledged message in the journal")
	if second_body == null:
		return
	var third := api.resume_classic(second.continuation, InteractionResponse.acknowledge(second.interaction), "prelude.3")
	assert_true(third.state == ScenarioRuntimeOperationResult.State.WAITING and third.interaction != null and third.interaction.kind == &"combat_action" and state.combat != null and state.combat.battle_id == "classic.battle.92", "after both clicks the party is in actionable battle 92")
	assert_true(_shown(third.events, 78) == 0 and _shown(third.events, 22) == 0 and third.began_combat, "neither message repeats when the battle starts")


func _test_session(content: RealmzContent) -> void:
	var session := GameSession.new()
	assert_equal(session.start(content, 45).state, SessionStep.State.COMPLETED, "the pursuit fixture starts")
	session._context.state.party = PartyState.new("land:0", Vector2i(1, 72), _party("pursuit", content))
	session._context.state.party_setup_completed = true
	var step := session.apply_debug_command(SessionDebugCommand.start_extra_action_point_program(13))
	# Debug-started programs are deliberately unsaveable; lift that so the pause itself is saved.
	session._debug_operation_active = false
	var seen: Array[int] = []
	for response_index: int in range(8):
		if step.state != SessionStep.State.WAITING_FOR_INTERACTION or step.interaction.kind != InteractionRequest.ACKNOWLEDGE:
			break
		var request := step.interaction
		var request_data: Dictionary = request.to_data()["data"]
		var payload: Dictionary = request_data["payload"]
		var message_id: int = payload.get("messageId", 0)
		seen.append(message_id)
		if message_id in [22, 78]:
			assert_equal(session.view().combat_view, null, "no battle exists while message %d waits" % message_id)
			var reloaded := session.restore(content, save_round_trip(session.snapshot()))
			assert_equal(reloaded.state, SessionStep.State.COMPLETED, "a save taken while message %d waits restores: %s" % [message_id, reloaded.error_message])
			request = session.view().pending_interaction
			assert_true(request != null and request.kind == InteractionRequest.ACKNOWLEDGE, "the restored session is still waiting on message %d" % message_id)
			if request == null:
				return
		step = session.respond(InteractionResponse.acknowledge(request))
	assert_true(seen.has(22) and seen.has(78) and seen.find(22) < seen.find(78), "the session asks for message 22 and then message 78: %s" % str(seen))
	assert_true(step.state != SessionStep.State.FAILED and session.view().combat_view != null and session.view().pending_interaction != null and session.view().pending_interaction.kind == &"combat_action", "both clicks lead into the fight: %s" % step.error_message)
