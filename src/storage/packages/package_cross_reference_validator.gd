## Validates and loads package cross reference validator data at the immutable package boundary.

class_name PackageCrossReferenceValidator
extends PackageDecoderBase

const CLASSIC_UNMATCHABLE_RACE_ID := "classic.race.-32768"
const CLASSIC_UNMATCHABLE_CASTE_ID := "classic.caste.-32768"

var warnings: Array[ScenarioCompatibilityWarning] = []


func clear_warnings() -> void:
	warnings.clear()


func validate_rule_references(races: Array[RaceDefinition], castes: Array[CasteDefinition], items: Array[ItemDefinition], spells: Array[SpellDefinition], monsters: Array[MonsterDefinition], battles: Array[BattleDefinition], treasures: Array[TreasureDefinition], shops: Array[ShopDefinition], message_ids: Dictionary, allow_deferred: bool = false) -> bool:
	var race_ids := _definition_ids(races)
	var caste_ids := _definition_ids(castes)
	var item_ids := _definition_ids(items)
	var monster_ids := _definition_ids(monsters)
	for item: ItemDefinition in items:
		if not item.cursed_item_id.is_empty() and not item_ids.has(item.cursed_item_id):
			if not _unavailable(allow_deferred, &"item", item.id, "cursedItemId", -1, &"item", item.cursed_item_id, "Item '%s' references unavailable cursed item '%s'." % [item.id, item.cursed_item_id]): return false
		if not item.specific_race_id.is_empty() and item.specific_race_id != CLASSIC_UNMATCHABLE_RACE_ID and not race_ids.has(item.specific_race_id):
			if not _unavailable(allow_deferred, &"item", item.id, "specificRaceId", -1, &"race", item.specific_race_id, "Item '%s' references unavailable race '%s'." % [item.id, item.specific_race_id]): return false
		if not item.specific_caste_id.is_empty() and item.specific_caste_id != CLASSIC_UNMATCHABLE_CASTE_ID and not caste_ids.has(item.specific_caste_id):
			if not _unavailable(allow_deferred, &"item", item.id, "specificCasteId", -1, &"caste", item.specific_caste_id, "Item '%s' references unavailable caste '%s'." % [item.id, item.specific_caste_id]): return false
	for caste: CasteDefinition in castes:
		for item_id: String in caste.start_items():
			if not item_ids.has(item_id):
				if not _unavailable(allow_deferred, &"caste", caste.id, "startingItems", -1, &"item", item_id, "Caste '%s' references unavailable starting item '%s'." % [caste.id, item_id]): return false
	if not validate_monster_record_references(monsters, items, spells, allow_deferred):
		return false
	for battle: BattleDefinition in battles:
		for slot: BattleMonsterSlotDefinition in battle.monster_slots():
			if not monster_ids.has(slot.monster_id):
				return _reject("Battle '%s' references unavailable monster '%s'." % [battle.id, slot.monster_id])
		for message_id: int in [battle.message_before_id, battle.message_after_id]:
			if message_id != 0 and not message_ids.has(absi(message_id)):
				var field := "messageBeforeId" if message_id == battle.message_before_id else "messageAfterId"
				if not _unavailable(allow_deferred, &"battle", battle.id, field, -1, &"message", absi(message_id), "Battle '%s' references unavailable message %d." % [battle.id, message_id]): return false
	for treasure: TreasureDefinition in treasures:
		for item_id: String in treasure.item_ids():
			if not item_ids.has(item_id):
				if not _unavailable(allow_deferred, &"treasure", treasure.id, "items", -1, &"item", item_id, "Treasure '%s' references unavailable item '%s'." % [treasure.id, item_id]): return false
	for shop: ShopDefinition in shops:
		for item_id: String in shop.item_ids():
			if not item_ids.has(item_id):
				if not _unavailable(allow_deferred, &"shop", shop.id, "stock", -1, &"item", item_id, "Shop '%s' references unavailable item '%s'." % [shop.id, item_id]): return false
	return true

func validate_monster_record_references(monsters: Array[MonsterDefinition], items: Array[ItemDefinition], spells: Array[SpellDefinition], allow_deferred: bool = false) -> bool:
	var item_ids := _definition_ids(items)
	var spell_ids := _definition_ids(spells)
	for monster: MonsterDefinition in monsters:
		for spell_id: String in monster.spell_ids():
			if spell_id.is_empty():
				continue
			if not spell_ids.has(spell_id):
				if not _unavailable(allow_deferred, &"monster", monster.id, "spells", -1, &"spell", spell_id, "Monster '%s' references unavailable spell '%s'." % [monster.id, spell_id]): return false
		for item_id: String in monster.item_ids():
			if not item_id.is_empty() and not item_ids.has(item_id):
				if not _unavailable(allow_deferred, &"monster", monster.id, "items", -1, &"item", item_id, "Monster '%s' references unavailable item '%s'." % [monster.id, item_id]): return false
		if not monster.weapon_id.is_empty() and not item_ids.has(monster.weapon_id):
			if not _unavailable(allow_deferred, &"monster", monster.id, "weaponId", -1, &"item", monster.weapon_id, "Monster '%s' references unavailable weapon '%s'." % [monster.id, monster.weapon_id]): return false
		for random_weapon_id: String in MonsterRules.random_weapon_item_ids(monster.random_weapon_table):
			if not item_ids.has(random_weapon_id):
				if not _unavailable(allow_deferred, &"monster", monster.id, "randomWeaponTable", -1, &"item", random_weapon_id, "Monster '%s' random weapon table %d can produce unavailable weapon '%s'." % [monster.id, monster.random_weapon_table, random_weapon_id]): return false
	return true

func validate_scenario_references(scenario: ScenarioDefinition, message_ids: Dictionary, encounters: Array[SimpleEncounterDefinition], complex_encounters: Array[ComplexEncounterDefinition], thief_encounters: Array[ThiefEncounterDefinition], items: Array[ItemDefinition], spells: Array[SpellDefinition], media_assets: Array[MediaAsset], allow_deferred: bool = false) -> bool:
	var encounter_ids_value: Variant = _validate_simple_encounters(scenario, message_ids, encounters, allow_deferred)
	if encounter_ids_value == null:
		return false
	var encounter_ids: Dictionary = encounter_ids_value
	var classic_spell_ids: Dictionary = {}
	for spell: SpellDefinition in spells:
		classic_spell_ids[spell.classic_id] = true
	var complex_ids_value: Variant = _validate_complex_encounters(scenario, message_ids, complex_encounters, thief_encounters, classic_spell_ids, allow_deferred)
	if complex_ids_value == null:
		return false
	var complex_ids: Dictionary = complex_ids_value
	var classic_item_ids: Dictionary = {}
	for item: ItemDefinition in items:
		classic_item_ids[item.classic_id] = true
	var media_resource_keys: Dictionary = {}
	for asset: MediaAsset in media_assets:
		media_resource_keys["%s:%d" % [asset.resource_type, asset.resource_id]] = true
	return _validate_scenario_programs(scenario, encounter_ids, complex_ids, classic_item_ids, media_resource_keys, message_ids, allow_deferred)


func _validate_simple_encounters(scenario: ScenarioDefinition, message_ids: Dictionary, encounters: Array[SimpleEncounterDefinition], allow_deferred: bool) -> Variant:
	var encounter_ids: Dictionary = {}
	for encounter: SimpleEncounterDefinition in encounters:
		encounter_ids[encounter.id] = true
		if not message_ids.has(absi(encounter.prompt_message_id)):
			if not _unavailable(allow_deferred, &"simple-encounter", str(encounter.id), "promptMessageId", -1, &"message", absi(encounter.prompt_message_id), "Simple Encounter %d references unavailable prompt message %d." % [encounter.id, encounter.prompt_message_id]): return null
		for response: SimpleEncounterResponse in encounter.responses():
			if scenario.program_by_id(response.result_program_id) == null:
				if not _unavailable(allow_deferred, &"simple-encounter", str(encounter.id), response.id, -1, &"scenario-program", response.result_program_id, "Simple Encounter %d response '%s' references unavailable result program '%s'." % [encounter.id, response.id, response.result_program_id]): return null
	return encounter_ids


func _validate_complex_encounters(scenario: ScenarioDefinition, message_ids: Dictionary, encounters: Array[ComplexEncounterDefinition], thief_encounters: Array[ThiefEncounterDefinition], classic_spell_ids: Dictionary, allow_deferred: bool) -> Variant:
	var thief_ids: Dictionary = {}
	for thief_encounter: ThiefEncounterDefinition in thief_encounters:
		thief_ids[thief_encounter.id] = true
		if thief_encounter.spell_id != 0 and not classic_spell_ids.has(thief_encounter.spell_id):
			if not _unavailable(allow_deferred, &"thief-encounter", str(thief_encounter.id), "spellId", -1, &"spell", thief_encounter.spell_id, "Thief Encounter %d references unavailable Classic spell %d." % [thief_encounter.id, thief_encounter.spell_id]): return null
	var complex_ids: Dictionary = {}
	for encounter: ComplexEncounterDefinition in encounters:
		complex_ids[encounter.id] = true
		if not message_ids.has(absi(encounter.prompt_message_id)):
			if not _unavailable(allow_deferred, &"complex-encounter", str(encounter.id), "promptMessageId", -1, &"message", absi(encounter.prompt_message_id), "Complex Encounter %d references unavailable prompt message %d." % [encounter.id, encounter.prompt_message_id]): return null
		for outcome: int in range(1, 5):
			if scenario.program_by_id(encounter.result_program_id(outcome)) == null:
				if not _unavailable(allow_deferred, &"complex-encounter", str(encounter.id), "result%d" % outcome, -1, &"scenario-program", encounter.result_program_id(outcome), "Complex Encounter %d references unavailable result program %d." % [encounter.id, outcome]): return null
		if encounter.thief and not thief_ids.has(encounter.thief_success):
			if not _unavailable(allow_deferred, &"complex-encounter", str(encounter.id), "thiefSuccess", -1, &"thief-encounter", encounter.thief_success, "Complex Encounter %d references unavailable Thief Encounter %d." % [encounter.id, encounter.thief_success]): return null
	return complex_ids


func _validate_scenario_programs(scenario: ScenarioDefinition, encounter_ids: Dictionary, complex_ids: Dictionary, classic_item_ids: Dictionary, media_resource_keys: Dictionary, message_ids: Dictionary, allow_deferred: bool) -> bool:
	for program_id: String in scenario.program_ids():
		var program := scenario.program_by_id(program_id)
		for index: int in range(program.instruction_count()):
			var instruction: Variant = program.instruction_at(index)
			if not instruction is ClassicActionDefinition:
				continue
			match instruction.opcode:
				1:
					if not message_ids.has(absi(instruction.operand_id)):
						if not _unavailable(allow_deferred, &"scenario-program", program.id, "id", instruction.slot, &"message", absi(instruction.operand_id), "Scenario program '%s' references unavailable message %d." % [program.id, instruction.operand_id]): return false
				4:
					if not encounter_ids.has(instruction.operand_id):
						if not _unavailable(allow_deferred, &"scenario-program", program.id, "id", instruction.slot, &"simple-encounter", instruction.operand_id, "Scenario program '%s' references unavailable Simple Encounter %d." % [program.id, instruction.operand_id]): return false
				5:
					if not complex_ids.has(instruction.operand_id):
						if not _unavailable(allow_deferred, &"scenario-program", program.id, "id", instruction.slot, &"complex-encounter", instruction.operand_id, "Scenario program '%s' references unavailable Complex Encounter %d." % [program.id, instruction.operand_id]): return false
				39:
					if scenario.program_by_id("xap:%d" % instruction.operand_id) == null:
						if not _unavailable(allow_deferred, &"scenario-program", program.id, "id", instruction.slot, &"xap", instruction.operand_id, "Scenario program '%s' references unavailable XAP %d." % [program.id, instruction.operand_id]): return false
				62:
					if not media_resource_keys.has("TEXT:%d" % instruction.operand_id):
						if not _unavailable(allow_deferred, &"scenario-program", program.id, "id", instruction.slot, &"TEXT", instruction.operand_id, "Scenario program '%s' opcode 62 references unavailable TEXT resource %d." % [program.id, instruction.operand_id]): return false
				67:
					if not classic_item_ids.has(instruction.extra_code[0]):
						if not _unavailable(allow_deferred, &"scenario-program", program.id, "extraCode[0]", instruction.slot, &"item", instruction.extra_code[0], "Scenario program '%s' opcode 67 references unavailable Classic item %d." % [program.id, instruction.extra_code[0]]): return false
					for target_id: int in [instruction.extra_code[3], instruction.extra_code[4]]:
						if not _validate_branch_destination(scenario, encounter_ids, complex_ids, program.id, instruction.slot, 67, instruction.extra_code[1], target_id, allow_deferred):
							return false
				72:
					if not _validate_branch_destination(scenario, encounter_ids, complex_ids, program.id, instruction.slot, 72, instruction.extra_code[3], instruction.extra_code[4], allow_deferred):
						return false
				78:
					for target_id: int in [instruction.extra_code[3], instruction.extra_code[4]]:
						if not _validate_branch_destination(scenario, encounter_ids, complex_ids, program.id, instruction.slot, 78, instruction.extra_code[2], target_id, allow_deferred):
							return false
				75:
					if not _validate_branch_destination(scenario, encounter_ids, complex_ids, program.id, instruction.slot, 75, instruction.extra_code[3], instruction.extra_code[4], allow_deferred):
						return false
				85:
					var mode: int = instruction.extra_code[0]
					var low_id: int = instruction.extra_code[1]
					var high_id: int = instruction.extra_code[2]
					if mode not in [0, 1, 2] or low_id < 0 or high_id < low_id or high_id > 32_767:
						return _reject("Scenario program '%s' opcode 85 has an invalid Classic destination range." % program.id)
					if instruction.extra_code[4] != 0 and not message_ids.has(absi(instruction.extra_code[4])):
						if not _unavailable(allow_deferred, &"scenario-program", program.id, "extraCode[4]", instruction.slot, &"message", absi(instruction.extra_code[4]), "Scenario program '%s' opcode 85 references unavailable message %d." % [program.id, instruction.extra_code[4]]): return false
					for target_id: int in range(low_id, high_id + 1):
						if not _validate_branch_destination(scenario, encounter_ids, complex_ids, program.id, instruction.slot, 85, mode, target_id, allow_deferred):
							return false
	return true


func _validate_branch_destination(scenario: ScenarioDefinition, encounter_ids: Dictionary, complex_ids: Dictionary, program_id: String, slot: int, opcode: int, mode: int, target_id: int, allow_deferred: bool) -> bool:
	match mode:
		0:
			if target_id == 0 or scenario.program_by_id("xap:%d" % target_id) != null:
				return true
			return _unavailable(allow_deferred, &"scenario-program", program_id, "branch", slot, &"xap", target_id, "Scenario program '%s' opcode %d references unavailable XAP %d." % [program_id, opcode, target_id])
		1:
			if encounter_ids.has(target_id):
				return true
			return _unavailable(allow_deferred, &"scenario-program", program_id, "branch", slot, &"simple-encounter", target_id, "Scenario program '%s' opcode %d references unavailable Simple Encounter %d." % [program_id, opcode, target_id])
		2:
			if complex_ids.has(target_id):
				return true
			return _unavailable(allow_deferred, &"scenario-program", program_id, "branch", slot, &"complex-encounter", target_id, "Scenario program '%s' opcode %d references unavailable Complex Encounter %d." % [program_id, opcode, target_id])
	return _reject("Scenario program '%s' opcode %d has invalid destination mode %d." % [program_id, opcode, mode])


func validate_timed_encounter_references(scenario: ScenarioDefinition, encounters: Array[TimedEncounterDefinition], allow_deferred: bool = false) -> bool:
	for encounter: TimedEncounterDefinition in encounters:
		var expected_program_id := "xap:%d" % encounter.classic_macro_id
		var program := scenario.program_by_id(encounter.program_id)
		if encounter.program_id != expected_program_id or program == null or program.owner_kind != &"extra-action-point":
			if program != null and program.owner_kind != &"extra-action-point":
				return _reject("Timed Encounter %d references Classic program '%s' with the wrong owner kind." % [encounter.id, encounter.program_id])
			return _unavailable(allow_deferred, &"timed-encounter", str(encounter.id), "programId", -1, &"xap", encounter.classic_macro_id, "Timed Encounter %d references unavailable Classic XAP program '%s'." % [encounter.id, encounter.program_id])
	return true

func validate_random_region_references(maps: Array[MapDefinition], scenario: ScenarioDefinition, battles: Array[BattleDefinition], allow_deferred: bool = false) -> bool:
	var battle_ids: Dictionary = {}
	for battle: BattleDefinition in battles:
		battle_ids[battle.classic_id] = true
	for map: MapDefinition in maps:
		for region: RandomEncounterRegion in map.random_regions():
			var doors := region.random_doors()
			var door_percents := region.random_door_percents()
			for index: int in doors.size():
				if door_percents[index] != 0 and (doors[index] < 0 or scenario.program_by_id("xap:%d" % doors[index]) == null):
					if not _unavailable(allow_deferred, &"random-rectangle", region.id, "randomDoors[%d]" % index, -1, &"xap", doors[index], "Random rectangle '%s' references unavailable XAP %d." % [region.id, doors[index]]): return false
			if region.battle_minimum == 0:
				continue
			var selected_bounds := RealmzRng.classic_between_bounds(region.battle_minimum, region.battle_maximum)
			for battle_id: int in range(selected_bounds.x, selected_bounds.y + 1):
				if not battle_ids.has(absi(battle_id)):
					if not _unavailable(allow_deferred, &"random-rectangle", region.id, "battleRange", -1, &"battle", absi(battle_id), "Random rectangle '%s' references unavailable battle %d." % [region.id, battle_id]): return false
	return true

func validate_player_map_opcode_references(scenario: ScenarioDefinition, world: WorldDefinition, allow_deferred: bool = false) -> bool:
	for program_id: String in scenario.program_ids():
		var program := scenario.program_by_id(program_id)
		for index: int in range(program.instruction_count()):
			var instruction: Variant = program.instruction_at(index)
			if not instruction is ClassicActionDefinition:
				continue
			match instruction.opcode:
				44:
					if program.owner_kind not in [&"simple-encounter-result", &"complex-encounter-result"] or instruction.operand_id < 1 or instruction.operand_id > 4:
						return _reject("Scenario program '%s' opcode 44 requires result 1 through 4 in a Simple or Complex Encounter result." % program.id)
				29:
					if world.player_map_by_classic_id(absi(instruction.operand_id)) == null:
						if not _unavailable(allow_deferred, &"scenario-program", program.id, "id", instruction.slot, &"player-map", absi(instruction.operand_id), "Scenario program '%s' references unavailable player-map record %d." % [program.id, absi(instruction.operand_id)]): return false
				57:
					if world.map_by_type_and_index(&"land", instruction.extra_code[2]) == null:
						if not _unavailable(allow_deferred, &"scenario-program", program.id, "extraCode[2]", instruction.slot, &"land-map", instruction.extra_code[2], "Scenario program '%s' opcode 57 references an unavailable land level." % program.id): return false
					if world.battle_terrain_set_by_landlook(instruction.extra_code[0]) == null:
						if not _unavailable(allow_deferred, &"scenario-program", program.id, "extraCode[0]", instruction.slot, &"landlook", instruction.extra_code[0], "Scenario program '%s' opcode 57 references an unavailable landlook." % program.id): return false
				92:
					var map_type := &"dungeon" if instruction.extra_code[2] != 0 else &"land"
					var map_index: int = maxi(instruction.extra_code[0], 0)
					var region_index: int = instruction.extra_code[1] if instruction.extra_code[1] >= 0 and instruction.extra_code[1] < 20 else 0
					var map := world.map_by_type_and_index(map_type, map_index)
					if map == null:
						if not _unavailable(allow_deferred, &"scenario-program", program.id, "extraCode[0]", instruction.slot, map_type, map_index, "Scenario program '%s' opcode 92 references an unavailable map." % program.id): return false
					elif map.random_region_by_index(region_index) == null:
						if not _unavailable(allow_deferred, &"scenario-program", program.id, "extraCode[1]", instruction.slot, &"random-rectangle", region_index, "Scenario program '%s' opcode 92 references an unavailable random rectangle." % program.id): return false
	return true


func _unavailable(allow_deferred: bool, source_kind: StringName, source_id: String, field: String, slot: int, target_kind: StringName, target_id: Variant, reason: String) -> bool:
	if not allow_deferred:
		return _reject(reason)
	warnings.append(ScenarioCompatibilityWarning.new(source_kind, source_id, field, slot, target_kind, target_id, reason))
	return true


func defer_or_reject(allow_deferred: bool, source_kind: StringName, source_id: String, field: String, slot: int, target_kind: StringName, target_id: Variant, reason: String) -> bool:
	return _unavailable(allow_deferred, source_kind, source_id, field, slot, target_kind, target_id, reason)

func program_context(owner_kind: StringName) -> StringName:
	match owner_kind:
		&"simple-encounter-result", &"complex-encounter-result":
			return &"encounter"
		&"trigger", &"extra-action-point":
			return &"action"
	return &""

func call_arguments_match(argument_names: Array[String], result_target: String, action: ScenarioActionDefinition) -> bool:
	if argument_names != action.parameter_names():
		return false
	if result_target.is_empty():
		return true
	return action.return_type != &"void" and _safe_identifier(result_target)

func contexts_are_compatible(caller: ScenarioActionDefinition, called: ScenarioActionDefinition) -> bool:
	for context: StringName in caller.allowed_contexts():
		if not called.allows_context(context):
			return false
	return true
