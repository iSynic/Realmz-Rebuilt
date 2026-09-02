extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const CORRECTION_PATH: String = "res://tests/fixtures/oracle/money-share-capacity-correction.json"
const DEPARTURE_OBSERVATION_PATH: String = "res://tests/fixtures/oracle/classic-pooled-wealth-departure-source-observation.json"


func selected_case_arguments() -> Array:
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "money workflow starts from the validated package fixture")
	return [loaded.content] if loaded.is_ok() else []


func run() -> void:
	_test_share_capacity_correction()
	_test_pooled_departure_source_observation()
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "money workflow starts from the validated package fixture")
	if not loaded.is_ok():
		return
	_test_session_money_workflow(loaded.content)
	_test_pooled_wealth_departure(loaded.content)


func _test_pooled_departure_source_observation() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEPARTURE_OBSERVATION_PATH))
	assert_true(fixture is Dictionary, "pooled-wealth departure source observation parses")
	if not fixture is Dictionary:
		return
	assert_equal(fixture.get("caseId"), "economy.pooled-wealth-departure", "the source observation remains linked to its differential case")
	var branches: Array = fixture.get("branches", [])
	assert_equal(branches.size(), 2, "the source observation owns both no-bank choices")
	if branches.size() == 2:
		assert_true(String(branches[0].get("outcome", "")).contains("continue"), "declining distribution continues ordinary movement")
		assert_true(String(branches[1].get("outcome", "")).contains("continue"), "accepted distribution continues the ordinary caller")
	var moveparty_source := (fixture.get("sources", []) as Array).filter(func(source: Dictionary) -> bool: return String(source.get("path", "")).ends_with("moveparty.c"))
	assert_equal(moveparty_source.size(), 1, "the observation distinguishes the internal moveparty fallback")
	if moveparty_source.size() == 1:
		assert_true(String(moveparty_source[0].get("observation", "")).contains("fallback"), "the internal early-return path is not generalized to ordinary travel")


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
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(first.id, "1".repeat(64), first, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "first money character enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(second.id, "2".repeat(64), second, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "second money character enters party setup")
	_begin_with_start_hook(session, "money fixture begins the adventure")
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
	assert_equal(restored.restore(content, save_round_trip(session.snapshot())).state, SessionStep.State.COMPLETED, "pooled wealth restores through the central save aggregate")
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
	assert_equal(final_restore.restore(content, save_round_trip(restored.snapshot())).state, SessionStep.State.COMPLETED, "shared personal wealth restores transactionally")
	assert_equal(final_restore._state.party.to_data(), restored._state.party.to_data(), "save restoration preserves complete pooled, personal, load, and movement state")


func _test_pooled_wealth_departure(content: RealmzContent) -> void:
	var blocked_session := _departure_session(content, 109)
	if blocked_session == null: return
	assert_equal(blocked_session.apply_debug_command(SessionDebugCommand.warp("dungeon:0", Vector2i(1, 0))).state, SessionStep.State.COMPLETED, "the blocked-departure fixture uses an authored dungeon wall destination")
	var invalid := blocked_session.submit_intent(PlayerIntent.move(Vector2i(2, 0)))
	assert_equal(invalid.error_code, &"invalid_direction", "an invalid direction fails before the pooled-wealth warning")
	assert_equal(blocked_session._state.party.pooled_wealth.gold, 10, "invalid movement preserves pooled wealth")
	var blocked_warning := blocked_session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_equal([blocked_warning.state, blocked_warning.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.YES_NO], "a no-bank movement attempt warns before resolving a blocked destination")
	assert_equal(blocked_session.view().party_coordinate, Vector2i(1, 0), "the warning commits no movement")
	assert_equal(blocked_session._state.party.pooled_wealth.gold, 10, "the warning commits no wealth loss")
	assert_true(blocked_warning.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 20005 and event.payload.get("stopExisting") == true), "the pooled-wealth question requests Castle's quiet-and-question sound")
	var warning_save_data := save_data(blocked_session.snapshot())
	var invalid_direction_data: Dictionary = warning_save_data.duplicate(true)
	invalid_direction_data["sessionContinuation"]["data"]["directionX"] = 2
	assert_equal(SaveEnvelope.from_data(invalid_direction_data), null, "the save envelope rejects an out-of-range pooled-departure direction")
	var forged_request_data: Dictionary = warning_save_data.duplicate(true)
	forged_request_data["sessionInteraction"]["data"]["payload"]["prompt"] = "Forged prompt"
	var forged_request_envelope := SaveEnvelope.from_data(forged_request_data)
	assert_not_null(forged_request_envelope, "a JSON-safe forged request reaches semantic restore validation")
	if forged_request_envelope != null:
		var forged_request_session := GameSession.new()
		assert_equal(forged_request_session.restore(content, forged_request_envelope).error_code, &"invalid_session_continuation", "restore rejects a request that does not match its pooled-departure continuation")
	var blocked_restored := GameSession.new()
	assert_equal(blocked_restored.restore(content, SaveEnvelope.from_data(warning_save_data)).state, SessionStep.State.COMPLETED, "the warning restores through the central save aggregate")
	var blocked_decline := blocked_restored.respond(InteractionResponse.yes_no(blocked_restored.view().pending_interaction, false))
	assert_equal(blocked_restored._state.party.pooled_wealth.gold, 0, "declining distribution clears the abandoned pool")
	assert_equal(blocked_restored.view().party_coordinate, Vector2i(1, 0), "declining continues into the original blocked movement result")
	assert_true(blocked_decline.events.any(func(event: DomainEvent) -> bool: return event.kind == &"movement_blocked"), "the blocked destination is resolved only after the no-bank choice")

	var distribute_session := _departure_session(content, 110)
	if distribute_session == null:
		return
	var distribution_warning := distribute_session.submit_intent(PlayerIntent.move(Vector2i(-1, -1)))
	var warning_restored := GameSession.new()
	assert_equal(warning_restored.restore(content, save_round_trip(distribute_session.snapshot())).state, SessionStep.State.COMPLETED, "an allowed movement warning restores before its response")
	var distribution := warning_restored.respond(InteractionResponse.yes_no(warning_restored.view().pending_interaction, true))
	assert_equal([distribution.state, distribution.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.POOLED_WEALTH_DEPARTURE], "accepting the warning opens typed pooled-wealth distribution")
	assert_equal(warning_restored.view().party_coordinate, Vector2i(1, 1), "opening Swap pauses the pending movement until distribution ends")
	assert_true(distribution.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 3003 and event.payload.get("stopExisting") == true), "direct Castle Swap entry quiets existing audio and requests sound 3003")
	var distribution_restored := GameSession.new()
	assert_equal(distribution_restored.restore(content, save_round_trip(warning_restored.snapshot())).state, SessionStep.State.COMPLETED, "the pooled distribution workspace restores transactionally")
	var request := distribution_restored.view().pending_interaction
	var character_id: String = distribution_restored._state.party.characters()[0].id
	var forged := distribution_restored.respond(InteractionResponse.from_data(request.request_id, InteractionRequest.POOLED_WEALTH_DEPARTURE, {"action": "to-character", "characterId": character_id, "denomination": "gold", "amount": 1}))
	assert_equal(forged.error_code, &"invalid_money_increment", "a forged non-Classic transfer fails without closing the restored workspace")
	assert_equal(distribution_restored._state.party.pooled_wealth.gold, 10, "the rejected transfer preserves exact pooled wealth")
	request = distribution_restored.view().pending_interaction
	var transfer_response := InteractionResponse.from_data(request.request_id, InteractionRequest.POOLED_WEALTH_DEPARTURE, {"action": "to-character", "characterId": character_id, "denomination": "gold", "amount": 5})
	var transferred := distribution_restored.respond(transfer_response)
	assert_equal(transferred.state, SessionStep.State.WAITING_FOR_INTERACTION, "an exact Swap transfer keeps the distribution workspace active")
	assert_equal([distribution_restored._state.party.pooled_wealth.gold, distribution_restored._state.party.character_by_id(character_id).money.gold], [5, 5], "the departure Swap transfers one exact Classic increment")
	assert_true(transferred.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 10051), "pool-to-character departure Swap requests Castle sound 10051")
	assert_equal(distribution_restored.respond(transfer_response).error_code, &"interaction_mismatch", "a response from the prior distribution revision cannot replay a committed transfer")
	request = distribution_restored.view().pending_interaction
	var shared := distribution_restored.respond(InteractionResponse.from_data(request.request_id, InteractionRequest.POOLED_WEALTH_DEPARTURE, {"action": "share"}))
	assert_equal(shared.state, SessionStep.State.WAITING_FOR_INTERACTION, "Share may drain the pool while keeping the source modal open for Done")
	assert_equal(distribution_restored._state.party.pooled_wealth.to_data(), {"gold": 0, "gems": 0, "jewelry": 0}, "departure Share processes jewelry, gems, and gold from the same pooled workspace")
	var mutation_restored := GameSession.new()
	assert_equal(mutation_restored.restore(content, save_round_trip(distribution_restored.snapshot())).state, SessionStep.State.COMPLETED, "an empty post-Share pool and its still-pending Done workspace restore together")
	request = mutation_restored.view().pending_interaction
	var done := mutation_restored.respond(InteractionResponse.from_data(request.request_id, InteractionRequest.POOLED_WEALTH_DEPARTURE, {"action": "leave"}))
	assert_equal(done.state, SessionStep.State.COMPLETED, "Done closes Swap and resumes the ordinary movement path")
	assert_equal(mutation_restored._state.party.pooled_wealth.gold, 0, "Done leaves no pooled remainder after Share")
	assert_equal(mutation_restored.view().party_coordinate, Vector2i.ZERO, "ordinary checkmoneypool resumes the original movement after Swap closes")
	assert_true(done.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 141), "Done requests Castle's Swap-close sound")

	var continue_session := _departure_session(content, 111)
	if continue_session == null:
		return
	var continue_warning := continue_session.submit_intent(PlayerIntent.move(Vector2i(-1, -1)))
	var continued := continue_session.respond(InteractionResponse.yes_no(continue_warning.interaction, false))
	assert_equal(continued.state, SessionStep.State.COMPLETED, "declining distribution resolves the original allowed movement")
	assert_equal(continue_session.view().party_coordinate, Vector2i.ZERO, "declining continues through the saved diagonal direction exactly once")
	assert_equal(continue_session._state.party.pooled_wealth.gold, 0, "continued movement leaves no pooled wealth behind")

	var bank_session := _departure_session(content, 112)
	if bank_session == null: return
	assert_equal(bank_session.apply_debug_command(SessionDebugCommand.warp("dungeon:0", Vector2i(1, 0))).state, SessionStep.State.COMPLETED, "the bank-before-movement fixture uses the same authored dungeon wall destination")
	bank_session._state.bank_available = true
	var banked_block := bank_session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_equal(banked_block.state, SessionStep.State.COMPLETED, "bank-backed pooled wealth resolves without a question before a blocked attempt")
	assert_equal(bank_session._state.party.pooled_wealth.to_data(), {"gold": 0, "gems": 0, "jewelry": 0}, "pre-movement banking clears every pooled denomination")
	assert_equal(bank_session._state.party.banked_wealth.to_data(), {"gold": 10, "gems": 1, "jewelry": 1}, "pre-movement banking preserves all denominations")
	assert_false(bank_session._state.bank_available, "pre-movement banking disables the location bank even when the destination is blocked")
	assert_true(banked_block.events.any(func(event: DomainEvent) -> bool: return event.kind == &"movement_blocked"), "the blocked destination resolves after banking")

	var camp_session := _departure_session(content, 113)
	if camp_session == null:
		return
	assert_equal(camp_session.submit_intent(PlayerIntent.camp()).state, SessionStep.State.COMPLETED, "departure ordering fixture enters camp")
	var camp_clock := [camp_session.view().realmz_day, camp_session.view().realmz_hour, camp_session.view().realmz_minute]
	var camp_warning := camp_session.submit_intent(PlayerIntent.move(Vector2i(-1, -1)))
	assert_equal(camp_warning.state, SessionStep.State.WAITING_FOR_INTERACTION, "camp movement resolves pooled wealth before camp departure")
	assert_true(camp_session._state.party_camping, "the pooled warning has not yet cleared camp state")
	assert_equal([camp_session.view().realmz_day, camp_session.view().realmz_hour, camp_session.view().realmz_minute], camp_clock, "the pooled warning has not yet advanced camp-departure time")
	var camp_departure := camp_session.respond(InteractionResponse.yes_no(camp_warning.interaction, false))
	var camp_event_kinds: Array[StringName] = []
	for event: DomainEvent in camp_departure.events:
		camp_event_kinds.append(event.kind)
	assert_true(camp_event_kinds.find(&"pooled_wealth_left_behind") < camp_event_kinds.find(&"camp_mode_changed"), "pool cleanup precedes camp clearing in the committed event trace")
	assert_false(camp_session._state.party_camping, "declining distribution resumes the source camp-departure path")


func _departure_session(content: RealmzContent, seed: int) -> GameSession:
	var pair := _playable_pair(content)
	assert_equal(pair.size(), 2, "departure workflow fixture supplies a compatible race and class")
	if pair.size() != 2:
		return null
	var session := GameSession.new()
	assert_equal(session.start(content, seed).state, SessionStep.State.COMPLETED, "pooled-wealth departure session starts")
	var character := _character("money.departure.%d" % seed, "Traveler", pair[0] as RaceDefinition, pair[1] as CasteDefinition, WealthState.new(10, 1, 1))
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(character.id, "d".repeat(64), character, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "departure character enters party setup")
	_begin_with_start_hook(session, "departure fixture begins the adventure")
	assert_equal(session.submit_intent(PlayerIntent.money_action(&"pool")).state, SessionStep.State.COMPLETED, "departure fixture enters movement with pooled wealth")
	return session


func _playable_pair(content: RealmzContent) -> Array:
	for caste: CasteDefinition in content.caste_definitions():
		for race: RaceDefinition in content.race_definitions():
			if not race.eligible_caste_ids.is_empty() and not race.eligible_caste_ids.has(caste.id):
				continue
			if not caste.eligible_race_ids.is_empty() and not caste.eligible_race_ids.has(race.id):
				continue
			return [race, caste]
	return []


func _begin_with_start_hook(session: GameSession, label: String) -> void:
	var started := session.submit_intent(PlayerIntent.begin_adventure())
	if started.state == SessionStep.State.WAITING_FOR_INTERACTION:
		assert_equal(session.respond(InteractionResponse.acknowledge(started.interaction)).state, SessionStep.State.COMPLETED, label)
	else:
		assert_equal(started.state, SessionStep.State.COMPLETED, label)


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
