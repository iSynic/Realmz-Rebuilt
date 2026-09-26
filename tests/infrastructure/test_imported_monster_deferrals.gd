extends RealmzTestCase


func run() -> void:
	_test_imported_attack_count_round_trips_while_fresh_package_stays_strict()
	_test_imported_battle_missing_monster_is_deferred_with_exact_warning()
	_test_imported_monster_out_of_catalog_item_is_deferred_with_exact_slot_warning()
	_test_schema_v4_native_monster_values()


func _test_imported_attack_count_round_trips_while_fresh_package_stays_strict() -> void:
	var record := _monster_record(127)
	var decoder := PackageEncounterContentDecoder.new()
	var strict_result: Variant = decoder.decode_monsters([record])
	assert_equal(strict_result, null, "fresh packages reject an attack count outside the fixed Classic attack rows")
	var imported_result: Variant = decoder.decode_monsters([record], true)
	assert_not_null(imported_result, "imported package retains raw attack count despite the fixed attack rows")
	if imported_result != null:
		var monsters: Array[MonsterDefinition] = imported_result
		assert_equal(monsters[0].attack_count, 127, "runtime typed definition retains the exact signed-byte attack count")
		assert_equal(monsters[0].attacks().size(), 0, "the unavailable Classic attack rows are not fabricated")


func _test_imported_battle_missing_monster_is_deferred_with_exact_warning() -> void:
	var battle := BattleDefinition.new("classic.battle.2", 2, [BattleMonsterSlotDefinition.new(Vector2i(1, 1), "classic.monster.7", false)])
	var validator := PackageCrossReferenceValidator.new()
	var no_races: Array[RaceDefinition] = []
	var no_castes: Array[CasteDefinition] = []
	var no_items: Array[ItemDefinition] = []
	var no_spells: Array[SpellDefinition] = []
	var no_monsters: Array[MonsterDefinition] = []
	var battles: Array[BattleDefinition] = [battle]
	var no_treasures: Array[TreasureDefinition] = []
	var no_shops: Array[ShopDefinition] = []
	assert_false(validator.validate_rule_references(no_races, no_castes, no_items, no_spells, no_monsters, battles, no_treasures, no_shops, {}, false), "fresh package rejects a battle slot with no matching monster definition")
	validator.clear_warnings()
	assert_true(validator.validate_rule_references(no_races, no_castes, no_items, no_spells, no_monsters, battles, no_treasures, no_shops, {}, true), "imported package retains the battle slot and admits deferred loading")
	assert_equal(validator.warnings.size(), 1, "deferred missing monster produces one diagnostic")
	if not validator.warnings.is_empty():
		var warning: ScenarioCompatibilityWarning = validator.warnings[0]
		assert_equal([warning.source_kind, warning.source_id, warning.field, warning.slot, warning.target_kind, warning.target_id], [&"battle", "classic.battle.2", "monsterSlots", 0, &"monster", "classic.monster.7"], "warning retains exact battle slot source and missing monster identity")


func _test_imported_monster_out_of_catalog_item_is_deferred_with_exact_slot_warning() -> void:
	var record := _monster_record(0, ["classic.item.1139", "", "", "", "", ""])
	var decoder := PackageEncounterContentDecoder.new()
	var decoded: Variant = decoder.decode_monsters([record], true)
	assert_not_null(decoded, "imported typed decoder preserves the native item ID above 999")
	if decoded == null: return
	var monsters: Array[MonsterDefinition] = decoded
	assert_equal(monsters[0].item_id_at(0), "classic.item.1139", "runtime definition retains exact imported item reference")
	var no_items: Array[ItemDefinition] = []
	var no_spells: Array[SpellDefinition] = []
	var validator := PackageCrossReferenceValidator.new()
	assert_false(validator.validate_monster_record_references(monsters, no_items, no_spells, false), "fresh content still rejects the missing item")
	validator.clear_warnings()
	assert_true(validator.validate_monster_record_references(monsters, no_items, no_spells, true), "imported content defers the unavailable item until the monster is consumed")
	assert_equal(validator.warnings.size(), 1, "missing imported monster item yields one compatibility warning")
	if not validator.warnings.is_empty():
		var warning: ScenarioCompatibilityWarning = validator.warnings[0]
		assert_equal([warning.source_kind, warning.source_id, warning.field, warning.slot, warning.target_kind, warning.target_id], [&"monster", "classic.monster.7", "itemIds", 0, &"item", "classic.item.1139"], "warning identifies exact native monster item slot and target")


func _test_schema_v4_native_monster_values() -> void:
	var record := _monster_record(0)
	record["magicToHit"] = -128
	record["randomWeaponTable"] = 32768
	var decoder := PackageEncounterContentDecoder.new()
	assert_equal(decoder.decode_monsters([record], true, 3), null, "v3 limits remain unchanged")
	assert_equal(decoder.decode_monsters([record], false, 4), null, "authored v4 remains strict")
	var decoded: Variant = decoder.decode_monsters([record], true, 4)
	assert_not_null(decoded, "v4 imports preserve full native monster ranges")
	if decoded != null:
		assert_equal([decoded[0].magic_to_hit, decoded[0].random_weapon_table], [-128, 32768], "native signed-byte and signed-short magnitude survive typed decoding")


func _monster_record(attack_count: int, item_ids: Array[String] = ["", "", "", "", "", ""]) -> Dictionary:
	return {
		"id": "classic.monster.7", "classicId": 7, "classicNameId": 0, "name": "Dagger",
		"description": "", "notOnMenu": false, "hitDice": 1, "staminaBonus": 0, "agility": 0,
		"movementMaximum": 0, "armor": 0, "magicResistance": 0, "requiredWeapon": 0,
		"magicToHit": 0, "traitor": false, "size": 0, "typeFlags": [0, 0, 0, 0, 0, 0, 0, 0],
		"attackCount": attack_count, "magicAttackCount": 0, "attacks": [], "damageBonus": 0,
		"castPercent": 0, "runPercent": 0, "surrenderPercent": 0, "missilePercent": 0,
		"canSummon": 0, "saves": [0, 0, 0, 0, 0, 0], "spellImmunities": [0, 0, 0, 0, 0, 0],
		"conditions": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		"money": [0, 0, 0], "spellIds": [], "itemIds": item_ids,
		"weaponId": "", "randomWeaponTable": 0, "iconId": 0, "spellPoints": 0, "experience": 0,
		"deathMacro": 0,
	}
