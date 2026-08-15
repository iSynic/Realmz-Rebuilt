class_name PackageCrossReferenceValidator
extends PackageDecoderBase

func _validate_rule_references(races: Array[RaceDefinition], castes: Array[CasteDefinition], items: Array[ItemDefinition], spells: Array[SpellDefinition], monsters: Array[MonsterDefinition], battles: Array[BattleDefinition], treasures: Array[TreasureDefinition], shops: Array[ShopDefinition], message_ids: Dictionary) -> bool:
	var race_ids := _definition_ids(races)
	var caste_ids := _definition_ids(castes)
	var item_ids := _definition_ids(items)
	var monster_ids := _definition_ids(monsters)
	for item: ItemDefinition in items:
		if not item.cursed_item_id.is_empty() and not item_ids.has(item.cursed_item_id):
			return _reject("Item '%s' references unavailable cursed item '%s'." % [item.id, item.cursed_item_id])
		if not item.specific_race_id.is_empty() and not race_ids.has(item.specific_race_id):
			return _reject("Item '%s' references unavailable race '%s'." % [item.id, item.specific_race_id])
		if not item.specific_caste_id.is_empty() and not caste_ids.has(item.specific_caste_id):
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

func _validate_scenario_references(scenario: ScenarioDefinition, message_ids: Dictionary, encounters: Array[SimpleEncounterDefinition], complex_encounters: Array[ComplexEncounterDefinition], thief_encounters: Array[ThiefEncounterDefinition]) -> bool:
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
	for thief_encounter: ThiefEncounterDefinition in thief_encounters:
		thief_ids[thief_encounter.id] = true
	for encounter: ComplexEncounterDefinition in complex_encounters:
		complex_ids[encounter.id] = true
		if not message_ids.has(absi(encounter.prompt_message_id)):
			return _reject("Complex Encounter %d references unavailable prompt message %d." % [encounter.id, encounter.prompt_message_id])
		for outcome: int in range(1, 5):
			if scenario.program_by_id(encounter.result_program_id(outcome)) == null:
				return _reject("Complex Encounter %d references unavailable result program %d." % [encounter.id, outcome])
		if encounter.thief and not thief_ids.has(encounter.thief_success):
			return _reject("Complex Encounter %d references unavailable Thief Encounter %d." % [encounter.id, encounter.thief_success])
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
			if region.battle_minimum < 1 or region.battle_maximum < region.battle_minimum:
				return _reject("Random rectangle '%s' has an invalid battle range." % region.id)
			for battle_id: int in range(region.battle_minimum, region.battle_maximum + 1):
				if not battle_ids.has(battle_id):
					return _reject("Random rectangle '%s' references unavailable battle %d." % [region.id, battle_id])
	return true

func _validate_player_map_opcode_references(scenario: ScenarioDefinition, world: WorldDefinition) -> bool:
	for program_id: String in scenario.program_ids():
		var program := scenario.program_by_id(program_id)
		for index: int in range(program.instruction_count()):
			var instruction: Variant = program.instruction_at(index)
			if instruction is ClassicActionDefinition and instruction.opcode == 29 and world.player_map_by_classic_id(absi(instruction.operand_id)) == null:
				_reject("Scenario program '%s' references unavailable player-map record %d." % [program.id, absi(instruction.operand_id)])
				return false
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

