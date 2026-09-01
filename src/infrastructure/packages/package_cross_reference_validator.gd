class_name PackageCrossReferenceValidator
extends PackageDecoderBase

const CLASSIC_UNMATCHABLE_RACE_ID := "classic.race.-32768"
const CLASSIC_UNMATCHABLE_CASTE_ID := "classic.caste.-32768"

func _validate_rule_references(races: Array[RaceDefinition], castes: Array[CasteDefinition], items: Array[ItemDefinition], spells: Array[SpellDefinition], monsters: Array[MonsterDefinition], battles: Array[BattleDefinition], treasures: Array[TreasureDefinition], shops: Array[ShopDefinition], message_ids: Dictionary) -> bool:
	var race_ids := _definition_ids(races)
	var caste_ids := _definition_ids(castes)
	var item_ids := _definition_ids(items)
	var monster_ids := _definition_ids(monsters)
	for item: ItemDefinition in items:
		if not item.cursed_item_id.is_empty() and not item_ids.has(item.cursed_item_id):
			return _reject("Item '%s' references unavailable cursed item '%s'." % [item.id, item.cursed_item_id])
		if not item.specific_race_id.is_empty() and item.specific_race_id != CLASSIC_UNMATCHABLE_RACE_ID and not race_ids.has(item.specific_race_id):
			return _reject("Item '%s' references unavailable race '%s'." % [item.id, item.specific_race_id])
		if not item.specific_caste_id.is_empty() and item.specific_caste_id != CLASSIC_UNMATCHABLE_CASTE_ID and not caste_ids.has(item.specific_caste_id):
			return _reject("Item '%s' references unavailable caste '%s'." % [item.id, item.specific_caste_id])
	for caste: CasteDefinition in castes:
		for item_id: String in caste.start_items():
			if not item_ids.has(item_id):
				return _reject("Caste '%s' references unavailable starting item '%s'." % [caste.id, item_id])
	if not _validate_monster_record_references(monsters, items, spells):
		return false
	for battle: BattleDefinition in battles:
		for slot: BattleMonsterSlotDefinition in battle.monster_slots():
			if not monster_ids.has(slot.monster_id):
				return _reject("Battle '%s' references unavailable monster '%s'." % [battle.id, slot.monster_id])
		for message_id: int in [battle.message_before_id, battle.message_after_id]:
			if message_id != 0 and not message_ids.has(absi(message_id)):
				return _reject("Battle '%s' references unavailable message %d." % [battle.id, message_id])
	for treasure: TreasureDefinition in treasures:
		for item_id: String in treasure.item_ids():
			if not item_ids.has(item_id):
				return _reject("Treasure '%s' references unavailable item '%s'." % [treasure.id, item_id])
	for shop: ShopDefinition in shops:
		for item_id: String in shop.item_ids():
			if not item_ids.has(item_id):
				return _reject("Shop '%s' references unavailable item '%s'." % [shop.id, item_id])
	return true

func _validate_monster_record_references(monsters: Array[MonsterDefinition], items: Array[ItemDefinition], spells: Array[SpellDefinition]) -> bool:
	var item_ids := _definition_ids(items)
	var spell_ids := _definition_ids(spells)
	for monster: MonsterDefinition in monsters:
		for spell_id: String in monster.spell_ids():
			if spell_id.is_empty():
				continue
			if not spell_ids.has(spell_id):
				return _reject("Monster '%s' references unavailable spell '%s'." % [monster.id, spell_id])
		for item_id: String in monster.item_ids():
			if not item_id.is_empty() and not item_ids.has(item_id):
				return _reject("Monster '%s' references unavailable item '%s'." % [monster.id, item_id])
		if not monster.weapon_id.is_empty() and not item_ids.has(monster.weapon_id):
			return _reject("Monster '%s' references unavailable weapon '%s'." % [monster.id, monster.weapon_id])
		for random_weapon_id: String in MonsterRules.random_weapon_item_ids(monster.random_weapon_table):
			if not item_ids.has(random_weapon_id):
				return _reject("Monster '%s' random weapon table %d can produce unavailable weapon '%s'." % [monster.id, monster.random_weapon_table, random_weapon_id])
	return true

func _validate_scenario_references(scenario: ScenarioDefinition, message_ids: Dictionary, encounters: Array[SimpleEncounterDefinition], complex_encounters: Array[ComplexEncounterDefinition], thief_encounters: Array[ThiefEncounterDefinition], items: Array[ItemDefinition], spells: Array[SpellDefinition], media_assets: Array[MediaAsset]) -> bool:
	var encounter_ids: Dictionary = {}
	for encounter: SimpleEncounterDefinition in encounters:
		encounter_ids[encounter.id] = true
		if not message_ids.has(absi(encounter.prompt_message_id)):
			return _reject("Simple Encounter %d references unavailable prompt message %d." % [encounter.id, encounter.prompt_message_id])
		for response: SimpleEncounterResponse in encounter.responses():
			if scenario.program_by_id(response.result_program_id) == null:
				return _reject("Simple Encounter %d response '%s' references unavailable result program '%s'." % [encounter.id, response.id, response.result_program_id])
	var complex_ids: Dictionary = {}
	var thief_ids: Dictionary = {}
	var classic_spell_ids: Dictionary = {}
	for spell: SpellDefinition in spells:
		classic_spell_ids[spell.classic_id] = true
	for thief_encounter: ThiefEncounterDefinition in thief_encounters:
		thief_ids[thief_encounter.id] = true
		if thief_encounter.spell_id != 0 and not classic_spell_ids.has(thief_encounter.spell_id):
			return _reject("Thief Encounter %d references unavailable Classic spell %d." % [thief_encounter.id, thief_encounter.spell_id])
	for encounter: ComplexEncounterDefinition in complex_encounters:
		complex_ids[encounter.id] = true
		if not message_ids.has(absi(encounter.prompt_message_id)):
			return _reject("Complex Encounter %d references unavailable prompt message %d." % [encounter.id, encounter.prompt_message_id])
		for outcome: int in range(1, 5):
			if scenario.program_by_id(encounter.result_program_id(outcome)) == null:
				return _reject("Complex Encounter %d references unavailable result program %d." % [encounter.id, outcome])
		if encounter.thief and not thief_ids.has(encounter.thief_success):
			return _reject("Complex Encounter %d references unavailable Thief Encounter %d." % [encounter.id, encounter.thief_success])
	var classic_item_ids: Dictionary = {}
	for item: ItemDefinition in items:
		classic_item_ids[item.classic_id] = true
	var media_resource_keys: Dictionary = {}
	for asset: MediaAsset in media_assets:
		media_resource_keys["%s:%d" % [asset.resource_type, asset.resource_id]] = true
	for program_id: String in scenario.program_ids():
		var program := scenario.program_by_id(program_id)
		for index: int in range(program.instruction_count()):
			var instruction: Variant = program.instruction_at(index)
			if not instruction is ClassicActionDefinition:
				continue
			match instruction.opcode:
				1:
					if not message_ids.has(absi(instruction.operand_id)):
						return _reject("Scenario program '%s' references unavailable message %d." % [program.id, instruction.operand_id])
				4:
					if not encounter_ids.has(instruction.operand_id):
						return _reject("Scenario program '%s' references unavailable Simple Encounter %d." % [program.id, instruction.operand_id])
				5:
					if not complex_ids.has(instruction.operand_id):
						return _reject("Scenario program '%s' references unavailable Complex Encounter %d." % [program.id, instruction.operand_id])
				39:
					if scenario.program_by_id("xap:%d" % instruction.operand_id) == null:
						return _reject("Scenario program '%s' references unavailable XAP %d." % [program.id, instruction.operand_id])
				62:
					if not media_resource_keys.has("TEXT:%d" % instruction.operand_id):
						return _reject("Scenario program '%s' opcode 62 references unavailable TEXT resource %d." % [program.id, instruction.operand_id])
				67:
					if not classic_item_ids.has(instruction.extra_code[0]):
						return _reject("Scenario program '%s' opcode 67 references unavailable Classic item %d." % [program.id, instruction.extra_code[0]])
					for target_id: int in [instruction.extra_code[3], instruction.extra_code[4]]:
						if not _validate_branch_destination(scenario, encounter_ids, complex_ids, program.id, 67, instruction.extra_code[1], target_id):
							return false
				72:
					if not _validate_branch_destination(scenario, encounter_ids, complex_ids, program.id, 72, instruction.extra_code[3], instruction.extra_code[4]):
						return false
				78:
					for target_id: int in [instruction.extra_code[3], instruction.extra_code[4]]:
						if not _validate_branch_destination(scenario, encounter_ids, complex_ids, program.id, 78, instruction.extra_code[2], target_id):
							return false
				75:
					if not _validate_branch_destination(scenario, encounter_ids, complex_ids, program.id, 75, instruction.extra_code[3], instruction.extra_code[4]):
						return false
				85:
					var mode: int = instruction.extra_code[0]
					var low_id: int = instruction.extra_code[1]
					var high_id: int = instruction.extra_code[2]
					if mode not in [0, 1, 2] or low_id < 0 or high_id < low_id or high_id > 32_767:
						return _reject("Scenario program '%s' opcode 85 has an invalid Classic destination range." % program.id)
					if instruction.extra_code[4] != 0 and not message_ids.has(absi(instruction.extra_code[4])):
						return _reject("Scenario program '%s' opcode 85 references unavailable message %d." % [program.id, instruction.extra_code[4]])
					for target_id: int in range(low_id, high_id + 1):
						if not _validate_branch_destination(scenario, encounter_ids, complex_ids, program.id, 85, mode, target_id):
							return false
	return true


func _validate_branch_destination(scenario: ScenarioDefinition, encounter_ids: Dictionary, complex_ids: Dictionary, program_id: String, opcode: int, mode: int, target_id: int) -> bool:
	match mode:
		0:
			if target_id == 0 or scenario.program_by_id("xap:%d" % target_id) != null:
				return true
			return _reject("Scenario program '%s' opcode %d references unavailable XAP %d." % [program_id, opcode, target_id])
		1:
			if encounter_ids.has(target_id):
				return true
			return _reject("Scenario program '%s' opcode %d references unavailable Simple Encounter %d." % [program_id, opcode, target_id])
		2:
			if complex_ids.has(target_id):
				return true
			return _reject("Scenario program '%s' opcode %d references unavailable Complex Encounter %d." % [program_id, opcode, target_id])
	return _reject("Scenario program '%s' opcode %d has invalid destination mode %d." % [program_id, opcode, mode])


func _validate_timed_encounter_references(scenario: ScenarioDefinition, encounters: Array[TimedEncounterDefinition]) -> bool:
	for encounter: TimedEncounterDefinition in encounters:
		var expected_program_id := "xap:%d" % encounter.classic_macro_id
		var program := scenario.program_by_id(encounter.program_id)
		if encounter.program_id != expected_program_id or program == null or program.owner_kind != &"extra-action-point":
			return _reject("Timed Encounter %d references unavailable Classic XAP program '%s'." % [encounter.id, encounter.program_id])
	return true

func _validate_random_region_references(maps: Array[MapDefinition], scenario: ScenarioDefinition, battles: Array[BattleDefinition]) -> bool:
	var battle_ids: Dictionary = {}
	for battle: BattleDefinition in battles:
		battle_ids[battle.classic_id] = true
	for map: MapDefinition in maps:
		for region: RandomEncounterRegion in map.random_regions():
			var doors := region.random_doors()
			var door_percents := region.random_door_percents()
			for index: int in doors.size():
				if door_percents[index] != 0 and (doors[index] < 0 or scenario.program_by_id("xap:%d" % doors[index]) == null):
					return _reject("Random rectangle '%s' references unavailable XAP %d." % [region.id, doors[index]])
			if region.battle_minimum == 0:
				continue
			var selected_bounds := RealmzRng.classic_between_bounds(region.battle_minimum, region.battle_maximum)
			for battle_id: int in range(selected_bounds.x, selected_bounds.y + 1):
				if not battle_ids.has(absi(battle_id)):
					return _reject("Random rectangle '%s' references unavailable battle %d." % [region.id, battle_id])
	return true

func _validate_player_map_opcode_references(scenario: ScenarioDefinition, world: WorldDefinition) -> bool:
	for program_id: String in scenario.program_ids():
		var program := scenario.program_by_id(program_id)
		for index: int in range(program.instruction_count()):
			var instruction: Variant = program.instruction_at(index)
			if not instruction is ClassicActionDefinition:
				continue
			match instruction.opcode:
				44:
					if program.owner_kind != &"complex-encounter-result" or instruction.operand_id < 1 or instruction.operand_id > 4:
						return _reject("Scenario program '%s' opcode 44 requires result 1 through 4 in a Complex Encounter result." % program.id)
				29:
					if world.player_map_by_classic_id(absi(instruction.operand_id)) == null:
						return _reject("Scenario program '%s' references unavailable player-map record %d." % [program.id, absi(instruction.operand_id)])
				57:
					if world.map_by_type_and_index(&"land", instruction.extra_code[2]) == null or world.battle_terrain_set_by_landlook(instruction.extra_code[0]) == null:
						return _reject("Scenario program '%s' opcode 57 references an unavailable land level or landlook." % program.id)
				92:
					var map_type := &"dungeon" if instruction.extra_code[2] != 0 else &"land"
					var map_index: int = maxi(instruction.extra_code[0], 0)
					var region_index: int = instruction.extra_code[1] if instruction.extra_code[1] >= 0 and instruction.extra_code[1] < 20 else 0
					var map := world.map_by_type_and_index(map_type, map_index)
					if map == null or map.random_region_by_index(region_index) == null:
						return _reject("Scenario program '%s' opcode 92 references an unavailable random rectangle." % program.id)
	return true

func _program_context(owner_kind: StringName) -> StringName:
	match owner_kind:
		&"simple-encounter-result", &"complex-encounter-result":
			return &"encounter"
		&"trigger", &"extra-action-point":
			return &"action"
	return &""

func _call_arguments_match(argument_names: Array[String], result_target: String, action: ScenarioActionDefinition) -> bool:
	if argument_names != action.parameter_names():
		return false
	if result_target.is_empty():
		return true
	return action.return_type != &"void" and _safe_identifier(result_target)

func _contexts_are_compatible(caller: ScenarioActionDefinition, called: ScenarioActionDefinition) -> bool:
	for context: StringName in caller.allowed_contexts():
		if not called.allows_context(context):
			return false
	return true
