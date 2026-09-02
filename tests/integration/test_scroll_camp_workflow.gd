extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const CORRECTION_PATH: String = "res://tests/fixtures/oracle/scroll-target-cancel-consumption-correction.json"
const TIMED_COORDINATE_CORRECTION_PATH: String = "res://tests/fixtures/oracle/timed-encounter-coordinate-correction.json"
const TIMED_RECOVERY_CORRECTION_PATH: String = "res://tests/fixtures/oracle/timed-encounter-recovery-correction.json"


func run() -> void:
	var correction: Variant = JSON.parse_string(FileAccess.get_file_as_string(CORRECTION_PATH))
	assert_true(correction is Dictionary, "the scroll target-cancel fidelity decision is parseable")
	if correction is Dictionary:
		assert_true(correction["castleSourceObservation"]["validScrollClearedBeforeTargetSelection"], "the fixture records Castle's premature scroll consumption")
		assert_true(correction["realmz2ChosenResult"]["invalidOrCancelledSelectionPreservesScroll"], "the fixture records the selected transactional scroll correction")
	var timed_coordinate_correction: Variant = JSON.parse_string(FileAccess.get_file_as_string(TIMED_COORDINATE_CORRECTION_PATH))
	assert_true(timed_coordinate_correction is Dictionary, "the timed-coordinate fidelity decision is parseable")
	if timed_coordinate_correction is Dictionary:
		assert_equal(timed_coordinate_correction["castleSourceObservation"]["yRequirementGuard"], "recx > -1", "the fixture records Castle's y-gate typo")
		assert_equal(timed_coordinate_correction["realmz2ChosenResult"]["successfulMoveCoordinate"], "committed destination", "the fixture records the semantic destination correction")
	var timed_recovery_correction: Variant = JSON.parse_string(FileAccess.get_file_as_string(TIMED_RECOVERY_CORRECTION_PATH))
	assert_true(timed_recovery_correction is Dictionary, "the timed-recovery fidelity decision is parseable")
	if timed_recovery_correction is Dictionary:
		assert_equal(timed_recovery_correction["castleSourceObservation"]["halfDayRecoveryCount"], 2, "the fixture records Castle's repeated recovery path")
		assert_equal(timed_recovery_correction["realmz2ChosenResult"]["halfDayRecoveryCount"], 1, "the fixture records one recovery per midnight")
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "scroll/camp workflow starts from the validated package fixture")
	if not loaded.is_ok():
		return
	var content := _scroll_content(loaded.content)
	_test_scroll_case_management(content)
	var session := GameSession.new()
	assert_equal(session.start(content, 117).state, SessionStep.State.COMPLETED, "scroll/camp session starts")
	var caster := _character("scroll.caster", "Cora", content)
	var target := _character("scroll.target", "Dain", content)
	var scroll_case := ItemInstance.new("scroll.case.instance", "classic.item.scroll-case", 0, true, true)
	var parchment := ItemInstance.new("scroll.parchment.instance", "classic.item.parchment", 3, false, true)
	caster.set_inventory([scroll_case, parchment])
	caster.carried_load = content.item_by_id(scroll_case.definition_id).instance_weight(0) + content.item_by_id(parchment.definition_id).instance_weight(3)
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(caster.id, "1".repeat(64), caster, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "scroll user enters party setup with an equipped case and parchment")
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(target.id, "2".repeat(64), target, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "scroll target enters party setup")
	var invalid := _character("scroll.invalid", "Invalid", content)
	invalid.write_scroll(0, "classic.spell.missing", 1)
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(invalid.id, "3".repeat(64), invalid, "fixture", content.package_hash)).error_code, &"vault_character_ineligible", "vault import rejects an unresolved scroll spell before it can poison later saves")
	assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "scroll/camp fixture begins")
	var active_caster := session._state.party.character_by_id(caster.id)
	var active_target := session._state.party.character_by_id(target.id)
	active_target.current_health = 5
	active_target.maximum_health = 20
	var outside_view: SpellView = session.view().party_members[0].spells[0]
	assert_false(outside_view.make_scroll.enabled, "scroll scribing is unavailable before entering camp")
	assert_equal(session.submit_intent(PlayerIntent.make_scroll("classic.spell.scroll-heal", active_caster.id, 2)).error_code, &"scroll_scribing_unavailable", "a forged out-of-camp scribing intent is rejected without mutation")

	var entered := session.submit_intent(PlayerIntent.camp())
	assert_equal(entered.state, SessionStep.State.COMPLETED, "Camp enters source-owned camp mode instead of performing an invented eight-hour rest"); assert_true(entered.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 10001), "Camp entry requests Castle sound 10001")
	assert_true(session._state.party_camping, "camp mode is session-owned")
	assert_equal(session._state.clock.total_minutes(), 25, "entering land camp advances Castle's five scaled time clicks")
	assert_equal([session.view().realmz_hour, session.view().realmz_minute], [0, 25], "the detached view exposes the sub-hour camp cost to presentation")
	assert_equal(active_caster.current_health, 12, "entering camp does not fabricate full healing")
	assert_true(session.view().availability(&"move").enabled, "movement remains available because the session now owns Classic camp departure ordering")
	assert_true(session.view().availability(&"rest").enabled, "Rest becomes available only after entering camp")
	assert_equal(session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH)).error_code, &"search_while_camped", "the ordinary Search command is replaced by scroll scribing in camp")

	var camp_save := save_round_trip(session.snapshot()); var exited := session.submit_intent(PlayerIntent.camp()); assert_true(exited.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 141), "explicit Camp exit requests Castle button sound 141")
	assert_not_null(camp_save, "camp mode is a committed save boundary")
	var restored := GameSession.new()
	assert_equal(restored.restore(content, camp_save).state, SessionStep.State.COMPLETED, "camp mode restores transactionally")
	active_caster = restored._state.party.character_by_id(caster.id)
	active_target = restored._state.party.character_by_id(target.id)
	restored._state.random_encounters_enabled = false
	var camp_spell: SpellView = restored.view().party_members[0].spells[0]
	assert_equal(camp_spell.scroll_power_levels, [1, 2, 3, 4, 5, 6, 7], "camp spell view exposes every affordable scroll power")
	var starting_spell_points := active_caster.spell_points
	var starting_load := active_caster.carried_load
	var scribing_draw_count := restored._rng.snapshot().draw_count
	var created := restored.submit_intent(PlayerIntent.make_scroll("classic.spell.scroll-heal", active_caster.id, 2))
	assert_equal(created.state, SessionStep.State.COMPLETED, "making a scroll commits through the typed spell intent")
	assert_equal(active_caster.spell_points, starting_spell_points - 8, "scroll scribing spends twice the normal power-scaled spell cost")
	assert_equal(active_caster.inventory()[1].charges, 2, "scroll scribing consumes exactly one parchment charge")
	assert_equal(active_caster.carried_load, starting_load - 1, "consumed parchment removes its per-charge load")
	assert_equal([active_caster.scroll_at(0).spell_id, active_caster.scroll_at(0).power], ["classic.spell.scroll-heal", 2], "scroll scribing fills the first empty fixed slot")
	assert_equal(restored._rng.snapshot().draw_count, scribing_draw_count, "scroll scribing consumes no effect RNG")
	assert_true(created.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("waitForCompletion") == false), "scroll scribing requests Castle's asynchronous completion sound")
	assert_equal(restored.submit_intent(PlayerIntent.make_scroll("classic.spell.scroll-fixed", active_caster.id, 2)).error_code, &"scroll_scribing_unavailable", "negative-cost Classic spells cannot be scribed above fixed power one")

	var rest_session := GameSession.new()
	assert_equal(rest_session.restore(content, camp_save).state, SessionStep.State.COMPLETED, "the dedicated Rest characterization starts from the committed camp boundary")
	rest_session._state.random_encounters_enabled = false
	var rest_caster := rest_session._state.party.character_by_id(caster.id)
	var rest_target := rest_session._state.party.character_by_id(target.id)
	rest_target.current_health = rest_target.maximum_health
	rest_caster.level = 6
	rest_caster.maximum_health = 20
	rest_caster.current_health = 5
	rest_caster.spell_points = 0
	rest_session._state.party.fatigue = 80
	rest_session._state.party.conditions.set_value(ConditionRules.PARTY_TORCH_LIT, 3)
	rest_session._state.clock.set_total_minutes(50)
	var rested := rest_session.submit_intent(PlayerIntent.rest())
	assert_equal(rested.state, SessionStep.State.COMPLETED, "one typed Rest intent commits one held-control pulse")
	assert_equal(rest_session._state.clock.total_minutes(), 75, "one outdoor Rest pulse advances five five-minute time clicks")
	assert_equal(_events(rested, &"time_advanced").map(func(event: DomainEvent) -> int: return int(event.payload["minutes"])), [5, 5, 5, 5, 5], "Rest publishes each Classic five-minute time click instead of collapsing the pulse into one twenty-five-minute event")
	assert_equal(_events(rested, &"time_advanced").map(func(event: DomainEvent) -> int: return int(event.payload["minute"])), [55, 0, 5, 10, 15], "the five-minute trace preserves the exact intermediate clock state around the crossed hour")
	assert_equal(rest_session._state.party.fatigue, 79, "Rest removes two fatigue before the crossed hour adds one")
	assert_equal(rest_session._state.party.conditions.value(ConditionRules.PARTY_TORCH_LIT), 1, "the crossed hour applies Castle's generic and torch-specific light decrements")
	assert_equal(rest_caster.spell_points, 3, "the crossed hour restores half the character level in spell points")
	assert_equal(rest_caster.current_health, 5, "an ordinary hour boundary does not restore health")
	assert_true(_has_event(rested, &"party_rested"), "Rest publishes a committed workflow event")

	var ration := ItemInstance.new("scroll.rations.instance", "classic.item.iron-rations", 2, false, true)
	var ration_items := rest_caster.inventory()
	ration_items.append(ration)
	rest_caster.set_inventory(ration_items)
	rest_caster.carried_load += content.item_by_id(ration.definition_id).instance_weight(ration.charges)
	rest_caster.current_health = 5
	rest_session._state.clock.set_total_minutes(710)
	var noon_rest := rest_session.submit_intent(PlayerIntent.rest())
	assert_equal(noon_rest.state, SessionStep.State.COMPLETED, "Rest crossing noon completes without an invented duration picker")
	assert_equal(rest_caster.current_health, 7, "charged Iron Rations preserve the full level-divided noon recovery")
	assert_equal(ration.charges, 1, "noon recovery consumes exactly one Iron Rations charge for the injured character")
	assert_true(_has_event(noon_rest, &"rest_ration_consumed"), "ration consumption is observable in the deterministic trace")
	var rest_save := save_round_trip(rest_session.snapshot())
	var rest_restored := GameSession.new()
	assert_equal(rest_restored.restore(content, rest_save).state, SessionStep.State.COMPLETED, "Rest recovery and its exact ration charge restore transactionally")
	assert_equal(rest_restored._state.party.character_by_id(caster.id).inventory()[-1].charges, 1, "save/reload does not replay the recovery draw or consume another ration")

	var poisoned_session := GameSession.new()
	assert_equal(poisoned_session.restore(content, camp_save).state, SessionStep.State.COMPLETED, "the poisoned half-day characterization starts from the committed camp boundary")
	poisoned_session._state.random_encounters_enabled = false
	var poisoned_caster := poisoned_session._state.party.character_by_id(caster.id)
	var poisoned_target := poisoned_session._state.party.character_by_id(target.id)
	poisoned_target.current_health = poisoned_target.maximum_health
	poisoned_caster.level = 6
	poisoned_caster.maximum_health = 20
	poisoned_caster.current_health = 10
	poisoned_caster.conditions.set_value(ConditionRules.POISONED, 3)
	poisoned_session._state.clock.set_total_minutes(710)
	var poisoned_noon := poisoned_session.submit_intent(PlayerIntent.rest())
	assert_equal(poisoned_noon.state, SessionStep.State.COMPLETED, "a poisoned Rest pulse crosses noon through the ordinary committed clock path")
	assert_equal(poisoned_caster.conditions.value(ConditionRules.POISONED), 2, "the hourly reduction decays positive Poisoned before half-day recovery")
	assert_equal(poisoned_caster.current_health, 10, "Castle's signed recovery term offsets the prior poison damage without creating net bonus health")
	assert_true(_event_position(poisoned_noon, &"condition_damaged") < _event_position(poisoned_noon, &"health_recovered"), "poison damage is observable before half-day recovery")
	assert_equal(_events(poisoned_noon, &"condition_damaged")[0].payload.get("amount"), 3, "the hourly tick damages by the pre-decay poison value")
	assert_equal(_events(poisoned_noon, &"health_recovered")[0].payload.get("amount"), 3, "half-day recovery uses the decayed poison value plus the unrationed level recovery")

	var timed_session := GameSession.new()
	assert_equal(timed_session.restore(content, camp_save).state, SessionStep.State.COMPLETED, "the timed-midnight fixture starts from the saved camp boundary")
	timed_session._state.random_encounters_enabled = false
	var timed_caster := timed_session._state.party.character_by_id(caster.id)
	var timed_target := timed_session._state.party.character_by_id(target.id)
	timed_target.current_health = timed_target.maximum_health
	timed_caster.level = 6
	timed_caster.maximum_health = 20
	timed_caster.current_health = 5
	var midnight_ration := ItemInstance.new("scroll.midnight-rations.instance", "classic.item.iron-rations", 2, false, true)
	var timed_items := timed_caster.inventory()
	timed_items.append(midnight_ration)
	timed_caster.set_inventory(timed_items)
	timed_caster.carried_load += content.item_by_id(midnight_ration.definition_id).instance_weight(midnight_ration.charges)
	timed_session._state.clock.set_total_minutes(RealmzClock.MINUTES_PER_DAY - 10)
	timed_session._rng = ScriptedRng.new([0])
	var timed := timed_session.submit_intent(PlayerIntent.rest())
	assert_equal([timed.state, timed.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.ACKNOWLEDGE], "crossing midnight dispatches the eligible timed XAP before returning to camp")
	assert_equal(timed_session._state.timed_encounter_override(0).get("day"), 5, "the timed record advances by its increment before its interaction yields")
	assert_true(_has_event(timed, &"timed_encounter_triggered"), "the timed dispatch has an explicit domain trace")
	assert_equal(_events(timed, &"timed_encounter_triggered")[0].payload.get("programId"), "xap:7", "the timed record invokes its Data ED3 XAP identity directly")
	assert_true(_event_position(timed, &"timed_encounter_checked") < _event_position(timed, &"rest_ration_consumed"), "midnight eligibility is settled before Castle's half-day recovery")
	assert_equal([timed_caster.current_health, midnight_ration.charges], [7, 1], "midnight recovery runs exactly once immediately before the first eligible dispatch")
	assert_equal(timed_session.rng_trace()[-1]["tag"], "timed-encounter.0", "the timed chance draw is centralized and semantically tagged")
	assert_equal(timed_session.view().party_coordinate, content.start_coordinate, "a yielding XAP retains the pre-teleport location until its issuing frame resumes")
	var timed_restored := GameSession.new()
	assert_equal(timed_restored.restore(content, save_round_trip(timed_session.snapshot())).state, SessionStep.State.COMPLETED, "the timed interaction and scan cursor restore transactionally")
	var timed_request := timed_restored.view().pending_interaction
	var timed_completed := timed_restored.respond(InteractionResponse.from_data(timed_request.request_id, InteractionRequest.ACKNOWLEDGE, {}))
	assert_equal(timed_completed.state, SessionStep.State.COMPLETED, "acknowledging the timed XAP resumes and completes the midnight scan")
	assert_equal(timed_restored.view().party_coordinate, Vector2i(2, 0), "the resumed XAP commits its explicit Classic teleport before the remaining timed scan")
	assert_equal(_events(timed_completed, &"timed_encounter_triggered").map(func(event: DomainEvent) -> Variant: return event.payload.get("programId")), ["xap:8"], "the remaining scan advances to the next timed XAP exactly once")
	assert_true(_events(timed_completed, &"message_shown").any(func(event: DomainEvent) -> bool: return event.payload.get("messageId") == 778), "the relocated coordinate satisfies the next timed record")
	assert_equal(timed_restored._state.timed_encounter_override(0).get("day"), 5, "save/resume does not advance the same timed record twice")
	assert_equal(timed_restored._state.timed_encounter_override(1).get("day"), 5, "the remaining timed record advances once after relocation")
	assert_equal([timed_restored._state.party.character_by_id(caster.id).current_health, timed_restored._state.party.character_by_id(caster.id).inventory()[-1].charges], [7, 1], "save/resume does not repeat midnight recovery")
	assert_equal(timed_restored.snapshot().continuation, null, "the completed timed scan leaves no stale continuation")

	var rebased_random := GameSession.new()
	assert_equal(rebased_random.restore(content, camp_save).state, SessionStep.State.COMPLETED, "the post-timed random characterization starts from the same committed camp boundary")
	rebased_random._state.clock.set_total_minutes(RealmzClock.MINUTES_PER_DAY - 10)
	rebased_random._rng = ScriptedRng.new([0, 0, 0, 32767, 32767, 32767, 0])
	var rebased_wait := rebased_random.submit_intent(PlayerIntent.rest())
	assert_equal([rebased_wait.state, rebased_wait.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.ACKNOWLEDGE], "the relocation fixture first yields at its Classic textbox")
	var rebased_request := rebased_random.view().pending_interaction
	var rebased_random_wait := rebased_random.respond(InteractionResponse.from_data(rebased_request.request_id, InteractionRequest.ACKNOWLEDGE, {}))
	assert_equal([rebased_random_wait.state, rebased_random_wait.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.YES_NO], "the final random check uses the XAP-relocated cell and reaches its source surprise choice")
	assert_true(_event_position(rebased_random_wait, &"party_teleported") < _event_position(rebased_random_wait, &"timed_encounter_triggered"), "XAP relocation precedes the remaining timed record")
	assert_true(_event_position(rebased_random_wait, &"timed_encounter_triggered") < _event_position(rebased_random_wait, &"random_encounter_checked"), "the remaining timed scan precedes the final random rectangle check")
	assert_equal(rebased_random.view().party_coordinate, Vector2i(2, 0), "the pending random encounter retains the relocated coordinate")
	var declined_rebased := rebased_random.respond(InteractionResponse.from_data(rebased_random_wait.interaction.request_id, InteractionRequest.YES_NO, {"accepted": false}))
	assert_equal(declined_rebased.state, SessionStep.State.COMPLETED, "declining the rebased random encounter completes the original Rest continuation")
	assert_equal(rebased_random.snapshot().continuation, null, "the rebased timed and random scans consume their continuation exactly once")

	var ineligible_timed := GameSession.new()
	assert_equal(ineligible_timed.restore(content, camp_save).state, SessionStep.State.COMPLETED, "the ineligible timed-event characterization starts from the same camp boundary")
	ineligible_timed._state.random_encounters_enabled = false
	var ineligible_caster := ineligible_timed._state.party.character_by_id(caster.id)
	var ineligible_target := ineligible_timed._state.party.character_by_id(target.id)
	ineligible_target.current_health = ineligible_target.maximum_health
	ineligible_caster.level = 6
	ineligible_caster.maximum_health = 20
	ineligible_caster.current_health = 5
	ineligible_timed._state.set_timed_encounter_override(0, {"day": 2, "percent": 0})
	ineligible_timed._state.clock.set_total_minutes(RealmzClock.MINUTES_PER_DAY - 10)
	ineligible_timed._rng = ScriptedRng.new([0, 0])
	var ineligible_result := ineligible_timed.submit_intent(PlayerIntent.rest())
	assert_equal(ineligible_result.state, SessionStep.State.COMPLETED, "an ineligible timed event does not invent an interaction")
	assert_equal(ineligible_timed._state.timed_encounter_override(0).get("day"), 5, "a failed chance still advances the timed record before continuing the scan")
	assert_equal(ineligible_caster.current_health, 6, "midnight recovery still runs once after a scan with no eligible dispatch")
	assert_true(_event_position(ineligible_result, &"timed_encounter_checked") < _event_position(ineligible_result, &"health_recovered"), "an ineligible timed scan still precedes midnight recovery")

	var interrupted_session := GameSession.new()
	assert_equal(interrupted_session.restore(content, camp_save).state, SessionStep.State.COMPLETED, "the interrupted-Rest fixture starts from the saved camp boundary")
	interrupted_session._state.party.coordinate = Vector2i(2, 0)
	interrupted_session._state.world.mark_visited("land:0", Vector2i(2, 0))
	interrupted_session._rng = ScriptedRng.new([0, 32767, 32767, 32767, 0])
	var interrupted := interrupted_session.submit_intent(PlayerIntent.rest())
	assert_equal([interrupted.state, interrupted.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.YES_NO], "Rest can stop at the source random-encounter choice")
	assert_equal(interrupted_session.snapshot().continuation.kind, &"post-clock", "the pending choice retains its Rest-owned post-clock continuation")
	var interrupted_restored := GameSession.new()
	assert_equal(interrupted_restored.restore(content, save_round_trip(interrupted_session.snapshot())).state, SessionStep.State.COMPLETED, "an interrupted Rest restores transactionally at the choice boundary")
	var interrupted_request := interrupted_restored.view().pending_interaction
	var declined_interrupt := interrupted_restored.respond(InteractionResponse.from_data(interrupted_request.request_id, InteractionRequest.YES_NO, {"accepted": false}))
	assert_equal(declined_interrupt.state, SessionStep.State.COMPLETED, "declining the interrupt returns to camp after the committed Rest pulse")
	assert_true(interrupted_restored._state.party_camping, "declining a Rest interruption preserves camp mode")
	assert_equal(interrupted_restored.snapshot().continuation, null, "the completed interrupted Rest leaves no stale continuation")

	var battle_departure := GameSession.new()
	assert_equal(battle_departure.restore(content, camp_save).state, SessionStep.State.COMPLETED, "the interrupted-departure fixture starts from the saved camp boundary")
	battle_departure._state.party.coordinate = Vector2i(2, 0)
	battle_departure._state.world.mark_visited("land:0", Vector2i(2, 0))
	battle_departure._rng = ScriptedRng.new([0, 32767, 32767, 32767, 0])
	var departure_interrupted := battle_departure.submit_intent(PlayerIntent.move(Vector2i.DOWN))
	assert_equal([departure_interrupted.state, departure_interrupted.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.YES_NO], "camp departure can stop before movement at Castle's random surprise choice")
	battle_departure._rng = RealmzRng.new(4711)
	var accepted_departure := battle_departure.respond(InteractionResponse.from_data(departure_interrupted.interaction.request_id, InteractionRequest.YES_NO, {"accepted": true}))
	assert_equal(accepted_departure.state, SessionStep.State.COMPLETED, "accepting the camp-departure interruption enters battle")
	assert_not_null(battle_departure._state.combat, "the random battle remains session-owned after camp departure")
	if battle_departure._state.combat != null:
		assert_equal([battle_departure._battle_return_continuation.kind, battle_departure._battle_return_continuation.exploration().resume_kind], [&"post-clock", &"move"], "the battle retains the exact second-stage post-clock movement return")
		var battle_save := save_round_trip(battle_departure.snapshot())
		var battle_restored := GameSession.new()
		var battle_restore := battle_restored.restore(content, battle_save)
		assert_equal([battle_restore.state, battle_restore.error_code, battle_restore.error_message], [SessionStep.State.COMPLETED, &"", ""], "an active random battle preserves its camp-departure return across save/reload")
		if battle_restore.state != SessionStep.State.COMPLETED:
			return
		battle_restored._state.random_encounters_enabled = false
		for monster: MonsterState in battle_restored._state.combat.monsters():
			monster.current_health = 0
		var actor_id := battle_restored._state.combat.active_actor_id()
		var returned := battle_restored.submit_intent(PlayerIntent.combat_action(&"finish", actor_id))
		returned = _drain_battle_return(battle_restored, returned)
		assert_equal(returned.state, SessionStep.State.COMPLETED, "finishing the interrupted battle resumes the original movement once")
		assert_equal(battle_restored._state.combat, null, "the terminal reward path releases the interrupted random battle")
		assert_equal(battle_restored._state.party.coordinate, Vector2i(2, 1), "the requested movement commits only after battle return")
		var returned_snapshot := battle_restored.snapshot()
		assert_not_null(returned_snapshot, "the resumed movement leaves a valid committed save boundary")
		if returned_snapshot != null:
			assert_equal(returned_snapshot.continuation, null, "the resumed movement consumes the persisted battle return")

	var dungeon_departure := GameSession.new()
	assert_equal(dungeon_departure.restore(content, camp_save).state, SessionStep.State.COMPLETED, "the dungeon-departure characterization starts from a committed camp boundary")
	dungeon_departure._state.party.map_id = "dungeon:0"
	dungeon_departure._state.party.coordinate = Vector2i(2, 0)
	dungeon_departure._state.random_encounters_enabled = false
	var dungeon_departed := dungeon_departure.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal(dungeon_departed.state, SessionStep.State.COMPLETED, "dungeon movement leaves camp before committing the requested cardinal step")
	assert_false(dungeon_departure._state.party_camping, "dungeon departure clears the same session-owned camp mode")
	assert_equal(dungeon_departure._state.party.coordinate, Vector2i(3, 0), "dungeon departure resumes the requested move")
	assert_equal(_events(dungeon_departed, &"time_advanced").slice(0, 2).map(func(event: DomainEvent) -> int: return int(event.payload["minutes"])), [1, 1], "dungeon departure exposes Castle's two one-minute time clicks before movement")

	var scroll_save := save_round_trip(restored.snapshot())
	var scroll_restored := GameSession.new()
	assert_equal(scroll_restored.restore(content, scroll_save).state, SessionStep.State.COMPLETED, "the exact five-slot scroll case restores")
	active_caster = scroll_restored._state.party.character_by_id(caster.id)
	active_target = scroll_restored._state.party.character_by_id(target.id)
	scroll_restored._rng = ScriptedRng.new([0, 0])
	var requested := scroll_restored.submit_intent(PlayerIntent.use_scroll(active_caster.id, 0))
	assert_equal([requested.state, requested.interaction.kind, requested.interaction.body.to_data().get("mode")], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.CHARACTER_SELECTION, "scroll-use"], "field scroll use yields the typed character picker")
	assert_equal([active_caster.scroll_at(0).power, active_caster.spell_points, scroll_restored._rng.snapshot().draw_count], [2, starting_spell_points - 8, 0], "opening scroll targeting consumes neither the scroll, spell points, nor effect RNG")
	assert_false(scroll_restored.view().party_members[0].scrolls[0].use.enabled, "a pending target request disables duplicate scroll use in the detached view")
	var pending_save := save_round_trip(scroll_restored.snapshot())
	var pending_restored := GameSession.new()
	assert_equal(pending_restored.restore(content, pending_save).state, SessionStep.State.COMPLETED, "pending scroll targeting restores transactionally")
	pending_restored._rng = ScriptedRng.new([0, 0])
	var pending := pending_restored.view().pending_interaction
	var rejected := pending_restored.respond(InteractionResponse.from_data(pending.request_id, InteractionRequest.CHARACTER_SELECTION, {"characterIds": ["missing.character"]}))
	assert_equal(rejected.error_code, &"invalid_scroll_target", "an invented scroll target is rejected explicitly")
	assert_equal([pending_restored._state.party.character_by_id(caster.id).scroll_at(0).power, pending_restored._rng.snapshot().draw_count], [2, 0], "a rejected target preserves the scroll and RNG position")
	var used := pending_restored.respond(InteractionResponse.from_data(pending.request_id, InteractionRequest.CHARACTER_SELECTION, {"characterIds": [target.id]}))
	assert_equal(used.state, SessionStep.State.COMPLETED, "a valid scroll target commits once")
	assert_true(pending_restored._state.party.character_by_id(caster.id).scroll_at(0).is_empty(), "the scroll clears only after a valid target resolves")
	assert_equal(pending_restored._state.party.character_by_id(caster.id).spell_points, starting_spell_points - 8, "using a scroll spends no spell points")
	assert_equal(pending_restored._state.party.character_by_id(target.id).current_health, 8, "the scroll applies its stored spell and power to the selected character")
	assert_true(used.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("waitForCompletion") == true), "using a field scroll requests Castle's synchronous opening sound")

	pending_restored._state.random_encounters_enabled = false
	var departure_start := pending_restored._state.clock.total_minutes()
	var departed := pending_restored.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal(departed.state, SessionStep.State.COMPLETED, "movement while camped performs the Classic departure and then the requested move")
	assert_false(pending_restored._state.party_camping, "automatic movement departure clears camp before moving")
	assert_equal(pending_restored.view().party_coordinate, Vector2i(2, 1), "the requested move commits after camp departure")
	assert_equal(_events(departed, &"time_advanced").slice(0, 15).map(func(event: DomainEvent) -> int: return int(event.payload["minutes"])), [5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5], "outdoor movement departure exposes fifteen five-minute time clicks before terrain movement time")
	var destination_cost := content.world.map_by_id("land:0").topology.cell_at(Vector2i(2, 1)).movement_cost
	assert_equal(pending_restored._state.clock.total_minutes(), departure_start + 75 + destination_cost * 5, "ordinary terrain movement time follows the exact authored departure cost, including zero")
	assert_true(_has_event(departed, &"camp_departed_for_movement"), "automatic departure has an explicit domain trace")

	var reentered := pending_restored.submit_intent(PlayerIntent.camp())
	assert_equal(reentered.state, SessionStep.State.COMPLETED, "Camp can be entered again after automatic departure")
	var left := pending_restored.submit_intent(PlayerIntent.camp())
	assert_equal(left.state, SessionStep.State.COMPLETED, "Camp toggles back out of camp mode")
	assert_false(pending_restored._state.party_camping, "leaving camp clears the session-owned mode")
	assert_equal(_events(left, &"time_advanced").map(func(event: DomainEvent) -> int: return int(event.payload["minutes"])), [5, 5], "explicit land camp departure exposes Castle's two scaled time clicks")
	assert_equal([pending_restored.view().realmz_hour, pending_restored.view().realmz_minute], [pending_restored._state.clock.hour(), pending_restored._state.clock.minute()], "the detached clock remains exact after camp departure")


func _test_scroll_case_management(content: RealmzContent) -> void:
	var source := _character("scroll.case-source", "Cora", content); var destination := _character("scroll.case-destination", "Dain", content); var occupied := _character("scroll.case-occupied", "Eryn", content)
	var case_definition := content.item_by_id("classic.item.scroll-case"); var source_case := ItemInstance.new("scroll.case.transfer", case_definition.id, 0, true, true); var occupied_case := ItemInstance.new("scroll.case.occupied", case_definition.id, 0, true, true)
	source.set_inventory([source_case]); source.carried_load = case_definition.instance_weight(0); occupied.set_inventory([occupied_case]); occupied.carried_load = case_definition.instance_weight(0)
	var scrolls: Array[SpellScrollState] = [SpellScrollState.new("classic.spell.scroll-fixed", 1), SpellScrollState.new("classic.spell.scroll-heal", 2), SpellScrollState.new(), SpellScrollState.new("classic.spell.scroll-fixed", 4), SpellScrollState.new("classic.spell.scroll-heal", 7)]
	assert_true(source.set_scroll_case(scrolls), "the case-management fixture starts with five source-shaped slots"); var session := GameSession.new(); assert_equal(session.start(content, 719).state, SessionStep.State.COMPLETED, "scroll-case management session starts")
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(source.id, "4".repeat(64), source, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "the case owner enters party setup"); assert_equal(session.submit_intent(PlayerIntent.import_vault_character(destination.id, "5".repeat(64), destination, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "the empty recipient enters party setup"); assert_equal(session.submit_intent(PlayerIntent.import_vault_character(occupied.id, "6".repeat(64), occupied, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "the recipient with a case enters party setup"); assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "the scroll-case management fixture begins")
	var active_source := session._state.party.character_by_id(source.id); assert_false(session.view().party_members[0].scrolls[0].use.enabled, "a combat-only scroll is not presented as field-castable"); assert_true(session.view().party_members[0].scrolls[0].discard.enabled, "the detached scroll slot exposes Castle's field-invalid discard branch")
	var before_discard := [active_source.spell_points, session._state.clock.total_minutes(), session._rng.snapshot().draw_count]; var discard_request := session.submit_intent(PlayerIntent.use_scroll(source.id, 0)); assert_equal([discard_request.state, discard_request.interaction.kind, discard_request.interaction.body.to_data().get("yesLabel")], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.YES_NO, "Discard"], "using a combat-only field scroll opens the typed discard choice")
	var discard_restored := GameSession.new(); assert_equal(discard_restored.restore(content, save_round_trip(session.snapshot())).state, SessionStep.State.COMPLETED, "the pending scroll discard choice restores transactionally"); var declined := discard_restored.respond(InteractionResponse.yes_no(discard_restored.view().pending_interaction, false)); assert_equal([declined.state, discard_restored._state.party.character_by_id(source.id).scroll_at(0).spell_id], [SessionStep.State.COMPLETED, "classic.spell.scroll-fixed"], "declining discard keeps the exact scroll")
	var repeated := discard_restored.submit_intent(PlayerIntent.use_scroll(source.id, 0)); var discarded := discard_restored.respond(InteractionResponse.yes_no(repeated.interaction, true)); active_source = discard_restored._state.party.character_by_id(source.id); assert_equal([discarded.state, active_source.scroll_at(0).is_empty()], [SessionStep.State.COMPLETED, true], "accepting discard clears only the selected slot")
	assert_equal([active_source.scroll_at(1).spell_id, active_source.scroll_at(3).power, active_source.scroll_at(4).power], ["classic.spell.scroll-heal", 4, 7], "discard preserves every other fixed case slot"); assert_equal([active_source.spell_points, discard_restored._state.clock.total_minutes(), discard_restored._rng.snapshot().draw_count], before_discard, "discard consumes no spell points, time, or RNG"); assert_true(active_source.set_scroll_case(scrolls), "the transfer fixture restores the exact five-slot source pattern")
	var active_destination := discard_restored._state.party.character_by_id(destination.id); var active_occupied := discard_restored._state.party.character_by_id(occupied.id); var item_actions := discard_restored.view().party_members[0].items[0].actions; var empty_target: ItemTransferTargetView = item_actions.trade_targets.filter(func(target: ItemTransferTargetView) -> bool: return target.character_id == destination.id)[0]; var occupied_target: ItemTransferTargetView = item_actions.trade_targets.filter(func(target: ItemTransferTargetView) -> bool: return target.character_id == occupied.id)[0]
	assert_true(empty_target.enabled, "an empty recipient can receive the type-13 case and its records"); assert_equal([occupied_target.enabled, occupied_target.reason], [false, "Eryn already carries a scroll case."], "a recipient with a case is disabled before it can overwrite five records"); var rejected := discard_restored.submit_intent(PlayerIntent.trade_item(source_case.id, source.id, occupied.id)); assert_equal([rejected.error_code, _scroll_data(active_source), active_occupied.inventory().size()], [&"item_cannot_trade", _scroll_data(source), 1], "a forged second-case transfer rejects without mutating either character")
	var before_transfer := [discard_restored._state.clock.total_minutes(), discard_restored._rng.snapshot().draw_count]; var traded := discard_restored.submit_intent(PlayerIntent.trade_item(source_case.id, source.id, destination.id)); assert_equal([traded.state, active_source.inventory().size(), active_destination.inventory().size(), active_destination.inventory()[0].equipped], [SessionStep.State.COMPLETED, 0, 1, false], "case transfer moves one exact item and unequips it on the recipient")
	assert_equal([_scroll_data(active_source), _scroll_data(active_destination)], [[{"spellId": "", "power": 0}, {"spellId": "", "power": 0}, {"spellId": "", "power": 0}, {"spellId": "", "power": 0}, {"spellId": "", "power": 0}], _scroll_data(source)], "case transfer clears the source and preserves all five ordered records"); assert_equal([active_source.carried_load, active_destination.carried_load, discard_restored._state.clock.total_minutes(), discard_restored._rng.snapshot().draw_count], [0, case_definition.instance_weight(0), before_transfer[0], before_transfer[1]], "case transfer commits exact load without time or RNG")
	var transfer_restored := GameSession.new(); assert_equal(transfer_restored.restore(content, save_round_trip(discard_restored.snapshot())).state, SessionStep.State.COMPLETED, "the transferred case and all five records restore transactionally"); assert_equal(_scroll_data(transfer_restored._state.party.character_by_id(destination.id)), _scroll_data(source), "save/restore retains the recipient's exact scroll order and powers")


func _scroll_data(character: CharacterState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []; for scroll: SpellScrollState in character.scroll_case(): result.append(scroll.to_data())
	return result


func _scroll_content(source: RealmzContent) -> RealmzContent:
	var empty_ints: Array[int] = []; var empty_ranges: Array[Vector2i] = []; var age_changes: Array[PackedInt32Array] = []
	for _index: int in 5: age_changes.append(PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	var race := RaceDefinition.new("classic.race.scroll", 1, "Human", empty_ints, empty_ints, empty_ints, empty_ints, empty_ints, empty_ranges, age_changes, 0, false, 10, 0, 0, 0, 1, 1, false, 0, 0, 0)
	var caste := CasteDefinition.new("classic.caste.scroll", 1, "Sorcerer", empty_ints, empty_ints, empty_ints, empty_ints, Vector2i(8, 8), Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO)
	var scroll_case := ItemDefinition.new("classic.item.scroll-case", 800, "Scroll Case"); scroll_case.item_type = 13; scroll_case.weight = 2
	var parchment := ItemDefinition.new("classic.item.parchment", 806, "Parchment"); parchment.weight = 0; parchment.initial_charges = 3; parchment.weight_per_charge = 1; parchment.drop_on_empty = true
	var rations := ItemDefinition.new("classic.item.iron-rations", 877, "Iron Rations"); rations.icon_id = 20; rations.weight = 1; rations.initial_charges = 4; rations.weight_per_charge = 1; rations.drop_on_empty = true
	var healing := SpellDefinition.new("classic.spell.scroll-heal", 1101, "Mending"); healing.cost = 2; healing.damage_min = 3; healing.damage_max = 3; healing.special = 57; healing.cannot = 4; healing.target_type = 1; healing.sound_start = 49; healing.in_camp = true
	var fixed := SpellDefinition.new("classic.spell.scroll-fixed", 1102, "Fixed Ward"); fixed.cost = -5; fixed.duration_min = 2; fixed.duration_max = 2; fixed.special = 8; fixed.target_type = 1; fixed.in_combat = true
	var races: Array[RaceDefinition] = [race]
	var castes: Array[CasteDefinition] = [caste]
	var items: Array[ItemDefinition] = []
	for source_item: ItemDefinition in source.item_definitions():
		if source_item.classic_id not in [800, 806, 877]:
			items.append(source_item)
	items.append_array([scroll_case, parchment, rations])
	var spells: Array[SpellDefinition] = [healing, fixed]
	var monsters: Array[MonsterDefinition] = [source.monster_by_classic_id(1)]
	var battles: Array[BattleDefinition] = [source.battle_by_classic_id(0), source.battle_by_classic_id(1)]
	var timed_program := ScenarioProgramDefinition.new("xap:7", &"extra-action-point", "xap.fixture.timed-midnight", [ClassicActionDefinition.new(0, 1, 1, 777, false, []), ClassicActionDefinition.new(1, 45, 45, 0, false, [-1, 2, 0, 0, 0])])
	var relocated_program := ScenarioProgramDefinition.new("xap:8", &"extra-action-point", "xap.fixture.timed-relocated", [ClassicActionDefinition.new(0, 1, 1, -778, false, [])])
	var timed_encounter := TimedEncounterDefinition.new(0, 2, 3, 100, 7, timed_program.id, -1, -1, -1, -1, 0, -1, TimedEncounterDefinition.LocationKind.ANY)
	var relocated_encounter := TimedEncounterDefinition.new(1, 2, 3, 100, 8, relocated_program.id, 0, -1, 2, 0, 0, -1, TimedEncounterDefinition.LocationKind.LAND)
	var messages: Array[MessageDefinition] = [MessageDefinition.new(777, "Midnight finds the party."), MessageDefinition.new(778, "The relocated watch answers.")]
	var triggers: Array[TriggerDefinition] = []
	var timed_encounters: Array[TimedEncounterDefinition] = [timed_encounter, relocated_encounter]
	return RealmzContent.new("scroll-camp-workflow", source.package_hash, "scroll-camp-content", source.rules_version, source.start_map_id, source.start_coordinate, source.world, ScenarioDefinition.new([timed_program, relocated_program], []), messages, triggers, [], races, castes, items, spells, monsters, battles, [], [], [], [], timed_encounters)


func _character(character_id: String, display_name: String, content: RealmzContent) -> CharacterState:
	var result := CharacterState.new(character_id, display_name, 12, 12)
	result.race_id = content.race_definitions()[0].id
	result.caste_id = content.caste_definitions()[0].id
	result.spellcaster_type = 1
	result.spell_points = 50
	result.maximum_spell_points = 50
	result.maximum_load = 100
	result.set_known_spells(["classic.spell.scroll-heal", "classic.spell.scroll-fixed"])
	return result


func _has_event(step: SessionStep, kind: StringName) -> bool:
	return step.events.any(func(event: DomainEvent) -> bool: return event.kind == kind)


func _events(step: SessionStep, kind: StringName) -> Array[DomainEvent]:
	var result: Array[DomainEvent] = []
	for event: DomainEvent in step.events:
		if event.kind == kind:
			result.append(event)
	return result


func _event_position(step: SessionStep, kind: StringName) -> int:
	for index: int in step.events.size():
		if step.events[index].kind == kind:
			return index
	return -1


func _drain_battle_return(session: GameSession, step: SessionStep) -> SessionStep:
	var current := step
	var boundary_count := 0
	while current.state == SessionStep.State.WAITING_FOR_INTERACTION and boundary_count < 256:
		var request := current.interaction
		var payload: Dictionary
		if request.kind == InteractionRequest.ALLY_SELECTION:
			payload = {"selectedIds": []}
		elif request.kind == InteractionRequest.LEVEL_UP and request.body.to_data().get("mode") == "result":
			payload = {"action": "continue", "characterId": request.body.to_data()["characterId"]}
		elif request.kind == InteractionRequest.LEVEL_UP:
			payload = {"action": "confirm-spells", "characterId": request.body.to_data()["characterId"], "spellIds": []}
		elif request.kind == InteractionRequest.TREASURE_DISTRIBUTION and request.body.to_data().get("mode") == "completion-confirmation":
			payload = {"action": "confirm-completion"}
		elif request.kind == InteractionRequest.TREASURE_DISTRIBUTION and not request.body.to_data().get("items", []).is_empty():
			payload = {"action": "discard", "instanceId": request.body.to_data()["items"][0]["instanceId"]}
		else:
			payload = {"action": "done"}
		current = session.respond(InteractionResponse.from_data(request.request_id, request.kind, payload))
		boundary_count += 1
	assert_true(boundary_count < 256, "the interrupted battle return remains bounded")
	return current
