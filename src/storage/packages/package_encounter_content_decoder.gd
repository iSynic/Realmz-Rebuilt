## Decodes monster, battle, treasure, shop, and encounter catalogs.

class_name PackageEncounterContentDecoder
extends PackageDecoderBase

func decode_monsters(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content monsters must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "classicNameId", "name", "description", "notOnMenu", "hitDice", "staminaBonus", "agility", "movementMaximum", "armor", "magicResistance", "requiredWeapon", "magicToHit", "traitor", "size", "typeFlags", "attackCount", "magicAttackCount", "attacks", "damageBonus", "castPercent", "runPercent", "surrenderPercent", "missilePercent", "canSummon", "saves", "spellImmunities", "conditions", "money", "spellIds", "itemIds", "weaponId", "randomWeaponTable", "iconId", "spellPoints", "experience", "deathMacro"]
	var integer_fields: Array[String] = ["classicId", "classicNameId", "hitDice", "staminaBonus", "agility", "movementMaximum", "armor", "magicResistance", "requiredWeapon", "magicToHit", "size", "attackCount", "magicAttackCount", "damageBonus", "castPercent", "runPercent", "surrenderPercent", "missilePercent", "canSummon", "randomWeaponTable", "iconId", "spellPoints", "experience", "deathMacro"]
	var result: Array[MonsterDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		var monster := _decode_monster_record(value_record, fields, integer_fields, ids)
		if monster == null:
			return null
		result.append(monster)
	return result

func _decode_monster_record(value_record: Variant, fields: Array[String], integer_fields: Array[String], ids: Dictionary) -> MonsterDefinition:
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
	return monster

func decode_monster_sets(value: Variant) -> Variant:
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
		var records: Variant = decode_monsters(entry["monsters"])
		if records == null:
			return null
		result[set_id] = records
	return result

func decode_battles(value: Variant) -> Variant:
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

func decode_treasures(value: Variant) -> Variant:
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

func decode_shops(value: Variant) -> Variant:
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

func decode_simple_encounters(value: Variant) -> Variant:
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

func decode_complex_encounters(value: Variant) -> Variant:
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

func decode_thief_encounters(value: Variant) -> Variant:
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

func decode_timed_encounters(value: Variant) -> Variant:
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
