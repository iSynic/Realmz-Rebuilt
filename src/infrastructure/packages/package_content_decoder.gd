class_name PackageContentDecoder
extends PackageDecoderBase

const ApplicationSpellText := preload("res://src/infrastructure/packages/classic_application_spell_text.gd")

func _construct_campaign_definition(value: Variant) -> CampaignDefinition:
	if not value is Dictionary:
		_reject("Content campaign metadata must be an object.")
		return null
	var record: Dictionary = value
	var fields: Array[String] = ["id", "name", "version", "author", "contact", "description", "splashAssetId", "recommendedPartyLevels", "maximumPartyLevels", "guidanceAuthored", "restrictions"]
	if not _exact_fields(record, fields) or not record["id"] is String or record["id"].is_empty() or not record["name"] is String or record["name"].is_empty() or not record["version"] is String or not record["author"] is String or not record["contact"] is Dictionary or not record["description"] is String or not record["splashAssetId"] is String or _integer(record["recommendedPartyLevels"]) < 0 or _integer(record["maximumPartyLevels"]) < 0 or not record["guidanceAuthored"] is bool or not record["restrictions"] is Dictionary:
		_reject("Campaign display metadata is malformed.")
		return null
	var contact: Dictionary = record["contact"]
	if not _exact_fields(contact, ["email", "web", "date", "fee"]) or not contact["email"] is String or not contact["web"] is String or not contact["date"] is String or not contact["fee"] is String:
		_reject("Campaign contact metadata is malformed.")
		return null
	var restrictions: Dictionary = record["restrictions"]
	var restriction_fields: Array[String] = ["description", "maxPartySize", "maxLevel", "bannedRaces", "bannedCastes"]
	if not _exact_fields(restrictions, restriction_fields) or not restrictions["description"] is String or _integer(restrictions["maxPartySize"]) < 1 or _integer(restrictions["maxPartySize"]) > 6 or _integer(restrictions["maxLevel"]) < 0 or not restrictions["bannedRaces"] is Array or not restrictions["bannedCastes"] is Array:
		_reject("Campaign restriction metadata is malformed.")
		return null
	var result := CampaignDefinition.new()
	result.id = record["id"]
	result.title = record["name"]
	result.version = record["version"]
	result.author = record["author"]
	result.contact = record["contact"].duplicate(true)
	result.description = record["description"]
	result.splash_asset_id = record["splashAssetId"]
	result.recommended_party_levels = _integer(record["recommendedPartyLevels"])
	result.maximum_party_levels = _integer(record["maximumPartyLevels"])
	result.guidance_authored = record["guidanceAuthored"]
	result.restrictions.description = restrictions["description"]
	result.restrictions.maximum_party_size = _integer(restrictions["maxPartySize"])
	result.restrictions.maximum_level = _integer(restrictions["maxLevel"])
	for race_id: Variant in restrictions["bannedRaces"]:
		if not race_id is String:
			_reject("Campaign banned race IDs must be strings.")
			return null
		result.restrictions.banned_races.append(race_id)
	for caste_id: Variant in restrictions["bannedCastes"]:
		if not caste_id is String:
			_reject("Campaign banned caste IDs must be strings.")
			return null
		result.restrictions.banned_castes.append(caste_id)
	return result

func _construct_messages(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content messages must be an array.")
		return null
	var messages: Array[MessageDefinition] = []
	var ids: Dictionary = {}
	for record: Variant in value:
		if not record is Dictionary or _integer(record.get("id")) < 0 or not record.get("text") is String:
			_reject("Message record is malformed.")
			return null
		var id := _integer(record["id"])
		if ids.has(id):
			_reject("Message ID %d is duplicated." % id)
			return null
		ids[id] = true
		messages.append(MessageDefinition.new(id, record["text"]))
	return messages

func _construct_option_labels(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content option labels must be an array.")
		return null
	var option_labels: Array[OptionLabelDefinition] = []
	var ids: Dictionary = {}
	for record: Variant in value:
		if not record is Dictionary or not _exact_fields(record, ["id", "text"]) or _integer(record.get("id")) < 0 or not record.get("text") is String:
			_reject("Option-label record is malformed.")
			return null
		var id := _integer(record["id"])
		if ids.has(id):
			_reject("Option-label ID %d is duplicated." % id)
			return null
		ids[id] = true
		option_labels.append(OptionLabelDefinition.new(id, record["text"]))
	return option_labels

func _construct_items(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content items must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "name", "unidentifiedName", "description", "iconId", "itemType", "strengthBonus", "blunt", "hands", "luckBonus", "movementBonus", "armorBonus", "magicResistanceBonus", "damageBonus", "spellPointBonus", "soundId", "weight", "cost", "initialCharges", "cursedItemId", "magical", "itemCategoryMaskLow", "itemCategoryMaskHigh", "raceRestrictions", "casteRestrictions", "specificRaceId", "specificCasteId", "raceClassOnly", "casteClassOnly", "versusSmall", "versusLarge", "heat", "cold", "electric", "versusUndead", "versusDemonDevil", "versusEvil", "special", "weightPerCharge", "dropOnEmpty"]
	var integer_fields: Array[String] = ["classicId", "iconId", "itemType", "strengthBonus", "blunt", "hands", "luckBonus", "movementBonus", "armorBonus", "magicResistanceBonus", "damageBonus", "spellPointBonus", "soundId", "weight", "cost", "initialCharges", "itemCategoryMaskLow", "itemCategoryMaskHigh", "raceRestrictions", "casteRestrictions", "raceClassOnly", "casteClassOnly", "versusSmall", "versusLarge", "heat", "cold", "electric", "versusUndead", "versusDemonDevil", "versusEvil", "weightPerCharge"]
	var result: Array[ItemDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
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
		result.append(item)
	return result

func _construct_races(value: Variant) -> Variant:
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
		if not value_record is Dictionary:
			_reject("Race definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, integer_fields, "Race definition")
		if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Race") or not record["name"] is String or not record["description"] is String or not record["eligibleCasteIds"] is Array or not record["doesNotDie"] is bool or not record["canRegenerate"] is bool or not record["ageRanges"] is Array or record["ageRanges"].size() != 5 or not record["ageChanges"] is Array or record["ageChanges"].size() != 5:
			_reject("Race definition is malformed or duplicated.")
			return null
		var classic_id: int = integers_value["classicId"]
		if classic_id < 1 or classic_id > 30 or classic_ids.has(classic_id) or record["id"] != "classic.race.%d" % classic_id:
			_reject("Race Classic IDs must uniquely cover 1 through 30.")
			return null
		classic_ids[classic_id] = true
		var hit_value: Variant = _integer_array(record["hitModifiers"], 8, "Race hit modifiers")
		var abilities_value: Variant = _integer_array(record["abilityBonuses"], 14, "Race ability bonuses")
		var save_value: Variant = _integer_array(record["saveBonuses"], 8, "Race save bonuses")
		var bonus_value: Variant = _integer_array(record["attributeBonuses"], 6, "Race attribute bonuses")
		var limits_value: Variant = _integer_array(record["attributeLimits"], 12, "Race attribute limits")
		var conditions_value: Variant = _integer_array(record["conditionLevels"], 40, "Race condition levels")
		var masks_value: Variant = _integer_array(record["itemCategoryMasks"], 2, "Race item masks")
		if hit_value == null or abilities_value == null or save_value == null or bonus_value == null or limits_value == null or conditions_value == null or masks_value == null:
			return null
		var ages: Array[Vector2i] = []
		for row: Variant in record["ageRanges"]:
			var pair_value: Variant = _integer_array(row, 2, "Race age range")
			if pair_value == null:
				return null
			var pair: Array[int] = pair_value
			ages.append(Vector2i(pair[0], pair[1]))
		var age_changes: Array[PackedInt32Array] = []
		for row: Variant in record["ageChanges"]:
			var changes_value: Variant = _integer_array(row, 15, "Race age change")
			if changes_value == null:
				return null
			var changes: Array[int] = changes_value
			age_changes.append(PackedInt32Array(changes))
		var integers: Dictionary = integers_value
		var masks: Array[int] = masks_value
		var eligible_castes: Array[String] = []
		for caste_id: Variant in record["eligibleCasteIds"]:
			if not caste_id is String or caste_id.is_empty():
				_reject("Race eligibility IDs must be non-empty strings.")
				return null
			eligible_castes.append(caste_id)
		has_functional_rules = has_functional_rules or integers["maximumAge"] != 0 or integers["baseMovement"] != 0 or integers["baseAttacks"] != 0 or integers["maximumAttacks"] != 0 or not eligible_castes.is_empty() or limits_value.any(func(number: int) -> bool: return number != 0)
		result.append(RaceDefinition.new(record["id"], integers["classicId"], record["name"], hit_value, save_value, bonus_value, limits_value, conditions_value, ages, age_changes, integers["maximumAge"], record["doesNotDie"], integers["baseMovement"], integers["magicResistance"], integers["twoHandBonus"], integers["missileBonus"], integers["baseAttacks"], integers["maximumAttacks"], record["canRegenerate"], integers["defaultIconSet"], masks[0], masks[1], integers["descriptorFlags"], record["description"], eligible_castes, abilities_value))
	if not result.is_empty() and not has_functional_rules:
		_reject("Content races cannot be a semantically empty 30-record table.")
		return null
	return result

func _construct_castes(value: Variant) -> Variant:
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
		if not value_record is Dictionary:
			_reject("Caste definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, integer_fields, "Caste definition")
		if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Caste") or not record["name"] is String or not record["description"] is String or not record["eligibleRaceIds"] is Array or not record["canUseMissile"] is bool or not record["getsMissileBonus"] is bool or not record["spellcasterRows"] is Array or record["spellcasterRows"].size() != 4:
			_reject("Caste definition is malformed or duplicated.")
			return null
		var classic_id: int = integers_value["classicId"]
		if classic_id < 1 or classic_id > 30 or classic_ids.has(classic_id) or record["id"] != "classic.caste.%d" % classic_id:
			_reject("Caste Classic IDs must uniquely cover 1 through 30.")
			return null
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
			return null
		var spellcasters: Array[Vector3i] = []
		for row: Variant in record["spellcasterRows"]:
			var row_value: Variant = _integer_array(row, 3, "Caste spellcaster row")
			if row_value == null:
				return null
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
				return null
			eligible_races.append(race_id)
		has_functional_rules = has_functional_rules or integers["casteClass"] != 0 or integers["movementBonus"] != 0 or integers["maximumAttacks"] != 0 or integers["startMoney"] != 0 or not eligible_races.is_empty() or victory_value.any(func(number: int) -> bool: return number != 0) or limits_value.any(func(number: int) -> bool: return number != 0) or stamina_value.any(func(number: int) -> bool: return number != 0) or attacks_value.any(func(number: int) -> bool: return number != 0)
		result.append(CasteDefinition.new(record["id"], integers["classicId"], record["name"], saves_value, bonuses_value, limits_value, conditions_value, Vector2i(stamina[0], stamina[1]), Vector2i(to_hit[0], to_hit[1]), Vector2i(dodge[0], dodge[1]), Vector2i(missile[0], missile[1]), Vector2i(hand[0], hand[1]), spellcasters, attacks_value, start_items_value, integers["casteClass"], integers["minimumAgeGroup"], integers["movementBonus"], integers["magicResistanceMultiplier"], integers["twoHandBonus"], integers["maximumStaminaBonus"], integers["bonusAttacks"], integers["maximumAttacks"], integers["startMoney"], record["canUseMissile"], record["getsMissileBonus"], integers["defaultIcon"], masks[0], masks[1], Vector2i(strength[0], strength[1]), record["description"], eligible_races, initial_abilities_value, level_abilities_value, victory_value))
	if not result.is_empty() and not has_functional_rules:
		_reject("Content castes cannot be a semantically empty 30-record table.")
		return null
	return result

func _construct_spells(value: Variant) -> Variant:
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
		result.append(spell)
	return result

func _construct_monsters(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content monsters must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "classicNameId", "name", "description", "notOnMenu", "hitDice", "staminaBonus", "agility", "movementMaximum", "armor", "magicResistance", "requiredWeapon", "magicToHit", "traitor", "size", "typeFlags", "attackCount", "magicAttackCount", "attacks", "damageBonus", "castPercent", "runPercent", "surrenderPercent", "missilePercent", "canSummon", "saves", "spellImmunities", "conditions", "money", "spellIds", "itemIds", "weaponId", "randomWeaponTable", "iconId", "spellPoints", "experience", "deathMacro"]
	var integer_fields: Array[String] = ["classicId", "classicNameId", "hitDice", "staminaBonus", "agility", "movementMaximum", "armor", "magicResistance", "requiredWeapon", "magicToHit", "size", "attackCount", "magicAttackCount", "damageBonus", "castPercent", "runPercent", "surrenderPercent", "missilePercent", "canSummon", "randomWeaponTable", "iconId", "spellPoints", "experience", "deathMacro"]
	var result: Array[MonsterDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Monster definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, integer_fields, "Monster definition")
		if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Monster") or not record["description"] is String or not record["notOnMenu"] is bool or not record["traitor"] is bool or not record["weaponId"] is String or not record["attacks"] is Array or _integer(record["classicNameId"]) < 0 or _integer(record["classicNameId"]) > 255 or _integer(record["requiredWeapon"]) < -128 or _integer(record["requiredWeapon"]) > 127 or _integer(record["magicToHit"]) < 0 or _integer(record["magicToHit"]) > 127 or _integer(record["randomWeaponTable"]) < 0 or _integer(record["randomWeaponTable"]) > 10:
			_reject("Monster definition is malformed or duplicated.")
			return null
		var type_value: Variant = _integer_array(record["typeFlags"], 8, "Monster type flags")
		var saves_value: Variant = _integer_array(record["saves"], 6, "Monster saves")
		var immunity_value: Variant = _integer_array(record["spellImmunities"], 6, "Monster spell immunities")
		var conditions_value: Variant = _integer_array(record["conditions"], 40, "Monster starting conditions")
		var money_value: Variant = _integer_array(record["money"], 3, "Monster wealth")
		var spell_ids_value: Variant = _fixed_or_empty_string_list(record["spellIds"], 10, 255, "Monster spell IDs")
		var item_ids_value: Variant = _fixed_string_list(record["itemIds"], 6, 255, "Monster item IDs")
		if type_value == null or saves_value == null or immunity_value == null or conditions_value == null or not _array_values_in_range(conditions_value, -128, 127) or money_value == null or spell_ids_value == null or item_ids_value == null:
			return null
		var attacks: Array[MonsterAttackDefinition] = []
		for attack_value: Variant in record["attacks"]:
			if not attack_value is Dictionary or not _exact_fields(attack_value, ["damageMin", "damageMax", "soundOrType", "special"]):
				_reject("Monster attack definition is malformed.")
				return null
			var attack_integers_value: Variant = _validated_integer_fields(attack_value, ["damageMin", "damageMax", "soundOrType", "special"], "Monster attack")
			if attack_integers_value == null:
				return null
			var attack_integers: Dictionary = attack_integers_value
			attacks.append(MonsterAttackDefinition.new(attack_integers["damageMin"], attack_integers["damageMax"], attack_integers["soundOrType"], attack_integers["special"]))
		var integers: Dictionary = integers_value
		if integers["attackCount"] < 0 or integers["attackCount"] > 5 or integers["attackCount"] > attacks.size():
			_reject("Monster attack count exceeds its fixed Classic attack rows.")
			return null
		var monster := MonsterDefinition.new(record["id"], integers["classicId"], record["name"], integers["hitDice"], integers["staminaBonus"], integers["agility"], integers["armor"], integers["magicResistance"], type_value, saves_value, immunity_value, money_value, spell_ids_value, item_ids_value, attacks, conditions_value, integers["classicNameId"], record["description"], record["notOnMenu"])
		monster.movement_max = integers["movementMaximum"]
		monster.required_weapon = integers["requiredWeapon"]
		monster.magic_to_hit = integers["magicToHit"]
		monster.traitor = record["traitor"]
		monster.size = integers["size"]
		monster.attack_count = integers["attackCount"]
		monster.magic_attack_count = integers["magicAttackCount"]
		monster.damage_bonus = integers["damageBonus"]
		monster.cast_percent = integers["castPercent"]
		monster.run_percent = integers["runPercent"]
		monster.surrender_percent = integers["surrenderPercent"]
		monster.missile_percent = integers["missilePercent"]
		monster.can_summon = integers["canSummon"]
		monster.weapon_id = record["weaponId"]
		monster.random_weapon_table = integers["randomWeaponTable"]
		monster.icon_id = integers["iconId"]
		monster.spell_points = integers["spellPoints"]
		monster.experience = integers["experience"]
		monster.death_macro = integers["deathMacro"]
		result.append(monster)
	return result

func _construct_monster_sets(value: Variant) -> Variant:
	if not value is Array:
		_reject("Monster sets must be an array.")
		return null
	var result: Dictionary = {}
	for entry: Variant in value:
		if not entry is Dictionary or not _exact_fields(entry, ["setId", "name", "monsters"]):
			_reject("Monster-set metadata is malformed.")
			return null
		var set_id := _integer(entry["setId"])
		if set_id not in [-1, 1] or result.has(set_id) or not entry["name"] is String or entry["name"].is_empty():
			_reject("Monster-set identity is invalid or duplicated.")
			return null
		var records: Variant = _construct_monsters(entry["monsters"])
		if records == null:
			return null
		result[set_id] = records
	return result

func _construct_battles(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content battles must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "monsterSlots", "distance", "messageBeforeId", "messageAfterId", "macroId"]
	var result: Array[BattleDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Battle definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, ["classicId", "distance", "messageBeforeId", "messageAfterId", "macroId"], "Battle definition")
		if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Battle", false) or not record["monsterSlots"] is Array or record["monsterSlots"].size() > 169:
			_reject("Battle definition is malformed or duplicated.")
			return null
		var monster_slots: Array[BattleMonsterSlotDefinition] = []
		var occupied: Dictionary = {}
		for slot_value: Variant in record["monsterSlots"]:
			if not slot_value is Dictionary or not _exact_fields(slot_value, ["x", "y", "monsterId", "invertTraitor"]) or not _is_integer(slot_value["x"]) or not _is_integer(slot_value["y"]) or _integer(slot_value["x"]) < 0 or _integer(slot_value["x"]) > 12 or _integer(slot_value["y"]) < 0 or _integer(slot_value["y"]) > 12 or not slot_value["monsterId"] is String or slot_value["monsterId"].is_empty() or not slot_value["invertTraitor"] is bool:
				_reject("Battle monster slot is malformed.")
				return null
			var coordinate := Vector2i(_integer(slot_value["x"]), _integer(slot_value["y"]))
			if occupied.has(coordinate):
				_reject("Battle monster slot coordinate is duplicated.")
				return null
			occupied[coordinate] = true
			monster_slots.append(BattleMonsterSlotDefinition.new(coordinate, slot_value["monsterId"], slot_value["invertTraitor"]))
		var integers: Dictionary = integers_value
		result.append(BattleDefinition.new(record["id"], integers["classicId"], monster_slots, integers["distance"], integers["messageBeforeId"], integers["messageAfterId"], integers["macroId"]))
	return result

func _construct_treasures(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content treasures must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "itemIds", "experience", "gold", "gems", "jewelry"]
	var result: Array[TreasureDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Treasure definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, ["classicId", "experience", "gold", "gems", "jewelry"], "Treasure definition")
		var item_ids_value: Variant = _string_list(record.get("itemIds"), "Treasure item IDs")
		if not _exact_fields(record, fields) or integers_value == null or item_ids_value == null or not _definition_identity(record, ids, "Treasure", false):
			_reject("Treasure definition is malformed or duplicated.")
			return null
		var integers: Dictionary = integers_value
		result.append(TreasureDefinition.new(record["id"], integers["classicId"], item_ids_value, integers["experience"], integers["gold"], integers["gems"], integers["jewelry"]))
	return result

func _construct_shops(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content shops must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "inflationPercent", "stock"]
	var result: Array[ShopDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Shop definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, ["classicId", "inflationPercent"], "Shop definition")
		if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Shop", false) or not record["stock"] is Array or record["stock"].size() > 1000:
			_reject("Shop definition is malformed or duplicated.")
			return null
		var item_ids: Array[String] = []
		var quantities: Array[int] = []
		var slots: Array[int] = []
		for stock_value: Variant in record["stock"]:
			if not stock_value is Dictionary or not _exact_fields(stock_value, ["slot", "itemId", "quantity"]) or not _is_integer(stock_value["slot"]) or _integer(stock_value["slot"]) < 0 or _integer(stock_value["slot"]) > 999 or slots.has(_integer(stock_value["slot"])) or not stock_value["itemId"] is String or stock_value["itemId"].is_empty() or not _is_integer(stock_value["quantity"]) or _integer(stock_value["quantity"]) < 0:
				_reject("Shop stock record is malformed.")
				return null
			slots.append(_integer(stock_value["slot"]))
			item_ids.append(stock_value["itemId"])
			quantities.append(_integer(stock_value["quantity"]))
		var integers: Dictionary = integers_value
		result.append(ShopDefinition.new(record["id"], integers["classicId"], item_ids, quantities, integers["inflationPercent"], slots))
	return result

func _construct_simple_encounters(value: Variant) -> Variant:
	if not value is Array:
		_reject("Simple Encounters must be an array.")
		return null
	var encounters: Array[SimpleEncounterDefinition] = []
	var ids: Dictionary = {}
	for record: Variant in value:
		if not record is Dictionary or not _exact_fields(record, ["id", "promptMessageId", "responses", "canBackOut", "maxTimes", "casteSuccess"]):
			_reject("Simple Encounter definition is malformed.")
			return null
		var encounter_id := _integer(record["id"])
		if encounter_id < 0 or ids.has(encounter_id) or not _is_integer(record["promptMessageId"]) or not record["responses"] is Array or record["responses"].is_empty() or record["responses"].size() > 4 or not record["canBackOut"] is bool or not _is_integer(record["maxTimes"]) or not _is_integer(record["casteSuccess"]):
			_reject("Simple Encounter identity, choices, or Classic fields are malformed.")
			return null
		var responses: Array[SimpleEncounterResponse] = []
		var response_ids: Dictionary = {}
		for response: Variant in record["responses"]:
			if not response is Dictionary or not _exact_fields(response, ["id", "label", "resultProgramId"]) or not response["id"] is String or response["id"].is_empty() or response_ids.has(response["id"]) or not response["label"] is String or response["label"].is_empty() or not response["resultProgramId"] is String or response["resultProgramId"].is_empty():
				_reject("Simple Encounter %d contains a malformed or duplicate response." % encounter_id)
				return null
			response_ids[response["id"]] = true
			responses.append(SimpleEncounterResponse.new(response["id"], response["label"], response["resultProgramId"]))
		ids[encounter_id] = true
		encounters.append(SimpleEncounterDefinition.new(encounter_id, _integer(record["promptMessageId"]), responses, record["canBackOut"], _integer(record["maxTimes"]), _integer(record["casteSuccess"])))
	return encounters

func _construct_complex_encounters(value: Variant) -> Variant:
	if not value is Array:
		_reject("Complex Encounters must be an array.")
		return null
	var fields: Array[String] = ["id", "promptMessageId", "actionResult", "wordResult", "groups", "spellIds", "spellResults", "itemIds", "itemResults", "canBackOut", "thief", "maxTimes", "casteSuccess", "thiefSuccess", "thiefFail", "texts"]
	var scalar_fields: Array[String] = ["id", "promptMessageId", "actionResult", "wordResult", "maxTimes", "casteSuccess", "thiefSuccess", "thiefFail"]
	var encounters: Array[ComplexEncounterDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Complex Encounter definition is not an object.")
			return null
		var record: Dictionary = value_record
		var scalars_value: Variant = _validated_integer_fields(record, scalar_fields, "Complex Encounter")
		if not _exact_fields(record, fields) or scalars_value == null or not record["canBackOut"] is bool or not record["thief"] is bool:
			_reject("Complex Encounter definition is malformed.")
			return null
		var scalars: Dictionary = scalars_value
		if scalars["id"] < 0 or ids.has(scalars["id"]) or not _integers_in_range(scalars, ["actionResult", "wordResult", "maxTimes", "casteSuccess", "thiefSuccess", "thiefFail"], -128, 127):
			_reject("Complex Encounter identity or Classic scalar fields are malformed.")
			return null
		var groups_value: Variant = _integer_array(record["groups"], 8, "Complex Encounter groups")
		var spell_ids_value: Variant = _integer_array(record["spellIds"], 10, "Complex Encounter spell IDs")
		var spell_results_value: Variant = _integer_array(record["spellResults"], 10, "Complex Encounter spell results")
		var item_ids_value: Variant = _integer_array(record["itemIds"], 5, "Complex Encounter item IDs")
		var item_results_value: Variant = _integer_array(record["itemResults"], 5, "Complex Encounter item results")
		var texts_value: Variant = _fixed_string_list(record["texts"], 9, 40, "Complex Encounter texts")
		if groups_value == null or spell_ids_value == null or spell_results_value == null or item_ids_value == null or item_results_value == null or texts_value == null:
			return null
		var groups: Array[int] = groups_value
		var spell_ids: Array[int] = spell_ids_value
		var spell_results: Array[int] = spell_results_value
		var item_ids: Array[int] = item_ids_value
		var item_results: Array[int] = item_results_value
		if not _array_values_in_range(groups, -128, 127) or not _array_values_in_range(spell_ids, -32768, 32767) or not _array_values_in_range(spell_results, -128, 127) or not _array_values_in_range(item_ids, -32768, 32767) or not _array_values_in_range(item_results, -128, 127):
			_reject("Complex Encounter arrays exceed Classic storage.")
			return null
		ids[scalars["id"]] = true
		encounters.append(ComplexEncounterDefinition.new(scalars["id"], scalars["promptMessageId"], scalars["actionResult"], scalars["wordResult"], groups, spell_ids, spell_results, item_ids, item_results, record["canBackOut"], record["thief"], scalars["maxTimes"], scalars["casteSuccess"], scalars["thiefSuccess"], scalars["thiefFail"], texts_value))
	return encounters

func _construct_thief_encounters(value: Variant) -> Variant:
	if not value is Array:
		_reject("Thief Encounters must be an array.")
		return null
	var fields: Array[String] = ["id", "typeFlags", "modifiers", "successCodes", "failureCodes", "successText", "failureText", "successSounds", "failureSounds", "spellId", "lowDamage", "highDamage", "tumblers", "prompts", "promptSounds"]
	var scalar_fields: Array[String] = ["id", "spellId", "lowDamage", "highDamage", "tumblers"]
	var encounters: Array[ThiefEncounterDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Thief Encounter definition is not an object.")
			return null
		var record: Dictionary = value_record
		var scalars_value: Variant = _validated_integer_fields(record, scalar_fields, "Thief Encounter")
		if not _exact_fields(record, fields) or scalars_value == null:
			_reject("Thief Encounter definition is malformed.")
			return null
		var scalars: Dictionary = scalars_value
		if scalars["id"] < 0 or ids.has(scalars["id"]) or not _integers_in_range(scalars, ["spellId", "lowDamage", "highDamage", "tumblers"], -32768, 32767):
			_reject("Thief Encounter identity or Classic scalar fields are malformed.")
			return null
		var type_flags_value: Variant = _boolean_array(record["typeFlags"], 10, "Thief Encounter type flags")
		var modifiers_value: Variant = _integer_array(record["modifiers"], 8, "Thief Encounter modifiers")
		var success_codes_value: Variant = _integer_array(record["successCodes"], 8, "Thief Encounter success codes")
		var failure_codes_value: Variant = _integer_array(record["failureCodes"], 8, "Thief Encounter failure codes")
		var success_text_value: Variant = _integer_array(record["successText"], 8, "Thief Encounter success text")
		var failure_text_value: Variant = _integer_array(record["failureText"], 8, "Thief Encounter failure text")
		var success_sounds_value: Variant = _integer_array(record["successSounds"], 8, "Thief Encounter success sounds")
		var failure_sounds_value: Variant = _integer_array(record["failureSounds"], 8, "Thief Encounter failure sounds")
		var prompts_value: Variant = _integer_array(record["prompts"], 3, "Thief Encounter prompts")
		var prompt_sounds_value: Variant = _integer_array(record["promptSounds"], 3, "Thief Encounter prompt sounds")
		if type_flags_value == null or modifiers_value == null or success_codes_value == null or failure_codes_value == null or success_text_value == null or failure_text_value == null or success_sounds_value == null or failure_sounds_value == null or prompts_value == null or prompt_sounds_value == null:
			return null
		for signed_bytes: Array[int] in [modifiers_value, success_codes_value, failure_codes_value]:
			if not _array_values_in_range(signed_bytes, -128, 127):
				_reject("Thief Encounter byte arrays exceed Classic storage.")
				return null
		for signed_shorts: Array[int] in [success_text_value, failure_text_value, success_sounds_value, failure_sounds_value, prompts_value, prompt_sounds_value]:
			if not _array_values_in_range(signed_shorts, -32768, 32767):
				_reject("Thief Encounter short arrays exceed Classic storage.")
				return null
		ids[scalars["id"]] = true
		encounters.append(ThiefEncounterDefinition.new(scalars["id"], type_flags_value, modifiers_value, success_codes_value, failure_codes_value, success_text_value, failure_text_value, success_sounds_value, failure_sounds_value, scalars["spellId"], scalars["lowDamage"], scalars["highDamage"], scalars["tumblers"], prompts_value, prompt_sounds_value))
	return encounters

func _construct_timed_encounters(value: Variant) -> Variant:
	if not value is Array:
		_reject("Timed Encounters must be an array.")
		return null
	var fields: Array[String] = ["id", "day", "increment", "chancePercent", "classicMacroId", "programId", "requiredLevel", "requiredRandomRectangle", "requiredX", "requiredY", "requiredItemId", "requiredQuestId", "locationKind"]
	var integer_fields: Array[String] = ["id", "day", "increment", "chancePercent", "classicMacroId", "requiredLevel", "requiredRandomRectangle", "requiredX", "requiredY", "requiredItemId", "requiredQuestId"]
	var encounters: Array[TimedEncounterDefinition] = []
	var ids: Dictionary = {}
	var location_kinds: Dictionary = {"any": TimedEncounterDefinition.LocationKind.ANY, "land": TimedEncounterDefinition.LocationKind.LAND, "dungeon": TimedEncounterDefinition.LocationKind.DUNGEON}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Timed Encounter definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, integer_fields, "Timed Encounter")
		if not _exact_fields(record, fields) or integers_value == null or not record["programId"] is String or record["programId"].is_empty() or not record["locationKind"] is String or not location_kinds.has(record["locationKind"]):
			_reject("Timed Encounter definition is malformed.")
			return null
		var integers: Dictionary = integers_value
		if integers["id"] < 0 or ids.has(integers["id"]) or integers["classicMacroId"] < 0 or not _integers_in_range(integers, integer_fields.slice(1), -32768, 32767):
			_reject("Timed Encounter identity or Classic fields are malformed.")
			return null
		ids[integers["id"]] = true
		encounters.append(TimedEncounterDefinition.new(integers["id"], integers["day"], integers["increment"], integers["chancePercent"], integers["classicMacroId"], record["programId"], integers["requiredLevel"], integers["requiredRandomRectangle"], integers["requiredX"], integers["requiredY"], integers["requiredItemId"], integers["requiredQuestId"], location_kinds[record["locationKind"]]))
	return encounters
