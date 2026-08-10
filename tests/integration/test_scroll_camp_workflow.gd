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
	assert_false(session.view().availability(&"move").enabled, "movement does not silently leave camp before the source departure continuation exists")
	assert_equal(session.submit_intent(PlayerIntent.move(Vector2i.RIGHT)).error_code, &"movement_while_camped", "direct movement while camped fails explicitly rather than preserving an impossible camp/movement state")
	assert_equal(session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH)).error_code, &"search_while_camped", "the ordinary Search command is replaced by scroll scribing in camp")

	var camp_save := SaveEnvelope.from_data(session.snapshot().to_data())
	assert_not_null(camp_save, "camp mode is a committed save boundary")
	var restored := GameSession.new()
	assert_equal(restored.restore(content, camp_save).state, SessionStep.State.COMPLETED, "camp mode restores transactionally")
	active_caster = restored._state.party.character_by_id(caster.id)
	active_target = restored._state.party.character_by_id(target.id)
	var camp_spell: SpellView = restored.view().party_members[0].spells[0]
	assert_equal(camp_spell.scroll_power_levels, [1, 2, 3, 4, 5, 6, 7], "camp spell view exposes every affordable scroll power")
	var starting_spell_points := active_caster.spell_points
	var starting_load := active_caster.carried_load
	var created := restored.submit_intent(PlayerIntent.make_scroll("classic.spell.scroll-heal", active_caster.id, 2))
	assert_equal(created.state, SessionStep.State.COMPLETED, "making a scroll commits through the typed spell intent")
	assert_equal(active_caster.spell_points, starting_spell_points - 8, "scroll scribing spends twice the normal power-scaled spell cost")
	assert_equal(active_caster.inventory()[1].charges, 2, "scroll scribing consumes exactly one parchment charge")
	assert_equal(active_caster.carried_load, starting_load - 1, "consumed parchment removes its per-charge load")
	assert_equal([active_caster.scroll_at(0).spell_id, active_caster.scroll_at(0).power], ["classic.spell.scroll-heal", 2], "scroll scribing fills the first empty fixed slot")
	assert_equal(restored._rng.snapshot().draw_count, 0, "scroll scribing consumes no effect RNG")
	assert_true(created.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("waitForCompletion") == false), "scroll scribing requests Castle's asynchronous completion sound")
	assert_equal(restored.submit_intent(PlayerIntent.make_scroll("classic.spell.scroll-fixed", active_caster.id, 2)).error_code, &"scroll_scribing_unavailable", "negative-cost Classic spells cannot be scribed above fixed power one")

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

	var left := pending_restored.submit_intent(PlayerIntent.camp())
	assert_equal(left.state, SessionStep.State.COMPLETED, "Camp toggles back out of camp mode")
	assert_false(pending_restored._state.party_camping, "leaving camp clears the session-owned mode")
	assert_equal(pending_restored._state.clock.total_minutes(), 35, "explicit land camp departure adds Castle's two scaled time clicks")
	assert_equal([pending_restored.view().realmz_hour, pending_restored.view().realmz_minute], [0, 35], "the detached clock remains exact after camp departure")


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
	var items: Array[ItemDefinition] = [scroll_case, parchment]
	var spells: Array[SpellDefinition] = [healing, fixed]
	return RealmzContent.new("scroll-camp-workflow", source.package_hash, "scroll-camp-content", source.rules_version, source.start_map_id, source.start_coordinate, source.world, ScenarioDefinition.new([], []), [], [], [], races, castes, items, spells)


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
