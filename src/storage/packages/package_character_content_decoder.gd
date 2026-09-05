## Decodes item, Race, Caste, and spell catalogs.

class_name PackageCharacterContentDecoder
extends PackageDecoderBase

const ApplicationSpellText := preload("res://src/storage/packages/classic_application_spell_text.gd")

func decode_items(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content items must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "name", "unidentifiedName", "description", "iconId", "itemType", "strengthBonus", "blunt", "hands", "luckBonus", "movementBonus", "armorBonus", "magicResistanceBonus", "damageBonus", "spellPointBonus", "soundId", "weight", "cost", "initialCharges", "cursedItemId", "magical", "itemCategoryMaskLow", "itemCategoryMaskHigh", "raceRestrictions", "casteRestrictions", "specificRaceId", "specificCasteId", "raceClassOnly", "casteClassOnly", "versusSmall", "versusLarge", "heat", "cold", "electric", "versusUndead", "versusDemonDevil", "versusEvil", "special", "weightPerCharge", "dropOnEmpty"]
	var integer_fields: Array[String] = ["classicId", "iconId", "itemType", "strengthBonus", "blunt", "hands", "luckBonus", "movementBonus", "armorBonus", "magicResistanceBonus", "damageBonus", "spellPointBonus", "soundId", "weight", "cost", "initialCharges", "itemCategoryMaskLow", "itemCategoryMaskHigh", "raceRestrictions", "casteRestrictions", "raceClassOnly", "casteClassOnly", "versusSmall", "versusLarge", "heat", "cold", "electric", "versusUndead", "versusDemonDevil", "versusEvil", "weightPerCharge"]
	var result: Array[ItemDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		var item := _decode_item_record(value_record, fields, integer_fields, ids)
		if item == null:
			return null
		result.append(item)
	return result

func _decode_item_record(value_record: Variant, fields: Array[String], integer_fields: Array[String], ids: Dictionary) -> ItemDefinition:
	if not value_record is Dictionary:
		_reject("Item definition is not an object.")
		return null
	var record: Dictionary = value_record
	var integers_value: Variant = _validated_integer_fields(record, integer_fields, "Item definition")
	if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Item") or not record["unidentifiedName"] is String or record["unidentifiedName"].is_empty() or not record["description"] is String or not record["cursedItemId"] is String or not record["specificRaceId"] is String or not record["specificCasteId"] is String or not record["magical"] is bool or not record["dropOnEmpty"] is bool:
		_reject("Item definition is malformed or duplicated.")
		return null
	if integers_value["classicId"] <= 0 or record["id"] != "classic.item.%d" % integers_value["classicId"]:
		_reject("Item definition identity must match its positive Classic ID.")
		return null
	var special_value: Variant = _integer_array(record["special"], 5, "Item special values")
	if special_value == null:
		return null
	var integers: Dictionary = integers_value
	var special: Array[int] = special_value
	var item := ItemDefinition.new(record["id"], integers["classicId"], record["name"], record["unidentifiedName"], record["description"])
	item.icon_id = integers["iconId"]
	item.item_type = integers["itemType"]
	item.strength_bonus = integers["strengthBonus"]
	item.blunt = integers["blunt"]
	item.hands = integers["hands"]
	item.luck_bonus = integers["luckBonus"]
	item.movement_bonus = integers["movementBonus"]
	item.armor_bonus = integers["armorBonus"]
	item.magic_resistance_bonus = integers["magicResistanceBonus"]
	item.damage_bonus = integers["damageBonus"]
	item.spell_point_bonus = integers["spellPointBonus"]
	item.sound_id = integers["soundId"]
	item.weight = integers["weight"]
	item.cost = integers["cost"]
	item.initial_charges = integers["initialCharges"]
	item.cursed_item_id = record["cursedItemId"]
	item.magical = record["magical"]
	item.item_category_mask_low = integers["itemCategoryMaskLow"]
	item.item_category_mask_high = integers["itemCategoryMaskHigh"]
	item.race_restrictions = integers["raceRestrictions"]
	item.caste_restrictions = integers["casteRestrictions"]
	item.specific_race_id = record["specificRaceId"]
	item.specific_caste_id = record["specificCasteId"]
	item.race_class_only = integers["raceClassOnly"]
	item.caste_class_only = integers["casteClassOnly"]
	item.vs_small = integers["versusSmall"]
	item.vs_large = integers["versusLarge"]
	item.heat = integers["heat"]
	item.cold = integers["cold"]
	item.electric = integers["electric"]
	item.vs_undead = integers["versusUndead"]
	item.vs_demon_devil = integers["versusDemonDevil"]
	item.vs_evil = integers["versusEvil"]
	item.special_1 = special[0]
	item.special_2 = special[1]
	item.special_3 = special[2]
	item.special_4 = special[3]
	item.special_5 = special[4]
	item.weight_per_charge = integers["weightPerCharge"]
	item.drop_on_empty = record["dropOnEmpty"]
	return item

func decode_races(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content races must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "name", "description", "eligibleCasteIds", "hitModifiers", "abilityBonuses", "saveBonuses", "attributeBonuses", "attributeLimits", "conditionLevels", "ageRanges", "ageChanges", "maximumAge", "doesNotDie", "baseMovement", "magicResistance", "twoHandBonus", "missileBonus", "baseAttacks", "maximumAttacks", "canRegenerate", "defaultIconSet", "itemCategoryMasks", "descriptorFlags"]
	var integer_fields: Array[String] = ["classicId", "maximumAge", "baseMovement", "magicResistance", "twoHandBonus", "missileBonus", "baseAttacks", "maximumAttacks", "defaultIconSet", "descriptorFlags"]
	var result: Array[RaceDefinition] = []
	var ids: Dictionary = {}
	var classic_ids: Dictionary = {}
	var has_functional_rules: bool = false
	for value_record: Variant in value:
		var decoded := _decode_race_record(value_record, fields, integer_fields, ids, classic_ids)
		if decoded.is_empty():
			return null
		result.append(decoded["definition"])
		has_functional_rules = has_functional_rules or bool(decoded["functional"])
	if not result.is_empty() and not has_functional_rules:
		_reject("Content races cannot be a semantically empty 30-record table.")
		return null
	return result

func _decode_race_record(value_record: Variant, fields: Array[String], integer_fields: Array[String], ids: Dictionary, classic_ids: Dictionary) -> Dictionary:
	if not value_record is Dictionary:
		_reject("Race definition is not an object.")
		return {}
	var record: Dictionary = value_record
	var integers_value: Variant = _validated_integer_fields(record, integer_fields, "Race definition")
	if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Race") or not record["name"] is String or not record["description"] is String or not record["eligibleCasteIds"] is Array or not record["doesNotDie"] is bool or not record["canRegenerate"] is bool or not record["ageRanges"] is Array or record["ageRanges"].size() != 5 or not record["ageChanges"] is Array or record["ageChanges"].size() != 5:
		_reject("Race definition is malformed or duplicated.")
		return {}
	var classic_id: int = integers_value["classicId"]
	if classic_id < 1 or classic_id > 30 or classic_ids.has(classic_id) or record["id"] != "classic.race.%d" % classic_id:
		_reject("Race Classic IDs must uniquely cover 1 through 30.")
		return {}
	classic_ids[classic_id] = true
	var hit_value: Variant = _integer_array(record["hitModifiers"], 8, "Race hit modifiers")
	var abilities_value: Variant = _integer_array(record["abilityBonuses"], 14, "Race ability bonuses")
	var save_value: Variant = _integer_array(record["saveBonuses"], 8, "Race save bonuses")
	var bonus_value: Variant = _integer_array(record["attributeBonuses"], 6, "Race attribute bonuses")
	var limits_value: Variant = _integer_array(record["attributeLimits"], 12, "Race attribute limits")
	var conditions_value: Variant = _integer_array(record["conditionLevels"], 40, "Race condition levels")
	var masks_value: Variant = _integer_array(record["itemCategoryMasks"], 2, "Race item masks")
	if hit_value == null or abilities_value == null or save_value == null or bonus_value == null or limits_value == null or conditions_value == null or masks_value == null:
		return {}
	var ages: Array[Vector2i] = []
	for row: Variant in record["ageRanges"]:
		var pair_value: Variant = _integer_array(row, 2, "Race age range")
		if pair_value == null:
			return {}
		var pair: Array[int] = pair_value
		ages.append(Vector2i(pair[0], pair[1]))
	var age_changes: Array[PackedInt32Array] = []
	for row: Variant in record["ageChanges"]:
		var changes_value: Variant = _integer_array(row, 15, "Race age change")
		if changes_value == null:
			return {}
		var changes: Array[int] = changes_value
		age_changes.append(PackedInt32Array(changes))
	var integers: Dictionary = integers_value
	var masks: Array[int] = masks_value
	var eligible_castes: Array[String] = []
	for caste_id: Variant in record["eligibleCasteIds"]:
		if not caste_id is String or caste_id.is_empty():
			_reject("Race eligibility IDs must be non-empty strings.")
			return {}
		eligible_castes.append(caste_id)
	var functional: bool = integers["maximumAge"] != 0 or integers["baseMovement"] != 0 or integers["baseAttacks"] != 0 or integers["maximumAttacks"] != 0 or not eligible_castes.is_empty() or limits_value.any(func(number: int) -> bool: return number != 0)
	var definition := RaceDefinition.new(record["id"], integers["classicId"], record["name"], hit_value, save_value, bonus_value, limits_value, conditions_value, ages, age_changes, integers["maximumAge"], record["doesNotDie"], integers["baseMovement"], integers["magicResistance"], integers["twoHandBonus"], integers["missileBonus"], integers["baseAttacks"], integers["maximumAttacks"], record["canRegenerate"], integers["defaultIconSet"], masks[0], masks[1], integers["descriptorFlags"], record["description"], eligible_castes, abilities_value)
	return {"definition": definition, "functional": functional}

func decode_castes(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content castes must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "name", "description", "eligibleRaceIds", "initialAbilityValues", "levelAbilityDice", "victoryThresholds", "saveBonuses", "attributeBonuses", "attributeLimits", "conditionLevels", "staminaDice", "strengthValues", "dodgeValues", "toHitValues", "missileValues", "handToHandValues", "spellcasterRows", "attackLevels", "startingItemIds", "casteClass", "minimumAgeGroup", "movementBonus", "magicResistanceMultiplier", "twoHandBonus", "maximumStaminaBonus", "bonusAttacks", "maximumAttacks", "startMoney", "canUseMissile", "getsMissileBonus", "defaultIcon", "itemCategoryMasks"]
	var integer_fields: Array[String] = ["classicId", "casteClass", "minimumAgeGroup", "movementBonus", "magicResistanceMultiplier", "twoHandBonus", "maximumStaminaBonus", "bonusAttacks", "maximumAttacks", "startMoney", "defaultIcon"]
	var result: Array[CasteDefinition] = []
	var ids: Dictionary = {}
	var classic_ids: Dictionary = {}
	var has_functional_rules: bool = false
	for value_record: Variant in value:
		var decoded := _decode_caste_record(value_record, fields, integer_fields, ids, classic_ids)
		if decoded.is_empty():
			return null
		result.append(decoded["definition"])
		has_functional_rules = has_functional_rules or bool(decoded["functional"])
	if not result.is_empty() and not has_functional_rules:
		_reject("Content castes cannot be a semantically empty 30-record table.")
		return null
	return result

func _decode_caste_record(value_record: Variant, fields: Array[String], integer_fields: Array[String], ids: Dictionary, classic_ids: Dictionary) -> Dictionary:
	if not value_record is Dictionary:
		_reject("Caste definition is not an object.")
		return {}
	var record: Dictionary = value_record
	var integers_value: Variant = _validated_integer_fields(record, integer_fields, "Caste definition")
	if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Caste") or not record["name"] is String or not record["description"] is String or not record["eligibleRaceIds"] is Array or not record["canUseMissile"] is bool or not record["getsMissileBonus"] is bool or not record["spellcasterRows"] is Array or record["spellcasterRows"].size() != 4:
		_reject("Caste definition is malformed or duplicated.")
		return {}
	var classic_id: int = integers_value["classicId"]
	if classic_id < 1 or classic_id > 30 or classic_ids.has(classic_id) or record["id"] != "classic.caste.%d" % classic_id:
		_reject("Caste Classic IDs must uniquely cover 1 through 30.")
		return {}
	classic_ids[classic_id] = true
	var initial_abilities_value: Variant = _integer_array(record["initialAbilityValues"], 14, "Caste initial ability values")
	var level_abilities_value: Variant = _integer_array(record["levelAbilityDice"], 14, "Caste level ability dice")
	var victory_value: Variant = _integer_array(record["victoryThresholds"], 30, "Caste victory thresholds")
	var saves_value: Variant = _integer_array(record["saveBonuses"], 8, "Caste save bonuses")
	var bonuses_value: Variant = _integer_array(record["attributeBonuses"], 6, "Caste attribute bonuses")
	var limits_value: Variant = _integer_array(record["attributeLimits"], 12, "Caste attribute limits")
	var conditions_value: Variant = _integer_array(record["conditionLevels"], 40, "Caste condition levels")
	var stamina_value: Variant = _integer_array(record["staminaDice"], 2, "Caste stamina dice")
	var strength_value: Variant = _integer_array(record["strengthValues"], 2, "Caste strength values")
	var dodge_value: Variant = _integer_array(record["dodgeValues"], 2, "Caste dodge values")
	var to_hit_value: Variant = _integer_array(record["toHitValues"], 2, "Caste to-hit values")
	var missile_value: Variant = _integer_array(record["missileValues"], 2, "Caste missile values")
	var hand_value: Variant = _integer_array(record["handToHandValues"], 2, "Caste hand-to-hand values")
	var attacks_value: Variant = _integer_array(record["attackLevels"], 10, "Caste attack levels")
	var masks_value: Variant = _integer_array(record["itemCategoryMasks"], 2, "Caste item masks")
	var start_items_value: Variant = _string_list(record["startingItemIds"], "Caste starting item IDs")
	if initial_abilities_value == null or level_abilities_value == null or victory_value == null or saves_value == null or bonuses_value == null or limits_value == null or conditions_value == null or stamina_value == null or strength_value == null or dodge_value == null or to_hit_value == null or missile_value == null or hand_value == null or attacks_value == null or masks_value == null or start_items_value == null:
		return {}
	var spellcasters: Array[Vector3i] = []
	for row: Variant in record["spellcasterRows"]:
		var row_value: Variant = _integer_array(row, 3, "Caste spellcaster row")
		if row_value == null:
			return {}
		var values: Array[int] = row_value
		spellcasters.append(Vector3i(values[0], values[1], values[2]))
	var integers: Dictionary = integers_value
	var stamina: Array[int] = stamina_value
	var strength: Array[int] = strength_value
	var dodge: Array[int] = dodge_value
	var to_hit: Array[int] = to_hit_value
	var missile: Array[int] = missile_value
	var hand: Array[int] = hand_value
	var masks: Array[int] = masks_value
	var eligible_races: Array[String] = []
	for race_id: Variant in record["eligibleRaceIds"]:
		if not race_id is String or race_id.is_empty():
			_reject("Caste eligibility IDs must be non-empty strings.")
			return {}
		eligible_races.append(race_id)
	var functional: bool = integers["casteClass"] != 0 or integers["movementBonus"] != 0 or integers["maximumAttacks"] != 0 or integers["startMoney"] != 0 or not eligible_races.is_empty() or victory_value.any(func(number: int) -> bool: return number != 0) or limits_value.any(func(number: int) -> bool: return number != 0) or stamina_value.any(func(number: int) -> bool: return number != 0) or attacks_value.any(func(number: int) -> bool: return number != 0)
	var attributes := CasteDefinition.AttributeDefinition.new(saves_value, bonuses_value, limits_value, conditions_value, Vector2i(strength[0], strength[1]))
	var progression := CasteDefinition.ProgressionDefinition.new(Vector2i(stamina[0], stamina[1]), Vector2i(to_hit[0], to_hit[1]), Vector2i(dodge[0], dodge[1]), Vector2i(missile[0], missile[1]), Vector2i(hand[0], hand[1]), spellcasters, attacks_value, initial_abilities_value, level_abilities_value, victory_value)
	var definition := _build_caste_definition(record, integers, attributes, progression, start_items_value, eligible_races, masks)
	return {"definition": definition, "functional": functional}


func _build_caste_definition(record: Dictionary, integers: Dictionary, attributes: CasteDefinition.AttributeDefinition, progression: CasteDefinition.ProgressionDefinition, starting_items: Array[String], eligible_races: Array[String], masks: Array[int]) -> CasteDefinition:
	var definition := CasteDefinition.new(record["id"], integers["classicId"], record["name"], attributes, progression, starting_items)
	definition.description = record["description"]
	definition.eligible_race_ids = eligible_races.duplicate()
	definition.caste_class = integers["casteClass"]
	definition.minimum_age_group = integers["minimumAgeGroup"]
	definition.movement_bonus = integers["movementBonus"]
	definition.magic_resistance_multiplier = maxi(1, integers["magicResistanceMultiplier"])
	definition.two_hand_bonus = integers["twoHandBonus"]
	definition.maximum_stamina_bonus = integers["maximumStaminaBonus"]
	definition.bonus_attacks = integers["bonusAttacks"]
	definition.maximum_attacks = integers["maximumAttacks"]
	definition.start_money = integers["startMoney"]
	definition.can_use_missile = record["canUseMissile"]
	definition.gets_missile_bonus = record["getsMissileBonus"]
	definition.default_icon = integers["defaultIcon"]
	definition.item_category_mask_low = masks[0]
	definition.item_category_mask_high = masks[1]
	return definition

func decode_spells(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content spells must be an array.")
		return null
	var application_text_error: String = ApplicationSpellText.error_message()
	if not application_text_error.is_empty():
		_reject(application_text_error)
		return null
	var fields: Array[String] = ["id", "classicId", "name", "description", "rangeMin", "rangeMax", "queueIcon", "toHitBonus", "saveBonus", "fixedTargetCount", "canRotate", "saveAdjust", "cannot", "resistanceAdjust", "cost", "damageMin", "damageMax", "powerDamageMin", "powerDamageMax", "durationMin", "durationMax", "powerDurationMin", "powerDurationMax", "lookStart", "lookEnd", "soundStart", "soundEnd", "targetType", "size", "special", "damageType", "spellClass", "inCombat", "inCamp"]
	var integer_fields := fields.slice(1)
	integer_fields.erase("name")
	integer_fields.erase("description")
	integer_fields.erase("canRotate")
	integer_fields.erase("inCombat")
	integer_fields.erase("inCamp")
	var result: Array[SpellDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		var spell := _decode_spell_record(value_record, fields, integer_fields, ids)
		if spell == null:
			return null
		result.append(spell)
	return result

func _decode_spell_record(value_record: Variant, fields: Array[String], integer_fields: Array[String], ids: Dictionary) -> SpellDefinition:
	if not value_record is Dictionary:
		_reject("Spell definition is not an object.")
		return null
	var record: Dictionary = value_record
	var integers_value: Variant = _validated_integer_fields(record, integer_fields, "Spell definition")
	if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Spell") or not record["description"] is String or not record["canRotate"] is bool or not record["inCombat"] is bool or not record["inCamp"] is bool:
		_reject("Spell definition is malformed or duplicated.")
		return null
	var integers: Dictionary = integers_value
	if integers["classicId"] <= 0 or record["id"] != "classic.spell.%d" % integers["classicId"]:
		_reject("Spell definition identity must match its positive Classic ID.")
		return null
	var description: String = record["description"]
	if ApplicationSpellText.owns(integers["classicId"]):
		if not description.is_empty():
			_reject("Stock Realmz spell descriptions are application-owned and may not be embedded in a scenario package.")
			return null
		description = ApplicationSpellText.description(integers["classicId"])
		if description.is_empty():
			_reject("The bundled Classic spell-description catalog is unavailable: %s" % ApplicationSpellText.error_message())
			return null
	var spell := SpellDefinition.new(record["id"], integers["classicId"], record["name"], description)
	spell.range_min = integers["rangeMin"]
	spell.range_max = integers["rangeMax"]
	spell.queue_icon = integers["queueIcon"]
	spell.to_hit_bonus = integers["toHitBonus"]
	spell.save_bonus = integers["saveBonus"]
	spell.fixed_target_count = integers["fixedTargetCount"]
	spell.can_rotate = record["canRotate"]
	spell.save_adjust = integers["saveAdjust"]
	spell.cannot = integers["cannot"]
	spell.resistance_adjust = integers["resistanceAdjust"]
	spell.cost = integers["cost"]
	spell.damage_min = integers["damageMin"]
	spell.damage_max = integers["damageMax"]
	spell.power_damage_min = integers["powerDamageMin"]
	spell.power_damage_max = integers["powerDamageMax"]
	spell.duration_min = integers["durationMin"]
	spell.duration_max = integers["durationMax"]
	spell.power_duration_min = integers["powerDurationMin"]
	spell.power_duration_max = integers["powerDurationMax"]
	spell.look_start = integers["lookStart"]
	spell.look_end = integers["lookEnd"]
	spell.sound_start = integers["soundStart"]
	spell.sound_end = integers["soundEnd"]
	spell.target_type = integers["targetType"]
	spell.size = integers["size"]
	spell.special = integers["special"]
	spell.damage_type = integers["damageType"]
	spell.spell_class = integers["spellClass"]
	spell.in_combat = record["inCombat"]
	spell.in_camp = record["inCamp"]
	return spell
