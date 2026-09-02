extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const CORRECTION_PATH: String = "res://tests/fixtures/oracle/field-spell-target-cancel-cost-correction.json"
const FAST_SPELL_CORRECTION_PATH: String = "res://tests/fixtures/oracle/fast-spell-activation-correction.json"


func run() -> void:
	var correction: Variant = JSON.parse_string(FileAccess.get_file_as_string(CORRECTION_PATH)); var utility_evidence: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/oracle/classic-field-encounter-utility.json")); assert_true(utility_evidence is Dictionary and utility_evidence.get("decisionId") == "FD-SPELL-004" and utility_evidence.get("applicationRecords", []).size() == 9, "the source-backed encounter-utility field contract is parseable and owns all nine application records"); var item_evidence: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/oracle/classic-field-party-items.json")); assert_true(item_evidence is Dictionary and item_evidence.get("applicationItems", []).size() == 2, "the source-backed party-state field-item contract owns both remaining application records")
	assert_true(correction is Dictionary, "the target-cancel fidelity decision is parseable")
	if correction is Dictionary:
		assert_true(correction["castleSourceObservation"]["spellPointsDeductedBeforeTargetSelection"], "the fixture records Castle's premature spell-point deduction")
		assert_true(correction["realmz2ChosenResult"]["invalidOrCancelledSelectionPreservesSpellPoints"], "the fixture records the selected transactional correction")
	var fast_spell_correction: Variant = JSON.parse_string(FileAccess.get_file_as_string(FAST_SPELL_CORRECTION_PATH))
	assert_true(fast_spell_correction is Dictionary, "the Fast Spell activation fidelity decision is parseable")
	if fast_spell_correction is Dictionary:
		assert_equal(fast_spell_correction.get("decisionId"), "FD-SPELL-003", "the Fast Spell correction retains its stable fidelity identity")
	var loaded := load_test_package(FIXTURE_PATH)
	if not loaded.is_ok():
		return
	var content := _field_content(loaded.content)
	var session := GameSession.new()
	assert_equal(session.start(content, 91).state, SessionStep.State.COMPLETED, "field-spell session starts")
	var caster := _character("field.caster", "Aster", content)
	var target := _character("field.target", "Bryn", content)
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(caster.id, "1".repeat(64), caster, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "caster enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(target.id, "2".repeat(64), target, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "target enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "field-spell fixture begins")
	var active_caster := session._state.party.character_by_id(caster.id)
	var active_target := session._state.party.character_by_id(target.id)
	active_caster.spell_points = 50; active_caster.maximum_spell_points = 50
	active_caster.set_known_spells(["classic.spell.field-bolt", "classic.spell.field-fixed", "classic.spell.field-light", "classic.spell.field-rest", "classic.spell.heal-poison", "classic.spell.remove-item", "classic.spell.1512", "classic.spell.4308", "classic.spell.1101", "classic.spell.2102", "classic.spell.3102", "classic.spell.1609", "classic.spell.2504", "classic.spell.2609", "classic.spell.2611", "classic.spell.3111", "classic.spell.3112", "classic.spell.3410", "classic.spell.3709", "classic.spell.3711", "classic.spell.2106"])
	active_target.current_health = 20
	active_target.maximum_health = 20
	active_target.magic_resistance = 120
	active_target.set_save_value_raw(1, -99)
	var bound := session.submit_intent(PlayerIntent.set_fast_spell(active_caster.id, 0, "classic.spell.field-bolt", 2))
	assert_equal(bound.state, SessionStep.State.COMPLETED, "Fast Spell binding is a typed committed character mutation")
	assert_true(bound.events.any(func(event: DomainEvent) -> bool: return event.kind == &"fast_spell_changed" and event.payload.get("slot") == 0), "binding publishes the exact detached slot change")
	assert_equal(session.view().party_members[0].fast_spells[0].spell_name, "Field Bolt", "the detached character view resolves a bound spell without exposing mutable state")
	var bound_save := save_round_trip(session.snapshot())
	var bound_restored := GameSession.new()
	assert_equal(bound_restored.restore(content, bound_save).state, SessionStep.State.COMPLETED, "Fast Spell state restores through the save v4 envelope")
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
	assert_equal([requested.state, requested.interaction.kind, requested.interaction.body.to_data().get("count")], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.CHARACTER_SELECTION, 1], "field casting yields the typed Castle target picker")
	var target_context := (requested.interaction.body as InteractionRequest.CharacterSelectionRequestBody).spell_context
	assert_equal([target_context.actor_id, target_context.spell_id, target_context.power, target_context.spell_point_cost, target_context.target_count], [active_caster.id, "classic.spell.field-bolt", 1, 2, 1], "the target request retains authoritative caster, spell, power, cost, and count display facts")
	var malformed_request := requested.interaction.to_data().duplicate(true); malformed_request["data"]["payload"]["spellContext"]["unexpected"] = true
	assert_equal(InteractionRequest.from_data(malformed_request), null, "the typed spell-target context rejects unknown saved fields")
	assert_equal(active_caster.spell_points, 50, "opening target selection does not reproduce Castle's premature spell-point deduction")
	assert_equal(session._rng.snapshot().draw_count, 0, "opening target selection consumes no effect randomness")
	var restored := GameSession.new()
	assert_equal(restored.restore(content, save_round_trip(session.snapshot())).state, SessionStep.State.COMPLETED, "field target selection restores transactionally")
	restored._rng = ScriptedRng.new([0, 0, 32_767])
	var pending := restored.view().pending_interaction
	assert_equal((pending.body as InteractionRequest.CharacterSelectionRequestBody).spell_context.to_data(), target_context.to_data(), "save restoration reconstructs the exact field-spell target display context")
	var rejected := restored.respond(InteractionResponse.from_data(pending.request_id, InteractionRequest.CHARACTER_SELECTION, {"characterIds": ["missing.character"]}))
	assert_equal(rejected.error_code, &"invalid_field_spell_target", "an invented field target is rejected explicitly")
	assert_equal([restored._state.party.character_by_id(active_caster.id).spell_points, restored._rng.snapshot().draw_count], [50, 0], "a rejected target spends neither spell points nor RNG")
	var completed := restored.respond(InteractionResponse.from_data(pending.request_id, InteractionRequest.CHARACTER_SELECTION, {"characterIds": [active_target.id]}))
	assert_equal(completed.state, SessionStep.State.COMPLETED, "a valid field target commits the spell")
	assert_equal(restored._state.party.character_by_id(active_caster.id).spell_points, 48, "field casting spends the absolute Classic cost once")
	assert_equal(restored._state.party.character_by_id(active_target.id).current_health, 16, "field damage applies after the selected character fails its indexed save")
	assert_equal(restored._rng.snapshot().draw_count, 3, "field casting rolls shared duration, damage, and save without a magic-resistance roll")
	assert_false(restored.rng_trace().any(func(entry: Dictionary) -> bool: return String(entry.get("tag", "")).contains("resistance")), "Castle field casting ignores magic resistance")
	assert_true(completed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("waitForCompletion") == true), "field casting requests Castle's synchronous opening spell sound")

	var restored_caster := restored._state.party.character_by_id(active_caster.id); var restored_target := restored._state.party.character_by_id(active_target.id); restored_caster.spell_points = 50; restored_target.conditions.set_value(ConditionRules.POISONED, 5); var cure_requested := restored.submit_intent(PlayerIntent.cast_spell("classic.spell.heal-poison", restored_caster.id, "", 1)); assert_equal([cure_requested.state, cure_requested.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.CHARACTER_SELECTION], "a field condition cure uses the same typed target boundary")
	var cure_restored := GameSession.new(); assert_equal(cure_restored.restore(content, save_round_trip(restored.snapshot())).state, SessionStep.State.COMPLETED, "pending field cure targeting restores transactionally"); var cure_pending := cure_restored.view().pending_interaction; var cured := cure_restored.respond(InteractionResponse.from_data(cure_pending.request_id, InteractionRequest.CHARACTER_SELECTION, {"characterIds": [restored_target.id]}))
	assert_equal([cured.state, cure_restored._state.party.character_by_id(restored_target.id).conditions.value(ConditionRules.POISONED), cure_restored._state.party.character_by_id(restored_caster.id).spell_points], [SessionStep.State.COMPLETED, 0, 30], "Heal Poison clears only its indexed condition and spends its stock cost after valid targeting"); assert_true(cured.events.any(func(event: DomainEvent) -> bool: return event.kind == &"field_spell_resolved" and event.payload.get("clearedCondition") == ConditionRules.POISONED), "the public field event identifies the cleared condition"); var remove_caster := cure_restored._state.party.character_by_id(restored_caster.id); var remove_target := cure_restored._state.party.character_by_id(restored_target.id); var cursed_definition := content.item_by_id("classic.item.cursed-blade"); var ordinary_definition := content.item_by_id("classic.item.ordinary-shield"); remove_caster.set_inventory([ItemInstance.new("field.cursed.caster", cursed_definition.id, 0, true, true)]); remove_target.set_inventory([ItemInstance.new("field.cursed.target", cursed_definition.id, 0, true, true), ItemInstance.new("field.ordinary.target", ordinary_definition.id, 0, true, true)]); remove_caster.conditions.set_value(ConditionRules.CURSED, -1); remove_target.conditions.set_value(ConditionRules.CURSED, 7); var remove_requested := cure_restored.submit_intent(PlayerIntent.cast_spell("classic.spell.remove-item", remove_caster.id, "", 2)); assert_equal([remove_requested.state, (remove_requested.interaction.body as InteractionRequest.CharacterSelectionRequestBody).count], [SessionStep.State.WAITING_FOR_INTERACTION, 2], "AOGM Remove Item uses power to select two exact party recipients before mutating either curse"); var remove_restored := GameSession.new(); assert_equal(remove_restored.restore(content, save_round_trip(cure_restored.snapshot())).state, SessionStep.State.COMPLETED, "Remove Item target selection restores before committing equipment changes"); var remove_pending := remove_restored.view().pending_interaction; var remove_result := remove_restored.respond(InteractionResponse.from_data(remove_pending.request_id, InteractionRequest.CHARACTER_SELECTION, {"characterIds": [remove_caster.id, remove_target.id]})); var removed_caster := remove_restored._state.party.character_by_id(remove_caster.id); var removed_target := remove_restored._state.party.character_by_id(remove_target.id); assert_equal([remove_result.state, removed_caster.spell_points, removed_caster.conditions.value(ConditionRules.CURSED), removed_target.conditions.value(ConditionRules.CURSED), removed_caster.inventory()[0].equipped, removed_target.inventory()[0].equipped, removed_target.inventory()[1].equipped], [SessionStep.State.COMPLETED, 18, 0, 0, false, false, true], "Remove Item spends once, clears each selected curse, force-unequips only cursed gear, and leaves ordinary equipment intact"); assert_equal(remove_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"field_spell_resolved").map(func(event: DomainEvent) -> Array: return event.payload.get("unequippedItemIds", [])), [["field.cursed.caster"], ["field.cursed.target"]], "Remove Item publishes source-ordered unequipped item identities for both recipients"); var removed_round_trip := GameSession.new(); assert_equal(removed_round_trip.restore(content, save_round_trip(remove_restored.snapshot())).state, SessionStep.State.COMPLETED, "committed Remove Item state restores through the public save envelope"); assert_equal([removed_round_trip._state.party.character_by_id(remove_caster.id).inventory()[0].equipped, removed_round_trip._state.party.character_by_id(remove_target.id).inventory()[0].equipped], [false, false], "Remove Item restoration retains both forced equipment removals"); cure_restored = remove_restored
	assert_equal(cure_restored.respond(InteractionResponse.from_data(cure_pending.request_id, InteractionRequest.CHARACTER_SELECTION, {"characterIds": [restored_target.id]})).state, SessionStep.State.FAILED, "the restored field cure response commits exactly once"); restored = cure_restored

	restored._rng = ScriptedRng.new([0, 0])
	var light := restored.submit_intent(PlayerIntent.cast_spell("classic.spell.field-light", active_caster.id, "", 1))
	assert_equal(light.state, SessionStep.State.COMPLETED, "party-state field magic commits without a character picker")
	assert_equal(restored._state.party.conditions.value(0), 29, "Classic light stores thirty turns per power minus one")
	assert_equal(restored.view().party_summary.light_remaining, 29, "the detached party view exposes the authoritative light condition")
	var wizard_probe := restored.view().party_coordinate + Vector2i(9, 0)
	assert_not_null(restored.view().map_view.cell_at(wizard_probe), "the Wizard's Eye probe lies inside the detached LOS projection")
	assert_false(restored.view().map_view.cell_at(wizard_probe).visible, "ordinary exploration does not reveal a cell beyond radius eight")
	var wizard_caster := restored._state.party.character_by_id(active_caster.id); wizard_caster.spell_points = 200; restored._rng = ScriptedRng.new([0, 0, 0, 0]); var wizard_eye := restored.submit_intent(PlayerIntent.cast_spell("classic.spell.1512", wizard_caster.id, "", 1))
	assert_equal([wizard_eye.state, restored._state.party.conditions.is_active(ConditionRules.PARTY_WIZARDS_EYE), restored.view().map_view.cell_at(wizard_probe).visible, restored.view().map_view.seen_coordinates().has(wizard_probe)], [SessionStep.State.COMPLETED, true, true, true], "casting Wizard's Eye immediately extends authoritative LOS and sight memory beyond the ordinary radius")

	restored._state.party.fatigue = 90
	restored._rng = ScriptedRng.new([0, 0])
	var rested := restored.submit_intent(PlayerIntent.cast_spell("classic.spell.field-rest", active_caster.id, "", 1))
	assert_equal(rested.state, SessionStep.State.COMPLETED, "Classic fatigue magic commits as a party-state field spell")
	assert_equal(restored._state.party.fatigue, 4, "Castle's updatefat clamp makes special 68 produce fatigue four")
	var heroism_caster := restored._state.party.character_by_id(active_caster.id); var heroism_before := [heroism_caster.current_health, heroism_caster.spell_points, heroism_caster.conditions.to_data()]; restored._rng = ScriptedRng.new([0, 0]); var heroism_result := restored.submit_intent(PlayerIntent.cast_spell("classic.spell.4308", heroism_caster.id, "", 1)); assert_equal([ClassicSpellCapabilityCatalog.field_character_disposition(content.spell_by_id("classic.spell.4308")), heroism_result.state, heroism_caster.current_health, heroism_caster.spell_points, heroism_caster.conditions.to_data()], [ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE, SessionStep.State.COMPLETED, heroism_before[0], heroism_before[1], heroism_before[2]], "field Heroism spends its zero cost and leaves the self target unchanged through the public intent boundary"); assert_equal(restored.rng_trace().map(func(entry: Dictionary) -> String: return String(entry.get("tag", ""))), ["field-spell.4308.duration", "field-spell.4308.damage"], "field Heroism preserves Castle's duration-before-damage draw order"); var discover_single := content.spell_by_id("classic.spell.1101"); var discover_group := content.spell_by_id("classic.spell.2102"); var discover_group_peer := content.spell_by_id("classic.spell.3102"); heroism_caster.spell_points = 10; var discover_before := [heroism_caster.current_health, heroism_caster.conditions.to_data(), restored._state.party.character_by_id(active_target.id).current_health, restored._state.party.character_by_id(active_target.id).conditions.to_data()]; restored._rng = ScriptedRng.new([0, 0, 0, 0, 0, 0]); var discover_all := restored.submit_intent(PlayerIntent.cast_spell(discover_group.id, heroism_caster.id, "", 1)); var discover_one := restored.submit_intent(PlayerIntent.cast_spell(discover_single.id, heroism_caster.id, active_target.id, 1)); var discover_saved := GameSession.new(); assert_equal(discover_saved.restore(content, save_round_trip(restored.snapshot())).state, SessionStep.State.COMPLETED, "field Discover Magic state restores through the public save envelope"); assert_equal([discover_single.special, discover_single.target_type, discover_group.special, discover_group.target_type, ClassicSpellCapabilityCatalog.field_character_disposition(discover_single), ClassicSpellCapabilityCatalog.field_character_disposition(discover_group), ClassicSpellCapabilityCatalog.field_character_disposition(discover_group_peer), discover_all.state, discover_one.state, heroism_caster.spell_points, heroism_caster.current_health, heroism_caster.conditions.to_data(), restored._state.party.character_by_id(active_target.id).current_health, restored._state.party.character_by_id(active_target.id).conditions.to_data(), discover_saved._state.party.character_by_id(heroism_caster.id).spell_points], [63, 1, 63, 4, ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE, ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE, ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE, SessionStep.State.COMPLETED, SessionStep.State.COMPLETED, 8, discover_before[0], discover_before[1], discover_before[2], discover_before[3], 8], "package Discover Magic I and both Discover Magic records preserve their target-one or whole-party field launch, spend once, leave character state unchanged, and save the committed cost"); var utility_ids := [1609, 2504, 2609, 2611, 3111, 3112, 3410, 3709, 3711]; var utility_spells := utility_ids.map(func(classic_id: int) -> SpellDefinition: return content.spell_by_id("classic.spell.%d" % classic_id)); assert_true(utility_spells.all(func(spell: SpellDefinition) -> bool: return ClassicSpellCapabilityCatalog.field_character_disposition(spell) == ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE), "all nine application encounter-utility profiles are admitted through their ordinary field launch"); heroism_caster.spell_points = 200; var utility_before := [heroism_caster.current_health, heroism_caster.conditions.to_data(), restored._state.party.character_by_id(active_target.id).current_health, restored._state.party.character_by_id(active_target.id).conditions.to_data()]; restored._rng = ScriptedRng.new([0, 0, 0, 0]); var shape := restored.submit_intent(PlayerIntent.cast_spell("classic.spell.1609", heroism_caster.id, "", 1)); var teleport := restored.submit_intent(PlayerIntent.cast_spell("classic.spell.3711", heroism_caster.id, active_target.id, 1)); var utility_saved := GameSession.new(); assert_equal(utility_saved.restore(content, save_round_trip(restored.snapshot())).state, SessionStep.State.COMPLETED, "committed encounter-utility casts restore through the public save envelope"); assert_equal([shape.state, teleport.state, heroism_caster.spell_points, heroism_caster.current_health, heroism_caster.conditions.to_data(), restored._state.party.character_by_id(active_target.id).current_health, restored._state.party.character_by_id(active_target.id).conditions.to_data(), utility_saved._state.party.character_by_id(heroism_caster.id).spell_points, shape.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 633 and not event.payload.get("waitForCompletion"))], [SessionStep.State.COMPLETED, SessionStep.State.COMPLETED, 105, utility_before[0], utility_before[1], utility_before[2], utility_before[3], 105, true], "Shape Earth preserves target-eleven party selection and completion sound while target-zero Teleport preserves one selected character; both spend fixed absolute cost without inventing a terrain effect"); assert_equal(restored.rng_trace().map(func(entry: Dictionary) -> String: return String(entry.get("tag", ""))), ["field-spell.1609.duration", "field-spell.1609.damage", "field-spell.3711.duration", "field-spell.3711.damage"], "encounter-utility field casts retain Castle's shared duration-before-damage draw order")
	var vapor_item := content.item_by_id("classic.item.609"); var refresh_item := content.item_by_id("classic.item.723"); heroism_caster.set_inventory([]); heroism_caster.carried_load = 0; var item_rules := RealmzRules.new(); var vapor_instance := item_rules.inventory.add_item(heroism_caster, vapor_item, "instance.vaporous-form", true); var refresh_instance := item_rules.inventory.add_item(heroism_caster, refresh_item, "instance.refresh-potion", true); restored._state.party.conditions.set_value(0, 0); restored._state.party.fatigue = 90; restored._rng = ScriptedRng.new([0, 0, 0, 0]); var vapor_result := restored.submit_intent(PlayerIntent.use_item(vapor_instance.id, heroism_caster.id)); var refresh_result := restored.submit_intent(PlayerIntent.use_item(refresh_instance.id, heroism_caster.id)); var item_saved := GameSession.new(); assert_equal(item_saved.restore(content, save_round_trip(restored.snapshot())).state, SessionStep.State.COMPLETED, "application party-state field items restore through the public save envelope"); assert_equal([ClassicSpellCapabilityCatalog.field_character_disposition(content.spell_by_id("classic.spell.4310")), ClassicSpellCapabilityCatalog.field_character_disposition(content.spell_by_id("classic.spell.4713")), vapor_result.state, refresh_result.state, restored._state.party.conditions.value(0), restored._state.party.fatigue, vapor_instance.charges, refresh_instance.charges, heroism_caster.spell_points, item_saved._state.party.conditions.value(0), item_saved._state.party.fatigue], [ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE, ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE, SessionStep.State.COMPLETED, SessionStep.State.COMPLETED, 1, 4, 1, 1, 105, 1, 4], "Vaporous Form and Refresh Potion spend one package-owned charge and reproduce Castle's party-condition-zero and fatigue-four effects without spell-point cost"); assert_equal(restored.rng_trace().map(func(entry: Dictionary) -> String: return String(entry.get("tag", ""))), ["field-spell.4310.duration", "field-spell.4310.damage", "field-spell.4713.duration", "field-spell.4713.damage"], "both application field items retain shared duration-before-damage RNG order"); var ally_definition: MonsterDefinition = content.monster_by_id("classic.monster.field-ally"); var ally := MonsterState.new("field.ally", ally_definition.id, ally_definition.name, 12, 12, ally_definition.hit_dice, ally_definition.agility, ally_definition.armor, 127, 0, false); restored._state.party.set_allies([ally]); restored._rng = ScriptedRng.new([0, 0, 0]); var aura := restored.submit_intent(PlayerIntent.cast_spell("classic.spell.2106", heroism_caster.id, "", 1)); var aura_saved := GameSession.new(); assert_equal(aura_saved.restore(content, save_round_trip(restored.snapshot())).state, SessionStep.State.COMPLETED, "a committed field ally effect restores through the public save envelope"); assert_equal([aura.state, heroism_caster.spell_points, heroism_caster.conditions.value(4), restored._state.party.character_by_id(active_target.id).conditions.value(4), ally.conditions.value(4), aura_saved._state.party.allies()[0].conditions.value(4), aura.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"field_spell_resolved").map(func(event: DomainEvent) -> Array: return [event.payload.get("targetId"), event.payload.get("targetKind")]), restored._rng.snapshot().draw_count], [SessionStep.State.COMPLETED, 101, 1, 1, 1, 1, [[heroism_caster.id, "character"], [active_target.id, "character"], [ally.id, "monster"]], 3], "target-nine field magic affects party characters then every held-over ally, ignores ally magic resistance, publishes target kinds, spends once, and consumes only the shared duration and damage draws")


func _field_content(source: RealmzContent) -> RealmzContent:
	var empty_ints: Array[int] = []
	var empty_ranges: Array[Vector2i] = []
	var age_changes: Array[PackedInt32Array] = []
	for _index: int in 5:
		age_changes.append(PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	var race := RaceDefinition.new("classic.race.field", 1, "Human", empty_ints, empty_ints, empty_ints, empty_ints, empty_ints, empty_ranges, age_changes, 0, false, 10, 0, 0, 0, 1, 1, false, 0, 0, 4096)
	var caste := CasteDefinition.new("classic.caste.field", 1, "Sorcerer", empty_ints, empty_ints, empty_ints, empty_ints, Vector2i(8, 8), Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, [], [], [], 1, 1, 0, 1, 0, 0, 0, 1, 0, true, false, 0, 0, 4096)
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
	var cure := SpellDefinition.new("classic.spell.heal-poison", 2206, "Heal Poison"); cure.cost = 20; cure.special = 110; cure.spell_class = 8; cure.damage_type = 8; cure.target_type = 0; cure.range_min = 1; cure.in_camp = true; cure.in_combat = true
	var remove_item := SpellDefinition.new("classic.spell.remove-item", 1410, "Remove Item"); remove_item.cost = 6; remove_item.special = 62; remove_item.spell_class = 7; remove_item.damage_type = 7; remove_item.cannot = 4; remove_item.target_type = 0; remove_item.range_min = 1; remove_item.in_camp = true; remove_item.in_combat = true
	var heroism := SpellDefinition.new("classic.spell.4308", 4308, "Heroism"); heroism.in_camp = true; heroism.in_combat = true; heroism.target_type = 5; heroism.spell_class = 8; heroism.damage_type = 8; heroism.cannot = 3; heroism.duration_min = 5; heroism.duration_max = 12
	var races: Array[RaceDefinition] = [race]; var castes: Array[CasteDefinition] = [caste]
	var cursed := ItemDefinition.new("classic.item.cursed-blade", 880, "Cursed Blade"); cursed.cursed_item_id = cursed.id; var ordinary := ItemDefinition.new("classic.item.ordinary-shield", 881, "Ordinary Shield"); var items: Array[ItemDefinition] = [cursed, ordinary]
	var ally_definition := MonsterDefinition.new("classic.monster.field-ally", 1, "Field Ally", 1, 0, 1, 0, 0, [], [], [], [], [], [], []); var library := PackageRepository.new().load_bundled_package("res://src/infrastructure/characters/realmz-classic-character-library.realmz2", "realmz-classic-character-library", "c7e093f46bcca49d2382d68c2995ae5ff90c0e706dbd538682b613af9b80e0bd"); items.append(library.content.item_by_classic_id(609)); items.append(library.content.item_by_classic_id(723)); var spells: Array[SpellDefinition] = [bolt, fixed, light, rest, cure, remove_item, heroism, library.content.spell_by_classic_id(1101), library.content.spell_by_classic_id(1512), library.content.spell_by_classic_id(2102), library.content.spell_by_classic_id(3102), library.content.spell_by_classic_id(2106)]; for classic_id: int in [1609, 2504, 2609, 2611, 3111, 3112, 3410, 3709, 3711, 4310, 4713]: spells.append(library.content.spell_by_classic_id(classic_id))
	var source_map := source.world.map_by_id(source.start_map_id); var los_map := MapDefinition.new(source_map.id, source_map.name, source_map.level_type, source_map.level_index, source_map.topology, source_map.dark, true, source_map.landlook, source_map.random_regions(), source_map.battle_terrain_set_id, source_map.base_scale)
	return RealmzContent.new("field-spell-workflow", source.package_hash, "field-spell-content", source.rules_version, source.start_map_id, source.start_coordinate, WorldDefinition.new([los_map]), ScenarioDefinition.new([], []), [], [], [], races, castes, items, spells, [ally_definition])


func _character(character_id: String, display_name: String, content: RealmzContent) -> CharacterState:
	var result := CharacterState.new(character_id, display_name, 20, 20)
	result.race_id = content.race_definitions()[0].id
	result.caste_id = content.caste_definitions()[0].id
	result.maximum_load = 100
	return result
