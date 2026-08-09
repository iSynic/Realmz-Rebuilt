extends RealmzTestCase


func run() -> void:
	_test_arithmetic_and_ranges()
	_test_character_creation_and_leveling()
	_test_live_aging_and_maximum_age()
	_test_monster_aging_attack()
	_test_conditions_time_and_persistence()
	_test_inventory_economy_and_treasure()
	_test_combat_magic_and_monsters()


func _test_arithmetic_and_ranges() -> void:
	var rules := RealmzRules.new()
	assert_equal(rules.arithmetic.signed_16(65_535), -1, "16-bit signed wrapping preserves Classic comparisons")
	assert_equal(rules.arithmetic.signed_32(4_294_967_295), -1, "32-bit signed wrapping preserves Classic values")
	assert_true(rules.arithmetic.percentage_succeeds(50, 50), "Classic percentage checks are inclusive unless source says otherwise")
	assert_false(rules.arithmetic.percentage_succeeds(50, 50, false), "strict source comparisons remain strict")
	var ranged := ScriptedRng.new([0, 32_767])
	assert_equal(ranged.draw_between(-3, 3, &"rules.range.low"), -3, "Castle randrange includes its lower bound")
	assert_equal(ranged.draw_between(-3, 3, &"rules.range.high"), 3, "Castle randrange includes its upper bound")


func _test_character_creation_and_leveling() -> void:
	var rules := RealmzRules.new()
	var race := _race()
	var caste := _caste()
	var creation_rng := ScriptedRng.new([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	var created := rules.characters.create_character("character.hero", "Hero", race, caste, 1, creation_rng)
	assert_not_null(created, "a valid race/caste pair constructs a direct Realmz character")
	assert_equal([created.brawn, created.knowledge, created.judgment, created.agility, created.vitality, created.luck], [2, 1, 1, 1, 1, 1], "attribute rolls apply gender and min/max constraints in Castle order")
	assert_equal(created.maximum_health, 1, "initial stamina uses the caste die")
	assert_equal(created.to_hit, -10, "caste and brawn to-hit bonuses are combined")
	assert_equal(created.magic_resistance, 5, "race and caste magic resistance inputs are applied")
	assert_equal(created.maximum_load, 500, "Classic load capacity retains its 500 minimum")
	assert_equal(created.age_days, 18 * 365, "age is rolled from the race range selected by caste")
	assert_equal(created.age_group, 1, "creation persists the caste-selected current age group independently from age days")
	assert_equal(created.inventory().size(), 1, "caste starting equipment becomes stable item instances")
	assert_equal(rules.characters.strength_bonuses(30, 5).damage_bonus, 5, "caste strength caps brawn damage without changing hit bonus")
	assert_equal(creation_rng.snapshot().draw_count, 12, "creation preserves Castle's discarded attribute and three special-bonus rolls")
	var creation_trace := creation_rng.trace()
	assert_equal([creation_trace[6]["tag"], creation_trace[7]["tag"], creation_trace[10]["tag"], creation_trace[11]["tag"]], ["character.create.attribute.discarded", "character.create.special-bonus.80.roll", "character.create.stamina", "character.create.age"], "creation trace exposes Castle's source-ordered random draws")

	var special_rng := ScriptedRng.new([0, 0, 0, 0, 0, 0, 0, 32_767, 32_767, 0, 0, 0, 0])
	var specially_gifted := rules.characters.create_character("character.special", "Special", race, caste, 1, special_rng)
	assert_equal(specially_gifted.special_value(7), 1, "each successful Castle creation bonus increments the randomly selected hit modifier")
	assert_equal(special_rng.snapshot().draw_count, 13, "a successful creation bonus consumes its separate inclusive index draw")

	var race_conditions := _ints_size(40, 0)
	race_conditions[4] = 2
	race_conditions[5] = 3
	race_conditions[10] = -3
	var caste_conditions := _ints_size(40, 0)
	caste_conditions[5] = 1
	caste_conditions[6] = 2
	var defense_race := RaceDefinition.new("race.defense", 2, "Defense Race", _ints_size(8, 0), _ints([100, -200, 0, 0, 0, 0, 0, 100]), _ints_size(6, 0), _attribute_limits(), race_conditions, [Vector2i(18, 18)], _age_changes(), 100)
	var defense_caste := CasteDefinition.new("caste.defense", 2, "Defense Caste", _ints([100, 0, 0, 0, 0, 0, 0, 100]), _ints_size(6, 0), _attribute_limits(), caste_conditions, Vector2i(8, 8), Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO)
	var defended := rules.characters.create_character("character.defense", "Defender", defense_race, defense_caste, 1, ScriptedRng.new([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	assert_equal([defended.save_value(0), defended.save_value(1), defended.save_value(7)], [120, -99, 120], "creation saves combine race and caste values within Castle's bounds")
	assert_equal(defended.conditions.value(4), 2, "racial starting conditions retain their authored duration")
	assert_equal(defended.conditions.value(5), -1, "caste condition level one replaces a racial value with a permanent condition")
	assert_equal(defended.conditions.value(6), 0, "later caste condition thresholds do not become level-one conditions")
	assert_equal(defended.conditions.value(10), -3, "negative racial starting conditions retain their authored strength")

	var aging_changes := _age_changes()
	aging_changes[0] = PackedInt32Array([1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7])
	aging_changes[1] = PackedInt32Array([-1, -1, -1, -1, -1, -1, -7, -8, 10, 10, 10, 10, 10, 10, 10])
	var aging_race := RaceDefinition.new("race.aging", 3, "Aging Race", _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _attribute_limits(), _ints_size(40, 0), [Vector2i(18, 18), Vector2i(25, 25), Vector2i(35, 35), Vector2i(50, 50), Vector2i(70, 70)], aging_changes, 100, false, 10, 5)
	var aged := rules.characters.create_character("character.aged", "Aged", aging_race, _caste(2), 1, ScriptedRng.new([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	assert_equal([aged.brawn, aged.knowledge, aged.judgment, aged.agility, aged.vitality, aged.luck], [2, 2, 3, 3, 5, 6], "creation cumulatively applies every race aging row through the caste minimum age group")
	assert_equal([aged.save_value(0), aged.save_value(1), aged.save_value(2), aged.save_value(3), aged.save_value(4), aged.save_value(5), aged.save_value(6), aged.save_value(7)], [61, 62, 63, 64, 65, 66, 67, 50], "creation applies Castle age defenses to only the first seven saves")
	assert_equal(aged.age_days, 25 * 365, "the caste minimum age group selects the matching race age range after aging modifiers")

	created.vitality = 18
	created.level = 1
	created.missile = 2
	var level_result := rules.characters.level_up(created, race, caste, ScriptedRng.new([0, 32_767, 0]))
	assert_equal(created.level, 2, "level-up commits the next Realmz level")
	assert_equal(created.normal_attacks, 2, "caste attack-level unlocks participate in the attack cap")
	assert_equal(created.missile, 3, "missile improvement is a Castle-scaled die")
	assert_equal(level_result.stamina_gained, 10, "level stamina includes the capped vitality bonus")
	assert_equal(level_result.magic_resistance_gained, 1, "the inclusive level resistance check is deterministic")
	assert_equal(created.to_hit, -8, "level to-hit growth mutates the character aggregate")


func _test_live_aging_and_maximum_age() -> void:
	var rules := RealmzRules.new()
	var changes := _age_changes()
	changes[1] = PackedInt32Array([1, 2, 3, 4, 5, 6, 7, -20, 100, -200, 3, 4, 5, 6, 7])
	var race := RaceDefinition.new("race.live-aging", 4, "Live Aging", _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _attribute_limits(), _ints_size(40, 0), [Vector2i(10, 19), Vector2i(20, 29), Vector2i(30, 39), Vector2i(40, 49), Vector2i(50, 59)], changes, 100, false, 10, 5)
	var caste := _caste()
	var character := CharacterState.new("character.live-aging", "Aging Hero", 10, 10)
	character.race_id = race.id
	character.caste_id = caste.id
	character.age_days = 19 * 365 + 364
	character.age_group = 1
	character.brawn = 15
	character.knowledge = 10
	character.judgment = 10
	character.agility = 10
	character.vitality = 10
	character.luck = 10
	character.to_hit = 10
	character.damage_bonus = 2
	character.magic_resistance = 20
	character.maximum_movement = 12
	character.set_save_value_raw(0, 100)
	character.set_save_value_raw(1, -50)
	var advanced := rules.characters.advance_age_days(character, race, caste, 1)
	assert_equal(advanced.transition, 1, "crossing an authored birthday boundary advances one Classic age band")
	assert_equal(character.age_group, 2, "the independent current age group advances by one")
	assert_equal([character.brawn, character.knowledge, character.judgment, character.agility, character.vitality, character.luck], [16, 12, 13, 14, 15, 16], "live aging applies the destination band's six attribute changes without creation bounds")
	assert_equal([character.to_hit, character.damage_bonus], [15, 3], "live brawn aging removes and reapplies Castle strength bonuses")
	assert_equal([character.magic_resistance, character.maximum_movement], [27, 2], "live aging applies magic resistance and floors maximum movement at two")
	assert_equal([character.save_value(0), character.save_value(1), character.save_value(7)], [200, -250, 50], "live aging changes seven saves without creation-time clamping")

	var skipped := CharacterState.from_data(character.to_data())
	assert_not_null(skipped, "the current age group survives the central character serialization boundary")
	skipped.age_days = 45 * 365
	skipped.age_group = 1
	var skipped_result := rules.characters.advance_age_days(skipped, race, caste, 0)
	assert_equal([skipped_result.transition, skipped.age_group], [1, 2], "one aging operation advances only one adjacent band even when age crosses several ranges")

	character.age_days = 25 * 365
	character.age_group = 2
	var reversed := rules.characters.advance_age_days(character, race, caste, -10 * 365)
	assert_equal([reversed.transition, character.age_group], [-1, 1], "age reversal erases only the current band and moves back one group")
	assert_equal(character.maximum_movement, 22, "reversing a movement penalty preserves Castle's non-invertible minimum-movement floor")
	var outside := rules.characters.advance_age_days(character, race, caste, 100 * 365)
	assert_equal([outside.transition, character.age_group], [0, 1], "an age outside all five authored ranges does not invent a transition")

	character.age_days = 100 * 365
	assert_equal(rules.characters.battle_experience(character, race, 1_500), 999, "characters at maximum age receive Castle's truncated two-thirds battle experience")
	race.does_not_die = true
	assert_equal(rules.characters.battle_experience(character, race, 1_500), 999, "the stored doesNotDie flag does not alter Castle's maximum-age experience rule")

	var clock_character := CharacterState.new("character.clock-aging", "Clock Hero", 10, 10)
	clock_character.race_id = race.id
	clock_character.caste_id = caste.id
	clock_character.age_days = 19 * 365 + 364
	clock_character.age_group = 1
	var clock_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, _characters([clock_character])), RealmzClock.new(RealmzClock.MINUTES_PER_DAY - 1))
	var aging_content := RealmzContent.new("aging", "0".repeat(64), "aging-content", "realmz-classic-1", "", Vector2i.ZERO, WorldDefinition.new([]), ScenarioDefinition.new([], []), [], [], [], [race], [caste])
	var clock_events := rules.clock.advance_minutes(clock_state, aging_content, 1)
	assert_equal(clock_character.age_days, 20 * 365, "each crossed midnight adds one day to every character")
	assert_true(clock_events.any(func(event: DomainEvent) -> bool: return event.kind == &"character_age_changed"), "a midnight age-band transition publishes a typed domain event")

	var haste := SpellDefinition.new("spell.haste-aging", 1, "Haste")
	haste.special = 24
	haste.duration_min = 0
	haste.duration_max = 0
	haste.damage_min = 0
	haste.damage_max = 0
	clock_character.age_days = 19 * 365 + 350
	clock_character.age_group = 1
	var haste_result := rules.magic.resolve_scenario_spell(clock_character, haste, 1, 0, true, ScriptedRng.new([0, 0]), caste, race)
	assert_equal([haste_result.aging.transition, clock_character.age_days, clock_character.age_group], [1, 19 * 365 + 380, 2], "Castle haste ages by power times thirty percent-months and invokes one age transition")

	var youth := SpellDefinition.new("spell.youth", 2, "Youth")
	youth.special = 92
	youth.duration_min = 1
	youth.duration_max = 1
	youth.damage_min = 0
	youth.damage_max = 0
	clock_character.age_days = 20 * 365
	clock_character.age_group = 2
	clock_character.maximum_health = 10
	clock_character.current_health = 8
	var youth_result := rules.magic.resolve_scenario_spell(clock_character, youth, 1, 0, true, ScriptedRng.new([0, 0, 32_767]), caste, race)
	assert_equal([youth_result.aging.transition, clock_character.age_group], [-1, 1], "the youth special reverses one current age band")
	assert_equal([clock_character.maximum_health, clock_character.current_health], [7, 5], "the youth special consumes Castle's one-to-three stamina loss draw")
	assert_true(clock_character.age_days >= 3_650, "the youth special never reduces age below ten years")


func _test_monster_aging_attack() -> void:
	var rules := RealmzRules.new()
	var changes := _age_changes()
	changes[1] = PackedInt32Array([1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0])
	var race := RaceDefinition.new("race.monster-aging", 17, "Monster Aging", _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _attribute_limits(), _ints_size(40, 0), [Vector2i(10, 19), Vector2i(20, 29), Vector2i(30, 39), Vector2i(40, 49), Vector2i(50, 59)], changes, 100)
	var caste := _caste()
	var attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 17)]
	var definition := MonsterDefinition.new("monster.aging", 17, "Aging Monster", 2, 0, 10, 0, 0, _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _ints_size(3, 0), [], [], attacks)
	var attacker := MonsterState.new("monster.aging.instance", definition.id, definition.name, 10, 10, 2, 10)
	var defender := CharacterState.new("character.aging-target", "Aging Target", 20, 20)
	defender.race_id = race.id
	defender.caste_id = caste.id
	defender.age_days = 19 * 365 + 364
	defender.age_group = 1
	defender.set_save_value_raw(7, 50)
	var rng := ScriptedRng.new([0, 0, 0, 32_767])
	var resolution := rules.combat.resolve_monster_attack(attacker, definition, 0, defender, race, caste, rng)
	assert_true(resolution.hit, "Castle special 17 is evaluated only after the ordinary monster attack hits")
	assert_equal([resolution.special_code, resolution.special_potency, resolution.special_save_chance, resolution.special_save_roll], [17, 1, 50, 100], "aging attacks retain the unused potency draw before the special-save roll")
	assert_false(resolution.special_saved, "a failed special save reaches the aging effect")
	assert_equal(resolution.special_age_days, 2, "aging attack days truncate maxAge times one percent times damageMax times hit dice")
	assert_not_null(resolution.aging, "a failed aging save returns the typed aging result")
	assert_equal([defender.age_days, defender.age_group, defender.brawn, defender.save_value(0)], [20 * 365 + 1, 2, 11, 52], "the aging special applies one adjacent live-age row before returning")
	assert_true(resolution.damage_deferred, "a changed age band defers ordinary physical damage until the Classic dialog returns")
	assert_equal(defender.current_health, 20, "the age-update boundary precedes ordinary physical damage")
	assert_equal(rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["combat.monster-attack.hit", "combat.monster-attack.damage", "combat.monster-attack.special-potency", "combat.monster-attack.special-save"], "monster aging preserves Castle's observable random order")

	var saved_target := CharacterState.new("character.saved-aging-target", "Saved Target", 20, 20)
	saved_target.race_id = race.id
	saved_target.caste_id = caste.id
	saved_target.age_days = 19 * 365 + 364
	saved_target.age_group = 1
	saved_target.set_save_value_raw(7, 50)
	var saved := rules.combat.resolve_monster_attack(attacker, definition, 0, saved_target, race, caste, ScriptedRng.new([0, 0, 0, 0]))
	assert_true(saved.special_saved, "an inclusive save-slot-seven success negates Classic monster aging")
	assert_equal([saved_target.age_days, saved_target.age_group], [19 * 365 + 364, 1], "a successful aging save leaves age state unchanged")
	assert_equal(saved_target.current_health, 19, "a saved aging special has no dialog boundary and commits ordinary damage immediately")

	var same_band_target := CharacterState.new("character.same-band-aging-target", "Same Band Target", 20, 20)
	same_band_target.race_id = race.id
	same_band_target.caste_id = caste.id
	same_band_target.age_days = 15 * 365
	same_band_target.age_group = 1
	same_band_target.set_save_value_raw(7, 50)
	var same_band := rules.combat.resolve_monster_attack(attacker, definition, 0, same_band_target, race, caste, ScriptedRng.new([0, 0, 0, 32_767]))
	assert_true(same_band.special_applied and not same_band.damage_deferred, "failed aging that remains in the same band does not invent a dialog boundary")
	assert_equal([same_band_target.age_days, same_band_target.age_group, same_band_target.current_health], [15 * 365 + 2, 1, 19], "same-band aging and physical damage commit in the original attack call")

	var monster_target := MonsterState.new("monster.aging-target", definition.id, "Monster Target", 20, 20, 2, 10)
	var monster_rng := ScriptedRng.new([0, 0, 0])
	var monster_resolution := rules.combat.resolve_monster_attack_monster(attacker, definition, 0, monster_target, monster_rng)
	assert_equal([monster_resolution.special_code, monster_resolution.special_potency, monster_target.current_health], [17, 1, 19], "monster targets consume generic special potency but receive no party-only aging effect")
	assert_equal(monster_rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["combat.monster-attack.hit", "combat.monster-attack.damage", "combat.monster-attack.special-potency"], "monster-target special 17 stops after Castle's shared potency draw")


func _test_conditions_time_and_persistence() -> void:
	var rules := RealmzRules.new()
	var character := CharacterState.new("character.conditions", "Conditions", 5, 10)
	character.maximum_spell_points = 10
	character.spell_points = 5
	character.conditions.set_value(ConditionRules.REGENERATING, 2)
	character.conditions.set_value(ConditionRules.DISEASED, 1)
	character.conditions.set_value(ConditionRules.POISONED, 2)
	character.conditions.set_value(ConditionRules.ENERGY_DRAIN, 2)
	character.conditions.set_value(ConditionRules.ABSORBING_ENERGY, 1)
	var party := PartyState.new("map.test", Vector2i(1, 1), _characters([character]))
	party.conditions.set_value(0, 1)
	var state := GameState.new(party, RealmzClock.new())
	var events := rules.conditions.tick_party(party)
	assert_equal(character.current_health, 4, "regeneration occurs before disease and poison damage")
	assert_equal(character.spell_points, 4, "energy drain occurs before energy absorption")
	assert_equal(character.conditions.value(ConditionRules.POISONED), 1, "positive character conditions decay after applying their effect")
	assert_equal(party.conditions.value(0), 0, "party conditions decay through the same fixed owner")
	assert_true(events.size() >= 4, "condition ticks publish domain observations")
	assert_equal(rules.clock.change_fatigue(party, 500), 135, "fatigue is clamped to Castle's upper bound")
	rules.clock.camp(state, null, 8)
	assert_equal(party.fatigue, 4, "camping returns fatigue to Castle's lower bound")
	assert_equal(state.clock.total_minutes(), 480, "camping advances only the session-owned Realmz clock")
	assert_equal(character.spell_points, character.maximum_spell_points, "camping restores available spell energy")

	state.combat = CombatState.new("battle.test", _monsters([MonsterState.new("monster.saved", "monster.test", "Saved Monster", 3, 6)]))
	var parsed: Variant = JSON.parse_string(JSON.stringify(state.to_data()))
	var restored := GameState.from_data(parsed)
	assert_not_null(restored, "the complete expanded game aggregate survives JSON")
	assert_equal(restored.to_data(), state.to_data(), "expanded party, condition, wealth, and combat state round-trip exactly")


func _test_inventory_economy_and_treasure() -> void:
	var rules := RealmzRules.new()
	var character := CharacterState.new("character.inventory", "Inventory", 8, 8)
	character.maximum_load = 50
	var item := ItemDefinition.new("item.wand", 1, "Wand")
	item.weight = 10
	item.initial_charges = 2
	item.weight_per_charge = 3
	item.drop_on_empty = true
	item.damage_bonus = 4
	var instance := rules.inventory.add_item(character, item, "item-instance.wand", true)
	assert_not_null(instance, "inventory accepts a definition-backed item within capacity")
	assert_equal(character.carried_load, 16, "item load includes charge weight")
	assert_true(rules.inventory.equip(character, instance.id, item), "equipment mutation is owned by inventory rules")
	assert_equal(rules.inventory.equipped_damage_bonus(character, _items([item])), 4, "equipped item damage is summed as Castle attack.c does")
	assert_true(rules.inventory.use_charge(character, instance.id, item), "a charged item can be used")
	assert_equal(character.carried_load, 13, "spent charges reduce load")
	assert_true(rules.inventory.use_charge(character, instance.id, item), "the final charge can be used")
	assert_equal(character.inventory().size(), 0, "drop-on-empty removes the exhausted instance")
	assert_equal(character.carried_load, 0, "exhausted item removal subtracts base and remaining charge load")

	var second := CharacterState.new("character.second", "Second", 8, 8)
	character.money = WealthState.new(3, 1, 1)
	second.money = WealthState.new(2, 0, 0)
	character.carried_load = 19
	second.carried_load = 2
	var party := PartyState.new("map.test", Vector2i.ZERO, _characters([character, second]))
	rules.economy.pool_party_wealth(party)
	assert_equal(party.pooled_wealth.to_data(), {"gold": 5, "gems": 1, "jewelry": 1}, "pooling gathers all three native wealth kinds")
	assert_equal(character.carried_load, 0, "pooling removes gold, gems, and jewelry weight")
	assert_true(rules.economy.take(party, 4, WealthState.Kind.GOLD), "payment spends pooled wealth first")
	assert_equal(party.pooled_wealth.gold, 1, "pool-first payment leaves the exact remainder")
	var shop := ShopDefinition.new("shop.test", 1, _strings([item.id]), _ints([1]), 150)
	item.cost = 30_000
	assert_equal(rules.economy.item_price(item, shop), 32_000, "buy prices retain Castle's 32000 cap")
	assert_equal(rules.economy.item_price(item, shop, true), 30_000, "sell price never uses inflation above 100 percent")
	var treasure := TreasureDefinition.new("treasure.test", 1, _strings([item.id]), -5, -10, 2, 0)
	var treasure_roll := rules.economy.roll_treasure(treasure, ScriptedRng.new([0, 32_767]))
	assert_equal(treasure_roll.experience, 1, "negative treasure values encode a one-to-absolute-value roll")
	assert_equal(treasure_roll.wealth.gold, 10, "signed random treasure can reach its inclusive maximum")


func _test_combat_magic_and_monsters() -> void:
	var rules := RealmzRules.new()
	var attacker := CharacterState.new("character.attacker", "Attacker", 10, 10)
	attacker.luck = 1
	attacker.hand_to_hand = 4
	var definition := _monster_definition()
	var defender := MonsterState.new("monster.defender", definition.id, definition.name, 5, 5, 1, 8, 5)
	var attack := rules.combat.resolve_character_attack(attacker, defender, definition, 2, ScriptedRng.new([0, 0]))
	assert_true(attack.hit, "inclusive Realmz attack roll hits at the computed chance")
	assert_equal(attack.chance, 56, "attack chance combines base, equipment, luck, and armor")
	assert_equal(attack.damage, 2, "equipped damage is committed to the target")
	var friendly := MonsterState.new("monster.friendly", definition.id, "Friendly", 5, 5, 1, 8, 5, 0, 0, false)
	var hostile := MonsterState.new("monster.hostile", definition.id, "Hostile", 5, 5, 1, 8, 5, 0, 0, true)
	var monster_attack := rules.combat.resolve_monster_attack_monster(friendly, definition, 0, hostile, ScriptedRng.new([0, 0]))
	assert_true(monster_attack.hit, "opposed-traitor monsters use the same source-backed attack resolution")
	assert_equal(hostile.current_health, 4, "friendly monster attacks mutate hostile combat state")
	defender.conditions.set_value(ConditionRules.HELPLESS, -1)
	var helpless := rules.combat.resolve_character_attack(attacker, defender, definition, 2, ScriptedRng.new([0, 32_767]))
	assert_true(helpless.killed, "helpless defenders are hit and take their remaining health")

	var quick := CharacterState.new("character.quick", "Quick", 10, 10)
	quick.agility = 15
	attacker.agility = 5
	var middle := MonsterState.new("monster.middle", definition.id, definition.name, 4, 4, 1, 10)
	var order := rules.combat.initiative_order(_characters([attacker, quick]), _monsters([middle]), 0, ScriptedRng.new([0, 0]))
	assert_equal(order, [quick.id, middle.id, attacker.id], "randomized initiative slots are shifted by agility like Castle")

	var spell := SpellDefinition.new("spell.fire", 1, "Fire")
	spell.cost = 2
	spell.duration_min = 2
	spell.duration_max = 2
	spell.damage_min = 4
	spell.damage_max = 4
	spell.damage_type = 1
	spell.spell_class = 1
	attacker.spell_points = 10
	defender = MonsterState.new("monster.spell-target", definition.id, definition.name, 8, 8, 1, 8, 0)
	defender.conditions.set_value(ConditionRules.FIRE_PROTECTION, 1)
	var spell_result := rules.magic.resolve_character_spell(attacker, defender, definition, spell, 1, 1, ScriptedRng.new([0, 0, 32_767, 32_767]))
	assert_true(spell_result.cast, "a funded spell commits its cost")
	assert_false(spell_result.resisted, "failed resistance reaches damage resolution")
	assert_equal(spell_result.damage, 2, "matching elemental protection halves damage")
	assert_equal(attacker.spell_points, 8, "spell points are mutated inside the rule operation")
	var powered := SpellDefinition.new("spell.powered", 1101, "Powered")
	powered.damage_min = 1
	powered.damage_max = 1
	powered.power_damage_min = 2
	powered.power_damage_max = 2
	powered.duration_min = 1
	powered.duration_max = 1
	powered.power_duration_min = 3
	powered.power_duration_max = 3
	var scenario_target := CharacterState.new("character.scenario-spell", "Scenario Spell", 20, 20)
	var scenario_rng := ScriptedRng.new([0, 0, 0, 0, 0, 0])
	var scenario_spell := rules.magic.resolve_scenario_spell(scenario_target, powered, 2, 0, true, scenario_rng)
	assert_equal(scenario_spell.damage, 5, "Castle scenario spell power adds one roll per power level")
	assert_equal(scenario_spell.duration, 7, "scenario spell duration uses the same source power loop")
	assert_equal(scenario_rng.snapshot().draw_count, 6, "scenario spell power preserves Castle RNG draw ordering")
	var stone := SpellDefinition.new("spell.stone", 2608, "Flesh to Stone")
	stone.special = 27
	stone.damage_min = 0
	stone.damage_max = 0
	stone.duration_min = 0
	stone.duration_max = 0
	var stoned := rules.magic.resolve_scenario_spell(scenario_target, stone, 1, 0, true, ScriptedRng.new([0, 0]))
	assert_true(scenario_target.conditions.is_active(ConditionRules.TURNED_TO_STONE), "Flesh to Stone owns the direct Realmz condition")
	assert_equal(scenario_target.current_health, -10, "Flesh to Stone follows Castle death-damage behavior")
	assert_true(stoned.target_defeated, "scenario spell result reports Castle death state")

	var built := rules.monsters.build_monster(definition, "monster.built", -1, 1, 0, ScriptedRng.new([0, 0, 0, 0, 0]))
	assert_equal(built.maximum_health, 3, "monster stamina applies HD dice and difficulty scaling")
	assert_equal(built.magic_resistance, 16, "Castle's two resistance difficulty adjustments are preserved")
	definition.random_weapon_table = 6
	var random_weapon_rng := ScriptedRng.new([0, 0, 0, 0, 0, 32_767])
	var randomly_armed := rules.monsters.build_monster(definition, "monster.random-weapon", -1, 1, 0, random_weapon_rng)
	assert_equal(randomly_armed.weapon_id, "classic.item.120", "negative Classic monster weapons select from their source combatsetup table")
	assert_equal(random_weapon_rng.snapshot().draw_count, 6, "random monster weapons consume one session-owned draw after construction variation")
	definition.missile_percent = 100
	assert_equal(rules.monsters.choose_action(built, definition, ScriptedRng.new([0])), &"missile", "monster AI considers missile behavior before casting")
	built.current_health = 1
	definition.run_percent = 100
	definition.surrender_percent = 50
	assert_equal(rules.monsters.morale_action(built, definition), &"fight", "Castle getup.c current/current morale behavior is preserved as explicit evidence")
	definition.surrender_percent = 101
	assert_equal(rules.monsters.morale_action(built, definition), &"panic", "the source morale bug still permits the authored 101 panic sentinel")


func _race() -> RaceDefinition:
	var ages: Array[Vector2i] = [Vector2i(18, 18), Vector2i(25, 25), Vector2i(35, 35), Vector2i(50, 50), Vector2i(70, 70)]
	return RaceDefinition.new("race.test", 1, "Test Race", _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _attribute_limits(), _ints_size(40, 0), ages, _age_changes(), 100, false, 10, 5, 0, 0, 1, 3)


func _caste(minimum_age_group: int = 1) -> CasteDefinition:
	var spellcasters: Array[Vector3i] = []
	return CasteDefinition.new("caste.test", 1, "Test Caste", _ints_size(8, 0), _ints_size(6, 0), _attribute_limits(), _ints_size(40, 0), Vector2i(8, 8), Vector2i(10, 2), Vector2i(0, 1), Vector2i(2, 6), Vector2i(4, 1), spellcasters, _ints([2]), _strings(["item.start"]), 0, minimum_age_group, 0, 1, 0, 3, 0, 3, 12, true, false, 0, 0, 0, Vector2i(0, 5))


func _age_changes() -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	for index: int in 5:
		result.append(PackedInt32Array(_ints_size(15, 0)))
	return result


func _monster_definition() -> MonsterDefinition:
	var attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 2)]
	var result := MonsterDefinition.new("monster.test", 1, "Test Monster", 2, 1, 8, 4, 10, _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _ints_size(3, 0), [], [], attacks)
	result.spell_points = 10
	return result


func _attribute_limits() -> Array[int]:
	var result: Array[int] = []
	for index: int in 6:
		result.append(1)
		result.append(30)
	return result


func _ints(values: Array[int]) -> Array[int]:
	return values


func _ints_size(count: int, value: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(count)
	result.fill(value)
	return result


func _strings(values: Array[String]) -> Array[String]:
	return values


func _characters(values: Array[CharacterState]) -> Array[CharacterState]:
	return values


func _monsters(values: Array[MonsterState]) -> Array[MonsterState]:
	return values


func _items(values: Array[ItemDefinition]) -> Array[ItemDefinition]:
	return values
