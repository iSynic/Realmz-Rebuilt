extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const CORRECTION_PATH: String = "res://tests/fixtures/oracle/field-spell-target-cancel-cost-correction.json"
const FAST_SPELL_CORRECTION_PATH: String = "res://tests/fixtures/oracle/fast-spell-activation-correction.json"


func run() -> void:
	var correction: Variant = JSON.parse_string(FileAccess.get_file_as_string(CORRECTION_PATH))
	assert_true(correction is Dictionary, "the target-cancel fidelity decision is parseable")
	if correction is Dictionary:
		assert_true(correction["castleSourceObservation"]["spellPointsDeductedBeforeTargetSelection"], "the fixture records Castle's premature spell-point deduction")
		assert_true(correction["realmz2ChosenResult"]["invalidOrCancelledSelectionPreservesSpellPoints"], "the fixture records the selected transactional correction")
	var fast_spell_correction: Variant = JSON.parse_string(FileAccess.get_file_as_string(FAST_SPELL_CORRECTION_PATH))
	assert_true(fast_spell_correction is Dictionary, "the Fast Spell activation fidelity decision is parseable")
	if fast_spell_correction is Dictionary:
		assert_equal(fast_spell_correction.get("decisionId"), "FD-SPELL-003", "the Fast Spell correction retains its stable fidelity identity")
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "field-spell workflow starts from the validated package fixture")
	if not loaded.is_ok():
		return
	var content := _field_content(loaded.content)
	var session := GameSession.new()
	assert_equal(session.start(content, 91).state, SessionStep.State.COMPLETED, "field-spell session starts")
	var caster := _character("field.caster", "Aster", content)
	var target := _character("field.target", "Bryn", content)
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(caster.id, "1".repeat(64), caster.to_data(), "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "caster enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(target.id, "2".repeat(64), target.to_data(), "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "target enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "field-spell fixture begins")
	var active_caster := session._state.party.character_by_id(caster.id)
	var active_target := session._state.party.character_by_id(target.id)
	active_caster.spell_points = 50
	active_caster.maximum_spell_points = 50
	active_caster.set_known_spells(["classic.spell.field-bolt", "classic.spell.field-fixed", "classic.spell.field-light", "classic.spell.field-rest"])
	active_target.current_health = 20
	active_target.maximum_health = 20
	active_target.magic_resistance = 120
	active_target.set_save_value_raw(1, -99)
	var bound := session.submit_intent(PlayerIntent.set_fast_spell(active_caster.id, 0, "classic.spell.field-bolt", 2))
	assert_equal(bound.state, SessionStep.State.COMPLETED, "Fast Spell binding is a typed committed character mutation")
	assert_true(bound.events.any(func(event: DomainEvent) -> bool: return event.kind == &"fast_spell_changed" and event.payload.get("slot") == 0), "binding publishes the exact detached slot change")
	assert_equal(session.view().party_members[0].fast_spells[0].spell_name, "Field Bolt", "the detached character view resolves a bound spell without exposing mutable state")
	var bound_save := SaveEnvelope.from_data(session.snapshot().to_data())
	var bound_restored := GameSession.new()
	assert_equal(bound_restored.restore(content, bound_save).state, SessionStep.State.COMPLETED, "Fast Spell state restores through the unchanged v3 save envelope")
	assert_equal(bound_restored.view().party_members[0].fast_spells[0].power, 2, "restoration retains the exact Fast Spell power")
	var invalid_binding := session.submit_intent(PlayerIntent.set_fast_spell(active_caster.id, 1, "classic.spell.missing", 1))
	assert_equal(invalid_binding.error_code, &"invalid_fast_spell", "Fast Spell binding rejects package-unknown spell identities")
	assert_true(active_caster.fast_spell_at(1).is_empty(), "a rejected binding leaves the selected slot mutation-free")
	var fast_cast := PlayerIntent.cast_spell(active_caster.fast_spell_at(0).spell_id, active_caster.id, active_target.id, active_caster.fast_spell_at(0).power)
	session._rng = ScriptedRng.new([0, 0, 32_767])
	var fast_result := session.submit_intent(fast_cast)
	assert_equal(fast_result.state, SessionStep.State.COMPLETED, "Fast Spell activation uses the ordinary typed field-cast intent")
	assert_equal([active_caster.spell_points, active_target.current_health], [46, 16], "Fast Spell activation pays and resolves exactly like the ordinary spell contract")
	active_caster.spell_points = 2
	active_target.current_health = 20
	session._rng = ScriptedRng.new([0, 0, 32_767])
	var exact_cost_result := session.submit_intent(PlayerIntent.cast_spell("classic.spell.field-bolt", active_caster.id, active_target.id, 1))
	assert_equal(exact_cost_result.state, SessionStep.State.COMPLETED, "FD-SPELL-003 permits a Fast Spell that spends the caster's exact remaining points")
	assert_equal(active_caster.spell_points, 0, "the exact-cost Fast Spell commits through the ordinary cast transaction")
	active_target.current_health = 20
	active_caster.spell_points = 50

	var spell_view: SpellView = session.view().party_members[0].spells[0]
	assert_true(spell_view.field_cast.enabled, "detached spell facts expose a source-backed field cast")
	assert_equal(spell_view.power_levels, [1, 2, 3, 4, 5, 6, 7], "positive-cost field spells expose every affordable Classic power")
	var fixed_view: SpellView = session.view().party_members[0].spells[1]
	assert_equal(fixed_view.power_levels, [1], "a negative Classic spell cost fixes power at one")

	session._rng = ScriptedRng.new([0, 0, 32_767])
	var requested := session.submit_intent(PlayerIntent.cast_spell("classic.spell.field-bolt", active_caster.id, "", 1))
	assert_equal([requested.state, requested.interaction.kind, requested.interaction.payload.get("count")], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.CHARACTER_SELECTION, 1], "field casting yields the typed Castle target picker")
	assert_equal(active_caster.spell_points, 50, "opening target selection does not reproduce Castle's premature spell-point deduction")
	assert_equal(session._rng.snapshot().draw_count, 0, "opening target selection consumes no effect randomness")
	var restored := GameSession.new()
	assert_equal(restored.restore(content, SaveEnvelope.from_data(session.snapshot().to_data())).state, SessionStep.State.COMPLETED, "field target selection restores transactionally")
	restored._rng = ScriptedRng.new([0, 0, 32_767])
	var pending := restored.view().pending_interaction
	var rejected := restored.respond(InteractionResponse.new(pending.request_id, InteractionRequest.CHARACTER_SELECTION, {"characterIds": ["missing.character"]}))
	assert_equal(rejected.error_code, &"invalid_field_spell_target", "an invented field target is rejected explicitly")
	assert_equal([restored._state.party.character_by_id(active_caster.id).spell_points, restored._rng.snapshot().draw_count], [50, 0], "a rejected target spends neither spell points nor RNG")
	var completed := restored.respond(InteractionResponse.new(pending.request_id, InteractionRequest.CHARACTER_SELECTION, {"characterIds": [active_target.id]}))
	assert_equal(completed.state, SessionStep.State.COMPLETED, "a valid field target commits the spell")
	assert_equal(restored._state.party.character_by_id(active_caster.id).spell_points, 48, "field casting spends the absolute Classic cost once")
	assert_equal(restored._state.party.character_by_id(active_target.id).current_health, 16, "field damage applies after the selected character fails its indexed save")
	assert_equal(restored._rng.snapshot().draw_count, 3, "field casting rolls shared duration, damage, and save without a magic-resistance roll")
	assert_false(restored.rng_trace().any(func(entry: Dictionary) -> bool: return String(entry.get("tag", "")).contains("resistance")), "Castle field casting ignores magic resistance")
	assert_true(completed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("waitForCompletion") == true), "field casting requests Castle's synchronous opening spell sound")

	restored._rng = ScriptedRng.new([0, 0])
	var light := restored.submit_intent(PlayerIntent.cast_spell("classic.spell.field-light", active_caster.id, "", 1))
	assert_equal(light.state, SessionStep.State.COMPLETED, "party-state field magic commits without a character picker")
	assert_equal(restored._state.party.conditions.value(0), 29, "Classic light stores thirty turns per power minus one")
	assert_equal(restored.view().party_summary.light_remaining, 29, "the detached party view exposes the authoritative light condition")

	restored._state.party.fatigue = 90
	restored._rng = ScriptedRng.new([0, 0])
	var rested := restored.submit_intent(PlayerIntent.cast_spell("classic.spell.field-rest", active_caster.id, "", 1))
	assert_equal(rested.state, SessionStep.State.COMPLETED, "Classic fatigue magic commits as a party-state field spell")
	assert_equal(restored._state.party.fatigue, 4, "Castle's updatefat clamp makes special 68 produce fatigue four")


func _field_content(source: RealmzContent) -> RealmzContent:
	var empty_ints: Array[int] = []
	var empty_ranges: Array[Vector2i] = []
	var age_changes: Array[PackedInt32Array] = []
	for _index: int in 5:
		age_changes.append(PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	var race := RaceDefinition.new("classic.race.field", 1, "Human", empty_ints, empty_ints, empty_ints, empty_ints, empty_ints, empty_ranges, age_changes, 0, false, 10, 0, 0, 0, 1, 1, false, 0, 0, 0)
	var caste := CasteDefinition.new("classic.caste.field", 1, "Sorcerer", empty_ints, empty_ints, empty_ints, empty_ints, Vector2i(8, 8), Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO)
	var bolt := SpellDefinition.new("classic.spell.field-bolt", 1101, "Field Bolt")
	bolt.cost = 2
	bolt.damage_min = 4
	bolt.damage_max = 4
	bolt.duration_min = 0
	bolt.duration_max = 0
	bolt.damage_type = 1
	bolt.target_type = 1
	bolt.sound_start = 2
	bolt.in_camp = true
	var fixed := SpellDefinition.new("classic.spell.field-fixed", 1102, "Fixed Ward")
	fixed.cost = -5
	fixed.duration_min = 2
	fixed.duration_max = 2
	fixed.special = 8
	fixed.target_type = 1
	fixed.in_camp = true
	var light := SpellDefinition.new("classic.spell.field-light", 1103, "Shine")
	light.cost = 3
	light.special = 50
	light.target_type = 7
	light.in_camp = true
	var rest := SpellDefinition.new("classic.spell.field-rest", 1104, "Sleepwalk")
	rest.cost = 3
	rest.special = 68
	rest.target_type = 11
	rest.in_camp = true
	var races: Array[RaceDefinition] = [race]
	var castes: Array[CasteDefinition] = [caste]
	var items: Array[ItemDefinition] = []
	var spells: Array[SpellDefinition] = [bolt, fixed, light, rest]
	return RealmzContent.new("field-spell-workflow", source.package_hash, "field-spell-content", source.rules_version, source.start_map_id, source.start_coordinate, source.world, ScenarioDefinition.new([], []), [], [], [], races, castes, items, spells)


func _character(character_id: String, display_name: String, content: RealmzContent) -> CharacterState:
	var result := CharacterState.new(character_id, display_name, 20, 20)
	result.race_id = content.race_definitions()[0].id
	result.caste_id = content.caste_definitions()[0].id
	result.maximum_load = 100
	return result
