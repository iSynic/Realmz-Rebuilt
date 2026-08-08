extends RealmzTestCase


func run() -> void:
	_test_arithmetic_and_ranges()
	_test_character_creation_and_leveling()
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
	var created := rules.characters.create_character("character.hero", "Hero", race, caste, 1, ScriptedRng.new([0, 0, 0, 0, 0, 0, 0, 0]))
	assert_not_null(created, "a valid race/caste pair constructs a direct Realmz character")
	assert_equal([created.brawn, created.knowledge, created.judgment, created.agility, created.vitality, created.luck], [2, 1, 1, 1, 1, 1], "attribute rolls apply gender and min/max constraints in Castle order")
	assert_equal(created.maximum_health, 1, "initial stamina uses the caste die")
	assert_equal(created.to_hit, -10, "caste and brawn to-hit bonuses are combined")
	assert_equal(created.magic_resistance, 5, "race and caste magic resistance inputs are applied")
	assert_equal(created.maximum_load, 500, "Classic load capacity retains its 500 minimum")
	assert_equal(created.age_days, 18 * 365, "age is rolled from the race range selected by caste")
	assert_equal(created.inventory().size(), 1, "caste starting equipment becomes stable item instances")
	assert_equal(rules.characters.strength_bonuses(30, 5).damage_bonus, 5, "caste strength caps brawn damage without changing hit bonus")

	var race_conditions := _ints_size(40, 0)
	race_conditions[4] = 2
	race_conditions[5] = 3
	race_conditions[10] = -3
	var caste_conditions := _ints_size(40, 0)
	caste_conditions[5] = 1
	caste_conditions[6] = 2
	var defense_race := RaceDefinition.new("race.defense", 2, "Defense Race", _ints_size(8, 0), _ints([100, -200, 0, 0, 0, 0, 0, 100]), _ints_size(6, 0), _attribute_limits(), race_conditions, [Vector2i(18, 18)], 100)
	var defense_caste := CasteDefinition.new("caste.defense", 2, "Defense Caste", _ints([100, 0, 0, 0, 0, 0, 0, 100]), _ints_size(6, 0), _attribute_limits(), caste_conditions, Vector2i(8, 8), Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO)
	var defended := rules.characters.create_character("character.defense", "Defender", defense_race, defense_caste, 1, ScriptedRng.new([0, 0, 0, 0, 0, 0, 0, 0]))
	assert_equal([defended.save_value(0), defended.save_value(1), defended.save_value(7)], [120, -99, 120], "creation saves combine race and caste values within Castle's bounds")
	assert_equal(defended.conditions.value(4), 2, "racial starting conditions retain their authored duration")
	assert_equal(defended.conditions.value(5), -1, "caste condition level one replaces a racial value with a permanent condition")
	assert_equal(defended.conditions.value(6), 0, "later caste condition thresholds do not become level-one conditions")
	assert_equal(defended.conditions.value(10), -3, "negative racial starting conditions retain their authored strength")

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
	rules.clock.camp(state, 8)
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
	return RaceDefinition.new("race.test", 1, "Test Race", _ints_size(8, 0), _ints_size(8, 0), _ints_size(6, 0), _attribute_limits(), _ints_size(40, 0), ages, 100, false, 10, 5, 0, 0, 1, 3)


func _caste() -> CasteDefinition:
	var spellcasters: Array[Vector3i] = []
	return CasteDefinition.new("caste.test", 1, "Test Caste", _ints_size(8, 0), _ints_size(6, 0), _attribute_limits(), _ints_size(40, 0), Vector2i(8, 8), Vector2i(10, 2), Vector2i(0, 1), Vector2i(2, 6), Vector2i(4, 1), spellcasters, _ints([2]), _strings(["item.start"]), 0, 1, 0, 1, 0, 3, 0, 3, 12, true, false, 0, 0, 0, Vector2i(0, 5))


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
