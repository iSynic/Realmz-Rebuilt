extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func run() -> void:
	var package_result := load_test_package(FIXTURE_PATH)
	if not package_result.is_ok():
		return
	var content := package_result.content
	var session := GameSession.new()
	assert_equal(session.start(content, 31).state, SessionStep.State.COMPLETED, "Party Order begins from a deterministic session")
	var setup_view := session.view()
	var race := setup_view.race_options[0]
	var caste_id := race.related_ids[0] if not race.related_ids.is_empty() else setup_view.caste_options[0].id
	var specs: Array[CharacterCreationSpec] = [
		CharacterCreationSpec.new("Alis", race.id, caste_id, 1),
		CharacterCreationSpec.new("Borin", race.id, caste_id, 1),
		CharacterCreationSpec.new("Cerys", race.id, caste_id, 1),
	]
	assert_equal(session.submit_intent(PartyIntents.create(specs)).state, SessionStep.State.COMPLETED, "the three-member fixture begins the adventure")
	var initial_ids: Array[String] = []
	var initial_state_by_id: Dictionary = {}
	for character: CharacterState in session.snapshot().game_state.party.characters():
		initial_ids.append(character.id)
		initial_state_by_id[character.id] = CharacterStateCodec.encode(character)
	assert_true(session.view().availability(&"reorder_party").enabled, "a noncombat party with at least two members may open Party Order")
	var requested_order: Array[String] = [initial_ids[2], initial_ids[0], initial_ids[1]]
	var rng_before := session.snapshot().rng_state.to_data()
	var reorder := session.submit_intent(PartyIntents.reorder(requested_order))
	assert_equal(reorder.state, SessionStep.State.COMPLETED, "a complete stable-ID permutation commits synchronously")
	assert_equal(reorder.events.size(), 1, "Party Order emits one committed domain event")
	assert_equal([reorder.events[0].kind, reorder.events[0].payload["previousCharacterIds"], reorder.events[0].payload["characterIds"]], [&"party_reordered", initial_ids, requested_order], "the event records both complete slot orders")
	assert_equal(session.view().party_members.map(func(character: CharacterView) -> String: return character.id), requested_order, "the detached view follows committed party order")
	for character: CharacterState in session.snapshot().game_state.party.characters():
		assert_equal(CharacterStateCodec.encode(character), initial_state_by_id[character.id], "reordering preserves every field owned by %s" % character.id)
	assert_equal(session.snapshot().rng_state.to_data(), rng_before, "Party Order consumes no gameplay randomness")

	var committed_state := save_data(session.snapshot())
	var duplicate := session.submit_intent(PartyIntents.reorder([requested_order[0], requested_order[0], requested_order[2]]))
	assert_equal([duplicate.state, duplicate.error_code], [SessionStep.State.FAILED, &"invalid_party_order"], "a duplicate character cannot fabricate a party slot")
	assert_equal(save_data(session.snapshot()), committed_state, "duplicate rejection is transactional")
	var unknown := session.submit_intent(PartyIntents.reorder([requested_order[0], requested_order[1], "character.unknown"]))
	assert_equal([unknown.state, unknown.error_code], [SessionStep.State.FAILED, &"invalid_party_order"], "an unknown identity cannot replace a current member")
	assert_equal(save_data(session.snapshot()), committed_state, "unknown-member rejection is transactional")

	var envelope := save_round_trip(session.snapshot())
	assert_not_null(envelope, "the reordered party produces a canonical save envelope")
	var restored := GameSession.new()
	assert_equal(restored.restore(content, envelope).state, SessionStep.State.COMPLETED, "the complete reordered party restores transactionally")
	assert_equal(restored.view().party_members.map(func(character: CharacterView) -> String: return character.id), requested_order, "save/restore retains slot order rather than sorting stable IDs")

	var solo := GameSession.new()
	solo.start(content, 32)
	assert_equal(solo.submit_intent(PartyIntents.create([CharacterCreationSpec.new("Solo", race.id, caste_id, 1)])).state, SessionStep.State.COMPLETED, "the one-member control party starts")
	assert_false(solo.view().availability(&"reorder_party").enabled, "a one-member party exposes an exact unavailable state")
	var solo_id := solo.view().party_members[0].id
	var solo_order := solo.submit_intent(PartyIntents.reorder([solo_id]))
	assert_equal([solo_order.state, solo_order.error_code], [SessionStep.State.FAILED, &"party_order_unavailable"], "one-member direct submission cannot bypass availability")
	_test_saved_party_admission(content)


func _test_saved_party_admission(content: RealmzContent) -> void:
	var source := GameSession.new()
	source.start(content, 91)
	var race := content.characters.race_definitions()[0]
	source.submit_intent(PartyIntents.create([CharacterCreationSpec.new("Transferred", race.id, race.eligible_caste_ids[0], 1)]))
	var original := source._context.state.party.characters()[0]
	original.current_health = -10
	original.brawn += 2
	original.conditions.set_value(ConditionRules.DISEASED, -1)
	original.conditions.set_value(ConditionRules.POISONED, -2)
	original.conditions.set_value(ConditionRules.INVISIBLE, 5)
	var before := save_data(source.snapshot())
	var destination := GameSession.new()
	destination.start(content, 92)
	var untouched := save_data(destination.snapshot())
	var context := SessionWorkflowContext.new(content, destination.snapshot().game_state, RealmzRules.new(), null, null, null)
	var review := PartyTransferRules.prepare(source.snapshot().game_state, content, context, destination.view().revision, "a".repeat(64))
	var candidate := review.candidates[0]
	assert_true(candidate.eligible(), "compatible saved hero is eligible without recovery")
	assert_equal([candidate.character.current_health, candidate.character.brawn, candidate.character.conditions.value(ConditionRules.DISEASED), candidate.character.conditions.value(ConditionRules.POISONED), candidate.character.conditions.value(ConditionRules.INVISIBLE)], [-10, original.brawn, -1, -2, 0], "transfer preserves permanent gains, death and lasting conditions while clearing timed effects")
	var invalid := destination.submit_intent(PartyIntents.import_saved_party([candidate.character, candidate.character], review))
	assert_equal(invalid.state, SessionStep.State.FAILED, "duplicate selections reject atomically")
	assert_equal(save_data(destination.snapshot()), untouched, "failed transfer leaves every setup field unchanged")
	assert_equal(destination.submit_intent(PartyIntents.import_saved_party([candidate.character], review)).state, SessionStep.State.COMPLETED, "reviewed selection appends in one transaction")
	assert_equal(destination.snapshot().rng_state.to_data(), context_rng(92), "party transfer consumes no destination randomness")
	assert_equal(save_data(source.snapshot()), before, "preparation and import preserve the source adventure")
	assert_equal(destination.submit_intent(PartyIntents.begin_adventure()).error_code, &"incapacitated_party", "dead-only imports cannot begin an adventure")
	assert_equal(destination.submit_intent(PartyIntents.import_saved_party([candidate.character], review)).error_code, &"party_import_stale", "repeated confirmation cannot duplicate a committed import")


func context_rng(seed: int) -> Dictionary:
	return RealmzRng.new(seed).snapshot().to_data()
