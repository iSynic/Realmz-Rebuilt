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
	_begin_fixture_adventure(session, content)
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
	_begin_fixture_adventure(control, content)
	control.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	var control_search := control.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(restored_search.events[0].payload["roll"], control_search.events[0].payload["roll"], "save/reload resumes the exact RNG branch")
	assert_equal(restored.snapshot().rng_state.draw_count, 1, "searching an already discovered area does not invent a random draw")
	assert_equal(restored.snapshot().game_state.clock.total_minutes(), 2, "restored mutation advances the persisted clock")

	var mismatched := SaveEnvelope.new(content.campaign_id, "0".repeat(64), content.rules_version, loaded_save.view_revision, loaded_save.game_state, loaded_save.rng_state)
	var before_failed_restore := restored.snapshot().to_data()
	assert_equal(restored.restore(content, mismatched).error_code, &"package_mismatch", "package mismatch fails explicitly")
	assert_equal(restored.snapshot().to_data(), before_failed_restore, "failed restore leaves the current session untouched")

	var party_session := GameSession.new()
	party_session.start(content, 7)
	var setup_view := party_session.view()
	assert_true(setup_view.party_setup_available, "fresh campaigns expose party creation through the detached view")
	assert_true(not setup_view.race_options.is_empty() and not setup_view.caste_options.is_empty(), "party creation options come from validated package definitions")
	var member := CharacterCreationSpec.new("Ari", setup_view.race_options[0].id, setup_view.caste_options[0].id, 1)
	var party_step := party_session.submit_intent(PlayerIntent.create_party([member]))
	assert_equal(party_step.state, SessionStep.State.COMPLETED, "typed party creation commits through GameSession")
	assert_equal(party_session.view().party_members[0].name, "Ari", "presentation sees the rule-created party member")
	assert_false(party_session.view().party_setup_available, "party creation closes after the committed setup")
	var party_save := party_session.snapshot()
	assert_true(party_save.game_state.party_setup_completed, "central save owns party setup completion")
	var restored_party := GameSession.new()
	assert_equal(restored_party.restore(content, party_save).state, SessionStep.State.COMPLETED, "created party restores transactionally")
	assert_equal(restored_party.view().party_members[0].name, "Ari", "created party survives save and restore")
	assert_equal(restored_party.submit_intent(PlayerIntent.create_party([member])).error_code, &"party_setup_closed", "party setup cannot be replayed after restore")

	var staged_setup := GameSession.new()
	staged_setup.start(content, 11)
	assert_true(staged_setup.view().party_members.is_empty(), "fresh setup has no synthetic placeholder character")
	assert_false(staged_setup.view().availability(&"begin_adventure").enabled, "an empty setup cannot begin the adventure")
	var empty_setup_save := staged_setup.snapshot()
	assert_not_null(empty_setup_save, "an empty committed party-setup boundary is saveable")
	var restored_setup := GameSession.new()
	assert_equal(restored_setup.restore(content, empty_setup_save).state, SessionStep.State.COMPLETED, "empty party setup restores without inventing a member")
	var finalized := restored_setup.submit_intent(PlayerIntent.finalize_character(member))
	assert_equal(finalized.state, SessionStep.State.COMPLETED, "one typed character draft finalizes into session-owned setup state")
	assert_true(restored_setup.view().party_setup_available, "finalizing a character does not implicitly leave party setup")
	assert_equal(restored_setup.view().party_members.size(), 1, "the finalized character appears in the detached setup view")
	assert_true(restored_setup.view().availability(&"begin_adventure").enabled, "a nonempty setup may explicitly begin")
	var staged_setup_save := restored_setup.snapshot()
	var resumed_setup := GameSession.new()
	assert_equal(resumed_setup.restore(content, staged_setup_save).state, SessionStep.State.COMPLETED, "an in-progress assembled party restores at the setup boundary")
	assert_true(resumed_setup.view().party_setup_available, "restored setup remains open after its revision advances")
	var imported := CharacterState.new("vault.character.one", "Vault Hero", 12, 12)
	imported.race_id = setup_view.race_options[0].id
	imported.caste_id = setup_view.caste_options[0].id
	var import_step := resumed_setup.submit_intent(PlayerIntent.import_vault_character(imported.id, "a".repeat(64), imported.to_data(), "fixture-source", "b".repeat(64)))
	assert_equal(import_step.state, SessionStep.State.COMPLETED, "vault import adds another member without completing party setup")
	assert_equal(resumed_setup.view().party_members.size(), 2, "created and vault characters may share one setup party")
	assert_true(resumed_setup.view().party_setup_available, "multiple committed setup edits remain available until Begin")
	var created_id := resumed_setup.view().party_members[0].id
	assert_equal(resumed_setup.submit_intent(PlayerIntent.remove_party_member(created_id)).state, SessionStep.State.COMPLETED, "typed removal updates the setup party")
	assert_equal(resumed_setup.view().party_members.size(), 1, "removal leaves the remaining vault character in setup")
	assert_true(resumed_setup.view().party_setup_available, "removing a member does not begin the adventure")
	assert_equal(resumed_setup.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "Begin explicitly commits the assembled party")
	assert_false(resumed_setup.view().party_setup_available, "party setup closes only after Begin")
	assert_equal(resumed_setup.submit_intent(PlayerIntent.remove_party_member(imported.id)).error_code, &"party_setup_closed", "party composition cannot change after Begin")


func _begin_fixture_adventure(session: GameSession, content: RealmzContent) -> void:
	var races := content.race_definitions()
	var castes := content.caste_definitions()
	assert_false(races.is_empty() or castes.is_empty(), "playable fixture provides one race and class for setup")
	if races.is_empty() or castes.is_empty():
		return
	var character := CharacterState.new("fixture.party.member", "Fixture Hero", 10, 10)
	character.race_id = races[0].id
	character.caste_id = castes[0].id
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(character.id, "1".repeat(64), character.to_data(), "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "fixture vault member enters party setup without consuming RNG")
	assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "fixture party explicitly begins before gameplay intents")
