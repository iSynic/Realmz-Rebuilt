extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func run() -> void:
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "exploration fixture loads: %s" % loaded.error_message)
	if not loaded.is_ok():
		return
	var content := loaded.content
	var session := GameSession.new()
	assert_equal(session.start(content, 1).state, SessionStep.State.COMPLETED, "exploration session starts")
	assert_equal(session.view().party_coordinate, Vector2i(1, 1), "Providence start coordinate is authoritative")
	assert_equal(session.view().map_view.cells().size(), 9, "GameView exposes a topology-derived map")

	var north := session.submit_intent(PlayerIntent.move(Vector2i.UP))
	assert_equal(session.view().party_coordinate, Vector2i(1, 0), "typed movement intent commits through GameSession")
	assert_true(_has_event(north, &"message_shown"), "message AP executes on entry")
	assert_true(_has_event(north, &"tile_replaced"), "Classic opcode 12 mutates the world overlay")
	assert_true(_has_event(north, &"random_region_triggered"), "random rectangle gates through the moved-to topology cell")
	assert_equal(session.view().map_view.cell_at(Vector2i(2, 2)).terrain_id, "classic.terrain.2", "presenter view reads the same tile overlay as simulation")

	session.submit_intent(PlayerIntent.move(Vector2i.DOWN))
	var blocked := session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_true(_has_event(blocked, &"movement_blocked"), "concealed secret blocks movement before discovery")
	assert_equal(session.view().party_coordinate, Vector2i(1, 1), "blocked movement does not mutate party location")
	var search := session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(search.events[0].payload["roll"], 37, "search follows Castle random-rectangle draw ordering through the centralized RNG")
	assert_true(_has_event(search, &"secret_discovered"), "search commits secret discovery")
	var secret_entry := session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_equal(session.view().party_coordinate, Vector2i(0, 1), "discovered secret permits movement")
	assert_true(_has_event(secret_entry, &"message_shown"), "secret AP uses the ordinary action sequence")

	session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	var transitioned := session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal(session.view().party_map_id, "land:1", "edge movement follows the compiled Layout transition")
	assert_equal(session.view().party_coordinate, Vector2i(0, 1), "transition preserves the cross-edge offset")
	assert_true(_has_event(transitioned, &"map_transitioned"), "map transition is an explicit domain event")

	var snapshot := session.snapshot()
	var replacement_cell := content.world.map_by_id("land:0").topology.cell_at(Vector2i(2, 2))
	assert_equal(snapshot.game_state.world.terrain_for("land:0", replacement_cell), "classic.terrain.2", "save aggregate owns tile mutation")
	var restored := GameSession.new()
	assert_equal(restored.restore(content, snapshot).state, SessionStep.State.COMPLETED, "exploration aggregate restores transactionally")
	assert_equal(restored.view().party_map_id, "land:1", "restored session retains transitioned map")
	assert_equal(restored.snapshot().game_state.world.terrain_for("land:0", replacement_cell), "classic.terrain.2", "restored session retains world overlays")

	var dungeon_envelope := session.snapshot()
	dungeon_envelope.game_state.party.map_id = "dungeon:0"
	dungeon_envelope.game_state.party.coordinate = Vector2i(2, 0)
	var dungeon_session := GameSession.new()
	assert_equal(dungeon_session.restore(content, dungeon_envelope).state, SessionStep.State.COMPLETED, "validated restore can establish the synthetic dungeon slice")
	var opened_door := dungeon_session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	var door_id := "dungeon:0:cell:1,0:door"
	assert_true(_has_event(opened_door, &"door_opened"), "entering the explicit dungeon door opens its world overlay")
	assert_true(dungeon_session.snapshot().game_state.world.door_is_open(door_id), "session snapshot owns the opened door")
	var restored_dungeon := GameSession.new()
	assert_equal(restored_dungeon.restore(content, dungeon_session.snapshot()).state, SessionStep.State.COMPLETED, "door-state save restores transactionally")
	assert_true(restored_dungeon.snapshot().game_state.world.door_is_open(door_id), "restored session retains the opened door")

	var surprise_session := GameSession.new()
	surprise_session.start(content, 1)
	surprise_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	var surprise_wait := surprise_session.submit_intent(PlayerIntent.move(Vector2i.UP))
	assert_equal(surprise_wait.state, SessionStep.State.WAITING_FOR_INTERACTION, "a source-backed random rectangle can yield a typed surprise choice")
	assert_equal(surprise_wait.interaction.kind, &"yes_no", "the random surprise uses the ordinary interaction presenter ABI")
	assert_equal(surprise_session.rng_trace()[-1]["tag"], "random-region.land:0:randlevel:rect:1.good-surprise", "Castle random-region draw order reaches the surprise roll after three door rolls")
	var surprise_snapshot := surprise_session.snapshot()
	assert_not_null(surprise_snapshot, "the random surprise interaction is a committed save boundary")
	assert_equal(surprise_snapshot.session_interaction.request_id, surprise_wait.interaction.request_id, "the save aggregate owns the non-VM interaction")
	assert_equal(surprise_snapshot.session_continuation["randomBattleStage"], "surprise-choice", "the save aggregate owns random battle continuation state")
	var restored_surprise := GameSession.new()
	assert_equal(restored_surprise.restore(content, SaveEnvelope.from_data(surprise_snapshot.to_data())).state, SessionStep.State.COMPLETED, "random surprise save restores transactionally")
	var accepted := restored_surprise.respond(InteractionResponse.new(surprise_wait.interaction.request_id, &"yes_no", {"accepted": true}))
	assert_true(_has_event(accepted, &"random_encounter_triggered"), "accepting the surprise choice starts the selected random battle")
	assert_equal(_event(accepted, &"battle_started").payload["surprise"], 1, "accepted random surprise gives the party source-backed initiative")
	var battle_coordinate := restored_surprise.view().party_coordinate
	var blocked_during_battle := restored_surprise.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_equal(blocked_during_battle.error_code, &"battle_in_progress", "active combat rejects exploration intents at the session boundary")
	assert_equal(restored_surprise.view().party_coordinate, battle_coordinate, "rejected combat-time movement cannot mutate topology state")
	var declined_surprise := GameSession.new()
	declined_surprise.restore(content, surprise_snapshot)
	var declined := declined_surprise.respond(InteractionResponse.new(surprise_wait.interaction.request_id, &"yes_no", {"accepted": false}))
	assert_equal(declined.state, SessionStep.State.COMPLETED, "declining an only-region surprise cleanly resumes exploration")
	assert_true(declined_surprise.view().combat_view == null, "declining the random encounter does not create combat state")
	assert_equal(declined_surprise.snapshot().session_continuation, {}, "declining the only region clears its continuation")

	var door_session := GameSession.new()
	door_session.start(content, 1)
	door_session.submit_intent(PlayerIntent.move(Vector2i.DOWN))
	var first_door := door_session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_true(_has_event(first_door, &"random_door_triggered"), "a positive random-door chance invokes its XAP through the normal VM")
	var door_region := content.world.map_by_id("land:0").random_region_by_id("land:0:randlevel:rect:2")
	assert_equal(door_session.snapshot().game_state.world.random_region(door_region).random_door_percents()[0], 0, "a positive random-door chance becomes one-shot world state")
	var restored_door := GameSession.new()
	restored_door.restore(content, door_session.snapshot())
	restored_door.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	var second_door := restored_door.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_false(_has_event(second_door, &"random_door_triggered"), "save/reload preserves consumed random doors")

	var destination_envelope := session.snapshot()
	destination_envelope.game_state.party.map_id = "land:1"
	destination_envelope.game_state.party.coordinate = Vector2i(0, 1)
	var destination_session := GameSession.new()
	assert_equal(destination_session.restore(content, destination_envelope).state, SessionStep.State.COMPLETED, "validated restore establishes the AP destination fixture")
	var relocated := destination_session.submit_intent(PlayerIntent.move(Vector2i.UP))
	assert_equal(destination_session.view().party_coordinate, Vector2i(1, 0), "the Classic AP header relocates the party after its actions")
	assert_equal(_message_ids(relocated), [5, 6], "the destination cell Action Point is rechecked exactly once")
	assert_equal(_event_count(relocated, &"party_moved"), 2, "the initial move and one AP relocation occur without recursive movement")

	var v1_data := session.snapshot().to_data()
	v1_data["formatVersion"] = 1
	v1_data.erase("sessionInteraction")
	var migrated_v1 := SaveEnvelope.from_data(v1_data)
	assert_not_null(migrated_v1, "save v1 migrates through the ordered pure transform")
	assert_equal(migrated_v1.to_data()["formatVersion"], 3, "migrated saves serialize as the current envelope version")
	var v2_data := surprise_snapshot.to_data()
	v2_data["formatVersion"] = 2
	v2_data["sessionContinuation"].erase("actionPointDestinationDepth")
	var migrated_v2 := SaveEnvelope.from_data(v2_data)
	assert_not_null(migrated_v2, "save v2 migrates through the ordered AP-destination transform")
	assert_equal(migrated_v2.session_continuation["actionPointDestinationDepth"], 0, "save v2 resumes before any AP destination recheck")


func _has_event(step: SessionStep, event_kind: StringName) -> bool:
	for event: DomainEvent in step.events:
		if event.kind == event_kind:
			return true
	return false


func _event(step: SessionStep, event_kind: StringName) -> DomainEvent:
	for event: DomainEvent in step.events:
		if event.kind == event_kind:
			return event
	return null


func _event_count(step: SessionStep, event_kind: StringName) -> int:
	var count := 0
	for event: DomainEvent in step.events:
		if event.kind == event_kind:
			count += 1
	return count


func _message_ids(step: SessionStep) -> Array[int]:
	var ids: Array[int] = []
	for event: DomainEvent in step.events:
		if event.kind == &"message_shown":
			ids.append(int(event.payload.get("messageId", -1)))
	return ids
