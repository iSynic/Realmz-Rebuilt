extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func run() -> void:
	var package_result := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(package_result.is_ok(), "integration fixture loads before session work")
	if not package_result.is_ok():
		return
	var content := package_result.content
	var session := GameSession.new()
	assert_equal(session.start(content, 1).state, SessionStep.State.COMPLETED, "validated content starts synchronously")
	var first_search := session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(first_search.state, SessionStep.State.COMPLETED, "search commits at one session boundary")
	assert_equal(first_search.events[0].payload["roll"], 52, "the committed event records the first deterministic draw")
	assert_equal(session.snapshot().rng_state.draw_count, 1, "the save aggregate owns the RNG draw count")
	assert_equal(session.snapshot().game_state.clock.total_minutes(), 1, "the save aggregate owns the Realmz clock")
	var held_snapshot := session.snapshot()
	session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(held_snapshot.rng_state.draw_count, 1, "a snapshot is detached from later session RNG mutations")
	assert_equal(held_snapshot.game_state.clock.total_minutes(), 1, "a snapshot is detached from later game-state mutations")

	var saves := SaveRepository.new("user://realmz2-tests/phase1-saves")
	assert_true(saves.save(content.campaign_id, "slot-a", held_snapshot), "verified temporary save is atomically installed: %s" % saves.last_error)
	var loaded_save := saves.load(content.campaign_id, "slot-a", content.package_hash)
	assert_not_null(loaded_save, "the complete save envelope reloads: %s" % saves.last_error)
	if loaded_save == null:
		return
	var restored := GameSession.new()
	assert_equal(restored.restore(content, loaded_save).state, SessionStep.State.COMPLETED, "transactional restore constructs a replacement session")
	assert_equal(restored.snapshot().rng_state.to_data(), held_snapshot.rng_state.to_data(), "restore retains the exact RNG state and draw index")
	var restored_search := restored.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))

	var control := GameSession.new()
	control.start(content, 1)
	control.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	var control_search := control.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(restored_search.events[0].payload["roll"], control_search.events[0].payload["roll"], "save/reload resumes the exact RNG branch")
	assert_equal(restored.snapshot().rng_state.draw_count, 1, "searching an already discovered area does not invent a random draw")
	assert_equal(restored.snapshot().game_state.clock.total_minutes(), 2, "restored mutation advances the persisted clock")

	var mismatched := SaveEnvelope.new(content.campaign_id, "0".repeat(64), content.rules_version, loaded_save.view_revision, loaded_save.game_state, loaded_save.rng_state)
	var before_failed_restore := restored.snapshot().to_data()
	assert_equal(restored.restore(content, mismatched).error_code, &"package_mismatch", "package mismatch fails explicitly")
	assert_equal(restored.snapshot().to_data(), before_failed_restore, "failed restore leaves the current session untouched")
