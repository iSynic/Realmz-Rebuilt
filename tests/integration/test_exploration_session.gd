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
	_begin_fixture_adventure(session, content)
	assert_equal(session.view().party_coordinate, Vector2i(1, 1), "Providence start coordinate is authoritative")
	assert_equal(session.view().map_view.cells().size(), 196, "GameView exposes its bounded topology-derived window")
	assert_true(session.view().map_view.can_move(Vector2i.UP), "the detached view exposes an authoritative passable movement direction")
	assert_false(session.view().map_view.can_move(Vector2i.LEFT), "the detached view exposes an authoritative blocked movement direction")
	assert_equal(session.view().map_view.visited_coordinates(), [Vector2i(1, 1)], "the minimap receives only session-owned visited coordinates")
	assert_equal(session.view().map_view.cell_at(Vector2i(2, 2)).overlay_asset_id, "fixture.special-land.neg-99", "the detached presentation view retains the validated special-land overlay identity")
	_test_location_notes(content)
	var diagonal_session := GameSession.new()
	assert_equal(diagonal_session.start(content, 1).state, SessionStep.State.COMPLETED, "a dedicated land-diagonal session starts")
	_begin_fixture_adventure(diagonal_session, content)
	assert_true(diagonal_session.view().map_view.can_move(Vector2i(-1, -1)), "land views expose source-backed diagonal movement availability")
	var diagonal_step := diagonal_session.submit_intent(PlayerIntent.move(Vector2i(-1, -1)))
	assert_equal(diagonal_step.state, SessionStep.State.COMPLETED, "a diagonal land move commits as one ordinary movement step")
	assert_equal(diagonal_session.view().party_coordinate, Vector2i.ZERO, "diagonal land movement changes both coordinates together")
	assert_equal(diagonal_session._state.clock.total_minutes(), content.world.map_by_id("land:0").topology.cell_at(Vector2i.ZERO).movement_cost * 5, "outdoor movement scales the authored Classic timeclick count to five-minute clicks")
	assert_equal(diagonal_session.snapshot().game_state.last_move_direction, Vector2i(-1, -1), "the save aggregate retains the complete diagonal movement vector")
	var restored_diagonal := GameSession.new()
	assert_equal(restored_diagonal.restore(content, SaveEnvelope.from_data(diagonal_session.snapshot().to_data())).state, SessionStep.State.COMPLETED, "diagonal movement state restores transactionally")
	assert_equal(restored_diagonal.snapshot().game_state.last_move_direction, Vector2i(-1, -1), "save/reload preserves a diagonal backup direction")
	var layout_maps: Array[MapDefinition] = [content.world.map_by_id("land:0"), content.world.map_by_id("land:1")]
	var layout_transitions: Array[MapTransition] = [MapTransition.new("layout:land:0:northwest:land:1", "land:0", &"northwest", "land:1", &"southeast")]
	var diagonal_layout_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, "land:0", Vector2i.ZERO, WorldDefinition.new(layout_maps, layout_transitions), ScenarioDefinition.new([], []), [], [], [], content.race_definitions(), content.caste_definitions())
	var diagonal_layout_session := GameSession.new()
	assert_equal(diagonal_layout_session.start(diagonal_layout_content, 1).state, SessionStep.State.COMPLETED, "a diagonal Layout transition session starts")
	_begin_fixture_adventure(diagonal_layout_session, diagonal_layout_content)
	var diagonal_layout_step := diagonal_layout_session.submit_intent(PlayerIntent.move(Vector2i(-1, -1)))
	assert_equal(diagonal_layout_session.view().party_map_id, "land:1", "diagonal boundary input follows the compiled diagonal Layout neighbor")
	assert_equal(diagonal_layout_session.view().party_coordinate, Vector2i(89, 89), "diagonal boundary input wraps to the opposite target corner")
	assert_true(_has_event(diagonal_layout_step, &"map_transitioned"), "diagonal Layout movement publishes the ordinary transition event")
	var restored_diagonal_layout := GameSession.new()
	assert_equal(restored_diagonal_layout.restore(diagonal_layout_content, SaveEnvelope.from_data(diagonal_layout_session.snapshot().to_data())).state, SessionStep.State.COMPLETED, "diagonal Layout movement restores transactionally")
	assert_equal(restored_diagonal_layout.view().party_coordinate, Vector2i(89, 89), "save/reload retains the diagonal Layout destination")

	var north := session.submit_intent(PlayerIntent.move(Vector2i.UP))
	assert_equal(session.view().party_coordinate, Vector2i(1, 0), "typed movement intent commits through GameSession")
	assert_true(_has_event(north, &"message_shown"), "message AP executes on entry")
	assert_equal(north.state, SessionStep.State.WAITING_FOR_INTERACTION, "positive Classic AP text creates a committed acknowledgement boundary")
	assert_equal(north.interaction.kind, &"acknowledge", "the active AP message uses the dedicated textbox interaction")
	assert_false(_has_event(north, &"tile_replaced"), "later AP mutations do not run before the player advances the text")
	var north_snapshot := SaveEnvelope.from_data(session.snapshot().to_data())
	assert_not_null(north_snapshot, "the Classic textbox and movement continuation serialize together")
	var north_restored := GameSession.new()
	assert_equal(north_restored.restore(content, north_snapshot).state, SessionStep.State.COMPLETED, "the Classic textbox boundary restores transactionally")
	var north_completed := north_restored.respond(InteractionResponse.new(north_restored.view().pending_interaction.request_id, &"acknowledge", {}))
	assert_true(_has_event(north_completed, &"tile_replaced"), "Classic opcode 12 mutates the world overlay after acknowledgement")
	assert_true(_has_event(north_completed, &"random_region_triggered"), "random rectangle gates after the moved-to AP finishes")
	var north_trigger_id := content.world.map_by_id("land:0").topology.cell_at(Vector2i(1, 0)).trigger_ids()[0]
	assert_true(north_restored.snapshot().game_state.world.trigger_is_disabled(north_trigger_id), "an ordinary placed Action Point becomes one-shot after its complete resumed timeline")
	session = north_restored
	assert_equal(session.view().map_view.cell_at(Vector2i(2, 2)).terrain_id, "classic.terrain.2", "presenter view reads the same tile overlay as simulation")

	session.submit_intent(PlayerIntent.move(Vector2i.DOWN))
	var blocked_start_minutes := session._state.clock.total_minutes()
	var hidden_destination := content.world.map_by_id("land:0").topology.cell_at(Vector2i(0, 1))
	var blocked := session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_true(_has_event(blocked, &"movement_blocked"), "concealed secret blocks movement before discovery")
	assert_equal(session.view().party_coordinate, Vector2i(1, 1), "blocked movement does not mutate party location")
	assert_equal(session._state.clock.total_minutes(), blocked_start_minutes + hidden_destination.movement_cost * 5, "a blocked land attempt pays the attempted tile's five-minute Classic timeclick cost")
	assert_true(_has_event(blocked, &"random_encounter_checked"), "a timed blocked land attempt performs the downstream random-region check at the committed cell")
	assert_equal(session.snapshot().session_continuation, {}, "a blocked attempt drains its post-time checks before returning a committed boundary")
	var search := session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(search.events[0].payload["roll"], 15, "search follows the centralized RNG after the blocked-attempt random-region draw")
	assert_true(_has_event(search, &"secret_discovered"), "search commits secret discovery")
	assert_true(session.view().map_view.can_move(Vector2i.LEFT), "movement cues update from the same discovered-secret overlay as simulation")
	var secret_entry := session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_equal(session.view().party_coordinate, Vector2i(0, 1), "discovered secret permits movement")
	assert_true(_has_event(secret_entry, &"message_shown"), "secret AP uses the ordinary action sequence")
	assert_equal(secret_entry.state, SessionStep.State.WAITING_FOR_INTERACTION, "secret AP positive text pauses before later player intents")
	assert_equal(session.respond(InteractionResponse.new(secret_entry.interaction.request_id, &"acknowledge", {})).state, SessionStep.State.COMPLETED, "acknowledging secret AP text completes the action sequence")

	_restore_fixture_position(session, content, "land:0", Vector2i(88, 1))
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
	assert_true(restored.snapshot().game_state.world.trigger_is_disabled(north_trigger_id), "save/reload preserves default one-shot Action Point state")

	var keep_source := content.trigger_by_id("ap.fixture.destination-source")
	var keep_program := ScenarioProgramDefinition.new(keep_source.program_id, &"trigger", keep_source.id, [ClassicActionDefinition.new(0, 24, 24, 0, false, [])])
	var keep_trigger := TriggerDefinition.new(keep_source.id, keep_program.id, keep_source.map_id, keep_source.coordinate, keep_source.active, keep_source.chance_percent, keep_source.post_action_location, keep_source.classic_record_index)
	var keep_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, "land:1", Vector2i(0, 1), content.world, ScenarioDefinition.new([keep_program], []), [], [keep_trigger], [], content.race_definitions(), content.caste_definitions())
	var keep_session := GameSession.new()
	keep_session.start(keep_content, 1)
	_begin_fixture_adventure(keep_session, keep_content)
	var kept := keep_session.submit_intent(PlayerIntent.move(Vector2i.UP))
	assert_true(_has_event(kept, &"action_point_kept"), "Classic opcode 24 marks the issuing placed Action Point as Keep Codes")
	assert_false(keep_session.snapshot().game_state.world.trigger_is_disabled(keep_trigger.id), "Keep Codes is the explicit exception to default one-shot Action Points")

	var ordered_ap_content := _duplicate_placed_ap_content(100, content)
	var ordered_ap_session := GameSession.new()
	ordered_ap_session.start(ordered_ap_content, 1)
	_begin_fixture_adventure(ordered_ap_session, ordered_ap_content)
	var ordered_ap_step := ordered_ap_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal(_event_count(ordered_ap_step, &"trigger_fired"), 1, "one coordinate selects only one placed Action Point")
	assert_equal(_event(ordered_ap_step, &"trigger_fired").payload["triggerId"], "ap.first-native", "the lowest Classic record index wins even when cell references are reversed")
	assert_false(ordered_ap_session.snapshot().game_state.world.trigger_is_disabled("ap.later-native"), "a later same-cell Action Point is not executed or consumed")

	var chance_ap_content := _duplicate_placed_ap_content(1, content)
	var chance_ap_session := GameSession.new()
	chance_ap_session.start(chance_ap_content, 1)
	_begin_fixture_adventure(chance_ap_session, chance_ap_content)
	var chance_ap_step := chance_ap_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_false(_has_event(chance_ap_step, &"trigger_fired"), "a failed selected AP chance does not fall through to a later same-cell record")
	assert_equal(chance_ap_session.rng_trace().size(), 1, "a positive sub-100 selected AP consumes one chance draw")
	assert_equal(chance_ap_session.rng_trace()[0]["tag"], "trigger.ap.first-native", "the chance draw belongs to the first native AP")

	var zero_ap_content := _duplicate_placed_ap_content(0, content)
	var zero_ap_session := GameSession.new()
	zero_ap_session.start(zero_ap_content, 1)
	_begin_fixture_adventure(zero_ap_session, zero_ap_content)
	var zero_ap_step := zero_ap_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_false(_has_event(zero_ap_step, &"trigger_fired"), "Classic percent zero disables the selected AP without falling through")
	assert_equal(zero_ap_session.rng_trace().size(), 0, "a disabled selected AP consumes no random draw")

	var disabled_ap_content := _duplicate_placed_ap_content(100, content)
	var disabled_ap_source := GameSession.new()
	disabled_ap_source.start(disabled_ap_content, 1)
	_begin_fixture_adventure(disabled_ap_source, disabled_ap_content)
	var disabled_ap_save := disabled_ap_source.snapshot()
	disabled_ap_save.game_state.world.disable_trigger("ap.first-native")
	var disabled_ap_session := GameSession.new()
	assert_equal(disabled_ap_session.restore(disabled_ap_content, disabled_ap_save).state, SessionStep.State.COMPLETED, "a disabled first-record fixture restores transactionally")
	var disabled_ap_step := disabled_ap_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_false(_has_event(disabled_ap_step, &"trigger_fired"), "a world-disabled selected AP does not fall through to a later same-cell record")
	assert_false(disabled_ap_session.snapshot().game_state.world.trigger_is_disabled("ap.later-native"), "the unselected later AP remains untouched")

	var dungeon_envelope := session.snapshot()
	dungeon_envelope.game_state.party.map_id = "dungeon:0"
	dungeon_envelope.game_state.party.coordinate = Vector2i(2, 0)
	var dungeon_session := GameSession.new()
	assert_equal(dungeon_session.restore(content, dungeon_envelope).state, SessionStep.State.COMPLETED, "validated restore can establish the synthetic dungeon slice")
	var rejected_diagonal := dungeon_session.submit_intent(PlayerIntent.move(Vector2i(-1, -1)))
	assert_equal(rejected_diagonal.error_code, &"invalid_direction", "dungeon movement remains cardinal even when land supports diagonals")
	assert_equal(dungeon_session.view().party_coordinate, Vector2i(2, 0), "a rejected dungeon diagonal cannot mutate location")
	var opened_door := dungeon_session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	var door_id := "dungeon:0:cell:1,0:door"
	assert_true(_has_event(opened_door, &"door_opened"), "entering the explicit dungeon door opens its world overlay")
	assert_true(dungeon_session.snapshot().game_state.world.door_is_open(door_id), "session snapshot owns the opened door")
	var restored_dungeon := GameSession.new()
	assert_equal(restored_dungeon.restore(content, dungeon_session.snapshot()).state, SessionStep.State.COMPLETED, "door-state save restores transactionally")
	assert_true(restored_dungeon.snapshot().game_state.world.door_is_open(door_id), "restored session retains the opened door")

	var surprise_session := GameSession.new()
	surprise_session.start(content, 1)
	_begin_fixture_adventure(surprise_session, content)
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
	_begin_fixture_adventure(door_session, content)
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
	assert_equal(destination_session.view().party_coordinate, Vector2i(0, 0), "the initial movement commits before the source AP textbox is acknowledged")
	assert_equal(_message_ids(relocated), [5], "the source Action Point presents only its current positive message")
	var destination_text := destination_session.respond(InteractionResponse.new(relocated.interaction.request_id, &"acknowledge", {}))
	assert_equal(destination_session.view().party_coordinate, Vector2i(1, 0), "the Classic AP header relocates the party after its actions")
	assert_equal(_message_ids(destination_text), [6], "the destination cell Action Point is rechecked exactly once and presents separately")
	var destination_completed := destination_session.respond(InteractionResponse.new(destination_text.interaction.request_id, &"acknowledge", {}))
	assert_equal(destination_completed.state, SessionStep.State.COMPLETED, "the destination textbox acknowledgement completes the rechecked AP")
	assert_equal(_event_count(relocated, &"party_moved") + _event_count(destination_text, &"party_moved") + _event_count(destination_completed, &"party_moved"), 2, "the initial move and one AP relocation occur without recursive movement")

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


func _test_location_notes(content: RealmzContent) -> void:
	var session := GameSession.new()
	assert_equal(session.start(content, 17).state, SessionStep.State.COMPLETED, "a dedicated location-note session starts")
	_begin_fixture_adventure(session, content)
	var original_coordinate := session._state.party.coordinate
	var initial_view := session.view()
	assert_not_null(initial_view.current_location_note, "the detached view identifies the party's current mapped location")
	assert_equal(initial_view.current_location_note.text, "", "a location without a saved note exposes an empty editor value")
	assert_true(initial_view.location_notes.is_empty(), "a new adventure begins without player-authored location notes")
	assert_true(initial_view.availability(&"set_location_note").enabled, "the core exposes location-note editing at an ordinary exploration boundary")
	var rng_before := session.rng_trace().size()
	var clock_before := session._state.clock.total_minutes()
	var created := session.submit_intent(PlayerIntent.set_location_note("The road narrows beside the old stones."))
	assert_equal(created.state, SessionStep.State.COMPLETED, "saving a current-location note commits synchronously")
	assert_true(_has_event(created, &"location_note_updated"), "location-note creation publishes one explicit domain event")
	assert_equal(session.view().current_location_note.text, "The road narrows beside the old stones.", "the current-location view reflects the committed note")
	assert_equal(session.view().location_notes.size(), 1, "the detached journal list exposes the committed note")
	assert_equal([session.view().location_notes[0].record_ordinal, session.view().location_notes[0].level_type], [0, &"land"], "the first land note preserves Castle's separate source-record order")
	assert_equal([session.rng_trace().size(), session._state.clock.total_minutes()], [rng_before, clock_before], "editing a location note consumes no gameplay RNG or time")
	var unchanged := session.submit_intent(PlayerIntent.set_location_note("The road narrows beside the old stones."))
	assert_equal(unchanged.error_code, &"location_note_unchanged", "an unchanged note is rejected without a false committed revision")
	var dark_envelope := session.snapshot()
	dark_envelope.game_state.world.set_map_darkness("land:0", true)
	dark_envelope.game_state.party.conditions.set_value(0, 60)
	assert_equal(session.restore(content, dark_envelope).state, SessionStep.State.COMPLETED, "the fixture can establish a source-shaped dark land-note boundary")
	var darkness_refresh := session.submit_intent(PlayerIntent.set_location_note("The road narrows beside the old stones."))
	assert_equal(darkness_refresh.state, SessionStep.State.COMPLETED, "saving unchanged text may refresh Castle's saved darkness metadata")
	assert_equal(session.view().current_location_note.darkness_value, 3, "a dark land note retains Castle's torch-derived darkness value")
	var too_long := session.submit_intent(PlayerIntent.set_location_note("é".repeat(128)))
	assert_equal(too_long.error_code, &"location_note_too_long", "the core enforces Castle's 255-byte note field at the typed boundary")
	assert_equal(session.view().current_location_note.text, "The road narrows beside the old stones.", "an oversized note cannot replace committed text")
	var second_land_coordinate := original_coordinate + Vector2i(1, 0)
	assert_not_null(content.world.map_by_id("land:0").topology.cell_at(second_land_coordinate), "the fixture provides a second land-note cell")
	_restore_fixture_position(session, content, "land:0", second_land_coordinate)
	assert_equal(session.submit_intent(PlayerIntent.set_location_note("The lower road.")).state, SessionStep.State.COMPLETED, "a second land note commits at a different current location")
	assert_equal([session.view().location_notes[0].record_ordinal, session.view().location_notes[1].record_ordinal], [0, 1], "land notes browse in source-record order rather than coordinate order")
	_restore_fixture_position(session, content, "dungeon:0", Vector2i(1, 1))
	assert_equal(session.submit_intent(PlayerIntent.set_location_note("Dungeon entrance.")).state, SessionStep.State.COMPLETED, "a dungeon note commits into its independent record stream")
	assert_equal([session.view().location_notes.size(), session.view().location_notes[0].record_ordinal, session.view().location_notes[0].level_type], [1, 0, &"dungeon"], "the detached browser exposes only the current map-kind stream")
	_restore_fixture_position(session, content, "land:0", original_coordinate)
	var saved := SaveEnvelope.from_data(JSON.parse_string(JSON.stringify(session.snapshot().to_data())))
	assert_not_null(saved, "location-note state survives canonical save-envelope serialization")
	var restored := GameSession.new()
	assert_equal(restored.restore(content, saved).state, SessionStep.State.COMPLETED, "location-note state restores transactionally")
	assert_equal(restored.view().location_notes[0].text, "The road narrows beside the old stones.", "restored views retain the exact note text")
	assert_equal([restored.view().location_notes.size(), restored.view().location_notes[1].text], [2, "The lower road."], "restore retains separate stream order without exposing dungeon records on land")
	var cleared := restored.submit_intent(PlayerIntent.set_location_note(""))
	assert_true(_has_event(cleared, &"location_note_removed"), "saving empty text removes the current location note")
	assert_equal([restored.view().location_notes.size(), restored.view().location_notes[0].record_ordinal], [1, 1], "clearing a note frees its record without renumbering later source records")

	var capacity_seed := GameSession.new()
	assert_equal(capacity_seed.start(content, 18).state, SessionStep.State.COMPLETED, "a dedicated capacity session starts")
	_begin_fixture_adventure(capacity_seed, content)
	var capacity_envelope := capacity_seed.snapshot()
	var added: int = 0
	for y: int in 90:
		for x: int in 90:
			var coordinate := Vector2i(x, y)
			if coordinate == capacity_envelope.game_state.party.coordinate:
				continue
			capacity_envelope.game_state.world.upsert_location_note(LocationNoteState.new("land:0", &"land", 0, coordinate, "Note %d" % added, 0, added))
			added += 1
			if added == LocationNoteState.MAX_NOTES_PER_MAP_KIND:
				break
		if added == LocationNoteState.MAX_NOTES_PER_MAP_KIND:
			break
	var capacity_session := GameSession.new()
	assert_equal(capacity_session.restore(content, capacity_envelope).state, SessionStep.State.COMPLETED, "the corrected bounded Classic location-note file restores at exact capacity")
	var capacity_rejection := capacity_session.submit_intent(PlayerIntent.set_location_note("One note too many"))
	assert_equal(capacity_rejection.error_code, &"location_note_capacity", "a new note cannot reproduce Castle's append-beyond-scan record defect")
	var duplicate_ordinal := LocationNoteState.new("land:0", &"land", 0, capacity_envelope.game_state.party.coordinate, "Corrupt duplicate ordinal", 0, 0)
	capacity_envelope.game_state.world._location_notes[duplicate_ordinal.id()] = duplicate_ordinal
	var corrupt_capacity := GameSession.new()
	assert_equal(corrupt_capacity.restore(content, capacity_envelope).error_code, &"invalid_game_state", "restore rejects duplicate source ordinals transactionally")


func _begin_fixture_adventure(session: GameSession, content: RealmzContent) -> void:
	var races := content.race_definitions()
	var castes := content.caste_definitions()
	assert_false(races.is_empty() or castes.is_empty(), "playable exploration fixture provides one race and class")
	if races.is_empty() or castes.is_empty():
		return
	var character := CharacterState.new("fixture.party.member", "Fixture Hero", 10, 10)
	character.race_id = races[0].id
	character.caste_id = castes[0].id
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(character.id, "1".repeat(64), character.to_data(), "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "fixture party import does not consume gameplay RNG")
	assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "exploration fixture explicitly leaves party setup")


func _restore_fixture_position(session: GameSession, content: RealmzContent, map_id: String, coordinate: Vector2i) -> void:
	var envelope := session.snapshot()
	envelope.game_state.party.map_id = map_id
	envelope.game_state.party.coordinate = coordinate
	assert_equal(session.restore(content, envelope).state, SessionStep.State.COMPLETED, "fixture position changes through the validated save boundary")


func _duplicate_placed_ap_content(first_chance: int, source_content: RealmzContent) -> RealmzContent:
	var empty_features: Array[MapFeature] = []
	var empty_ids: Array[String] = []
	var origin_triggers: Array[String] = []
	var target_triggers: Array[String] = ["ap.later-native", "ap.first-native"]
	var cells: Array[MapCell] = [
		MapCell.new("ap-order:cell:0,0", Vector2i.ZERO, "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", origin_triggers, empty_ids, {}, empty_features),
		MapCell.new("ap-order:cell:1,0", Vector2i(1, 0), "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", target_triggers, empty_ids, {}, empty_features),
	]
	var map := MapDefinition.new("ap-order", "Placed AP Order", &"land", 0, MapTopology.new(2, 1, cells))
	var maps: Array[MapDefinition] = [map]
	var first := TriggerDefinition.new("ap.first-native", "program.first-native", map.id, Vector2i(1, 0), true, first_chance, null, 2)
	var later := TriggerDefinition.new("ap.later-native", "program.later-native", map.id, Vector2i(1, 0), true, 100, null, 9)
	var triggers: Array[TriggerDefinition] = [later, first]
	var programs: Array[ScenarioProgramDefinition] = [
		ScenarioProgramDefinition.new(first.program_id, &"trigger", first.id, []),
		ScenarioProgramDefinition.new(later.program_id, &"trigger", later.id, []),
	]
	return RealmzContent.new("ap-order", "0".repeat(64), "ap-order-content", "realmz-classic-1", map.id, Vector2i.ZERO, WorldDefinition.new(maps), ScenarioDefinition.new(programs, []), [], triggers, [], source_content.race_definitions(), source_content.caste_definitions())
