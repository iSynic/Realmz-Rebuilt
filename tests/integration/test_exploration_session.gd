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
	assert_true(_has_event(north, &"tile_replaced"), "AP replacement mutates the world overlay")
	assert_true(_has_event(north, &"random_encounter_triggered"), "random rectangle gates through the moved-to topology cell")
	assert_equal(session.view().map_view.cell_at(Vector2i(2, 2)).terrain_id, "classic.terrain.2", "presenter view reads the same tile overlay as simulation")

	session.submit_intent(PlayerIntent.move(Vector2i.DOWN))
	var blocked := session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_true(_has_event(blocked, &"movement_blocked"), "concealed secret blocks movement before discovery")
	assert_equal(session.view().party_coordinate, Vector2i(1, 1), "blocked movement does not mutate party location")
	var search := session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(search.events[0].payload["roll"], 52, "search uses the centralized Castle-compatible RNG")
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


func _has_event(step: SessionStep, event_kind: StringName) -> bool:
	for event: DomainEvent in step.events:
		if event.kind == event_kind:
			return true
	return false
