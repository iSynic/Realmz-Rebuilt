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

	var age_source := GameSession.new()
	age_source.start(content, 17)
	_begin_fixture_adventure(age_source, content)
	var age_save := age_source.snapshot()
	var aging_race := _aging_race(content)
	assert_not_null(aging_race, "the fixture contains a complete adjacent Classic age range")
	var first_aging_character := age_save.game_state.party.characters()[0]
	first_aging_character.race_id = aging_race.id
	first_aging_character.age_group = 1
	first_aging_character.age_days = aging_race.age_range(1).x * 365 - 1
	var second_aging_character := CharacterState.from_data(first_aging_character.to_data())
	second_aging_character.id = "fixture.party.second-aging-member"
	second_aging_character.name = "Second Aging Hero"
	assert_true(age_save.game_state.party.add_character(second_aging_character), "the synthetic save carries a second ordered age update")
	age_save.game_state.clock.advance_minutes(RealmzClock.MINUTES_PER_DAY - 1)
	var age_session := GameSession.new()
	assert_equal(age_session.restore(content, age_save).state, SessionStep.State.COMPLETED, "the pre-midnight aging fixture restores")
	var first_age_update := age_session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(first_age_update.state, SessionStep.State.WAITING_FOR_INTERACTION, "crossing midnight blocks at the first Classic age-update dialog")
	assert_equal(first_age_update.interaction.kind, InteractionRequest.AGE_UPDATE, "midnight exposes a dedicated typed age-update request")
	assert_equal(first_age_update.interaction.payload["characterId"], first_aging_character.id, "party order determines the first Castle age-update dialog")
	assert_equal(first_age_update.interaction.payload["changes"].size(), 15, "the request preserves all fifteen displayed Castle age deltas")
	assert_true(first_age_update.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 3002), "opening the age dialog requests Castle sound 3002")
	var age_boundary_save := SaveEnvelope.from_data(age_session.snapshot().to_data())
	assert_not_null(age_boundary_save, "the first age-update click boundary is centrally saveable")
	var age_restored := GameSession.new()
	assert_equal(age_restored.restore(content, age_boundary_save).state, SessionStep.State.COMPLETED, "the ordered age-update queue restores transactionally")
	assert_equal(age_restored.view().pending_interaction.payload["characterId"], first_aging_character.id, "restore retains the exact current age dialog")
	var wrong_age_response := age_restored.respond(InteractionResponse.acknowledge(age_restored.view().pending_interaction))
	assert_equal(wrong_age_response.error_code, &"invalid_interaction_response", "a generic textbox acknowledgement cannot bypass the age-update contract")
	var second_age_update := age_restored.respond(InteractionResponse.age_update(age_restored.view().pending_interaction))
	assert_equal(second_age_update.state, SessionStep.State.WAITING_FOR_INTERACTION, "acknowledging the first character advances to the next ordered age dialog")
	assert_equal(second_age_update.interaction.payload["characterId"], second_aging_character.id, "the second dialog retains Castle party order")
	assert_true(second_age_update.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 3002), "each age dialog independently requests Castle sound 3002")
	var age_completed := age_restored.respond(InteractionResponse.age_update(second_age_update.interaction))
	assert_equal(age_completed.state, SessionStep.State.COMPLETED, "the final age acknowledgement completes the interrupted session operation")
	assert_equal(age_restored.snapshot().session_continuation, {}, "the completed age-update queue clears its save continuation")
	assert_equal([age_restored.view().party_members[0].age_group, age_restored.view().party_members[1].age_group], [2, 2], "both committed age mutations survive the staged presentation boundary")

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
	var saved_age_group := party_save.game_state.party.characters()[0].age_group
	assert_true(saved_age_group >= 1 and saved_age_group <= 5, "the central save owns the character's independent Classic age group")
	var restored_party := GameSession.new()
	assert_equal(restored_party.restore(content, party_save).state, SessionStep.State.COMPLETED, "created party restores transactionally")
	assert_equal(restored_party.view().party_members[0].name, "Ari", "created party survives save and restore")
	assert_equal(restored_party.view().party_members[0].age_group, saved_age_group, "save restoration preserves the exact current age group")
	assert_equal(restored_party.submit_intent(PlayerIntent.create_party([member])).error_code, &"party_setup_closed", "party setup cannot be replayed after restore")
	var legacy_save_data := party_save.to_data()
	legacy_save_data["gameState"]["party"]["characters"][0].erase("ageGroup")
	var legacy_save := SaveEnvelope.from_data(legacy_save_data)
	assert_not_null(legacy_save, "a prerecord ageGroup character remains readable inside save v3")
	var legacy_restored := GameSession.new()
	assert_equal(legacy_restored.restore(content, legacy_save).state, SessionStep.State.COMPLETED, "restore infers missing nested age-group state without changing the save envelope version")
	assert_equal(legacy_restored.view().party_members[0].age_group, saved_age_group, "legacy inference uses the authored age range for the saved character")

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

	var fumble_item := content.item_by_id("classic.item.6")
	assert_not_null(fumble_item, "the integration fixture contains a charged Classic melee weapon")
	if fumble_item != null:
		var fumble_session := GameSession.new()
		fumble_session.start(content, 23)
		var recovery_character := CharacterState.new("fixture.fumble-recipient", "Recovery Hero", 10, 10)
		recovery_character.maximum_load = 500
		fumble_session._state.party = PartyState.new(content.start_map_id, content.start_coordinate, [recovery_character])
		fumble_session._state.party_setup_completed = true
		fumble_session._state.combat = CombatState.new("classic.battle.0")
		fumble_session._state.combat.completed = true
		fumble_session._state.combat.outcome = &"retreated"
		fumble_session._state.last_battle_outcome = &"retreated"
		var dropped := ItemInstance.new("fixture.fumbled-item", fumble_item.id, 7, false, true)
		assert_true(fumble_session._state.combat.queue_fumbled_item(dropped), "a completed retreat retains its battle-local fumbled weapon")
		var ally_step := fumble_session._finish_direct_battle([])
		assert_equal(ally_step.interaction.kind, InteractionRequest.ALLY_SELECTION, "the established body-count stage remains ahead of recovery")
		var recovery_step := fumble_session.respond(InteractionResponse.new(ally_step.interaction.request_id, InteractionRequest.ALLY_SELECTION, {"selectedIds": []}))
		assert_equal(recovery_step.state, SessionStep.State.WAITING_FOR_INTERACTION, "retreat still enters the typed fumbled-weapon recovery boundary")
		assert_equal(recovery_step.interaction.kind, InteractionRequest.TREASURE_DISTRIBUTION, "post-battle recovery uses the dedicated treasure-distribution request")
		var fumble_boundary := SaveEnvelope.from_data(fumble_session.snapshot().to_data())
		assert_not_null(fumble_boundary, "the pending fumble assignment is centrally saveable")
		var recovered_session := GameSession.new()
		assert_equal(recovered_session.restore(content, fumble_boundary).state, SessionStep.State.COMPLETED, "the post-battle recovery request restores transactionally")
		var restored_fumble_request := recovered_session.view().pending_interaction
		var recovered_step := recovered_session.respond(InteractionResponse.new(restored_fumble_request.request_id, InteractionRequest.TREASURE_DISTRIBUTION, {"action": "assign", "instanceId": dropped.id, "characterId": recovery_character.id}))
		assert_equal(recovered_step.state, SessionStep.State.COMPLETED, "assigning the final fumbled weapon completes post-battle processing")
		var recovered_inventory := recovered_session._state.party.character_by_id(recovery_character.id).inventory()
		assert_equal(recovered_inventory.size(), 1, "the selected recipient owns one recovered item")
		if not recovered_inventory.is_empty():
			assert_equal(recovered_inventory[0].to_data(), dropped.to_data(), "save/resume retains the exact recovered instance and charge count")
		assert_true(recovered_session._state.combat.fumbled_items().is_empty(), "save/resume removes the assigned item from the battle queue")


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


func _aging_race(content: RealmzContent) -> RaceDefinition:
	for race: RaceDefinition in content.race_definitions():
		if race.max_age > 0 and race.age_range(1).x == race.age_range(0).y + 1:
			return race
	return null
