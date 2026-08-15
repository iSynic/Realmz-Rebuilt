extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func run() -> void:
	var package_result := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(package_result.is_ok(), "the synthetic package loads before Party Order testing")
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
	assert_equal(session.submit_intent(PlayerIntent.create_party(specs)).state, SessionStep.State.COMPLETED, "the three-member fixture begins the adventure")
	var initial_ids: Array[String] = []
	var initial_state_by_id: Dictionary = {}
	for character: CharacterState in session.snapshot().game_state.party.characters():
		initial_ids.append(character.id)
		initial_state_by_id[character.id] = character.to_data()
	assert_true(session.view().availability(&"reorder_party").enabled, "a noncombat party with at least two members may open Party Order")
	var requested_order: Array[String] = [initial_ids[2], initial_ids[0], initial_ids[1]]
	var rng_before := session.snapshot().rng_state.to_data()
	var reorder := session.submit_intent(PlayerIntent.reorder_party(requested_order))
	assert_equal(reorder.state, SessionStep.State.COMPLETED, "a complete stable-ID permutation commits synchronously")
	assert_equal(reorder.events.size(), 1, "Party Order emits one committed domain event")
	assert_equal([reorder.events[0].kind, reorder.events[0].payload["previousCharacterIds"], reorder.events[0].payload["characterIds"]], [&"party_reordered", initial_ids, requested_order], "the event records both complete slot orders")
	assert_equal(session.view().party_members.map(func(character: CharacterView) -> String: return character.id), requested_order, "the detached view follows committed party order")
	for character: CharacterState in session.snapshot().game_state.party.characters():
		assert_equal(character.to_data(), initial_state_by_id[character.id], "reordering preserves every field owned by %s" % character.id)
	assert_equal(session.snapshot().rng_state.to_data(), rng_before, "Party Order consumes no gameplay randomness")

	var committed_state := save_data(session.snapshot())
	var duplicate := session.submit_intent(PlayerIntent.reorder_party([requested_order[0], requested_order[0], requested_order[2]]))
	assert_equal([duplicate.state, duplicate.error_code], [SessionStep.State.FAILED, &"invalid_party_order"], "a duplicate character cannot fabricate a party slot")
	assert_equal(save_data(session.snapshot()), committed_state, "duplicate rejection is transactional")
	var unknown := session.submit_intent(PlayerIntent.reorder_party([requested_order[0], requested_order[1], "character.unknown"]))
	assert_equal([unknown.state, unknown.error_code], [SessionStep.State.FAILED, &"invalid_party_order"], "an unknown identity cannot replace a current member")
	assert_equal(save_data(session.snapshot()), committed_state, "unknown-member rejection is transactional")

	var envelope := save_round_trip(session.snapshot())
	assert_not_null(envelope, "the reordered party produces a canonical save envelope")
	var restored := GameSession.new()
	assert_equal(restored.restore(content, envelope).state, SessionStep.State.COMPLETED, "the complete reordered party restores transactionally")
	assert_equal(restored.view().party_members.map(func(character: CharacterView) -> String: return character.id), requested_order, "save/restore retains slot order rather than sorting stable IDs")

	var solo := GameSession.new()
	solo.start(content, 32)
	assert_equal(solo.submit_intent(PlayerIntent.create_party([CharacterCreationSpec.new("Solo", race.id, caste_id, 1)])).state, SessionStep.State.COMPLETED, "the one-member control party starts")
	assert_false(solo.view().availability(&"reorder_party").enabled, "a one-member party exposes an exact unavailable state")
	var solo_id := solo.view().party_members[0].id
	var solo_order := solo.submit_intent(PlayerIntent.reorder_party([solo_id]))
	assert_equal([solo_order.state, solo_order.error_code], [SessionStep.State.FAILED, &"party_order_unavailable"], "one-member direct submission cannot bypass availability")
