extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const CORRECTION_PATH: String = "res://tests/fixtures/oracle/scroll-target-cancel-consumption-correction.json"


func run() -> void:
	var correction: Variant = JSON.parse_string(FileAccess.get_file_as_string(CORRECTION_PATH))
	assert_true(correction is Dictionary, "the scroll target-cancel fidelity decision is parseable")
	if correction is Dictionary:
		assert_true(correction["castleSourceObservation"]["validScrollClearedBeforeTargetSelection"], "the fixture records Castle's premature scroll consumption")
		assert_true(correction["realmz2ChosenResult"]["invalidOrCancelledSelectionPreservesScroll"], "the fixture records the selected transactional scroll correction")
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "scroll/camp workflow starts from the validated package fixture")
	if not loaded.is_ok():
		return
	var content := _scroll_content(loaded.content)
	var session := GameSession.new()
	assert_equal(session.start(content, 117).state, SessionStep.State.COMPLETED, "scroll/camp session starts")
	var caster := _character("scroll.caster", "Cora", content)
	var target := _character("scroll.target", "Dain", content)
	var scroll_case := ItemInstance.new("scroll.case.instance", "classic.item.scroll-case", 0, true, true)
	var parchment := ItemInstance.new("scroll.parchment.instance", "classic.item.parchment", 3, false, true)
	caster.set_inventory([scroll_case, parchment])
	caster.carried_load = content.item_by_id(scroll_case.definition_id).instance_weight(0) + content.item_by_id(parchment.definition_id).instance_weight(3)
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(caster.id, "1".repeat(64), caster.to_data(), "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "scroll user enters party setup with an equipped case and parchment")
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(target.id, "2".repeat(64), target.to_data(), "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "scroll target enters party setup")
	var invalid := _character("scroll.invalid", "Invalid", content)
	invalid.write_scroll(0, "classic.spell.missing", 1)
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(invalid.id, "3".repeat(64), invalid.to_data(), "fixture", content.package_hash)).error_code, &"vault_character_ineligible", "vault import rejects an unresolved scroll spell before it can poison later saves")
	assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "scroll/camp fixture begins")
	var active_caster := session._state.party.character_by_id(caster.id)
	var active_target := session._state.party.character_by_id(target.id)
	active_target.current_health = 5
	active_target.maximum_health = 20
	var outside_view: SpellView = session.view().party_members[0].spells[0]
	assert_false(outside_view.make_scroll.enabled, "scroll scribing is unavailable before entering camp")
	assert_equal(session.submit_intent(PlayerIntent.make_scroll("classic.spell.scroll-heal", active_caster.id, 2)).error_code, &"scroll_scribing_unavailable", "a forged out-of-camp scribing intent is rejected without mutation")

	var entered := session.submit_intent(PlayerIntent.camp())
	assert_equal(entered.state, SessionStep.State.COMPLETED, "Camp enters source-owned camp mode instead of performing an invented eight-hour rest")
	assert_true(session._state.party_camping, "camp mode is session-owned")
	assert_equal(session._state.clock.total_minutes(), 25, "entering land camp advances Castle's five scaled time clicks")
	assert_equal([session.view().realmz_hour, session.view().realmz_minute], [0, 25], "the detached view exposes the sub-hour camp cost to presentation")
	assert_equal(active_caster.current_health, 12, "entering camp does not fabricate full healing")
	assert_true(session.view().availability(&"move").enabled, "movement remains available because the session now owns Classic camp departure ordering")
	assert_true(session.view().availability(&"rest").enabled, "Rest becomes available only after entering camp")
	assert_equal(session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH)).error_code, &"search_while_camped", "the ordinary Search command is replaced by scroll scribing in camp")

	var camp_save := SaveEnvelope.from_data(session.snapshot().to_data())
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
	rest_session._state.clock.set_total_minutes(50)
	var rested := rest_session.submit_intent(PlayerIntent.rest())
	assert_equal(rested.state, SessionStep.State.COMPLETED, "one typed Rest intent commits one held-control pulse")
	assert_equal(rest_session._state.clock.total_minutes(), 75, "one outdoor Rest pulse advances five five-minute time clicks")
	assert_equal(rest_session._state.party.fatigue, 79, "Rest removes two fatigue before the crossed hour adds one")
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
	var rest_save := SaveEnvelope.from_data(rest_session.snapshot().to_data())
	var rest_restored := GameSession.new()
	assert_equal(rest_restored.restore(content, rest_save).state, SessionStep.State.COMPLETED, "Rest recovery and its exact ration charge restore transactionally")
	assert_equal(rest_restored._state.party.character_by_id(caster.id).inventory()[-1].charges, 1, "save/reload does not replay the recovery draw or consume another ration")

	var interrupted_session := GameSession.new()
	assert_equal(interrupted_session.restore(content, camp_save).state, SessionStep.State.COMPLETED, "the interrupted-Rest fixture starts from the saved camp boundary")
	interrupted_session._state.party.coordinate = Vector2i(2, 0)
	interrupted_session._state.world.mark_visited("land:0", Vector2i(2, 0))
	interrupted_session._rng = ScriptedRng.new([0, 32767, 32767, 32767, 0])
	var interrupted := interrupted_session.submit_intent(PlayerIntent.rest())
	assert_equal([interrupted.state, interrupted.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.YES_NO], "Rest can stop at the source random-encounter choice")
	assert_equal(interrupted_session.snapshot().session_continuation.get("kind"), "post-clock", "the pending choice retains its Rest-owned post-clock continuation")
	var interrupted_restored := GameSession.new()
	assert_equal(interrupted_restored.restore(content, SaveEnvelope.from_data(interrupted_session.snapshot().to_data())).state, SessionStep.State.COMPLETED, "an interrupted Rest restores transactionally at the choice boundary")
	var interrupted_request := interrupted_restored.view().pending_interaction
	var declined_interrupt := interrupted_restored.respond(InteractionResponse.new(interrupted_request.request_id, InteractionRequest.YES_NO, {"accepted": false}))
	assert_equal(declined_interrupt.state, SessionStep.State.COMPLETED, "declining the interrupt returns to camp after the committed Rest pulse")
	assert_true(interrupted_restored._state.party_camping, "declining a Rest interruption preserves camp mode")
	assert_equal(interrupted_restored.snapshot().session_continuation, {}, "the completed interrupted Rest leaves no stale continuation")

	var battle_departure := GameSession.new()
	assert_equal(battle_departure.restore(content, camp_save).state, SessionStep.State.COMPLETED, "the interrupted-departure fixture starts from the saved camp boundary")
	battle_departure._state.party.coordinate = Vector2i(2, 0)
	battle_departure._state.world.mark_visited("land:0", Vector2i(2, 0))
	battle_departure._rng = ScriptedRng.new([0, 32767, 32767, 32767, 0])
	var departure_interrupted := battle_departure.submit_intent(PlayerIntent.move(Vector2i.DOWN))
	assert_equal([departure_interrupted.state, departure_interrupted.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.YES_NO], "camp departure can stop before movement at Castle's random surprise choice")
	battle_departure._rng = RealmzRng.new(4711)
	var accepted_departure := battle_departure.respond(InteractionResponse.new(departure_interrupted.interaction.request_id, InteractionRequest.YES_NO, {"accepted": true}))
	assert_equal(accepted_departure.state, SessionStep.State.COMPLETED, "accepting the camp-departure interruption enters battle")
	assert_not_null(battle_departure._state.combat, "the random battle remains session-owned after camp departure")
	if battle_departure._state.combat != null:
		assert_equal([battle_departure._state.combat.return_continuation.get("kind"), battle_departure._state.combat.return_continuation.get("resumeKind")], ["post-clock", "move"], "the battle retains the exact post-clock movement return")
		var battle_save := SaveEnvelope.from_data(battle_departure.snapshot().to_data())
		var battle_state_round_trip := GameState.from_data(battle_save.game_state.to_data())
		assert_not_null(battle_state_round_trip, "the active random battle state remains structurally valid with its return continuation")
		if battle_state_round_trip != null:
			assert_true(GameSession._valid_post_time_continuation(content, battle_state_round_trip, battle_state_round_trip.combat.return_continuation, null, null), "the restored battle return matches the current topology and party location")
		var battle_restored := GameSession.new()
		var battle_restore := battle_restored.restore(content, battle_save)
		assert_equal([battle_restore.state, battle_restore.error_code, battle_restore.error_message], [SessionStep.State.COMPLETED, &"", ""], "an active random battle preserves its camp-departure return across save/reload")
		if battle_restore.state != SessionStep.State.COMPLETED:
			return
		battle_restored._state.random_encounters_enabled = false
		for monster: MonsterState in battle_restored._state.combat.monsters():
			monster.current_health = 0
		battle_restored._state.combat.completed = true
		battle_restored._state.combat.outcome = &"victory"
		var returned := battle_restored._finish_direct_battle([])
		returned = _drain_battle_return(battle_restored, returned)
		assert_equal(returned.state, SessionStep.State.COMPLETED, "finishing the interrupted battle resumes the original movement once")
		assert_equal(battle_restored._state.combat, null, "the terminal reward path releases the interrupted random battle")
		assert_equal(battle_restored._state.party.coordinate, Vector2i(2, 1), "the requested movement commits only after battle return")
		var returned_snapshot := battle_restored.snapshot()
		assert_not_null(returned_snapshot, "the resumed movement leaves a valid committed save boundary")
		if returned_snapshot != null:
			assert_equal(returned_snapshot.session_continuation, {}, "the resumed movement consumes the persisted battle return")

	var dungeon_departure := GameSession.new()
	assert_equal(dungeon_departure.restore(content, camp_save).state, SessionStep.State.COMPLETED, "the dungeon-departure characterization starts from a committed camp boundary")
	dungeon_departure._state.party.map_id = "dungeon:0"
	dungeon_departure._state.party.coordinate = Vector2i(2, 0)
	dungeon_departure._state.random_encounters_enabled = false
	var dungeon_departed := dungeon_departure.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal(dungeon_departed.state, SessionStep.State.COMPLETED, "dungeon movement leaves camp before committing the requested cardinal step")
	assert_false(dungeon_departure._state.party_camping, "dungeon departure clears the same session-owned camp mode")
	assert_equal(dungeon_departure._state.party.coordinate, Vector2i(3, 0), "dungeon departure resumes the requested move")
	assert_equal(_events(dungeon_departed, &"time_advanced")[0].payload["minutes"], 2, "dungeon departure advances Castle's two one-minute time clicks before movement")

	var scroll_save := SaveEnvelope.from_data(restored.snapshot().to_data())
	var scroll_restored := GameSession.new()
	assert_equal(scroll_restored.restore(content, scroll_save).state, SessionStep.State.COMPLETED, "the exact five-slot scroll case restores")
	active_caster = scroll_restored._state.party.character_by_id(caster.id)
	active_target = scroll_restored._state.party.character_by_id(target.id)
	scroll_restored._rng = ScriptedRng.new([0, 0])
	var requested := scroll_restored.submit_intent(PlayerIntent.use_scroll(active_caster.id, 0))
	assert_equal([requested.state, requested.interaction.kind, requested.interaction.payload.get("mode")], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.CHARACTER_SELECTION, "scroll-use"], "field scroll use yields the typed character picker")
	assert_equal([active_caster.scroll_at(0).power, active_caster.spell_points, scroll_restored._rng.snapshot().draw_count], [2, starting_spell_points - 8, 0], "opening scroll targeting consumes neither the scroll, spell points, nor effect RNG")
	assert_false(scroll_restored.view().party_members[0].scrolls[0].use.enabled, "a pending target request disables duplicate scroll use in the detached view")
	var pending_save := SaveEnvelope.from_data(scroll_restored.snapshot().to_data())
	var pending_restored := GameSession.new()
	assert_equal(pending_restored.restore(content, pending_save).state, SessionStep.State.COMPLETED, "pending scroll targeting restores transactionally")
	pending_restored._rng = ScriptedRng.new([0, 0])
	var pending := pending_restored.view().pending_interaction
	var rejected := pending_restored.respond(InteractionResponse.new(pending.request_id, InteractionRequest.CHARACTER_SELECTION, {"characterIds": ["missing.character"]}))
	assert_equal(rejected.error_code, &"invalid_scroll_target", "an invented scroll target is rejected explicitly")
	assert_equal([pending_restored._state.party.character_by_id(caster.id).scroll_at(0).power, pending_restored._rng.snapshot().draw_count], [2, 0], "a rejected target preserves the scroll and RNG position")
	var used := pending_restored.respond(InteractionResponse.new(pending.request_id, InteractionRequest.CHARACTER_SELECTION, {"characterIds": [target.id]}))
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
	assert_equal(_events(departed, &"time_advanced")[0].payload["minutes"], 75, "outdoor movement departure advances fifteen time clicks before terrain movement time")
	assert_true(pending_restored._state.clock.total_minutes() > departure_start + 75, "ordinary terrain movement time follows the departure cost")
	assert_true(_has_event(departed, &"camp_departed_for_movement"), "automatic departure has an explicit domain trace")

	var reentered := pending_restored.submit_intent(PlayerIntent.camp())
	assert_equal(reentered.state, SessionStep.State.COMPLETED, "Camp can be entered again after automatic departure")
	var left := pending_restored.submit_intent(PlayerIntent.camp())
	assert_equal(left.state, SessionStep.State.COMPLETED, "Camp toggles back out of camp mode")
	assert_false(pending_restored._state.party_camping, "leaving camp clears the session-owned mode")
	assert_equal(_events(left, &"time_advanced")[0].payload["minutes"], 10, "explicit land camp departure adds Castle's two scaled time clicks")
	assert_equal([pending_restored.view().realmz_hour, pending_restored.view().realmz_minute], [pending_restored._state.clock.hour(), pending_restored._state.clock.minute()], "the detached clock remains exact after camp departure")


func _scroll_content(source: RealmzContent) -> RealmzContent:
	var empty_ints: Array[int] = []
	var empty_ranges: Array[Vector2i] = []
	var age_changes: Array[PackedInt32Array] = []
	for _index: int in 5:
		age_changes.append(PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	var race := RaceDefinition.new("classic.race.scroll", 1, "Human", empty_ints, empty_ints, empty_ints, empty_ints, empty_ints, empty_ranges, age_changes, 0, false, 10, 0, 0, 0, 1, 1, false, 0, 0, 0)
	var caste := CasteDefinition.new("classic.caste.scroll", 1, "Sorcerer", empty_ints, empty_ints, empty_ints, empty_ints, Vector2i(8, 8), Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO)
	var scroll_case := ItemDefinition.new("classic.item.scroll-case", 800, "Scroll Case")
	scroll_case.item_type = 13
	scroll_case.weight = 2
	var parchment := ItemDefinition.new("classic.item.parchment", 806, "Parchment")
	parchment.weight = 0
	parchment.initial_charges = 3
	parchment.weight_per_charge = 1
	parchment.drop_on_empty = true
	var rations := ItemDefinition.new("classic.item.iron-rations", 877, "Iron Rations")
	rations.weight = 1
	rations.initial_charges = 4
	rations.weight_per_charge = 1
	rations.drop_on_empty = true
	var healing := SpellDefinition.new("classic.spell.scroll-heal", 1101, "Mending")
	healing.cost = 2
	healing.damage_min = 3
	healing.damage_max = 3
	healing.special = 57
	healing.cannot = 4
	healing.target_type = 1
	healing.sound_start = 49
	healing.in_camp = true
	var fixed := SpellDefinition.new("classic.spell.scroll-fixed", 1102, "Fixed Ward")
	fixed.cost = -5
	fixed.duration_min = 2
	fixed.duration_max = 2
	fixed.special = 8
	fixed.target_type = 1
	fixed.in_camp = true
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
	return RealmzContent.new("scroll-camp-workflow", source.package_hash, "scroll-camp-content", source.rules_version, source.start_map_id, source.start_coordinate, source.world, ScenarioDefinition.new([], []), [], [], [], races, castes, items, spells, monsters, battles)


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


func _drain_battle_return(session: GameSession, step: SessionStep) -> SessionStep:
	var current := step
	var boundary_count := 0
	while current.state == SessionStep.State.WAITING_FOR_INTERACTION and boundary_count < 64:
		var request := current.interaction
		var payload: Dictionary
		if request.kind == InteractionRequest.ALLY_SELECTION:
			payload = {"selectedIds": []}
		elif request.kind == InteractionRequest.LEVEL_UP and request.payload.get("mode") == "result":
			payload = {"action": "continue", "characterId": request.payload["characterId"]}
		elif request.kind == InteractionRequest.LEVEL_UP:
			payload = {"action": "confirm-spells", "characterId": request.payload["characterId"], "spellIds": []}
		elif request.kind == InteractionRequest.TREASURE_DISTRIBUTION and request.payload.get("mode") == "completion-confirmation":
			payload = {"action": "confirm-completion"}
		elif request.kind == InteractionRequest.TREASURE_DISTRIBUTION and request.payload.get("item") is Dictionary:
			payload = {"action": "discard", "instanceId": request.payload["item"]["instanceId"]}
		else:
			payload = {"action": "done"}
		current = session.respond(InteractionResponse.new(request.request_id, request.kind, payload))
		boundary_count += 1
	assert_true(boundary_count < 64, "the interrupted battle return remains bounded")
	return current
