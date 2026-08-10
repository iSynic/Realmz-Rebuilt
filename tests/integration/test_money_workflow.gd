extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const CORRECTION_PATH: String = "res://tests/fixtures/oracle/money-share-capacity-correction.json"


func run() -> void:
	_test_share_capacity_correction()
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "money workflow starts from the validated package fixture")
	if not loaded.is_ok():
		return
	_test_session_money_workflow(loaded.content)


func _test_share_capacity_correction() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(CORRECTION_PATH))
	assert_true(fixture is Dictionary, "FD-ECONOMY-003 source observation fixture parses")
	if not fixture is Dictionary:
		return
	assert_true(bool(fixture["castleSourceObservation"]["shareAssignmentAllowed"]), "Castle Share admits jewelry when only one load unit remains")
	assert_equal(int(fixture["castleSourceObservation"]["shareResultingLoad"]), 114, "Castle Share can exceed maximum load by fourteen")
	var character := CharacterState.new("money.capacity", "Capacity", 10, 10)
	character.carried_load = 99
	character.maximum_load = 100
	var characters: Array[CharacterState] = [character]
	var party := PartyState.new("map.capacity", Vector2i.ZERO, characters)
	party.pooled_wealth.jewelry = 1
	var rules := EconomyRules.new()
	var probe := rules.share_probe(party)
	assert_false(probe.allowed, "FD-ECONOMY-003 requires the complete jewelry weight to fit")
	assert_false(rules.share_pooled_wealth(party), "capacity-blocked Share commits no partial mutation")
	assert_equal([character.carried_load, character.money.jewelry, party.pooled_wealth.jewelry], [99, 0, 1], "the corrected result preserves load and pooled jewelry")


func _test_session_money_workflow(content: RealmzContent) -> void:
	var session := GameSession.new()
	assert_equal(session.start(content, 107).state, SessionStep.State.COMPLETED, "money session starts")
	var pair := _playable_pair(content)
	assert_equal(pair.size(), 2, "fixture supplies a compatible race and class")
	if pair.size() != 2:
		return
	var race := pair[0] as RaceDefinition
	var caste := pair[1] as CasteDefinition
	var first := _character("money.first", "Alis", race, caste, WealthState.new(10, 2, 1))
	var second := _character("money.second", "Borin", race, caste, WealthState.new(5, 0, 0))
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(first.id, "1".repeat(64), first.to_data(), "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "first money character enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(second.id, "2".repeat(64), second.to_data(), "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "second money character enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "money fixture begins the adventure")
	var initial_view := session.view()
	assert_not_null(initial_view.money_workspace, "detached view exposes the ordinary money workspace")
	assert_true(initial_view.availability(&"money_action").enabled, "ordinary money actions are available outside battle and interactions")
	assert_true(initial_view.money_workspace.pool.enabled, "detached Pool availability comes from the core")
	assert_false(initial_view.money_workspace.share.enabled, "Share is unavailable while the pool is empty")
	assert_equal([initial_view.money_workspace.characters[0].gold, initial_view.money_workspace.characters[0].gems, initial_view.money_workspace.characters[0].jewelry], [10, 2, 1], "detached character wealth includes every Classic denomination")

	var invalid := session.submit_intent(PlayerIntent.money_action(&"to-pool", first.id, "gold", 1))
	assert_equal(invalid.error_code, &"invalid_money_increment", "forged non-Classic gold increments fail explicitly")
	assert_equal(session._state.party.character_by_id(first.id).money.gold, 10, "rejected money action mutates no wealth")
	var pooled := session.submit_intent(PlayerIntent.money_action(&"pool"))
	assert_equal(pooled.state, SessionStep.State.COMPLETED, "typed Pool commits synchronously")
	assert_equal(session._state.party.pooled_wealth.to_data(), {"gold": 15, "gems": 2, "jewelry": 1}, "Pool collects all denominations in party order without loss")
	assert_equal([session._state.party.character_by_id(first.id).carried_load, session._state.party.character_by_id(second.id).carried_load], [0, 0], "Pool removes denomination load from every character")
	assert_true(pooled.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 128), "Pool requests Castle sound 128")
	assert_true(session._state.party.character_by_id(first.id).maximum_movement < 99, "Pool recalculates Classic movement instead of leaving a stale value")
	var duplicate_pool := session.submit_intent(PlayerIntent.money_action(&"pool"))
	assert_equal(duplicate_pool.error_code, &"money_action_unavailable", "a no-op Pool intent fails transactionally")

	var restored := GameSession.new()
	assert_equal(restored.restore(content, SaveEnvelope.from_data(session.snapshot().to_data())).state, SessionStep.State.COMPLETED, "pooled wealth restores through the central save aggregate")
	assert_equal(restored.view().money_workspace.pooled_jewelry, 1, "restored detached money facts retain non-gold denominations")
	var to_character := restored.submit_intent(PlayerIntent.money_action(&"to-character", first.id, "gold", 5))
	assert_equal(to_character.state, SessionStep.State.COMPLETED, "Swap moves one Classic gold increment from pool to character")
	assert_equal([restored._state.party.pooled_wealth.gold, restored._state.party.character_by_id(first.id).money.gold], [10, 5], "gold Swap preserves exact denomination totals")
	assert_true(to_character.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 10051), "pool-to-character Swap requests Castle sound 10051")
	var to_pool := restored.submit_intent(PlayerIntent.money_action(&"to-pool", first.id, "gold", 5))
	assert_equal(to_pool.state, SessionStep.State.COMPLETED, "Swap returns one Classic gold increment to the pool")
	assert_true(to_pool.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 663), "character-to-pool Swap requests Castle sound 663")

	var carried_first := restored._state.party.character_by_id(first.id)
	carried_first.maximum_load = 10
	var capacity_view := restored.view().money_workspace.character(first.id).transfer(&"jewelry")
	assert_false(capacity_view.to_character.enabled, "detached Swap availability blocks jewelry that does not fully fit")
	var blocked_jewelry := restored.submit_intent(PlayerIntent.money_action(&"to-character", first.id, "jewelry", 1))
	assert_equal(blocked_jewelry.error_code, &"money_action_unavailable", "a forged capacity-blocked jewelry transfer fails transactionally")
	assert_equal(restored._state.party.pooled_wealth.jewelry, 1, "blocked Swap preserves pooled jewelry")
	carried_first.maximum_load = 500

	var shared := restored.submit_intent(PlayerIntent.money_action(&"share"))
	assert_equal(shared.state, SessionStep.State.COMPLETED, "typed Share commits synchronously")
	assert_equal(restored._state.party.pooled_wealth.to_data(), {"gold": 0, "gems": 0, "jewelry": 0}, "Share drains every denomination that can fit")
	assert_equal([carried_first.money.gold, carried_first.money.gems, carried_first.money.jewelry], [8, 1, 1], "Share assigns jewelry, gems, then gold in party order")
	var carried_second := restored._state.party.character_by_id(second.id)
	assert_equal([carried_second.money.gold, carried_second.money.gems, carried_second.money.jewelry], [7, 1, 0], "Share continues round-robin assignment across the party")
	assert_true(carried_first.carried_load <= carried_first.maximum_load and carried_second.carried_load <= carried_second.maximum_load, "corrected Share never overloads a recipient")
	assert_true(shared.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 128), "Share requests Castle sound 128")
	var duplicate_share := restored.submit_intent(PlayerIntent.money_action(&"share"))
	assert_equal(duplicate_share.error_code, &"money_action_unavailable", "a no-op Share intent fails transactionally")
	var final_restore := GameSession.new()
	assert_equal(final_restore.restore(content, SaveEnvelope.from_data(restored.snapshot().to_data())).state, SessionStep.State.COMPLETED, "shared personal wealth restores transactionally")
	assert_equal(final_restore._state.party.to_data(), restored._state.party.to_data(), "save restoration preserves complete pooled, personal, load, and movement state")


func _playable_pair(content: RealmzContent) -> Array:
	for caste: CasteDefinition in content.caste_definitions():
		for race: RaceDefinition in content.race_definitions():
			if not race.eligible_caste_ids.is_empty() and not race.eligible_caste_ids.has(caste.id):
				continue
			if not caste.eligible_race_ids.is_empty() and not caste.eligible_race_ids.has(race.id):
				continue
			return [race, caste]
	return []


func _character(character_id: String, display_name: String, race: RaceDefinition, caste: CasteDefinition, wealth: WealthState) -> CharacterState:
	var result := CharacterState.new(character_id, display_name, 10, 10)
	result.race_id = race.id
	result.caste_id = caste.id
	result.brawn = 5
	result.maximum_load = 500
	result.money = wealth
	result.carried_load = wealth.gold + wealth.gems + wealth.jewelry * 15
	result.maximum_movement = 99
	result.movement = 99
	return result
