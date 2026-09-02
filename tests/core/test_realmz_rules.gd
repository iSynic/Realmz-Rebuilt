extends RealmzTestCase


func run() -> void:
	_test_arithmetic_and_ranges()
	_test_party_setup_scaling()
	_test_character_creation_and_leveling()
	_test_live_aging_and_maximum_age()
	_test_monster_ordinary_attacks()
	_test_monster_aging_attack()
	_test_monster_status_attacks()
	_test_monster_resource_drains()
	_test_monster_charm_attacks()
	_test_monster_elemental_attacks()
	_test_monster_permanent_afflictions()
	_test_conditions_time_and_persistence()
	_test_inventory_economy_and_treasure()
	_test_temple_services_and_wealth()
	_test_projectile_resolution()
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


func _test_party_setup_scaling() -> void:
	assert_equal([PartySetupRules.experience_percent(6, 6, 0), PartySetupRules.experience_percent(6, 3, 1), PartySetupRules.experience_percent(6, 60, -2)], [100, 250, 20], "party guidance uses Castle's difficulty and recommended-to-current ratio with 20 through 250 percent bounds")
	assert_equal(PartySetupRules.experience_percent(6, 0, 0), 0, "an empty party reports no stale Classic experience percentage")
	assert_equal([PartySetupRules.scale_experience(101, 6, 6, -1), PartySetupRules.scale_money(101, -1), PartySetupRules.scale_money(101, 2)], [67, 67, 167], "Classic reward scaling retains floating multiplication followed by integer truncation")


func _test_temple_services_and_wealth() -> void:
	var rules := RealmzRules.new()
	var no_items: Array[ItemDefinition] = []
	assert_equal(rules.temple.service_rows(100).size(), 9, "the Classic temple exposes all nine fixed services")
	assert_equal([rules.temple.service_cost(TempleRules.HEAL_SMALL, 100), rules.temple.service_cost(TempleRules.REVIVE_DEAD, 50)], [250, 750], "temple prices scale and truncate from Castle's fixed base table")
	var character := CharacterState.new("temple.character", "Patient", 1, 20)
	character.maximum_load = 2000
	character.money.gold = 500
	character.carried_load = 500
	var party := PartyState.new("land:0", Vector2i.ZERO, [character])
	party.pooled_wealth.gold = 250
	assert_true(rules.economy.take_from_pool_and_character(party, character, 600, WealthState.Kind.GOLD), "temple payment uses pooled gold before the selected character")
	assert_equal([party.pooled_wealth.gold, character.money.gold, character.carried_load], [0, 150, 150], "selected-character temple payment removes the matching carried-gold load")
	assert_true(rules.economy.take_from_pool_and_character(party, character, -25, WealthState.Kind.GOLD), "a negative authored Temple percentage retains Castle's signed charge behavior")
	assert_equal(party.pooled_wealth.gold, 25, "a negative Classic temple charge adds its magnitude to the pool")
	var healing_rng := ScriptedRng.new([0, 32_767])
	var small := rules.temple.apply_service(character, TempleRules.HEAL_SMALL, healing_rng, no_items)
	assert_equal([small.healing(), character.current_health], [1, 2], "Heal Small Wounds uses Castle Rand(8)")
	var medium := rules.temple.apply_service(character, TempleRules.HEAL_MEDIUM, healing_rng, no_items)
	assert_equal([medium.healing(), character.current_health], [18, 20], "Heal Medium Wounds uses inclusive randrange(3,24) and clamps at maximum stamina")
	character.current_health = 5
	character.conditions.set_value(TempleRules.CONDITION_STONE, -1)
	var blocked := rules.temple.apply_service(character, TempleRules.HEAL_LARGE, ScriptedRng.new([]), no_items)
	assert_false(blocked.applied, "ordinary temple healing cannot affect a petrified character")
	assert_equal(character.current_health, 5, "petrification leaves stamina unchanged during healing")
	var flesh := rules.temple.apply_service(character, TempleRules.RESTORE_FLESH, ScriptedRng.new([]), no_items)
	assert_true(flesh.applied and not character.conditions.is_active(TempleRules.CONDITION_STONE), "Restore Flesh clears Castle's stone condition")
	character.conditions.set_value(TempleRules.CONDITION_DISEASED, 12)
	rules.temple.apply_service(character, TempleRules.HEAL_DISEASE, ScriptedRng.new([]), no_items)
	assert_equal(character.conditions.value(TempleRules.CONDITION_DISEASED), 0, "Heal Disease clears the exact source condition")
	var cursed_definition := ItemDefinition.new("item.temple-cursed", 880, "Cursed Blade")
	cursed_definition.cursed_item_id = cursed_definition.id
	var cursed_instance := ItemInstance.new("instance.temple-cursed", cursed_definition.id, 0, true, true)
	character.set_inventory([cursed_instance])
	character.conditions.set_value(TempleRules.CONDITION_CURSED, -1)
	var curse := rules.temple.apply_service(character, TempleRules.REMOVE_CURSE, ScriptedRng.new([]), [cursed_definition])
	assert_equal([character.conditions.value(TempleRules.CONDITION_CURSED), cursed_instance.equipped, curse.unequipped_item_ids], [0, false, [cursed_instance.id]], "Remove Cursed Items clears the condition and force-unequips cursed gear")
	character.current_health = -10
	character.set_ability_value(2, 40)
	var revive := rules.temple.apply_service(character, TempleRules.REVIVE_DEAD, ScriptedRng.new([]), no_items)
	assert_equal([character.current_health, character.ability_value(2), revive.applied], [-9, 38, true], "Revive Dead restores eligible dead characters at -9 stamina and subtracts two from Castle spec slot two")
	character.current_health = -10
	character.set_ability_value(2, 40)
	character.conditions.set_value(TempleRules.CONDITION_STONE, -1)
	rules.temple.apply_service(character, TempleRules.REVIVE_DEAD, ScriptedRng.new([]), no_items)
	assert_equal([character.current_health, character.ability_value(2), character.conditions.value(TempleRules.CONDITION_STONE)], [-10, 40, 0], "Castle's anomalous stone-dead Revive path clears stone without reviving or applying the ability penalty")


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
	var level_result := rules.characters.level_up(created, race, caste, ScriptedRng.new([0, 0, 32_767, 0]))
	assert_equal(created.level, 2, "level-up commits the next Realmz level")
	assert_equal(created.normal_attacks, 2, "caste attack-level unlocks participate in the attack cap")
	assert_equal(created.missile, 3, "missile improvement is a Castle-scaled die")
	assert_equal(level_result.stamina_gained, 10, "level stamina includes the capped vitality bonus")
	assert_equal(level_result.magic_resistance_gained, 1, "the inclusive level resistance check is deterministic")
	assert_equal(created.to_hit, -8, "level to-hit growth mutates the character aggregate")

	var progression_race := _progression_race()
	var progression_caste := _progression_caste()
	var progression_rng := ScriptedRng.new(_ints_size(20, 0))
	var advanced := rules.characters.create_character("character.advanced", "Advanced", progression_race, progression_caste, 1, progression_rng, false, 3)
	assert_not_null(advanced, "Castle's fixed level-three choice constructs through two ordinary level-up operations")
	assert_equal([advanced.level, advanced.prestige_penalty, advanced.experience], [3, 40, -12_345], "advanced creation retains Castle's target level, quadratic prestige penalty, and caste victory threshold")
	assert_equal([advanced.maximum_health, advanced.current_health, advanced.two_hand], [3, 3, 100], "advanced creation accumulates level stamina and preserves the clamped race-plus-caste two-hand statistic")
	assert_equal([advanced.special_value(0), advanced.ability_value(0), advanced.ability_value(3), advanced.ability_value(14)], [7, 16, 6, 0], "racial combat modifiers remain separate from initialized and leveled trained abilities, while the invalid fifteenth source field stays zero")
	assert_equal(advanced.conditions.value(4), -1, "a caste level threshold replaces an existing non-permanent racial duration with Castle's permanent sentinel")
	assert_equal(progression_rng.snapshot().draw_count, 20, "level-three creation consumes the level-one roll followed by both complete ordinary level-up RNG sequences")
	assert_equal(progression_rng.trace().filter(func(entry: Dictionary) -> bool: return entry["tag"] == "character.level.registration-check").size(), 2, "each intervening Castle level consumes its registration-era compatibility draw")


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


func _test_monster_ordinary_attacks() -> void:
	var rules := RealmzRules.new()
	var evil_flags := _ints_size(8, 0)
	evil_flags[4] = 1
	var attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(2, 4)]
	var definition := MonsterDefinition.new("monster.ordinary", 700, "Ordinary Monster", 2, 0, 10, 0, 0, evil_flags, _ints_size(8, 0), _ints_size(6, 0), _ints_size(3, 0), [], [], attacks)
	definition.damage_bonus = 3
	var attacker := MonsterState.new("monster.ordinary.attacker", definition.id, definition.name, 20, 20, 2)
	attacker.conditions.set_value(ConditionRules.PROTECTION_FROM_EVIL, 1)
	var defender := CharacterState.new("character.ordinary.target", "Target", 30, 30)
	defender.armor = 7
	defender.conditions.set_value(ConditionRules.PROTECTION_FROM_EVIL, 1)
	var rng := ScriptedRng.new([0, 0, 32_767])
	var result := rules.combat.resolve_monster_attack(attacker, definition, 0, defender, null, null, rng, 0, MonsterAttackContext.new(null, 140, false, 5, false, 12))
	assert_equal(result.chance, 64, "ordinary monster accuracy combines damage plus, source day scaling, attacker protection, effective defender luck and armor, and evil-only protection")
	assert_equal(result.damage, 7, "unarmed monster damage combines damage plus with the authored attack row")
	assert_equal(rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["combat.monster-attack.defender-luck", "combat.monster-attack.hit", "combat.monster-attack.damage"], "party-target monster attacks preserve Castle's luck-before-hit draw order")

	var neutral_definition := MonsterDefinition.new("monster.ordinary.neutral", 701, "Neutral Monster", 2, 0, 10, 0, 0, _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _ints_size(3, 0), [], [], attacks)
	neutral_definition.damage_bonus = 3
	var neutral_attacker := MonsterState.new("monster.ordinary.neutral.attacker", neutral_definition.id, neutral_definition.name, 20, 20, 2)
	neutral_attacker.conditions.set_value(ConditionRules.PROTECTION_FROM_EVIL, 1)
	var neutral_target := CharacterState.new("character.ordinary.neutral-target", "Neutral Target", 30, 30)
	neutral_target.armor = 7
	neutral_target.conditions.set_value(ConditionRules.PROTECTION_FROM_EVIL, 1)
	var neutral_result := rules.combat.resolve_monster_attack(neutral_attacker, neutral_definition, 0, neutral_target, null, null, ScriptedRng.new([0, 0, 0]), 0, MonsterAttackContext.new(null, 140, false, 5))
	assert_equal(neutral_result.chance, 79, "protection from evil does not defend against a non-evil monster")

	var weak_definition := MonsterDefinition.new("monster.ordinary.weak", 702, "Weak Monster", 0, 0, 10, 0, 0, _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _ints_size(3, 0), [], [], [MonsterAttackDefinition.new(1, 1)])
	weak_definition.damage_bonus = -20
	var weak_attacker := MonsterState.new("monster.ordinary.weak.attacker", weak_definition.id, weak_definition.name, 5, 5, 0)
	var armored_target := CharacterState.new("character.ordinary.armored", "Armored", 10, 10)
	armored_target.armor = 100
	var weak_result := rules.combat.resolve_monster_attack(weak_attacker, weak_definition, 0, armored_target, null, null, ScriptedRng.new([0, 32_767]), 0, MonsterAttackContext.new(null, 0, false, 0))
	assert_equal(weak_result.chance, 10, "ordinary monster accuracy retains Castle's ten-percent floor")
	assert_false(weak_result.hit, "the minimum chance does not become an automatic hit")
	var negative_target := CharacterState.new("character.ordinary.negative", "Negative Damage Target", 10, 10)
	var negative_result := rules.combat.resolve_monster_attack(weak_attacker, weak_definition, 0, negative_target, null, null, ScriptedRng.new([0, 0, 0]), 0, MonsterAttackContext.new(null, 0, false, 0))
	assert_equal([negative_result.damage, negative_target.current_health], [0, 10], "FD-COMBAT-004 prevents a negative monster damage total from healing its target")

	var weapon := ItemDefinition.new("item.monster-blade", 44, "Monster Blade")
	weapon.item_type = 2
	weapon.damage_bonus = 2
	weapon.vs_small = 6
	weapon.heat = 8
	weapon.vs_evil = 4
	weapon.special_1 = 121
	var weapon_target := CharacterState.new("character.ordinary.weapon-target", "Weapon Target", 30, 30)
	weapon_target.armor = 7
	weapon_target.set_save_value_raw(1, 100)
	weapon_target.conditions.set_value(ConditionRules.FIRE_PROTECTION, 1)
	var weapon_result := rules.combat.resolve_monster_attack(MonsterState.new("monster.ordinary.weapon", definition.id, definition.name, 20, 20, 2), definition, 0, weapon_target, null, null, ScriptedRng.new([0, 0, 32_767, 32_767, 0]), 0, MonsterAttackContext.new(weapon, 140, false, 5, true))
	assert_equal(weapon_result.chance, 89, "monster weapons contribute magic plus and double-to-hit metadata to accuracy")
	assert_equal([weapon_result.physical_damage, weapon_result.weapon_effects[0].get("amount"), weapon_result.damage], [6, 2, 8], "monster weapon damage preserves physical, elemental mitigation, and Dragon Hide reduction")
	assert_equal([weapon_result.physical_damage_reduction, weapon_result.physical_feedback_sound_id], [5, 694], "Dragon Hide reports Castle's full reduction and synchronous feedback sound")

	var monster_target_definition := MonsterDefinition.new("monster.ordinary.weapon-gated", 703, "Weapon-gated Monster", 1, 0, 10, 0, 0, evil_flags, _ints_size(8, 0), _ints_size(6, 0), _ints_size(3, 0), [], [], [MonsterAttackDefinition.new(1, 1)])
	monster_target_definition.required_weapon = -1
	var monster_target := MonsterState.new("monster.ordinary.weapon-gated.target", monster_target_definition.id, monster_target_definition.name, 20, 20, 1)
	var blocked := rules.combat.resolve_monster_attack_monster(MonsterState.new("monster.ordinary.weapon-gated.attacker", definition.id, definition.name, 20, 20, 2), definition, 0, monster_target, monster_target_definition, ScriptedRng.new([0]), MonsterAttackContext.new(weapon, 140))
	assert_equal(blocked.block_reason, &"classic_blunt_weapon_required", "monster-carried weapons obey the target monster's required-weapon family")
	weapon.blunt = -1
	var armed_target := MonsterState.new("monster.ordinary.armed-target", monster_target_definition.id, monster_target_definition.name, 20, 20, 1)
	var armed := rules.combat.resolve_monster_attack_monster(MonsterState.new("monster.ordinary.armed-attacker", definition.id, definition.name, 20, 20, 2), definition, 0, armed_target, monster_target_definition, ScriptedRng.new([0, 0, 0, 0, 32_767]), MonsterAttackContext.new(weapon, 140))
	assert_true(armed.hit and not armed.blocked, "a matching monster-carried blunt weapon passes the required-weapon gate")
	assert_equal(armed.damage, 11, "monster weapon damage includes magic plus, the physical die, elemental metadata, and matching target-type damage")

	var helpless_target := CharacterState.new("character.ordinary.helpless", "Helpless", 5, 5)
	helpless_target.conditions.set_value(ConditionRules.HELPLESS, -1)
	var helpless := rules.combat.resolve_monster_attack(weak_attacker, weak_definition, 0, helpless_target, null, null, ScriptedRng.new([0, 32_767, 32_767]), 0, MonsterAttackContext.new(null, 0, false, 0))
	assert_true(helpless.hit and helpless.killed, "Castle's helpless party branch bypasses a failed ordinary hit")
	assert_equal(helpless.damage, 15, "helpless party damage includes the target's remaining stamina plus Rand(10)")


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
	var rng := ScriptedRng.new([0, 0, 0, 0, 32_767])
	var resolution := rules.combat.resolve_monster_attack(attacker, definition, 0, defender, race, caste, rng)
	assert_true(resolution.hit, "Castle special 17 is evaluated only after the ordinary monster attack hits")
	assert_equal([resolution.special_code, resolution.special_potency, resolution.special_save_chance, resolution.special_save_roll], [17, 1, 50, 100], "aging attacks retain the unused potency draw before the special-save roll")
	assert_false(resolution.special_saved, "a failed special save reaches the aging effect")
	assert_equal(resolution.special_age_days, 2, "aging attack days truncate maxAge times one percent times damageMax times hit dice")
	assert_not_null(resolution.aging, "a failed aging save returns the typed aging result")
	assert_equal([defender.age_days, defender.age_group, defender.brawn, defender.save_value(0)], [20 * 365 + 1, 2, 11, 52], "the aging special applies one adjacent live-age row before returning")
	assert_true(resolution.damage_deferred, "a changed age band defers ordinary physical damage until the Classic dialog returns")
	assert_equal(defender.current_health, 20, "the age-update boundary precedes ordinary physical damage")
	assert_equal(rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["combat.monster-attack.defender-luck", "combat.monster-attack.hit", "combat.monster-attack.damage", "combat.monster-attack.special-potency", "combat.monster-attack.special-save"], "monster aging preserves Castle's observable random order")

	var saved_target := CharacterState.new("character.saved-aging-target", "Saved Target", 20, 20)
	saved_target.race_id = race.id
	saved_target.caste_id = caste.id
	saved_target.age_days = 19 * 365 + 364
	saved_target.age_group = 1
	saved_target.set_save_value_raw(7, 50)
	var saved := rules.combat.resolve_monster_attack(attacker, definition, 0, saved_target, race, caste, ScriptedRng.new([0, 0, 0, 0, 0]))
	assert_true(saved.special_saved, "an inclusive save-slot-seven success negates Classic monster aging")
	assert_equal([saved_target.age_days, saved_target.age_group], [19 * 365 + 364, 1], "a successful aging save leaves age state unchanged")
	assert_equal(saved_target.current_health, 19, "a saved aging special has no dialog boundary and commits ordinary damage immediately")

	var same_band_target := CharacterState.new("character.same-band-aging-target", "Same Band Target", 20, 20)
	same_band_target.race_id = race.id
	same_band_target.caste_id = caste.id
	same_band_target.age_days = 15 * 365
	same_band_target.age_group = 1
	same_band_target.set_save_value_raw(7, 50)
	var same_band := rules.combat.resolve_monster_attack(attacker, definition, 0, same_band_target, race, caste, ScriptedRng.new([0, 0, 0, 0, 32_767]))
	assert_true(same_band.special_applied and not same_band.damage_deferred, "failed aging that remains in the same band does not invent a dialog boundary")
	assert_equal([same_band_target.age_days, same_band_target.age_group, same_band_target.current_health], [15 * 365 + 2, 1, 19], "same-band aging and physical damage commit in the original attack call")

	var monster_target := MonsterState.new("monster.aging-target", definition.id, "Monster Target", 20, 20, 2, 10)
	var monster_rng := ScriptedRng.new([0, 0, 0])
	var monster_resolution := rules.combat.resolve_monster_attack_monster(attacker, definition, 0, monster_target, definition, monster_rng)
	assert_equal([monster_resolution.special_code, monster_resolution.special_potency, monster_target.current_health], [17, 1, 19], "monster targets consume generic special potency but receive no party-only aging effect")
	assert_equal(monster_rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["combat.monster-attack.hit", "combat.monster-attack.damage", "combat.monster-attack.special-potency"], "monster-target special 17 stops after Castle's shared potency draw")


func _test_monster_status_attacks() -> void:
	var rules := RealmzRules.new()
	var status_cases := {
		1: [ConditionRules.RUNS_AWAY, 5],
		2: [ConditionRules.HELPLESS, 5],
		3: [ConditionRules.CURSED, 7],
		4: [ConditionRules.STUPID, 5],
		5: [ConditionRules.SLOW, 7],
		6: [ConditionRules.POISONED, 4],
		7: [ConditionRules.CONFUSED, 5],
		16: [ConditionRules.DISEASED, 4],
	}
	for special_code: int in status_cases:
		var attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, special_code)]
		var definition := MonsterDefinition.new("monster.status.%d" % special_code, special_code, "Status Monster", 4, 0, 10, 0, 0, _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _ints_size(3, 0), [], [], attacks)
		var attacker := MonsterState.new("monster.status.%d.instance" % special_code, definition.id, definition.name, 10, 10, 4, 10)
		var defender := CharacterState.new("character.status.%d" % special_code, "Status Target", 20, 20)
		defender.set_save_value_raw(status_cases[special_code][1], 50)
		var resolution := rules.combat.resolve_monster_attack(attacker, definition, 0, defender, null, null, ScriptedRng.new([0, 0, 0, 32_767, 32_767]))
		assert_true(resolution.special_applied, "failed save applies Classic monster status special %d" % special_code)
		assert_equal(defender.conditions.value(status_cases[special_code][0]), 4, "status special %d mutates its exact Classic condition slot" % special_code)
		assert_equal([resolution.special_save_index, resolution.special_condition_index, resolution.special_sound_id], [status_cases[special_code][1], status_cases[special_code][0], 630], "status special %d reports its Castle save, condition, and party sound" % special_code)

	var poison_attack: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 6)]
	var poison_definition := MonsterDefinition.new("monster.status.poison", 906, "Poison Monster", 4, 0, 10, 0, 0, _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _ints_size(3, 0), [], [], poison_attack)
	var poisoner := MonsterState.new("monster.status.poison.instance", poison_definition.id, poison_definition.name, 10, 10, 4, 10)
	var saved_target := CharacterState.new("character.status.saved", "Saved Target", 20, 20)
	saved_target.set_save_value_raw(4, 50)
	var saved_rng := ScriptedRng.new([0, 0, 0, 32_767, 0])
	var saved := rules.combat.resolve_monster_attack(poisoner, poison_definition, 0, saved_target, null, null, saved_rng)
	assert_true(saved.special_handled and saved.special_saved and not saved.special_applied, "a successful party save handles but negates the status special")
	assert_equal(saved_rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["combat.monster-attack.defender-luck", "combat.monster-attack.hit", "combat.monster-attack.damage", "combat.monster-attack.special-potency", "combat.monster-attack.special-save"], "party status attacks draw defender luck, damage, and generic potency before the save")

	var permanent_target := CharacterState.new("character.status.permanent", "Permanent Target", 20, 20)
	permanent_target.set_save_value_raw(4, 0)
	permanent_target.conditions.set_value(ConditionRules.POISONED, -1)
	var permanent := rules.combat.resolve_monster_attack(poisoner, poison_definition, 0, permanent_target, null, null, ScriptedRng.new([0, 0, 0, 32_767, 32_767]))
	assert_equal([permanent.special_saved, permanent.special_blocked, permanent.special_block_reason, permanent.special_announced], [false, true, &"permanent_condition", false], "a failed save is still consumed before Castle's permanent-condition sentinel blocks the status")
	assert_equal([permanent_target.conditions.value(ConditionRules.POISONED), permanent_target.current_health], [-1, 19], "a permanent status remains unchanged while ordinary physical damage still commits")

	var near_cap := CharacterState.new("character.status.near-cap", "Near Cap", 20, 20)
	near_cap.set_save_value_raw(4, 0)
	near_cap.conditions.set_value(ConditionRules.POISONED, 29)
	var exceeded := rules.combat.resolve_monster_attack(poisoner, poison_definition, 0, near_cap, null, null, ScriptedRng.new([0, 0, 0, 32_767, 32_767]))
	assert_equal([near_cap.conditions.value(ConditionRules.POISONED), exceeded.special_condition_before, exceeded.special_condition_after], [33, 29, 33], "Castle's corrected party gate checks the starting duration rather than capping the result at thirty")
	var capped := CharacterState.new("character.status.capped", "Capped", 20, 20)
	capped.set_save_value_raw(4, 0)
	capped.conditions.set_value(ConditionRules.POISONED, 30)
	var capped_result := rules.combat.resolve_monster_attack(poisoner, poison_definition, 0, capped, null, null, ScriptedRng.new([0, 0, 0, 32_767, 32_767]))
	assert_equal([capped.conditions.value(ConditionRules.POISONED), capped_result.special_applied, capped_result.special_announced, capped_result.special_block_reason], [30, false, true, &"party_condition_cap"], "a party duration already at thirty does not stack but still announces the failed special")

	var target_saves := _ints_size(8, 0)
	var target_immunities := _ints_size(6, 0)
	var target_definition := MonsterDefinition.new("monster.status.target", 907, "Status Target", 4, 0, 10, 0, 0, _ints_size(8, 0), target_saves, target_immunities, _ints_size(3, 0), [], [], [])
	var monster_target := MonsterState.new("monster.status.target.instance", target_definition.id, target_definition.name, 20, 20, 4, 10)
	monster_target.conditions.set_value(ConditionRules.POISONED, 30)
	var monster_status := rules.combat.resolve_monster_attack_monster(poisoner, poison_definition, 0, monster_target, target_definition, ScriptedRng.new([0, 0, 32_767, 32_767]))
	assert_equal([monster_target.conditions.value(ConditionRules.POISONED), monster_status.special_applied, monster_status.special_sound_id], [34, true, 630], "monster status durations stack without the party's thirty-round gate")

	var disease_attack: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 16)]
	var disease_definition := MonsterDefinition.new("monster.status.disease", 916, "Disease Monster", 4, 0, 10, 0, 0, _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _ints_size(3, 0), [], [], disease_attack)
	var diseaser := MonsterState.new("monster.status.disease.instance", disease_definition.id, disease_definition.name, 10, 10, 4, 10)
	var diseased_monster := MonsterState.new("monster.status.disease-target", target_definition.id, target_definition.name, 20, 20, 4, 10)
	var disease := rules.combat.resolve_monster_attack_monster(diseaser, disease_definition, 0, diseased_monster, target_definition, ScriptedRng.new([0, 0, 32_767, 32_767]))
	assert_equal(disease.special_sound_id, 684, "Castle uses sound 684 only when disease affects a monster target")

	target_immunities[4] = 1
	var immune_definition := MonsterDefinition.new("monster.status.immune", 908, "Immune Target", 4, 0, 10, 0, 0, _ints_size(8, 0), target_saves, target_immunities, _ints_size(3, 0), [], [], [])
	var immune_target := MonsterState.new("monster.status.immune.instance", immune_definition.id, immune_definition.name, 20, 20, 4, 10)
	var immune_rng := ScriptedRng.new([0, 0, 32_767, 32_767])
	var immune := rules.combat.resolve_monster_attack_monster(poisoner, poison_definition, 0, immune_target, immune_definition, immune_rng)
	assert_true(immune.special_saved and not immune.special_applied, "monster spell immunity uses the save-family index and negates poison")
	assert_equal(immune_rng.snapshot().draw_count, 4, "monster immunity still consumes Castle's save roll")
	var permanent_monster := MonsterState.new("monster.status.permanent.instance", target_definition.id, target_definition.name, 20, 20, 4, 10)
	permanent_monster.conditions.set_value(ConditionRules.POISONED, -1)
	var permanent_monster_result := rules.combat.resolve_monster_attack_monster(poisoner, poison_definition, 0, permanent_monster, target_definition, ScriptedRng.new([0, 0, 32_767, 32_767]))
	assert_equal([permanent_monster_result.special_block_reason, permanent_monster.conditions.value(ConditionRules.POISONED), permanent_monster.current_health], [&"permanent_condition", -1, 19], "the negative permanent sentinel blocks monster status mutation but not ordinary physical damage")

	var stupid_attack: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 4)]
	var stupid_definition := MonsterDefinition.new("monster.status.stupid", 904, "Stupid Monster", 4, 0, 10, 0, 0, _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _ints_size(3, 0), [], [], stupid_attack)
	var stupefier := MonsterState.new("monster.status.stupid.instance", stupid_definition.id, stupid_definition.name, 10, 10, 4, 10)
	var undead_flags := _ints_size(8, 0)
	undead_flags[1] = 1
	var undead_definition := MonsterDefinition.new("monster.status.undead", 910, "Undead Target", 4, 0, 10, 0, 0, undead_flags, target_saves, _ints_size(6, 0), _ints_size(3, 0), [], [], [])
	var undead_target := MonsterState.new("monster.status.undead.instance", undead_definition.id, undead_definition.name, 20, 20, 4, 10)
	var undead_rng := ScriptedRng.new([0, 0, 32_767, 32_767])
	var undead := rules.combat.resolve_monster_attack_monster(stupefier, stupid_definition, 0, undead_target, undead_definition, undead_rng)
	assert_true(undead.special_saved and not undead.special_applied, "Castle's undead type flag automatically saves against mental status special 4")
	assert_equal(undead_rng.snapshot().draw_count, 4, "the undead auto-save is evaluated after consuming the save roll")

	var curse_attack: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 3)]
	var curse_definition := MonsterDefinition.new("monster.status.curse", 903, "Curse Monster", 4, 0, 10, 0, 0, _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _ints_size(3, 0), [], [], curse_attack)
	var curser := MonsterState.new("monster.status.curse.instance", curse_definition.id, curse_definition.name, 10, 10, 4, 10)
	var averaged_saves := _ints_size(8, 60)
	var averaged_definition := MonsterDefinition.new("monster.status.average", 909, "Average Target", 4, 0, 10, 0, 0, _ints_size(8, 0), averaged_saves, _ints_size(6, 0), _ints_size(3, 0), [], [], [])
	var averaged_target := MonsterState.new("monster.status.average.instance", averaged_definition.id, averaged_definition.name, 20, 20, 4, 10)
	var averaged := rules.combat.resolve_monster_attack_monster(curser, curse_definition, 0, averaged_target, averaged_definition, ScriptedRng.new([0, 0, 32_767, 0]))
	assert_equal([averaged.special_save_index, averaged.special_save_chance, averaged.special_saved], [7, 60, true], "monster special save seven uses Castle's integer average of the six authored saves")

	var resistant_target := MonsterState.new("monster.status.resistant.instance", target_definition.id, target_definition.name, 20, 20, 4, 10, 0, 101)
	var resistant_rng := ScriptedRng.new([0, 0, 32_767])
	var resisted := rules.combat.resolve_monster_attack_monster(poisoner, poison_definition, 0, resistant_target, target_definition, resistant_rng)
	assert_equal([resisted.hit, resisted.damage, resisted.special_condition_index, resisted.special_blocked, resisted.special_block_reason, resistant_target.current_health], [false, 0, ConditionRules.POISONED, true, &"magic_resistance", 20], "a monster target above 100 magic resistance turns the entire special attack into Castle's whiff while retaining diagnostic identity")
	assert_equal(resistant_rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["combat.monster-attack.hit", "combat.monster-attack.damage", "combat.monster-attack.special-potency"], "the resistance whiff occurs after potency but before the monster save draw")

	var restored_target := CharacterState.from_data(near_cap.to_data())
	assert_not_null(restored_target, "a status-mutated character survives the central state serialization boundary")
	assert_equal(restored_target.conditions.value(ConditionRules.POISONED), 33, "save restoration preserves the exact status duration")


func _test_monster_resource_drains() -> void:
	var rules := RealmzRules.new()
	var empty8 := _ints_size(8, 0)
	var empty6 := _ints_size(6, 0)
	var empty3 := _ints_size(3, 0)
	var spell_attack: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 8)]
	var spell_definition := MonsterDefinition.new("monster.resource.spell", 908, "Spell Drainer", 4, 0, 10, 0, 0, empty8, empty8, empty6, empty3, [], [], spell_attack)
	var spell_attacker := MonsterState.new("monster.resource.spell.instance", spell_definition.id, spell_definition.name, 20, 20, 4, 10, 0, 0, 2)
	var spell_target := CharacterState.new("character.resource.spell", "Spell Target", 20, 20)
	spell_target.maximum_spell_points = 20
	spell_target.spell_points = 20
	spell_target.set_save_value_raw(6, 0)
	var spell_rng := ScriptedRng.new([0, 0, 0, 32_767, 32_767])
	var spell_result := rules.combat.resolve_monster_attack(spell_attacker, spell_definition, 0, spell_target, null, null, spell_rng)
	assert_equal([spell_result.special_code, spell_result.special_save_index, spell_result.special_saved, spell_result.special_resource], [8, 6, false, &"spell_points"], "Classic spell drain uses save slot six and identifies spell energy")
	assert_equal([spell_result.special_amount, spell_result.special_target_before, spell_result.special_target_after], [12, 20, 8], "spell drain takes three points per attacker hit die, capped by the target balance")
	assert_equal([spell_result.special_actor_before, spell_result.special_actor_after, spell_attacker.maximum_spell_points], [2, 14, 2], "Castle lets drained spell points raise the attacker above its normal maximum")
	assert_equal([spell_target.spell_points, spell_target.current_health, spell_target.lifetime_record.damage_taken, spell_target.lifetime_record.hits_taken], [8, 19, 1, 1], "spell drain and ordinary physical damage commit once through the lifetime record owner")
	assert_equal(spell_rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["combat.monster-attack.defender-luck", "combat.monster-attack.hit", "combat.monster-attack.damage", "combat.monster-attack.special-potency", "combat.monster-attack.special-save"], "spell drain preserves Castle's defender-luck and shared potency-before-save order")
	var restored_attacker := MonsterState.from_data(spell_attacker.to_data())
	assert_not_null(restored_attacker, "a spell drainer above its normal maximum survives central combat-state serialization")
	assert_equal([restored_attacker.spell_points, restored_attacker.maximum_spell_points], [14, 2], "restoration preserves Castle's uncapped drained spell energy")

	var saved_spell_target := CharacterState.new("character.resource.spell-saved", "Saved Spell Target", 20, 20)
	saved_spell_target.maximum_spell_points = 20
	saved_spell_target.spell_points = 20
	saved_spell_target.set_save_value_raw(6, 100)
	var saved_spell := rules.combat.resolve_monster_attack(spell_attacker, spell_definition, 0, saved_spell_target, null, null, ScriptedRng.new([0, 0, 0, 32_767, 0]))
	assert_true(saved_spell.special_saved and not saved_spell.special_applied, "an inclusive slot-six save negates spell drain")
	assert_equal(saved_spell_target.spell_points, 20, "saved spell drain leaves the target balance unchanged")
	var empty_spell_target := CharacterState.new("character.resource.spell-empty", "Empty Spell Target", 20, 20)
	empty_spell_target.set_save_value_raw(6, 0)
	var empty_spell_rng := ScriptedRng.new([0, 0, 0, 32_767, 32_767])
	var empty_spell := rules.combat.resolve_monster_attack(spell_attacker, spell_definition, 0, empty_spell_target, null, null, empty_spell_rng)
	assert_true(not empty_spell.special_saved and not empty_spell.special_applied and not empty_spell.special_announced, "a failed spell-drain save against an empty balance produces no false result announcement")
	assert_equal(empty_spell_rng.snapshot().draw_count, 5, "Castle rolls defender luck and the spell-drain save before testing whether the target has spell points")

	var monster_saves := _ints_size(8, 0)
	var monster_target_definition := MonsterDefinition.new("monster.resource.target", 909, "Spell Target Monster", 2, 0, 10, 0, 0, empty8, monster_saves, empty6, empty3, [], [], [])
	var monster_spell_target := MonsterState.new("monster.resource.target.instance", monster_target_definition.id, monster_target_definition.name, 20, 20, 2, 10, 0, 0, 8)
	var monster_spell_attacker := MonsterState.new("monster.resource.spell.monster-attacker", spell_definition.id, spell_definition.name, 20, 20, 4, 10, 0, 0, 2)
	var monster_spell := rules.combat.resolve_monster_attack_monster(monster_spell_attacker, spell_definition, 0, monster_spell_target, monster_target_definition, ScriptedRng.new([0, 0, 32_767, 32_767]))
	assert_equal([monster_spell.special_save_index, monster_spell.special_amount, monster_spell_target.spell_points, monster_spell_attacker.spell_points], [6, 8, 0, 10], "monster spell drain uses the sixth save family and transfers the available balance")

	var experience_attack: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 9)]
	var experience_definition := MonsterDefinition.new("monster.resource.experience", 909, "Experience Drainer", 4, 0, 10, 0, 0, empty8, empty8, empty6, empty3, [], [], experience_attack)
	var experience_attacker := MonsterState.new("monster.resource.experience.instance", experience_definition.id, experience_definition.name, 20, 20, 4, 10)
	var experience_target := CharacterState.new("character.resource.experience", "Experience Target", 20, 20)
	experience_target.experience = 100
	experience_target.set_save_value_raw(5, 0)
	var experience_result := rules.combat.resolve_monster_attack(experience_attacker, experience_definition, 0, experience_target, null, null, ScriptedRng.new([0, 0, 0, 32_767, 32_767]))
	assert_equal([experience_result.special_save_index, experience_result.special_resource, experience_result.special_amount], [5, &"experience", 400], "Classic experience drain removes twenty points per attacker maximum stamina after save five")
	assert_equal([experience_result.special_target_before, experience_result.special_target_after, experience_target.experience], [100, -300, -300], "experience drain subtracts from earned experience without a zero floor")
	assert_equal([experience_result.special_announced, experience_result.special_sound_id], [true, 630], "a failed experience drain requests Castle result sound 630")
	var restored_experience := CharacterState.from_data(experience_target.to_data())
	assert_not_null(restored_experience, "negative drained experience survives the central character-state boundary")
	assert_equal(restored_experience.experience, -300, "restoration preserves the exact drained experience value")
	var saved_experience_target := CharacterState.new("character.resource.experience-saved", "Saved Experience Target", 20, 20)
	saved_experience_target.experience = 100
	saved_experience_target.set_save_value_raw(5, 100)
	var saved_experience := rules.combat.resolve_monster_attack(experience_attacker, experience_definition, 0, saved_experience_target, null, null, ScriptedRng.new([0, 0, 0, 32_767, 0]))
	assert_true(saved_experience.special_saved and not saved_experience.special_applied, "an inclusive slot-five save negates experience drain")
	assert_equal([saved_experience_target.experience, saved_experience.special_sound_id], [100, 0], "saved experience drain changes no experience and requests no result sound")

	var monster_experience_target := MonsterState.new("monster.resource.experience-target", monster_target_definition.id, monster_target_definition.name, 20, 20, 2, 10)
	var monster_experience_rng := ScriptedRng.new([0, 0, 32_767])
	var monster_experience := rules.combat.resolve_monster_attack_monster(experience_attacker, experience_definition, 0, monster_experience_target, monster_target_definition, monster_experience_rng)
	assert_equal([monster_experience.special_handled, monster_experience.special_block_reason, monster_experience_target.current_health], [true, &"party_target_only", 19], "experience drain has no monster-target case but ordinary physical damage still lands")
	assert_equal(monster_experience_rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["combat.monster-attack.hit", "combat.monster-attack.damage", "combat.monster-attack.special-potency"], "monster-target experience drain stops after the shared potency draw without inventing a save")


func _test_monster_charm_attacks() -> void:
	var rules := RealmzRules.new()
	var empty8 := _ints_size(8, 0)
	var empty6 := _ints_size(6, 0)
	var empty3 := _ints_size(3, 0)
	var attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 10)]
	var definition := MonsterDefinition.new("monster.charm", 910, "Charmer", 4, 0, 10, 0, 0, empty8, empty8, empty6, empty3, [], [], attacks)
	var hostile := MonsterState.new("monster.charm.hostile", definition.id, definition.name, 20, 20, 4, 10, 0, 0, 0, true)
	var character := CharacterState.new("character.charm", "Charm Target", 20, 20)
	character.set_save_value_raw(0, 0)
	var charm_rng := ScriptedRng.new([0, 0, 0, 0, 0])
	var charmed := rules.combat.resolve_monster_attack(hostile, definition, 0, character, null, null, charm_rng)
	assert_true(character.traitor and charmed.special_applied, "failed save zero makes a loyal party character adopt the hostile attacker's allegiance")
	assert_equal([charmed.special_save_index, charmed.special_allegiance_before, charmed.special_allegiance_after, charmed.special_announced], [0, false, true, true], "party charm exposes Castle's allegiance transition and first-charm feedback")
	assert_equal(charm_rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["combat.monster-attack.defender-luck", "combat.monster-attack.hit", "combat.monster-attack.damage", "combat.monster-attack.special-potency", "combat.monster-attack.special-save"], "charm retains defender luck and the shared potency draw before its save")
	var restored := CharacterState.from_data(character.to_data())
	assert_not_null(restored, "battle allegiance survives the central character serialization boundary")
	assert_true(restored.traitor, "save restoration preserves an in-progress charmed character")

	var protected := CharacterState.new("character.charm-protected", "Protected Target", 20, 20)
	protected.set_save_value_raw(0, 0)
	var saved := rules.combat.resolve_monster_attack(hostile, definition, 0, protected, null, null, ScriptedRng.new([0, 0, 0, 0, 0]), 50)
	assert_true(saved.special_saved and not protected.traitor, "party charm resistance adds fifty to save zero before the inclusive roll")

	var friendly := MonsterState.new("monster.charm.friendly", definition.id, "Friendly Charmer", 20, 20, 4, 10, 0, 0, 0, false)
	var target_definition := MonsterDefinition.new("monster.charm.target", 911, "Charm Target Monster", 2, 0, 10, 0, 0, empty8, empty8, empty6, empty3, [], [], [])
	var monster_target := MonsterState.new("monster.charm.target.instance", target_definition.id, target_definition.name, 20, 20, 2, 10, 0, 0, 0, true)
	var monster_charm := rules.combat.resolve_monster_attack_monster(friendly, definition, 0, monster_target, target_definition, ScriptedRng.new([0, 0, 0, 0]))
	assert_true(not monster_target.traitor and monster_charm.special_applied, "failed monster charm adopts the attacking monster's allegiance")
	assert_true(monster_charm.special_announced, "monster-target charm reports every failed save as Castle does")
	var undead_flags := _ints_size(8, 0)
	undead_flags[1] = 1
	var undead_definition := MonsterDefinition.new("monster.charm.undead", 912, "Undead", 2, 0, 10, 0, 0, undead_flags, empty8, empty6, empty3, [], [], [])
	var undead := MonsterState.new("monster.charm.undead.instance", undead_definition.id, undead_definition.name, 20, 20, 2, 10, 0, 0, 0, true)
	var undead_result := rules.combat.resolve_monster_attack_monster(friendly, definition, 0, undead, undead_definition, ScriptedRng.new([0, 0, 0, 32_767]))
	assert_true(undead_result.special_saved and undead.traitor, "undead automatically save against charm after consuming the source save roll")


func _test_monster_elemental_attacks() -> void:
	var rules := RealmzRules.new()
	var correction_fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/oracle/monster-elemental-protection-correction.json"))
	assert_true(correction_fixture is Dictionary, "the elemental-protection fidelity decision has a parseable source-observation fixture")
	assert_equal([int(correction_fixture["castleSourceObservation"]["monsterColdThroughMentalCommittedElementalDamage"]), int(correction_fixture["castleSourceObservation"]["monsterColdThroughMentalDisplayedElementalDamage"])], [8, 4], "the source fixture records Castle's committed-versus-displayed monster-target anomaly")
	var element_cases := {
		11: [ConditionRules.FIRE_PROTECTION, &"fire"],
		12: [ConditionRules.COLD_PROTECTION, &"cold"],
		13: [ConditionRules.ELECTRICAL_PROTECTION, &"electrical"],
		14: [ConditionRules.CHEMICAL_PROTECTION, &"chemical"],
		15: [ConditionRules.MENTAL_PROTECTION, &"mental"],
	}
	for special_code: int in element_cases:
		var attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 8, 0, special_code)]
		var definition := MonsterDefinition.new("monster.element.%d" % special_code, 900 + special_code, "Elemental Monster", 4, 0, 10, 0, 0, _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _ints_size(3, 0), [], [], attacks)
		var attacker := MonsterState.new("monster.element.%d.instance" % special_code, definition.id, definition.name, 20, 20, 4, 10)
		var defender := CharacterState.new("character.element.%d" % special_code, "Element Target", 20, 20)
		defender.set_save_value_raw(special_code - 10, 100)
		defender.conditions.set_value(element_cases[special_code][0], 1)
		var rng := ScriptedRng.new([0, 0, 0, 0, 32_767, 0])
		var result := rules.combat.resolve_monster_attack(attacker, definition, 0, defender, null, null, rng)
		assert_equal([result.special_element, result.special_damage_rolled, result.special_damage_amount, result.special_display_amount], [element_cases[special_code][1], 8, 2, 2], "elemental special %d applies save then matching protection to committed damage" % special_code)
		assert_equal(defender.current_health, 17, "elemental special %d commits one physical plus two protected elemental damage" % special_code)
		assert_equal(rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["combat.monster-attack.defender-luck", "combat.monster-attack.hit", "combat.monster-attack.damage", "combat.monster-attack.special-potency", "combat.monster-attack.special-damage", "combat.monster-attack.special-save"], "elemental special %d rolls defender luck and damage before its save" % special_code)

	var cold_attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 8, 0, 12)]
	var cold_definition := MonsterDefinition.new("monster.element.cold", 912, "Cold Monster", 4, 0, 10, 0, 0, _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _ints_size(3, 0), [], [], cold_attacks)
	var cold_attacker := MonsterState.new("monster.element.cold.attacker", cold_definition.id, cold_definition.name, 20, 20, 4, 10)
	var protected_definition := MonsterDefinition.new("monster.element.protected", 913, "Protected Monster", 2, 0, 10, 0, 0, _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _ints_size(3, 0), [], [], [])
	var protected_monster := MonsterState.new("monster.element.protected.instance", protected_definition.id, protected_definition.name, 20, 20, 2, 10)
	protected_monster.conditions.set_value(ConditionRules.COLD_PROTECTION, 1)
	var corrected := rules.combat.resolve_monster_attack_monster(cold_attacker, cold_definition, 0, protected_monster, protected_definition, ScriptedRng.new([0, 0, 0, 32_767, 32_767]))
	var chosen_damage: int = correction_fixture["realmz2ChosenResult"]["allProtectedTargetsCommittedElementalDamage"]
	assert_equal([corrected.special_damage_rolled, corrected.special_damage_amount, corrected.special_display_amount, protected_monster.current_health], [8, chosen_damage, chosen_damage, 19 - chosen_damage], "FD-COMBAT-001 makes monster cold protection reduce actual damage as well as its reported amount")


func _test_monster_permanent_afflictions() -> void:
	var rules := RealmzRules.new()
	var empty8 := _ints_size(8, 0)
	var empty6 := _ints_size(6, 0)
	var empty3 := _ints_size(3, 0)
	var blind_attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 18)]
	var blind_definition := MonsterDefinition.new("monster.blind", 918, "Blinder", 4, 0, 10, 0, 0, empty8, empty8, empty6, empty3, [], [], blind_attacks)
	var blinder := MonsterState.new("monster.blind.instance", blind_definition.id, blind_definition.name, 20, 20, 4, 10)
	var blind_target := CharacterState.new("character.blind", "Blind Target", 20, 20)
	blind_target.set_save_value_raw(7, 0)
	var blinded := rules.combat.resolve_monster_attack(blinder, blind_definition, 0, blind_target, null, null, ScriptedRng.new([0, 0, 0, 0, 32_767]))
	assert_equal([blinded.special_condition_index, blinded.special_condition_after, blind_target.conditions.value(ConditionRules.BLIND), blind_target.current_health], [ConditionRules.BLIND, -1, -1, 19], "failed special save permanently blinds a party target before ordinary damage")
	assert_true(blinded.special_announced and blinded.special_sound_id == 0, "blindness reports its result without inventing a sound")

	var stone_attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1, 0, 19)]
	var stone_definition := MonsterDefinition.new("monster.stone", 919, "Petrifier", 4, 0, 10, 0, 0, empty8, empty8, empty6, empty3, [], [], stone_attacks)
	var petrifier := MonsterState.new("monster.stone.instance", stone_definition.id, stone_definition.name, 20, 20, 4, 10)
	var stone_target := CharacterState.new("character.stone", "Stone Target", 20, 20)
	stone_target.set_save_value_raw(7, 0)
	var petrified := rules.combat.resolve_monster_attack(petrifier, stone_definition, 0, stone_target, null, null, ScriptedRng.new([0, 0, 0, 0, 32_767]))
	assert_equal([stone_target.current_health, stone_target.conditions.value(ConditionRules.TURNED_TO_STONE), petrified.killed, petrified.physical_damage_skipped, petrified.total_damage()], [0, -1, true, true, 0], "party petrification force-kills with Castle's permanent sentinel and skips the rolled physical damage")

	var target_definition := MonsterDefinition.new("monster.affliction.target", 920, "Affliction Target", 2, 0, 10, 0, 0, empty8, empty8, empty6, empty3, [], [], [])
	var monster_target := MonsterState.new("monster.affliction.target.instance", target_definition.id, target_definition.name, 20, 20, 2, 10)
	var monster_stone := rules.combat.resolve_monster_attack_monster(petrifier, stone_definition, 0, monster_target, target_definition, ScriptedRng.new([0, 0, 0, 32_767]))
	assert_equal([monster_target.current_health, monster_target.conditions.value(ConditionRules.TURNED_TO_STONE), monster_stone.killed, monster_stone.physical_damage_skipped], [0, 1, true, true], "monster petrification retains Castle's positive stone sentinel and force-kill path")
	var resistant_target := MonsterState.new("monster.affliction.resistant", target_definition.id, target_definition.name, 20, 20, 2, 10, 0, 101)
	var resistant := rules.combat.resolve_monster_attack_monster(petrifier, stone_definition, 0, resistant_target, target_definition, ScriptedRng.new([0, 0, 0]))
	assert_equal([resistant.hit, resistant.special_block_reason, resistant_target.current_health], [false, &"magic_resistance", 20], "above-100 monster resistance whiffs permanent affliction and ordinary damage after potency")


func _test_conditions_time_and_persistence() -> void:
	var rules := RealmzRules.new()
	var torch_party := PartyState.new("map.test", Vector2i.ZERO, [])
	torch_party.conditions.set_value(ConditionRules.PARTY_TORCH_LIT, 3)
	var torch_events := rules.conditions.tick_party(torch_party)
	assert_equal(torch_party.conditions.value(ConditionRules.PARTY_TORCH_LIT), 1, "Torch Lit receives Castle's generic and torch-specific hourly decrements")
	assert_false(torch_events.any(func(event: DomainEvent) -> bool: return event.kind == &"party_condition_expired"), "a positive torch remainder does not publish expiration")
	torch_party.conditions.set_value(ConditionRules.PARTY_TORCH_LIT, 2)
	torch_events = rules.conditions.tick_party(torch_party)
	assert_equal(torch_party.conditions.value(ConditionRules.PARTY_TORCH_LIT), 0, "a two-point torch expires after the two source-ordered decrements")
	assert_equal(torch_events.filter(func(event: DomainEvent) -> bool: return event.kind == &"party_condition_expired" and event.payload.get("condition") == ConditionRules.PARTY_TORCH_LIT).size(), 1, "torch expiration publishes once when the specific decrement reaches zero")
	torch_party.conditions.set_value(ConditionRules.PARTY_TORCH_LIT, 1)
	torch_events = rules.conditions.tick_party(torch_party)
	assert_equal(torch_party.conditions.value(ConditionRules.PARTY_TORCH_LIT), 0, "a one-point torch expires in the generic pass without becoming negative")
	assert_equal(torch_events.filter(func(event: DomainEvent) -> bool: return event.kind == &"party_condition_expired" and event.payload.get("condition") == ConditionRules.PARTY_TORCH_LIT).size(), 1, "generic-pass torch expiration is not duplicated")
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
	var state := GameState.new(party, RealmzClock.new()); state.dungeon_heading = 3; state.dungeon_multiview = false
	var events := rules.conditions.tick_party(party)
	assert_equal(character.current_health, 4, "regeneration occurs before disease and poison damage")
	assert_equal(character.spell_points, 4, "energy drain occurs before energy absorption")
	assert_equal(character.conditions.value(ConditionRules.POISONED), 1, "positive character conditions decay after applying their effect")
	assert_equal(party.conditions.value(0), 0, "party conditions decay through the same fixed owner")
	assert_true(events.size() >= 4, "condition ticks publish domain observations")
	assert_equal(rules.clock.change_fatigue(party, 500), 135, "fatigue is clamped to Castle's upper bound")
	state.combat = CombatState.new("battle.test", _monsters([MonsterState.new("monster.saved", "monster.test", "Saved Monster", 3, 6)]))
	var parsed: Variant = JSON.parse_string(JSON.stringify(state.to_data()))
	var restored := GameState.from_data(parsed)
	assert_not_null(restored, "the complete expanded game aggregate survives JSON")
	assert_equal(restored.to_data(), state.to_data(), "expanded party, condition, wealth, and combat state round-trip exactly")


func _test_inventory_economy_and_treasure() -> void:
	var icon_definition := ItemDefinition.new("item.icon-lookup", 0, "Icon Test"); var unidentified_icon_cases: Array[Vector2i] = [Vector2i(7, 2), Vector2i(18, 12), Vector2i(31, 20), Vector2i(38, 35), Vector2i(55, 50), Vector2i(84, 82), Vector2i(94, 89), Vector2i(520, 527), Vector2i(548, 546), Vector2i(6105, 6100), Vector2i(6118, 6110), Vector2i(6125, 6122), Vector2i(6138, 6137), Vector2i(6186, 6183), Vector2i(6194, 6190), Vector2i(6199, 6197), Vector2i(6205, 6202), Vector2i(6209, 12009), Vector2i(6163, 6162), Vector2i(6176, 6177)]
	for icon_case: Vector2i in unidentified_icon_cases:
		icon_definition.icon_id = icon_case.x; assert_equal(icon_definition.visible_icon_id(false), icon_case.y, "Castle's unidentified CICN %d uses its generic image" % icon_case.x); assert_equal(icon_definition.visible_icon_id(true), icon_case.x, "identified CICN %d retains authored art" % icon_case.x)
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
	assert_equal(rules.inventory.combat_equipment(character, _items([item])).equipped_damage_bonus, 4, "equipped item damage is summed as Castle attack.c does")
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
	assert_equal(rules.economy.item_price(item, shop, true), 15_000, "shop sale halves base cost and never uses inflation above 100 percent")
	var worn_instance := ItemInstance.new("item-instance.priced-wand", item.id, 1, false, true)
	assert_equal(rules.economy.shop_sell_price(item, worn_instance, 150), 7_500, "charged-item sale value uses Castle's current-to-authored charge ratio after halving")
	worn_instance.charges = -1
	assert_equal(rules.economy.shop_sell_price(item, worn_instance, 150), 7_500, "Castle's later absolute-cost step preserves a negative current-charge ratio as positive value")
	worn_instance.charges = 1
	worn_instance.identified = false
	assert_equal(rules.economy.shop_sell_price(item, worn_instance, 150), 150, "unidentified shop sales retain Castle's one-fiftieth penalty")
	var uncharged := ItemDefinition.new("item.uncharged", 2, "Uncharged")
	uncharged.cost = 101
	uncharged.initial_charges = 0
	assert_equal(rules.economy.shop_sell_price(uncharged, ItemInstance.new("item-instance.uncharged", uncharged.id, 0, false, true), 100), 50, "zero-charge definitions retain full condition instead of Castle's undefined 0/0 conversion")
	var treasure := TreasureDefinition.new("treasure.test", 1, _strings([item.id]), -5, -10, 2, 0)
	var treasure_roll := rules.economy.roll_treasure(treasure, ScriptedRng.new([0, 32_767]))
	assert_equal(treasure_roll.experience, 1, "negative treasure values encode a one-to-absolute-value roll")
	assert_equal(treasure_roll.wealth.gold, 10, "signed random treasure can reach its inclusive maximum")


func _test_projectile_resolution() -> void:
	var rules := RealmzRules.new()
	var caster := CharacterState.new("character.projectile-rules", "Archer", 20, 20)
	caster.level = 4
	caster.missile = 20
	var caste := _caste()
	caste.gets_missile_bonus = true
	var item := ItemDefinition.new("item.projectile-rules", 104, "Bow +1")
	item.damage_bonus = 1
	var spell := SpellDefinition.new("spell.projectile-rules", 4101, "Arrow")
	spell.spell_class = 9
	spell.damage_type = 9
	spell.target_type = 1
	spell.damage_min = 4
	spell.damage_max = 4
	spell.fixed_target_count = 3
	spell.to_hit_bonus = 10
	var target := MonsterState.new("monster.projectile-rules", "monster.projectile-rules", "Target", 30, 30, 1, 1)
	var rng := ScriptedRng.new([0, 0, 0, 0, 0, 0])
	var result := rules.magic.resolve_character_projectile(caster, caste, item, target, spell, 1, rng)
	assert_not_null(result, "ordinary class-9 physical missiles use the dedicated resolver")
	assert_equal([result.hit_count, result.miss_count, result.damage_per_hit, result.total_damage, target.current_health], [3, 0, 6, 18, 12], "Castle rolls projectile damage and caste bonus once, then reuses that damage for every fixed hit")
	assert_equal(rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["combat.projectile.duration", "combat.projectile.damage", "combat.projectile.caste-bonus", "combat.projectile.miss.0", "combat.projectile.miss.1", "combat.projectile.miss.2"], "projectile RNG order keeps shared damage before per-hit dodge checks")
	var shielded := MonsterState.new("monster.projectile-shield", "monster.projectile-rules", "Shielded", 30, 30, 1, 1)
	shielded.conditions.set_value(ConditionRules.SHIELD_FROM_PROJECTILES, -1)
	var shield_rng := ScriptedRng.new([0, 0, 0])
	var shield_result := rules.magic.resolve_character_projectile(caster, caste, item, shielded, spell, 1, shield_rng)
	assert_equal([shield_result.hit_count, shield_result.miss_count, shielded.current_health], [0, 1, 30], "projectile shield terminates the repeated volley before damage")
	assert_equal(shield_rng.snapshot().draw_count, 3, "an automatic projectile-shield miss consumes no dodge roll")


func _test_combat_magic_and_monsters() -> void:
	var rules := RealmzRules.new()
	var attacker := CharacterState.new("character.attacker", "Attacker", 10, 10)
	attacker.luck = 1
	attacker.hand_to_hand = 4
	var definition := _monster_definition()
	var defender := MonsterState.new("monster.defender", definition.id, definition.name, 5, 5, 1, 8, 5)
	var sword := ItemDefinition.new("item.sword", 25, "Sword")
	sword.item_type = 2
	sword.damage_bonus = 2
	sword.vs_small = 1
	var sword_instance := rules.inventory.add_item(attacker, sword, "item-instance.sword", true)
	assert_true(rules.inventory.equip(attacker, sword_instance.id, sword), "the melee fixture occupies Castle's weapon type")
	var equipment := rules.inventory.combat_equipment(attacker, _items([sword]))
	var attack := rules.combat.resolve_character_attack(attacker, equipment, defender, definition, ScriptedRng.new([0, 0, 0, 0, 0]))
	assert_true(attack.hit, "inclusive Realmz attack roll hits at the computed chance")
	assert_equal(attack.chance, 56, "attack chance combines base, equipment, luck, and armor")
	assert_equal(attack.damage, 3, "melee damage combines the equipped magic plus and Castle's physical weapon roll")
	assert_equal(attack.critical_rolls, [1, 1], "player melee preserves Castle's two post-damage critical draws even while critical-skill content remains unavailable")
	defender.current_health = 5
	var fumble := rules.combat.resolve_character_attack(attacker, equipment, defender, definition, ScriptedRng.new([0, 0, 1609]), 0, false, true, true)
	assert_true(fumble.fumbled and not fumble.hit and fumble.damage == 0, "an armed player roll from 51 through 59 fumbles and forces the attack to miss")
	assert_equal(fumble.fumble_roll, 55, "the player fumble range uses Castle's level-scaled Rand contract")
	assert_equal(defender.current_health, 5, "a fumbled player attack commits no damage")
	sword.cursed_item_id = "item.cursed-replacement"
	var cursed_fumble := rules.combat.resolve_character_attack(attacker, equipment, defender, definition, ScriptedRng.new([0, 0, 1609, 0, 0, 0]), 0, false, true, true)
	assert_false(cursed_fumble.fumbled, "a cursed melee weapon cannot leave the character on a fumble roll")
	assert_equal(cursed_fumble.fumble_block_reason, &"cursed_weapon", "the failed cursed removal remains observable without cancelling the attack")
	assert_true(cursed_fumble.hit and defender.current_health < 5, "Castle continues the ordinary attack when cursed removal fails")
	sword.cursed_item_id = ""
	defender.current_health = 5
	var full_queue := rules.combat.resolve_character_attack(attacker, equipment, defender, definition, ScriptedRng.new([0, 0, 1609, 0, 0, 0]), 0, false, true, false)
	assert_false(full_queue.fumbled, "a full twenty-item battle queue suppresses another player fumble")
	assert_equal(full_queue.fumble_block_reason, &"fumble_queue_full", "the queue-capacity gate has a stable diagnostic identity")
	assert_true(full_queue.hit and defender.current_health < 5, "Castle continues the ordinary attack when its fumble queue is full")
	sword_instance.equipped = false
	defender.current_health = 5
	var unarmed_rng := ScriptedRng.new([0, 0, 1609, 0, 0, 0])
	var unarmed_fumble_roll := rules.combat.resolve_character_attack(attacker, rules.inventory.combat_equipment(attacker, _items([sword])), defender, definition, unarmed_rng, 0, false, true, true)
	assert_false(unarmed_fumble_roll.fumbled, "an unarmed character cannot fumble despite a source-range roll")
	assert_equal([unarmed_fumble_roll.fumble_roll, unarmed_rng.snapshot().draw_count], [55, 6], "an unarmed character still consumes the fumble draw before ordinary damage")
	sword_instance.equipped = true
	definition.magic_to_hit = 3
	var magic_block := rules.combat.resolve_character_attack(attacker, equipment, defender, definition, ScriptedRng.new([0, 0]))
	assert_true(magic_block.blocked, "a hit with an insufficient weapon plus stops before damage")
	assert_equal(magic_block.block_reason, &"classic_magic_weapon_required", "magical weapon requirements have a stable source-backed failure identity")
	definition.magic_to_hit = 0
	definition.required_weapon = -1
	var blunt_block := rules.combat.resolve_character_attack(attacker, equipment, defender, definition, ScriptedRng.new([0, 0]))
	assert_equal(blunt_block.block_reason, &"classic_blunt_weapon_required", "an armed non-blunt hit cannot damage a blunt-only monster")
	sword.blunt = -1
	var blunt_hit := rules.combat.resolve_character_attack(attacker, equipment, defender, definition, ScriptedRng.new([0, 0, 0, 0, 0]))
	assert_true(blunt_hit.hit and not blunt_hit.blocked, "an armed blunt weapon satisfies the source-backed family requirement")
	sword.blunt = 0
	definition.required_weapon = 26
	var specific_block := rules.combat.resolve_character_attack(attacker, equipment, defender, definition, ScriptedRng.new([0, 0]))
	assert_equal(specific_block.block_reason, &"classic_specific_weapon_required", "the wrong specific weapon cannot satisfy the authored Item Number")
	definition.required_weapon = 25
	var specific_hit := rules.combat.resolve_character_attack(attacker, equipment, defender, definition, ScriptedRng.new([0, 0, 0, 0, 0]))
	assert_true(specific_hit.hit and not specific_hit.blocked, "FD-COMBAT-003 compares the authored requirement directly with the Classic item ID")
	sword.classic_id = 147
	definition.required_weapon = -109
	var high_specific_hit := rules.combat.resolve_character_attack(attacker, equipment, defender, definition, ScriptedRng.new([0, 0, 0, 0, 0]))
	assert_true(high_specific_hit.hit and not high_specific_hit.blocked, "specific Item Numbers above 127 preserve their signed-byte package representation")
	sword.classic_id = 25
	definition.required_weapon = 0
	var friendly := MonsterState.new("monster.friendly", definition.id, "Friendly", 5, 5, 1, 8, 5, 0, 0, false)
	var hostile := MonsterState.new("monster.hostile", definition.id, "Hostile", 5, 5, 1, 8, 5, 0, 0, true)
	var monster_attack := rules.combat.resolve_monster_attack_monster(friendly, definition, 0, hostile, definition, ScriptedRng.new([0, 0]))
	assert_true(monster_attack.hit, "opposed-traitor monsters use the same source-backed attack resolution")
	assert_equal(hostile.current_health, 4, "friendly monster attacks mutate hostile combat state")
	var monster_weapon := ItemDefinition.new("item.monster-fumble", 701, "Monster Fumble Blade")
	monster_weapon.item_type = 2
	monster_weapon.vs_small = 1
	var monster_fumbler := MonsterState.new("monster.fumbler", definition.id, definition.name, 5, 5, 4, 8, 0)
	var monster_fumble_target := MonsterState.new("monster.fumble-target", definition.id, definition.name, 5, 5, 1, 8, 0)
	var monster_fumble := rules.combat.resolve_monster_attack_monster(monster_fumbler, definition, 0, monster_fumble_target, definition, ScriptedRng.new([0, 942]), MonsterAttackContext.new(monster_weapon), true)
	assert_true(monster_fumble.fumbled and not monster_fumble.hit, "an armed monster roll from 21 through 34 fumbles and forces a miss")
	assert_equal(monster_fumble.fumble_roll, 23, "monster fumbles use Castle's hit-dice-scaled Rand contract")
	assert_equal(monster_fumble_target.current_health, 5, "a monster fumble commits no physical damage")
	var unarmed_monster_rng := ScriptedRng.new([0, 942, 0])
	var unarmed_monster_fumble_roll := rules.combat.resolve_monster_attack_monster(monster_fumbler, definition, 0, monster_fumble_target, definition, unarmed_monster_rng, MonsterAttackContext.new(), true)
	assert_false(unarmed_monster_fumble_roll.fumbled, "an unarmed monster cannot fumble despite a source-range roll")
	assert_equal([unarmed_monster_fumble_roll.fumble_roll, unarmed_monster_rng.snapshot().draw_count], [23, 3], "an unarmed monster still consumes the fumble draw before authored damage")
	defender.current_health = 5
	defender.conditions.set_value(ConditionRules.HELPLESS, -1)
	var helpless := rules.combat.resolve_character_attack(attacker, equipment, defender, definition, ScriptedRng.new([0, 32_767, 0, 0, 0]))
	assert_true(helpless.killed, "helpless defenders are hit and take their remaining health")

	var zero_blade := ItemDefinition.new("item.zero-blade", 26, "Zero Blade")
	zero_blade.item_type = 2
	zero_blade.vs_small = 1
	var armed := CharacterState.new("character.armed-zero", "Armed", 10, 10)
	armed.luck = 1
	armed.hand_to_hand = 20
	var zero_instance := rules.inventory.add_item(armed, zero_blade, "item-instance.zero-blade", true)
	rules.inventory.equip(armed, zero_instance.id, zero_blade)
	var armed_target := MonsterState.new("monster.armed-target", definition.id, definition.name, 20, 20, 1, 8, 0)
	var armed_attack := rules.combat.resolve_character_attack(armed, rules.inventory.combat_equipment(armed, _items([zero_blade])), armed_target, definition, ScriptedRng.new([0, 0, 0, 0, 0]))
	assert_equal(armed_attack.damage, 1, "a real zero-plus melee weapon does not accidentally invoke hand-to-hand damage")

	var ring := ItemDefinition.new("item.damage-ring", 601, "Damage Ring")
	ring.item_type = 0
	ring.damage_bonus = 3
	var unarmed := CharacterState.new("character.unarmed-ring", "Unarmed", 10, 10)
	unarmed.luck = 1
	unarmed.hand_to_hand = 4
	var ring_instance := rules.inventory.add_item(unarmed, ring, "item-instance.damage-ring", true)
	rules.inventory.equip(unarmed, ring_instance.id, ring)
	var unarmed_target := MonsterState.new("monster.unarmed-target", definition.id, definition.name, 20, 20, 1, 8, 0)
	var unarmed_attack := rules.combat.resolve_character_attack(unarmed, rules.inventory.combat_equipment(unarmed, _items([ring])), unarmed_target, definition, ScriptedRng.new([0, 0, 32_767, 0, 0]))
	assert_equal(unarmed_attack.damage, 7, "a nonweapon damage item contributes its bonus without suppressing the hand-to-hand roll")
	definition.required_weapon = -2
	var unarmed_requirement := rules.combat.resolve_character_attack(unarmed, rules.inventory.combat_equipment(unarmed, _items([ring])), unarmed_target, definition, ScriptedRng.new([0, 0]))
	assert_equal(unarmed_requirement.block_reason, &"classic_sharp_weapon_required", "FD-COMBAT-003 does not let an unarmed attack bypass a bladed-weapon requirement")
	definition.required_weapon = 0
	var armor := ItemDefinition.new("item.target-armor", 201, "Target Armor")
	armor.item_type = 4
	armor.armor_bonus = 5
	var character_target := CharacterState.new("character.armored-target", "Armored", 20, 20)
	character_target.conditions.set_value(ConditionRules.PROTECTION_FROM_EVIL, 1)
	var armor_instance := rules.inventory.add_item(character_target, armor, "item-instance.target-armor", true)
	rules.inventory.equip(character_target, armor_instance.id, armor)
	var versus_character := rules.combat.resolve_character_attack_character(unarmed, rules.inventory.combat_equipment(unarmed, _items([ring, armor])), character_target, rules.inventory.combat_equipment(character_target, _items([ring, armor])), ScriptedRng.new([0, 0, 0, 0, 0]))
	assert_equal(versus_character.chance, 61, "character defense derives equipped armor without applying Castle's monster-only protection-from-evil penalty")

	var second_blade := ItemDefinition.new("item.second-blade", 27, "Second Blade")
	second_blade.item_type = 2
	var second_instance := rules.inventory.add_item(armed, second_blade, "item-instance.second-blade", true)
	rules.inventory.equip(armed, second_instance.id, second_blade)
	var conflicting_equipment := rules.inventory.combat_equipment(armed, _items([zero_blade, second_blade]))
	assert_false(conflicting_equipment.valid, "multiple equipped type-2 items fail instead of selecting a weapon by inventory accident")
	assert_equal(conflicting_equipment.error_code, &"multiple_melee_weapons", "conflicting Classic melee slots have a stable failure identity")

	var elemental_definition := MonsterDefinition.new("monster.elemental-target", 2, "Elemental Target", 2, 1, 8, 0, 0, _ints_size(8, 0), _ints([100, 0, 0, 0, 0, 0, 0, 0]), _ints_size(6, 0), _ints_size(3, 0), [], [], [MonsterAttackDefinition.new(1, 1)])
	var elemental_target := MonsterState.new("monster.elemental-target.instance", elemental_definition.id, elemental_definition.name, 20, 20, 1, 8, 0)
	elemental_target.conditions.set_value(ConditionRules.FIRE_PROTECTION, 1)
	second_instance.equipped = false
	zero_blade.heat = 8
	var record_damage_before := armed.lifetime_record.damage_given; var record_hits_before := armed.lifetime_record.hits_given; var elemental_attack := rules.combat.resolve_character_attack(armed, rules.inventory.combat_equipment(armed, _items([zero_blade])), elemental_target, elemental_definition, ScriptedRng.new([0, 0, 32_767, 0, 0, 0, 0]))
	assert_equal(elemental_attack.weapon_effects[0].get("amount"), 2, "FD-COMBAT-002 applies the monster defender's fire save after protection")
	assert_equal([elemental_attack.damage, armed.lifetime_record.damage_given - record_damage_before, armed.lifetime_record.hits_given - record_hits_before], [3, 3, 1], "corrected elemental mitigation commits the same damage and hit once to the source-owned lifetime record")

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
	var spell_group := rules.magic.resolve_character_targeted_spell(attacker, SpellTargetSelection.for_monster(defender, definition), spell, 1, 1, ScriptedRng.new([0, 0, 32_767, 32_767]))
	var spell_result := spell_group.resolutions[0]
	assert_true(spell_result.cast, "a funded spell commits its cost")
	assert_false(spell_result.resisted, "failed resistance reaches damage resolution")
	assert_equal(spell_result.damage, 2, "matching elemental protection halves damage")
	assert_equal(attacker.spell_points, 8, "spell points are mutated inside the rule operation")
	var cannot_spell := SpellDefinition.new("spell.cannot-monster-save", 1307, "Cannot Flag")
	cannot_spell.cost = 0
	cannot_spell.damage_min = 4
	cannot_spell.damage_max = 4
	cannot_spell.damage_type = 1
	cannot_spell.spell_class = 1
	cannot_spell.cannot = 3
	defender = MonsterState.new("monster.cannot-save-target", definition.id, definition.name, 8, 8, 1, 8, 0)
	defender.set_save_value(0, 100)
	var cannot_rng := ScriptedRng.new([0, 0, 0])
	var cannot_group := rules.magic.resolve_character_targeted_spell(attacker, SpellTargetSelection.for_monster(defender, definition), cannot_spell, 1, cannot_spell.classic_tier(), cannot_rng)
	var cannot_result := cannot_group.resolutions[0]
	assert_false(cannot_result.saved, "savevs consumes the roll but forces the monster's save to fail when Classic cannot is greater than one")
	assert_equal(cannot_rng.snapshot().draw_count, 3, "the forced failed save still consumes Castle's duration, damage, and save draws")
	assert_equal(cannot_result.damage, 4, "the forced failed save leaves ordinary monster spell damage unhalved")
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
	definition.cast_percent = 100
	var adjacent_choice_rng := ScriptedRng.new([0, 0])
	assert_equal(rules.monsters.choose_action(built, definition, adjacent_choice_rng, true), &"cast", "an adjacent enemy makes Castle fall through a successful missile roll into casting")
	assert_equal(adjacent_choice_rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["monster.ai.missile", "monster.ai.cast"], "adjacent missile fallback preserves Castle's two-draw action order")
	var range_fallback_rng := ScriptedRng.new([0])
	assert_equal(rules.monsters.choose_action_after_missile(built, definition, range_fallback_rng), &"cast", "an out-of-range or unaffordable missile resumes at Castle's casting choice")
	assert_equal(range_fallback_rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["monster.ai.cast"], "post-missile fallback does not repeat the missile-choice draw")
	built.conditions.set_value(ConditionRules.STUPID, -1)
	var blocked_cast_rng := ScriptedRng.new([0, 0])
	assert_equal(rules.monsters.choose_action(built, definition, blocked_cast_rng, true), &"advance", "a condition-blocked cast falls through to physical action")
	assert_equal(blocked_cast_rng.snapshot().draw_count, 2, "Castle consumes the cast-choice roll before checking the blocking condition")
	built.conditions.set_value(ConditionRules.STUPID, 0)
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


func _progression_race() -> RaceDefinition:
	var hit_modifiers := _ints_size(8, 0)
	hit_modifiers[0] = 7
	var ability_bonuses := _ints_size(14, 0)
	ability_bonuses[0] = 2
	ability_bonuses[5] = 1
	var attribute_bonuses := _ints_size(6, 0)
	attribute_bonuses[0] = 15
	attribute_bonuses[3] = 17
	var conditions := _ints_size(40, 0)
	conditions[4] = 6
	return RaceDefinition.new("race.progression", 2, "Progression Race", hit_modifiers, _ints_size(8, 0), attribute_bonuses, _attribute_limits(), conditions, [Vector2i(18, 18), Vector2i(25, 25), Vector2i(35, 35), Vector2i(50, 50), Vector2i(70, 70)], _age_changes(), 100, false, 10, 0, 70, 0, 1, 3, false, 0, 0, 0, 0, "", [], ability_bonuses)


func _progression_caste() -> CasteDefinition:
	var conditions := _ints_size(40, 0)
	conditions[4] = 2
	var initial_abilities := _ints_size(14, 0)
	initial_abilities[0] = 10
	initial_abilities[3] = 5
	initial_abilities[5] = 20
	var level_abilities := _ints_size(14, 0)
	level_abilities[0] = 4
	var victory := _ints_size(30, 0)
	victory[2] = 12_345
	return CasteDefinition.new("caste.progression", 2, "Progression Caste", _ints_size(8, 0), _ints_size(6, 0), _attribute_limits(), conditions, Vector2i(1, 1), Vector2i(0, 1), Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, [], [], [], 0, 1, 0, 1, 50, 0, 0, 3, 0, true, false, 0, 0, 0, Vector2i(0, 8), "", [], initial_abilities, level_abilities, victory)


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
