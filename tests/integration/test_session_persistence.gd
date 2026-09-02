extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func selected_case_arguments() -> Array:
	var package_result := PackageRepository.new().load_package(FIXTURE_PATH)
	return [package_result.content if package_result.is_ok() else null]


func run() -> void:
	var content: RealmzContent = selected_case_arguments()[0]
	assert_not_null(content, "integration fixture loads before session work")
	if content == null:
		return
	_test_lifecycle_close_persistence(content)
	_test_snapshot_rng_and_age_persistence(content)
	_test_party_and_creator_persistence(content)
	_test_combat_and_reward_persistence(content)


func _test_lifecycle_close_persistence(content: RealmzContent) -> void:
	var closing_session := GameSession.new()
	assert_equal(closing_session.start(content, 5).state, SessionStep.State.COMPLETED, "a lifecycle fixture starts from validated content")
	var closing_snapshot := closing_session.snapshot()
	assert_not_null(closing_snapshot, "End Adventure can preserve the committed boundary before closing")
	var close_step := closing_session.close()
	assert_equal([close_step.state, close_step.interaction.body.to_data().get("prompt")], [SessionStep.State.WAITING_FOR_INTERACTION, "The End Adventure application hook runs."], "End Adventure runs its Global hook before party release")
	var end_hook_snapshot := closing_session.snapshot()
	assert_not_null(end_hook_snapshot, "the End Adventure hook is a committed save boundary")
	var end_hook_data := save_data(end_hook_snapshot)
	var missing_hook_field: Dictionary = end_hook_data.duplicate(true)
	missing_hook_field["sessionContinuation"]["data"].erase("partyRevived")
	assert_equal(SaveEnvelope.from_data(missing_hook_field), null, "the save envelope rejects an incomplete application-hook continuation")
	var wrong_hook_type: Dictionary = end_hook_data.duplicate(true)
	wrong_hook_type["sessionContinuation"]["data"]["partyRevived"] = 1
	assert_equal(SaveEnvelope.from_data(wrong_hook_type), null, "the save envelope rejects a mistyped application-hook continuation")
	var wrong_hook_resume: Dictionary = end_hook_data.duplicate(true)
	wrong_hook_resume["sessionContinuation"]["data"]["hook"] = String(ScenarioApplicationHooks.SHOP)
	assert_equal(SaveEnvelope.from_data(wrong_hook_resume), null, "the save envelope rejects a hook that cannot own the serialized resume operation")
	var end_hook_save := SaveEnvelope.from_data(end_hook_data)
	assert_not_null(end_hook_save, "the exact End Adventure application-hook continuation round-trips")
	var closing_restored := GameSession.new()
	assert_equal(closing_restored.restore(content, end_hook_save).state, SessionStep.State.COMPLETED, "the End Adventure hook restores at its exact textbox boundary")
	var death_hook := closing_restored.respond(InteractionResponse.acknowledge(closing_restored.view().pending_interaction))
	assert_equal([death_hook.state, death_hook.interaction.body.to_data().get("prompt")], [SessionStep.State.WAITING_FOR_INTERACTION, "The Party Death application hook runs."], "Castle party release chains the Party Death hook after End Adventure")
	var death_hook_save := save_round_trip(closing_restored.snapshot())
	var death_hook_restored := GameSession.new()
	assert_equal(death_hook_restored.restore(content, death_hook_save).state, SessionStep.State.COMPLETED, "the chained Party Death hook restores transactionally")
	var closed := death_hook_restored.respond(InteractionResponse.acknowledge(death_hook_restored.view().pending_interaction))
	assert_equal(closed.state, SessionStep.State.COMPLETED, "End Adventure closes after both source-ordered Global hooks")
	assert_true(closed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"session_ended" and event.payload.get("campaignId") == content.campaign_id), "session close publishes the detached campaign identity once")
	assert_false(death_hook_restored.view().session_started, "closed gameplay is no longer exposed as an active session")
	assert_equal(death_hook_restored.snapshot(), null, "a closed session cannot be persisted as active gameplay")
	assert_equal(death_hook_restored.close().error_code, &"session_not_started", "repeated close fails instead of publishing duplicate teardown")
	var closing_controller := GameSessionController.new()
	assert_equal(closing_controller.start(content, 6).state, SessionStep.State.COMPLETED, "the host controller owns the replacement session")
	assert_equal(closing_controller.close().state, SessionStep.State.WAITING_FOR_INTERACTION, "the host controller exposes the End Adventure hook interaction")
	assert_equal(closing_controller.respond(InteractionResponse.acknowledge(closing_controller.view().pending_interaction)).state, SessionStep.State.WAITING_FOR_INTERACTION, "the host controller advances into the chained Party Death hook")
	assert_equal(closing_controller.respond(InteractionResponse.acknowledge(closing_controller.view().pending_interaction)).state, SessionStep.State.COMPLETED, "the host controller commits close after both hook interactions")
	assert_false(closing_controller.view().session_started, "controller close refreshes the detached view")
	closing_controller.free()


func _test_snapshot_rng_and_age_persistence(content: RealmzContent) -> void:
	var session := GameSession.new()
	assert_equal(session.start(content, 1).state, SessionStep.State.COMPLETED, "validated content starts synchronously")
	_begin_fixture_adventure(session, content)
	assert_false(session.view().availability(&"cast_spell").enabled, "the spell workspace does not expose an incomplete targetless cast intent")
	assert_equal(session.view().availability(&"cast_spell").reason, "No known spell has a supported Classic field use.", "the disabled cast control states the exact package-backed field-spell boundary")
	var first_search := session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(first_search.state, SessionStep.State.COMPLETED, "search commits at one session boundary")
	assert_equal(first_search.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"search_completed")[0].payload["roll"], 52, "the committed event records the first deterministic draw")
	assert_equal(session.snapshot().rng_state.draw_count, 9, "the save aggregate owns the secret roll and both source-ordered random-region scans")
	assert_equal(session.snapshot().game_state.clock.total_minutes(), 25, "one held Area Search pulse owns Castle's five outdoor timeclicks")
	var held_snapshot := session.snapshot()
	var constructor_state := GameState.from_data(held_snapshot.game_state.to_data())
	var constructor_vm := ScenarioVmSnapshot.from_data(held_snapshot.scenario_vm.to_data())
	var constructor_copy := SessionSnapshot.new(held_snapshot.campaign_id, held_snapshot.package_hash, held_snapshot.rules_version, held_snapshot.view_revision, constructor_state, held_snapshot.rng_state, constructor_vm, held_snapshot.scenario_action_state, held_snapshot.continuation, held_snapshot.battle_return_continuation, held_snapshot.session_interaction)
	var constructor_trace_size := constructor_copy.scenario_vm.trace.size()
	constructor_state.clock.advance_minutes(5)
	constructor_vm.trace.append({"event": "mutated-after-construction"})
	assert_equal(constructor_copy.game_state.clock.total_minutes(), 25, "SessionSnapshot detaches constructor-owned game state")
	assert_equal(constructor_copy.scenario_vm.trace.size(), constructor_trace_size, "SessionSnapshot detaches constructor-owned VM state")
	session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(held_snapshot.rng_state.draw_count, 9, "a snapshot is detached from later session RNG mutations")
	assert_equal(held_snapshot.game_state.clock.total_minutes(), 25, "a snapshot is detached from later game-state mutations")

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
	assert_equal(restored_search.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"search_completed")[0].payload["roll"], control_search.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"search_completed")[0].payload["roll"], "save/reload resumes the exact RNG branch")
	assert_equal(restored.snapshot().rng_state.draw_count, 17, "an already discovered Area Search skips secret rolls but retains both source-ordered random-region scans")
	assert_equal(restored.snapshot().game_state.clock.total_minutes(), 50, "restored Area Search advances the persisted clock by another five outdoor timeclicks")

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
	assert_equal(first_age_update.interaction.body.to_data()["characterId"], first_aging_character.id, "party order determines the first Castle age-update dialog")
	assert_equal(first_age_update.interaction.body.to_data()["changes"].size(), 15, "the request preserves all fifteen displayed Castle age deltas")
	assert_true(first_age_update.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 3002), "opening the age dialog requests Castle sound 3002")
	var age_boundary_save := save_round_trip(age_session.snapshot())
	assert_not_null(age_boundary_save, "the first age-update click boundary is centrally saveable")
	assert_true(age_boundary_save.continuation.age().updates[0] is InteractionRequest.AgeUpdateBody, "save restoration keeps live age-update continuation entries typed")
	var pending_close_session := GameSession.new()
	assert_equal(pending_close_session.restore(content, age_boundary_save).state, SessionStep.State.COMPLETED, "a pending interaction restores for lifecycle closure")
	var pending_close_snapshot := save_data(pending_close_session.snapshot())
	assert_equal(pending_close_session.close().error_code, &"session_not_committed", "a modal gameplay interaction must resolve before End Adventure")
	assert_equal(save_data(pending_close_session.snapshot()), pending_close_snapshot, "rejected modal teardown preserves the complete session and continuation")
	var age_restored := GameSession.new()
	assert_equal(age_restored.restore(content, age_boundary_save).state, SessionStep.State.COMPLETED, "the ordered age-update queue restores transactionally")
	assert_equal(age_restored.view().pending_interaction.body.to_data()["characterId"], first_aging_character.id, "restore retains the exact current age dialog")
	var wrong_age_response := age_restored.respond(InteractionResponse.acknowledge(age_restored.view().pending_interaction))
	assert_equal(wrong_age_response.error_code, &"invalid_interaction_response", "a generic textbox acknowledgement cannot bypass the age-update contract")
	var second_age_update := age_restored.respond(InteractionResponse.age_update(age_restored.view().pending_interaction))
	assert_equal(second_age_update.state, SessionStep.State.WAITING_FOR_INTERACTION, "acknowledging the first character advances to the next ordered age dialog")
	assert_equal(second_age_update.interaction.body.to_data()["characterId"], second_aging_character.id, "the second dialog retains Castle party order")
	assert_true(second_age_update.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 3002), "each age dialog independently requests Castle sound 3002")
	var age_completed := age_restored.respond(InteractionResponse.age_update(second_age_update.interaction))
	assert_equal(age_completed.state, SessionStep.State.COMPLETED, "the final age acknowledgement completes the interrupted session operation")
	assert_equal(age_restored.snapshot().continuation, null, "the completed age-update queue clears its save continuation")
	assert_equal([age_restored.view().party_members[0].age_group, age_restored.view().party_members[1].age_group], [2, 2], "both committed age mutations survive the staged presentation boundary")

	var mismatched := SaveEnvelope.new(content.campaign_id, "0".repeat(64), content.rules_version, loaded_save.view_revision, loaded_save.game_state, loaded_save.rng_state)
	var before_failed_restore := save_data(restored.snapshot())
	assert_equal(restored.restore(content, mismatched).error_code, &"package_mismatch", "package mismatch fails explicitly")
	assert_equal(save_data(restored.snapshot()), before_failed_restore, "failed restore leaves the current session untouched")


func _test_party_and_creator_persistence(content: RealmzContent) -> void:
	var party_session := GameSession.new()
	party_session.start(content, 7)
	var setup_view := party_session.view()
	assert_true(setup_view.party_setup_available, "fresh campaigns expose party creation through the detached view")
	assert_equal([setup_view.party_setup.difficulty, setup_view.party_setup.monster_set, setup_view.party_setup.available_monster_sets, setup_view.party_setup.current_party_levels, setup_view.party_setup.experience_percent, setup_view.campaign_summary.maximum_party_levels], [0, 0, [0, -1, 1], 0, 0, 0], "fresh setup exposes source-backed defaults and registered Castle's uncapped aggregate party guidance")
	assert_equal(party_session.submit_intent(PlayerIntent.set_party_setup_options(1, -1)).state, SessionStep.State.COMPLETED, "difficulty and Monster Set commit through one typed setup intent")
	assert_equal([party_session.snapshot().game_state.difficulty, party_session.snapshot().game_state.monster_set], [1, -1], "the central save owns selected setup options")
	assert_equal(party_session.submit_intent(PlayerIntent.set_party_setup_options(3, 0)).error_code, &"invalid_difficulty", "difficulty outside Castle's five choices fails explicitly")
	assert_true(not setup_view.race_options.is_empty() and not setup_view.caste_options.is_empty(), "party creation options come from validated package definitions"); var member := CharacterCreationSpec.new("Ari", setup_view.race_options[0].id, setup_view.caste_options[0].id, 1)
	var uncapped_session := GameSession.new(); uncapped_session.start(content, 6); assert_equal(uncapped_session.submit_intent(PlayerIntent.create_party([CharacterCreationSpec.new("One", member.race_id, member.caste_id, 1, "", "", 3), CharacterCreationSpec.new("Two", member.race_id, member.caste_id, 1, "", "", 3), CharacterCreationSpec.new("Three", member.race_id, member.caste_id, 1, "", "", 3), CharacterCreationSpec.new("Four", member.race_id, member.caste_id, 1, "", "", 3), CharacterCreationSpec.new("Five", member.race_id, member.caste_id, 1, "", "", 3), CharacterCreationSpec.new("Six", member.race_id, member.caste_id, 1, "", "", 3)])).state, SessionStep.State.COMPLETED, "registered Castle ignores the Data SC aggregate maximum while retaining its recommended-level experience guidance")
	var party_step := party_session.submit_intent(PlayerIntent.create_party([member]))
	assert_equal(party_step.state, SessionStep.State.COMPLETED, "typed party creation commits through GameSession")
	assert_equal(party_session.view().party_members[0].name, "Ari", "presentation sees the rule-created party member")
	assert_equal(party_session.view().party_setup.experience_percent, 250, "selected Hard difficulty and a low-level party produce Castle's clamped experience guidance")
	assert_false(party_session.view().party_setup_available, "party creation closes after the committed setup")
	var party_save := party_session.snapshot()
	assert_true(party_save.game_state.party_setup_completed, "central save owns party setup completion")
	assert_equal(party_save.game_state.experience_multiplier, 2.5, "party commitment freezes Castle's displayed experience ratio for the playthrough")
	var saved_age_group := party_save.game_state.party.characters()[0].age_group
	assert_true(saved_age_group >= 1 and saved_age_group <= 5, "the central save owns the character's independent Classic age group")
	var restored_party := GameSession.new()
	assert_equal(restored_party.restore(content, party_save).state, SessionStep.State.COMPLETED, "created party restores transactionally")
	assert_equal(restored_party.view().party_members[0].name, "Ari", "created party survives save and restore")
	assert_equal(restored_party.view().party_members[0].age_group, saved_age_group, "save restoration preserves the exact current age group")
	assert_equal([restored_party.snapshot().game_state.difficulty, restored_party.snapshot().game_state.monster_set], [1, -1], "save restoration preserves difficulty and Monster Set exactly")
	assert_equal(restored_party.snapshot().game_state.experience_multiplier, 2.5, "save restoration preserves the committed setup experience multiplier instead of recomputing from later levels")
	var invalid_multiplier_data := party_save.game_state.to_data()
	invalid_multiplier_data["experienceMultiplier"] = -0.5
	assert_equal(GameState.from_data(invalid_multiplier_data), null, "save restoration rejects experience ratios between the legacy migration sentinel and Castle's minimum twenty percent")
	assert_equal(restored_party.submit_intent(PlayerIntent.create_party([member])).error_code, &"party_setup_closed", "party setup cannot be replayed after restore")
	var corrupt_load_save := SaveEnvelope.from_data(save_data(party_save))
	corrupt_load_save.game_state.party.characters()[0].carried_load += 1
	var before_corrupt_load_restore := save_data(restored_party.snapshot())
	assert_equal(restored_party.restore(content, corrupt_load_save).error_code, &"invalid_game_state", "restore rejects a carried-load value that does not match package item weights and personal wealth")
	assert_equal(save_data(restored_party.snapshot()), before_corrupt_load_restore, "a rejected carried-load snapshot leaves the active session untouched")
	var corrupt_multiplier_data := save_data(party_save)
	corrupt_multiplier_data["gameState"]["experienceMultiplier"] = 3.0
	assert_equal(SaveEnvelope.from_data(corrupt_multiplier_data), null, "restore rejects an out-of-range persisted setup multiplier")

	var staged_setup := GameSession.new()
	staged_setup.start(content, 11)
	assert_true(staged_setup.view().party_members.is_empty(), "fresh setup has no synthetic placeholder character")
	assert_false(staged_setup.view().availability(&"begin_adventure").enabled, "an empty setup cannot begin the adventure")
	var empty_setup_save := staged_setup.snapshot()
	assert_not_null(empty_setup_save, "an empty committed party-setup boundary is saveable")
	var restored_setup := GameSession.new()
	assert_equal(restored_setup.restore(content, empty_setup_save).state, SessionStep.State.COMPLETED, "empty party setup restores without inventing a member")
	var before_generation_draws := restored_setup.snapshot().rng_state.draw_count
	var generated := restored_setup.submit_intent(PlayerIntent.generate_character_draft(member))
	assert_equal(generated.state, SessionStep.State.COMPLETED, "one typed specification generates a session-owned Classic character draft")
	assert_not_null(restored_setup.view().character_draft, "the detached setup view exposes the generated character before acceptance")
	assert_equal([restored_setup.view().portrait_options.size(), restored_setup.view().combat_icon_options.size()], [120, 120], "the detached setup view exposes both validated package appearance catalogs")
	assert_equal([restored_setup.view().character_draft.portrait_id, restored_setup.view().character_draft.combat_icon_id], ["realmz-portrait-257", "realmz-combat-icon-9000"], "the Human zero-set correction chooses the first proven browseable portrait/tactical pair")
	assert_equal(restored_setup.view().party_members.size(), 0, "generation does not add the draft to the party before acceptance")
	assert_equal(restored_setup.view().character_draft.items.size(), 0, "the provisional Review state precedes Castle's post-spell addinitialitems stage")
	assert_true(restored_setup.snapshot().rng_state.draw_count > before_generation_draws, "the committed draft owns the complete Classic creation RNG consumption")
	assert_false(restored_setup.view().availability(&"begin_adventure").enabled, "a generated draft must be accepted or cancelled before Begin")
	var generated_save := restored_setup.snapshot()
	var restored_draft := GameSession.new()
	assert_equal(restored_draft.restore(content, generated_save).state, SessionStep.State.COMPLETED, "the generated Review boundary restores transactionally")
	assert_equal(restored_draft.view().character_draft.brawn, restored_setup.view().character_draft.brawn, "restore preserves the exact rolled attributes")
	assert_equal([restored_draft.view().character_draft.portrait_id, restored_draft.view().character_draft.combat_icon_id], ["realmz-portrait-257", "realmz-combat-icon-9000"], "save restoration preserves stable package appearance identities")
	var invalid_appearance_session := GameSession.new()
	invalid_appearance_session.start(content, 11)
	var invalid_appearance_spec := CharacterCreationSpec.new("Wrong Kind", member.race_id, member.caste_id, member.gender, "realmz-combat-icon-9000", "realmz-combat-icon-9000")
	assert_equal(invalid_appearance_session.submit_intent(PlayerIntent.generate_character_draft(invalid_appearance_spec)).error_code, &"invalid_character_appearance", "a combat icon cannot cross the typed portrait boundary")
	var before_finalization_draws := restored_draft.snapshot().rng_state.draw_count
	var finalized := restored_draft.submit_intent(PlayerIntent.finalize_character())
	assert_equal(finalized.state, SessionStep.State.WAITING_FOR_INTERACTION, "accepting the reviewed draft adds it and reaches Castle's explicit reusable-character decision")
	assert_equal(finalized.interaction.kind, InteractionRequest.YES_NO, "vault publication is a typed yes/no interaction rather than a presentation-owned filesystem shortcut")
	var publication_save := save_round_trip(restored_draft.snapshot())
	assert_not_null(publication_save, "the pending publication decision survives the serialized save boundary")
	var publication_session := GameSession.new()
	assert_equal(publication_session.restore(content, publication_save).state, SessionStep.State.COMPLETED, "the publication decision restores with its exact finalized character")
	var declined_publication := publication_session.respond(InteractionResponse.yes_no(publication_session.view().pending_interaction, false))
	assert_equal(declined_publication.state, SessionStep.State.COMPLETED, "keeping a character in the current party completes setup without requesting an external vault write")
	assert_true(declined_publication.events.any(func(event: DomainEvent) -> bool: return event.kind == &"character_publication_declined"), "the declined publication decision is explicit in the committed event stream")
	restored_setup = publication_session
	assert_equal(restored_setup.snapshot().rng_state.draw_count, before_finalization_draws, "finalization and publication choice reuse the reviewed character without rolling again")
	assert_equal(restored_setup.view().character_draft, null, "acceptance clears the provisional character")
	assert_true(restored_setup.view().party_setup_available, "finalizing a character does not implicitly leave party setup")
	assert_equal(restored_setup.view().party_members.size(), 1, "the finalized character appears in the detached setup view")
	assert_equal(restored_setup.view().party_members[0].items.size(), content.caste_by_id(member.caste_id).start_items().size(), "acceptance adds the caste's initial items after the spell-selection stage")
	var finalized_character := restored_setup.snapshot().game_state.party.characters()[0]
	var finalized_caste := content.caste_by_id(finalized_character.caste_id)
	var first_start_item := content.item_by_id(finalized_caste.start_items()[0])
	assert_true(finalized_character.inventory()[0].identified, "Castle starting equipment enters the finalized character already identified")
	assert_equal(finalized_character.inventory()[0].charges, first_start_item.initial_charges, "starting equipment preserves the authored initial charge count")
	assert_equal(finalized_character.carried_load, RealmzRules.new().inventory.calculated_load(finalized_character, content.item_definitions()), "finalization materializes exact wealth and item weight into carried load")
	assert_true(restored_setup.view().availability(&"begin_adventure").enabled, "a nonempty setup may explicitly begin")

	var advanced_session := GameSession.new()
	advanced_session.start(content, 37)
	var advanced_spec := CharacterCreationSpec.new("Veteran", member.race_id, member.caste_id, member.gender, "", "", 3)
	var advanced_generation := advanced_session.submit_intent(PlayerIntent.generate_character_draft(advanced_spec))
	assert_equal(advanced_generation.state, SessionStep.State.COMPLETED, "a fixed higher starting level reaches the ordinary saveable Review boundary")
	assert_equal([advanced_session.view().character_draft.level, advanced_session.view().character_draft.experience], [3, -content.caste_by_id(member.caste_id).victory_threshold(2)], "the session exposes the target level and matching caste victory threshold without a shortcut profile")
	var invalid_level_spec := CharacterCreationSpec.new("Invalid Veteran", member.race_id, member.caste_id, member.gender, "", "", 2)
	assert_equal(advanced_session.submit_intent(PlayerIntent.generate_character_draft(invalid_level_spec)).error_code, &"invalid_starting_level", "non-Classic starting levels fail before consuming another character roll")
	var staged_setup_save := restored_setup.snapshot()
	var resumed_setup := GameSession.new()
	assert_equal(resumed_setup.restore(content, staged_setup_save).state, SessionStep.State.COMPLETED, "an in-progress assembled party restores at the setup boundary")
	assert_true(resumed_setup.view().party_setup_available, "restored setup remains open after its revision advances")
	var imported := CharacterState.new("vault.character.one", "Vault Hero", 12, 12)
	imported.race_id = setup_view.race_options[0].id
	imported.caste_id = setup_view.caste_options[0].id
	imported.maximum_load = 100_000
	imported.money.gold = 7
	var imported_definition := content.item_definitions()[0]
	imported.set_inventory([ItemInstance.new("vault.character.one.item.0", imported_definition.id, imported_definition.initial_charges, false, true)])
	imported.carried_load = 0
	var wrong_kind_import := CharacterState.from_data(imported.to_data())
	wrong_kind_import.portrait_id = "realmz-combat-icon-9000"
	assert_equal(resumed_setup.submit_intent(PlayerIntent.import_vault_character(wrong_kind_import.id, "c".repeat(64), wrong_kind_import, "fixture-source", "b".repeat(64))).error_code, &"vault_character_ineligible", "vault import rejects a package asset used in the wrong appearance role")
	var import_step := resumed_setup.submit_intent(PlayerIntent.import_vault_character(imported.id, "a".repeat(64), imported, "fixture-source", "b".repeat(64)))
	assert_equal(import_step.state, SessionStep.State.COMPLETED, "vault import adds another member without completing party setup")
	assert_equal(resumed_setup.view().party_members.size(), 2, "created and vault characters may share one setup party")
	assert_equal(resumed_setup._state.party.character_by_id(imported.id).carried_load, 7 + imported_definition.instance_weight(imported_definition.initial_charges), "vault import derives carried load from target-package definitions instead of trusting a stale local total")
	var conflicting_import := CharacterState.from_data(imported.to_data())
	conflicting_import.id = "vault.character.conflicting"
	conflicting_import.name = "Conflicting Hero"
	var party_before_conflict := resumed_setup.view().party_members.size()
	assert_equal(resumed_setup.submit_intent(PlayerIntent.import_vault_character(conflicting_import.id, "d".repeat(64), conflicting_import, "fixture-source", "b".repeat(64))).error_code, &"duplicate_item_ownership", "vault import rejects a second character revision that claims an exact item instance already owned by the party")
	assert_equal(resumed_setup.view().party_members.size(), party_before_conflict, "rejected duplicate item ownership leaves the assembled party unchanged")
	var duplicate_save_data := resumed_setup.snapshot().game_state.to_data()
	var duplicate_character_data: Dictionary = duplicate_save_data["party"]["characters"][1].duplicate(true)
	duplicate_character_data["id"] = "vault.character.corrupt-save"
	duplicate_character_data["name"] = "Corrupt Save Hero"
	duplicate_save_data["party"]["characters"].append(duplicate_character_data)
	assert_equal(GameState.from_data(duplicate_save_data), null, "state restoration rejects duplicate exact-item ownership even when no combat is active")
	assert_true(resumed_setup.view().party_setup_available, "multiple committed setup edits remain available until Begin")
	var created_id := resumed_setup.view().party_members[0].id
	assert_equal(resumed_setup.submit_intent(PlayerIntent.remove_party_member(created_id)).state, SessionStep.State.COMPLETED, "typed removal updates the setup party")
	assert_equal(resumed_setup.view().party_members.size(), 1, "removal leaves the remaining vault character in setup")
	assert_true(resumed_setup.view().party_setup_available, "removing a member does not begin the adventure")
	var resumed_begin := resumed_setup.submit_intent(PlayerIntent.begin_adventure())
	assert_equal(resumed_begin.state, SessionStep.State.WAITING_FOR_INTERACTION, "Begin commits the party before yielding to the Start Game hook")
	assert_equal(resumed_setup.respond(InteractionResponse.acknowledge(resumed_begin.interaction)).state, SessionStep.State.COMPLETED, "acknowledging Start Game enters ordinary exploration")
	assert_false(resumed_setup.view().party_setup_available, "party setup closes only after Begin")
	assert_equal(resumed_setup.submit_intent(PlayerIntent.remove_party_member(imported.id)).error_code, &"party_setup_closed", "party composition cannot change after Begin")

	var reroll_session := GameSession.new()
	reroll_session.start(content, 31)
	assert_equal(reroll_session.submit_intent(PlayerIntent.generate_character_draft(member)).state, SessionStep.State.COMPLETED, "the first Classic roll reaches Review")
	var first_roll_data := reroll_session.view().character_draft
	var first_roll_draws := reroll_session.snapshot().rng_state.draw_count
	assert_equal(reroll_session.submit_intent(PlayerIntent.generate_character_draft(member)).state, SessionStep.State.COMPLETED, "Reroll replaces the provisional character")
	assert_true(reroll_session.snapshot().rng_state.draw_count > first_roll_draws, "Reroll advances rather than rewinds the session RNG")
	assert_equal(reroll_session.view().character_draft.id, first_roll_data.id, "Reroll retains one provisional character identity")
	assert_equal(reroll_session.submit_intent(PlayerIntent.cancel_character_draft()).state, SessionStep.State.COMPLETED, "Cancel discards the provisional character")
	assert_equal(reroll_session.view().character_draft, null, "cancelled creation does not leak into party setup")
	assert_equal(reroll_session.snapshot().rng_state.draw_count > first_roll_draws, true, "Cancel does not roll back Classic creation draws")

	var spellcaster_spec := _spellcaster_creation_spec(content)
	assert_not_null(spellcaster_spec, "the fixture exposes a source-shaped spellcasting race and class")
	if spellcaster_spec != null:
		var spell_session := GameSession.new()
		spell_session.start(content, 41)
		assert_equal(spell_session.submit_intent(PlayerIntent.generate_character_draft(spellcaster_spec)).state, SessionStep.State.COMPLETED, "a spellcaster reaches the saveable Review boundary")
		var spell_view := spell_session.view()
		assert_true(spell_view.character_draft_spell_points_total > 0, "Castle's getnumspells formula provides starting selection points")
		assert_false(spell_view.character_draft_spell_options.is_empty(), "the package supplies the caster's eligible Classic spell records")
		for option: CharacterSpellOptionView in spell_view.character_draft_spell_options:
			assert_true(option.classic_id % 100 >= 1 and option.classic_id % 100 <= 12, "starting selection exposes only Castle's twelve cspells slots per level")
			assert_false(option.name.begins_with("Unnamed Classic spell"), "resource-only name slots cannot become selectable character spells")
		if not spell_view.character_draft_spell_options.is_empty():
			var selected_spell := spell_view.character_draft_spell_options[0]
			assert_true(selected_spell.selection_cost <= spell_view.character_draft_spell_points_total, "the first available spell fits the deterministic starting budget")
			var spell_change := spell_session.submit_intent(PlayerIntent.set_character_draft_spells([selected_spell.id]))
			assert_equal(spell_change.state, SessionStep.State.COMPLETED, "typed starting-spell selection mutates only the generated draft")
			assert_equal(spell_session.view().character_draft.spells[0].id, selected_spell.id, "the detached Review view exposes the chosen spell")
			var spell_save := spell_session.snapshot()
			var restored_spell_session := GameSession.new()
			assert_equal(restored_spell_session.restore(content, spell_save).state, SessionStep.State.COMPLETED, "starting-spell selection restores at the same creator boundary")
			assert_equal(restored_spell_session.view().character_draft.spells[0].id, selected_spell.id, "restore preserves the exact selected spell")
			var confirmation := restored_spell_session.submit_intent(PlayerIntent.finalize_character())
			assert_equal(confirmation.state, SessionStep.State.WAITING_FOR_INTERACTION, "unspent Classic spell points require the source confirmation boundary")
			assert_equal(confirmation.interaction.kind, InteractionRequest.YES_NO, "the unspent-point decision is a typed yes/no interaction")
			assert_true(restored_spell_session.view().party_setup_available, "the creator remains mounted while its confirmation is pending")
			var confirmation_save := save_round_trip(restored_spell_session.snapshot())
			assert_not_null(confirmation_save, "the unspent-point continuation survives the serialized save-v4 boundary")
			if confirmation_save == null:
				confirmation_save = restored_spell_session.snapshot()
			var restored_confirmation := GameSession.new()
			var confirmation_restore := restored_confirmation.restore(content, confirmation_save)
			assert_equal(confirmation_restore.state, SessionStep.State.COMPLETED, "the unspent-point confirmation restores transactionally: %s" % confirmation_restore.error_message)
			var confirmation_session := restored_confirmation if confirmation_restore.state == SessionStep.State.COMPLETED else restored_spell_session
			var declined := confirmation_session.respond(InteractionResponse.from_data(confirmation.interaction.request_id, InteractionRequest.YES_NO, {"accepted": false}))
			assert_equal(declined.state, SessionStep.State.COMPLETED, "declining returns to starting-spell selection without discarding the draft")
			assert_not_null(confirmation_session.view().character_draft, "the declined character remains available for another spell choice")
			confirmation = confirmation_session.submit_intent(PlayerIntent.finalize_character())
			var accepted := confirmation_session.respond(InteractionResponse.from_data(confirmation.interaction.request_id, InteractionRequest.YES_NO, {"accepted": true}))
			assert_equal(accepted.state, SessionStep.State.WAITING_FOR_INTERACTION, "accepting unspent points commits the reviewed character before the reusable-vault decision")
			assert_equal(confirmation_session.view().party_members.size(), 1, "the accepted caster enters party setup exactly once")
			assert_equal(confirmation_session.view().party_members[0].spells[0].id, selected_spell.id, "finalization preserves the selected starting spell")
			var requested_publication := confirmation_session.respond(InteractionResponse.yes_no(accepted.interaction, true))
			assert_equal(requested_publication.state, SessionStep.State.COMPLETED, "accepting vault publication returns to committed party setup")
			assert_true(requested_publication.events.any(func(event: DomainEvent) -> bool: return event.kind == &"character_publication_requested"), "the host receives one typed request to publish the finalized revision")



func _test_combat_and_reward_persistence(content: RealmzContent) -> void:
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
		# Simulate a save or live session created before empty Castle body-count
		# boundaries were removed. Continue must heal it into the next real stage.
		var stale_ally_request := InteractionRequest.from_payload("fixture.stale-empty-ally", InteractionRequest.ALLY_SELECTION, {"prompt": "Choose the allies who will continue with the party.", "candidates": [], "maximum": 4, "selectedIds": [], "requiredIds": []})
		fumble_session._session_interaction = stale_ally_request
		var combat_body := SessionContinuation.CombatBody.new()
		combat_body.battle_id = fumble_session._state.combat.battle_id
		fumble_session._session_continuation = SessionContinuation.combat_state(&"combat-ally-selection", combat_body)
		var recovery_step := fumble_session.respond(InteractionResponse.from_data(stale_ally_request.request_id, stale_ally_request.kind, {"selectedIds": []}))
		assert_equal(recovery_step.state, SessionStep.State.WAITING_FOR_INTERACTION, "retreat opens one typed treasure boundary containing the fumbled weapon")
		assert_false(recovery_step.events.any(func(event: DomainEvent) -> bool: return event.kind == &"allies_selected"), "a stale empty body-count stage is bypassed rather than manufactured")
		assert_equal(recovery_step.interaction.kind, InteractionRequest.TREASURE_DISTRIBUTION, "post-battle recovery uses the ordinary treasure-distribution request")
		var merged_reward := recovery_step.interaction.body as InteractionRequest.TreasureRequestBody
		assert_not_null(merged_reward, "the merged post-battle request retains its typed treasure body")
		if merged_reward != null:
			assert_equal(merged_reward.mode, &"ordinary", "Castle fumbles enter the ordinary booty workspace rather than a second recovery screen")
			assert_equal(merged_reward.items.map(func(item: InteractionRequestValue.RewardItem) -> String: return item.instance_id), [dropped.id], "the exact fumbled instance leads the ordinary reward queue")
		var fumble_boundary := save_round_trip(fumble_session.snapshot())
		assert_not_null(fumble_boundary, "the ordinary reward containing a fumbled item is centrally saveable")
		var recovered_session := GameSession.new()
		assert_equal(recovered_session.restore(content, fumble_boundary).state, SessionStep.State.COMPLETED, "the merged post-battle reward restores transactionally")
		var restored_fumble_request := recovered_session.view().pending_interaction
		var recovered_step := recovered_session.respond(InteractionResponse.from_data(restored_fumble_request.request_id, InteractionRequest.TREASURE_DISTRIBUTION, {"action": "assign", "instanceId": dropped.id, "characterId": recovery_character.id}))
		assert_equal(recovered_step.state, SessionStep.State.WAITING_FOR_INTERACTION, "assigning the final fumbled weapon returns to Castle's shared booty workspace")
		var done_step := recovered_session.respond(InteractionResponse.from_data(recovered_step.interaction.request_id, InteractionRequest.TREASURE_DISTRIBUTION, {"action": "done"}))
		assert_equal(done_step.state, SessionStep.State.COMPLETED, "Done completes the combined post-battle treasure workspace")
		var recovered_inventory := recovered_session._state.party.character_by_id(recovery_character.id).inventory()
		assert_equal(recovered_inventory.size(), 1, "the selected recipient owns one recovered item")
		if not recovered_inventory.is_empty():
			assert_equal(recovered_inventory[0].to_data(), dropped.to_data(), "save/resume retains the exact recovered instance and charge count")
		assert_equal(recovered_session._state.combat, null, "save/resume releases the completed battle after the combined reward closes")

	var original_scenario := content.scenario
	var party_death_program := ScenarioProgramDefinition.new("fixture.party-death-revival", &"extra-action-point", "fixture.party-death-revival", [
		ClassicActionDefinition.new(0, 1, 1, 21, false, []),
		ClassicActionDefinition.new(1, 119, 119, 0, false, []),
	])
	content.scenario = ScenarioDefinition.new(
		[party_death_program],
		[],
		ScenarioApplicationHooks.new("", party_death_program.id, "", "", "")
	)
	var revived_defeat := GameSession.new()
	revived_defeat.start(content, 24)
	var defeated_character := CharacterState.new("fixture.party-death-revival", "Revived Hero", 0, 10)
	defeated_character.conditions.set_value(ConditionRules.ANIMATED, -1)
	revived_defeat._state.party = PartyState.new(content.start_map_id, content.start_coordinate, [defeated_character])
	revived_defeat._state.party_setup_completed = true
	var defeat_hook := _complete_public_defeat(revived_defeat, content, defeated_character)
	assert_equal([defeat_hook.state, defeat_hook.interaction.body.to_data().get("prompt")], [SessionStep.State.WAITING_FOR_INTERACTION, "The Party Death application hook runs."], "total defeat enters the Party Death program before releasing the party")
	var defeat_boundary := save_round_trip(revived_defeat.snapshot())
	var restored_defeat := GameSession.new()
	assert_equal(restored_defeat.restore(content, defeat_boundary).state, SessionStep.State.COMPLETED, "the Party Death hook restores before its revival instruction")
	var revived := restored_defeat.respond(InteractionResponse.acknowledge(restored_defeat.view().pending_interaction))
	assert_equal(revived.state, SessionStep.State.COMPLETED, "opcode 119 suppresses defeat teardown and completes the no-reward battle return")
	assert_true(revived.events.any(func(event: DomainEvent) -> bool: return event.kind == &"party_defeat_revived"), "the resumed hook records the source-backed defeat revival boundary")
	assert_equal(revived.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"battle_returned").size(), 1, "revival publishes one terminal no-reward battle return")
	assert_false(revived.events.any(func(event: DomainEvent) -> bool: return event.kind in [&"reward_opened", &"reward_completed"]), "the direct no-reward return skips treasure, experience, and after-message reward processing")
	assert_equal([restored_defeat.view().session_started, restored_defeat._state.party.character_by_id(defeated_character.id).current_health, restored_defeat._state.combat, restored_defeat._state.last_battle_outcome], [true, 1, null, &"retreated"], "revival retains the session, restores one stamina, records retreat, and releases combat exactly once")

	content.scenario = original_scenario
	var ordinary_defeat := GameSession.new()
	ordinary_defeat.start(content, 25)
	var lost_character := CharacterState.new("fixture.party-defeat", "Lost Hero", 0, 10)
	ordinary_defeat._state.party = PartyState.new(content.start_map_id, content.start_coordinate, [lost_character])
	ordinary_defeat._state.party_setup_completed = true
	var ordinary_death_hook := _complete_public_defeat(ordinary_defeat, content, lost_character)
	assert_equal(ordinary_death_hook.interaction.body.to_data().get("prompt"), "The Party Death application hook runs.", "ordinary total defeat runs the package Party Death hook")
	var released := ordinary_defeat.respond(InteractionResponse.acknowledge(ordinary_death_hook.interaction))
	assert_true(released.events.any(func(event: DomainEvent) -> bool: return event.kind == &"session_ended" and event.payload.get("reason") == "party-defeat"), "a Party Death hook without revival releases the defeated session")
	assert_false(ordinary_defeat.view().session_started, "ordinary total defeat does not return to exploration")

	var battle: BattleDefinition = content.battle_by_id("classic.battle.0")
	assert_not_null(battle, "the integration fixture exposes a terminal reward battle")
	if battle != null:
		var reward_session := GameSession.new()
		reward_session.start(content, 71)
		var reward_character := CharacterState.new("fixture.reward-recipient", "Reward Hero", 20, 20)
		reward_character.race_id = content.race_definitions()[0].id
		reward_character.caste_id = content.caste_definitions()[0].id
		reward_character.experience = -10_000_000
		reward_character.maximum_load = 5_000
		reward_session._state.party = PartyState.new(content.start_map_id, content.start_coordinate, [reward_character])
		reward_session._state.party_setup_completed = true
		reward_session._state.monster_set = -1
		var setup: CombatFlowResult = reward_session._rules.combat_flow.start_battle(reward_session._state, content, battle, reward_session._rng)
		assert_true(setup.ok, "the terminal reward integration starts through the source-backed battle builder")
		if setup.ok:
			assert_true(reward_session._state.combat.monsters().all(func(monster: MonsterState) -> bool: return monster.definition_id.begins_with("classic.monster-set.-1.")), "battle construction resolves every authored slot through the selected Classic Monster Set")
			var reordered_turns: Array[String] = [reward_character.id]
			for actor_id: String in reward_session._state.combat.turn_order():
				if actor_id != reward_character.id:
					reordered_turns.append(actor_id)
			reward_session._state.combat.set_turn_order(reordered_turns)
			reward_session._state.combat.turn_index = 0
			reward_session._state.combat.active_turn = null
			var tactical_view := reward_session.view()
			assert_true(tactical_view.combat_view.movement_options.any(func(option: CombatMoveOptionView) -> bool: return option.enabled), "the active fixture character has at least one core-probed tactical step")
			assert_true(tactical_view.availability(&"combat_move").enabled, "the public combat-move action derives from the active battle view instead of the stale global fallback: %s" % tactical_view.availability(&"combat_move").reason)
			assert_false(tactical_view.availability(&"cast_spell").enabled, "the combat spell action remains disabled when the active character has no core-proven cast option")
			assert_equal(tactical_view.availability(&"cast_spell").reason, "No legal Classic combat spell is available.", "the disabled combat spell action no longer claims its typed picker is unwired")
			reward_character.maximum_spell_attacks = 2
			reward_character.maximum_spell_points = 100
			reward_character.spell_points = 100
			var legal_combat_spell: SpellDefinition = null
			for spell: SpellDefinition in content.spell_definitions():
				reward_character.set_known_spells([spell.id])
				if not reward_session._rules.combat_flow.character_spell_options(reward_session._state, content, reward_character.id).is_empty():
					legal_combat_spell = spell
					break
			assert_not_null(legal_combat_spell, "the integration fixture contains at least one core-proven combat spell option")
			if legal_combat_spell != null:
				# This legacy integration fixture mutates session-owned state directly;
				# invalidate the detached-view cache before observing that mutation.
				reward_session._view_projector.clear()
				var spell_ready_view := reward_session.view()
				assert_true(spell_ready_view.availability(&"cast_spell").enabled, "the public combat spell action is enabled only when core supplies at least one legal spell, power, and target option: %s" % spell_ready_view.availability(&"cast_spell").reason)
			assert_false(tactical_view.availability(&"move").enabled, "an active battle cannot advertise exploration movement through the detached application view")
			assert_false(tactical_view.availability(&"search").enabled, "an active battle cannot advertise exploration Search through the detached application view")
			reward_session._session_interaction = InteractionRequest.from_payload("fixture.combat-action", InteractionRequest.COMBAT, {})
			assert_true(reward_session.view().availability(&"combat_move").enabled, "the typed battle interaction keeps its legal movement action available: %s" % reward_session.view().availability(&"combat_move").reason)
			reward_session._session_interaction = null
			for monster: MonsterState in reward_session._state.combat.monsters():
				if monster.traitor:
					monster.current_health = 0
			reward_session._state.combat.active_turn = null
			reward_session._state.combat.pending_monster_attack = null
			reward_session._state.combat.pending_reaction = null
			var terminal := reward_session.submit_intent(PlayerIntent.combat_action(&"finish", reward_character.id))
			assert_false(terminal.events.any(func(event: DomainEvent) -> bool: return event.kind == &"allies_selected"), "terminal victory skips body-count when no eligible ally survived")
			assert_equal([terminal.state, terminal.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.TREASURE_DISTRIBUTION], "victory enters the ordinary typed booty workspace")
			var initial_boundary := reward_session.snapshot()
			assert_not_null(initial_boundary, "the complete direct reward aggregate validates before canonical JSON")
			if initial_boundary == null:
				return
			var corrupt_reward_data := save_data(initial_boundary)
			corrupt_reward_data["sessionContinuation"]["data"]["runtimeContinuation"]["data"]["state"]["experienceAwards"]["fixture.missing-character"] = 1
			var corrupt_reward := SaveEnvelope.from_data(corrupt_reward_data)
			var stable_reward_state := save_data(reward_session.snapshot())
			assert_equal(reward_session.restore(content, corrupt_reward).error_code, &"invalid_session_continuation", "restore rejects a reward continuation that references a missing recipient")
			assert_equal(save_data(reward_session.snapshot()), stable_reward_state, "a rejected reward continuation leaves the active session untouched")
			var boundary_count := 0
			var reward_completed := false
			while terminal.state == SessionStep.State.WAITING_FOR_INTERACTION and boundary_count < 64:
				var saved_boundary := SaveEnvelope.from_data(JSON.parse_string(JSON.stringify(save_data(reward_session.snapshot()))))
				assert_not_null(saved_boundary, "terminal reward boundary %d survives canonical save JSON" % boundary_count)
				if saved_boundary == null:
					break
				var resumed_reward := GameSession.new()
				var restore_step := resumed_reward.restore(content, saved_boundary)
				assert_equal(restore_step.state, SessionStep.State.COMPLETED, "terminal reward boundary %d restores transactionally" % boundary_count)
				if restore_step.state != SessionStep.State.COMPLETED:
					break
				reward_session = resumed_reward
				var request: InteractionRequest = reward_session.view().pending_interaction
				var payload: Dictionary
				if request.kind == InteractionRequest.LEVEL_UP and request.body.to_data().get("mode") == "result":
					payload = {"action": "continue", "characterId": request.body.to_data()["characterId"]}
				elif request.kind == InteractionRequest.LEVEL_UP:
					payload = {"action": "confirm-spells", "characterId": request.body.to_data()["characterId"], "spellIds": []}
				elif request.kind == InteractionRequest.TREASURE_DISTRIBUTION and request.body.to_data().get("mode") == "completion-confirmation":
					payload = {"action": "confirm-completion"}
				elif request.kind == InteractionRequest.TREASURE_DISTRIBUTION and not request.body.to_data().get("items", []).is_empty():
					payload = {"action": "discard", "instanceId": request.body.to_data()["items"][0]["instanceId"]}
				else:
					payload = {"action": "done"}
				terminal = reward_session.respond(InteractionResponse.from_data(request.request_id, request.kind, payload))
				reward_completed = reward_completed or terminal.events.any(func(event: DomainEvent) -> bool: return event.kind == &"reward_completed")
				boundary_count += 1
			assert_true(boundary_count < 64, "terminal reward return is bounded")
			assert_equal([terminal.state, reward_session._state.combat, reward_session._state.last_battle_outcome], [SessionStep.State.COMPLETED, null, &"victory"], "restored victory completes and releases the battle-owned reward chain exactly once")
			assert_true(reward_completed, "ordinary session completion publishes the reward return event")
			assert_equal(terminal.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"battle_returned").size(), 1, "restored victory publishes one terminal battle-return event")


func _complete_public_defeat(session: GameSession, content: RealmzContent, character: CharacterState) -> SessionStep:
	var battle := content.battle_by_id("classic.battle.0")
	if battle == null:
		return SessionStep.failed(session.view().revision, &"missing_fixture_battle", "The fixture battle is unavailable.")
	character.current_health = 1
	var setup := session._rules.combat_flow.start_battle(session._state, content, battle, session._rng)
	if not setup.ok or session._state.combat == null:
		return SessionStep.failed(session.view().revision, setup.error_code, setup.error_message)
	var attacker: MonsterState = null
	for monster: MonsterState in session._state.combat.monsters():
		if monster.traitor and attacker == null:
			attacker = monster
		elif monster.traitor:
			monster.current_health = 0
	if attacker == null:
		return SessionStep.failed(session.view().revision, &"missing_fixture_attacker", "The fixture battle has no hostile monster.")
	attacker.target_id = character.id
	var turn_order: Array[String] = [character.id, attacker.id]
	session._state.combat.set_turn_order(turn_order)
	session._state.combat.turn_index = 0
	session._state.combat.active_turn = null
	var scripted_values: Array[int] = []
	scripted_values.resize(512)
	scripted_values.fill(0)
	session._rng = ScriptedRng.new(scripted_values)
	return session.submit_intent(PlayerIntent.combat_action(&"finish", character.id))


func _begin_fixture_adventure(session: GameSession, content: RealmzContent) -> void:
	var races := content.race_definitions()
	var castes := content.caste_definitions()
	assert_false(races.is_empty() or castes.is_empty(), "playable fixture provides one race and class for setup")
	if races.is_empty() or castes.is_empty():
		return
	var character := CharacterState.new("fixture.party.member", "Fixture Hero", 10, 10)
	character.race_id = races[0].id
	character.caste_id = castes[0].id
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(character.id, "1".repeat(64), character, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "fixture vault member enters party setup without consuming RNG")
	var begin_step := session.submit_intent(PlayerIntent.begin_adventure())
	assert_equal([begin_step.state, begin_step.interaction.body.to_data().get("prompt")], [SessionStep.State.WAITING_FOR_INTERACTION, "The Start Game application hook runs."], "fixture party commits before the Start Game hook")
	var begin_boundary := save_round_trip(session.snapshot())
	var restored := GameSession.new()
	assert_equal(restored.restore(content, begin_boundary).state, SessionStep.State.COMPLETED, "the Start Game textbox restores without rerunning the hook")
	var completed := restored.respond(InteractionResponse.acknowledge(restored.view().pending_interaction))
	assert_equal(completed.state, SessionStep.State.COMPLETED, "Start Game completion enters ordinary exploration")
	assert_true(completed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"adventure_begun"), "Start Game completion publishes the application boundary")
	assert_equal(session.restore(content, restored.snapshot()).state, SessionStep.State.COMPLETED, "the helper returns the completed adventure state to its caller")


func _spellcaster_creation_spec(content: RealmzContent) -> CharacterCreationSpec:
	for caste: CasteDefinition in content.caste_definitions():
		var caster_at_level_one := false
		var maximum_spell_level := 0
		for row: Vector3i in caste.spellcaster_rows():
			caster_at_level_one = caster_at_level_one or row.y == 1
			maximum_spell_level += row.z
		if not caster_at_level_one or maximum_spell_level < 1:
			continue
		for race: RaceDefinition in content.race_definitions():
			if not race.eligible_caste_ids.is_empty() and not race.eligible_caste_ids.has(caste.id):
				continue
			if not caste.eligible_race_ids.is_empty() and not caste.eligible_race_ids.has(race.id):
				continue
			return CharacterCreationSpec.new("Mira", race.id, caste.id, 2)
	return null


func _aging_race(content: RealmzContent) -> RaceDefinition:
	for race: RaceDefinition in content.race_definitions():
		if race.max_age > 0 and race.age_range(1).x == race.age_range(0).y + 1:
			return race
	return null
