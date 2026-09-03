class_name PackageDomainAssembler
extends PackageDecoderBase


func assemble(manifest: Dictionary, content: Dictionary, world: Dictionary, scenario: Dictionary, media_assets: Array[MediaAsset] = [], trusted_install: bool = false, application_content: RealmzContent = null, application_media_assets: Array[MediaAsset] = []) -> RealmzContent:
	clear_error()
	if application_content != null and application_content.rules_version != manifest["engine"]["rulesVersion"]:
		_reject("The scenario rules version does not match the loaded application definition catalog.")
		return null
	var _content_decoder := PackageContentDecoder.new(_diagnostic)
	var _scenario_decoder := PackageScenarioDecoder.new(_diagnostic)
	var _world_decoder := PackageWorldDecoder.new(_diagnostic)
	var _reference_validator := PackageCrossReferenceValidator.new(_diagnostic)
	var _media_validator := PackageMediaValidatorResolver.new(_diagnostic)
	if not content.has("campaign") or not content["campaign"] is Dictionary or content["campaign"].get("id") != manifest["campaignId"]:
		_reject("Content campaign identity does not match the manifest.")
		return null
	var campaign_definition := _content_decoder._construct_campaign_definition(content["campaign"])
	if campaign_definition == null:
		return null
	var messages_value: Variant = _content_decoder._construct_messages(content.get("messages"))
	if messages_value == null:
		return null
	var messages: Array[MessageDefinition] = messages_value
	var option_labels_value: Variant = _content_decoder._construct_option_labels(content.get("optionLabels"))
	if option_labels_value == null:
		return null
	var option_labels: Array[OptionLabelDefinition] = option_labels_value
	var message_ids: Dictionary = {}
	for message: MessageDefinition in messages:
		message_ids[message.id] = true
	var encounters_value: Variant = _content_decoder._construct_simple_encounters(content.get("simpleEncounters"))
	if encounters_value == null:
		return null
	var simple_encounters: Array[SimpleEncounterDefinition] = encounters_value
	var complex_encounters_value: Variant = _content_decoder._construct_complex_encounters(content.get("complexEncounters"))
	var thief_encounters_value: Variant = _content_decoder._construct_thief_encounters(content.get("thiefEncounters"))
	var timed_encounters_value: Variant = _content_decoder._construct_timed_encounters(content.get("timedEncounters"))
	if complex_encounters_value == null or thief_encounters_value == null or timed_encounters_value == null:
		return null
	if not trusted_install and CanonicalJson.encode(content.get("timedEncounters")) != CanonicalJson.encode(world.get("timedEncounters")):
		_reject("Content and world timed-encounter inventories do not match.")
		return null
	var complex_encounters: Array[ComplexEncounterDefinition] = complex_encounters_value
	var thief_encounters: Array[ThiefEncounterDefinition] = thief_encounters_value
	var timed_encounters: Array[TimedEncounterDefinition] = timed_encounters_value
	_normalize_missing_encounter_prompts(messages, message_ids, simple_encounters, complex_encounters)
	var races_value: Variant = _content_decoder._construct_races(content.get("races"))
	var castes_value: Variant = _content_decoder._construct_castes(content.get("castes"))
	var items_value: Variant = _content_decoder._construct_items(content.get("items"))
	var spells_value: Variant = _content_decoder._construct_spells(content.get("spells"))
	var monsters_value: Variant = _content_decoder._construct_monsters(content.get("monsters"))
	var monster_sets_value: Variant = _content_decoder._construct_monster_sets(content.get("monsterSets"))
	var battles_value: Variant = _content_decoder._construct_battles(content.get("battles"))
	var treasures_value: Variant = _content_decoder._construct_treasures(content.get("treasures"))
	var shops_value: Variant = _content_decoder._construct_shops(content.get("shops"))
	if races_value == null or castes_value == null or items_value == null or spells_value == null or monsters_value == null or monster_sets_value == null or battles_value == null or treasures_value == null or shops_value == null:
		return null
	var effective_catalogs := _compose_catalogs(races_value, castes_value, items_value, spells_value, media_assets, application_content, application_media_assets)
	if effective_catalogs.is_empty(): return null
	var races: Array[RaceDefinition] = effective_catalogs["races"]
	var castes: Array[CasteDefinition] = effective_catalogs["castes"]
	var items: Array[ItemDefinition] = effective_catalogs["items"]
	var spells: Array[SpellDefinition] = effective_catalogs["spells"]; var effective_media_assets: Array[MediaAsset] = effective_catalogs["media"]
	var monsters: Array[MonsterDefinition] = monsters_value
	var monster_sets: Dictionary = monster_sets_value
	var battles: Array[BattleDefinition] = battles_value
	var treasures: Array[TreasureDefinition] = treasures_value
	var shops: Array[ShopDefinition] = shops_value
	var all_monsters: Array[MonsterDefinition] = monsters.duplicate()
	var base_monster_ids := _definition_ids(monsters)
	for set_id: Variant in monster_sets:
		var set_monsters: Array[MonsterDefinition] = monster_sets[set_id]
		var covered_classic_ids: Dictionary = {}
		for monster: MonsterDefinition in set_monsters:
			covered_classic_ids["classic.monster.%d" % monster.classic_id] = true
			all_monsters.append(monster)
		if not trusted_install and covered_classic_ids.size() != base_monster_ids.size():
			_reject("Monster set %d does not define every packaged Classic monster." % int(set_id))
			return null
		for base_id: Variant in base_monster_ids if not trusted_install else []:
			if not covered_classic_ids.has(base_id):
				_reject("Monster set %d is missing Classic monster '%s'." % [int(set_id), base_id])
				return null
	if not trusted_install and not _media_validator._validate_monster_media(all_monsters, effective_media_assets):
		return null
	var appearance_options := _media_validator._construct_character_appearance_options(effective_media_assets, races)
	var scenario_definition := _scenario_decoder._construct_scenario(scenario, manifest["campaignId"])
	if scenario_definition == null:
		return null
	var triggers_value: Variant = _world_decoder._construct_triggers(world.get("triggers"), scenario_definition)
	if triggers_value == null:
		return null
	var triggers: Array[TriggerDefinition] = triggers_value
	if not trusted_install and not _reference_validator._validate_scenario_references(scenario_definition, message_ids, simple_encounters, complex_encounters, thief_encounters, items, spells, effective_media_assets):
		return null
	if not trusted_install and not _reference_validator._validate_timed_encounter_references(scenario_definition, timed_encounters):
		return null
	if not trusted_install and not _reference_validator._validate_rule_references(races, castes, items, spells, monsters, battles, treasures, shops, message_ids):
		return null
	for set_id: Variant in monster_sets if not trusted_install else {}:
		if not _reference_validator._validate_monster_record_references(monster_sets[set_id], items, spells):
			return null
	var trigger_ids: Dictionary = {}
	for trigger: TriggerDefinition in triggers:
		if trigger_ids.has(trigger.id):
			_reject("Trigger ID '%s' is duplicated." % trigger.id)
			return null
		trigger_ids[trigger.id] = true
	var battle_terrain_sets_value: Variant = _world_decoder._construct_battle_terrain_sets(world.get("battleTerrainSets"))
	if battle_terrain_sets_value == null:
		return null
	var battle_terrain_sets: Array[BattleTerrainSetDefinition] = battle_terrain_sets_value
	var battle_terrain_sets_by_id: Dictionary = {}
	for terrain_set: BattleTerrainSetDefinition in battle_terrain_sets:
		battle_terrain_sets_by_id[terrain_set.id] = terrain_set
	var maps_value: Variant = _world_decoder._construct_maps(world.get("maps"), trigger_ids, battle_terrain_sets_by_id, not battles.is_empty(), not trusted_install)
	if maps_value == null:
		return null
	var maps: Array[MapDefinition] = maps_value
	var player_maps_value: Variant = _world_decoder._construct_player_maps(world.get("playerMaps"), maps, effective_media_assets)
	if player_maps_value == null:
		return null
	var player_maps: Array[PlayerMapDefinition] = player_maps_value
	if not trusted_install and not _reference_validator._validate_random_region_references(maps, scenario_definition, battles):
		return null
	var transitions_value: Variant = _world_decoder._construct_transitions(world.get("transitions"), maps)
	if transitions_value == null:
		return null
	var transitions: Array[MapTransition] = transitions_value
	var world_definition := WorldDefinition.new(maps, transitions, battle_terrain_sets, player_maps)
	if not trusted_install and not _reference_validator._validate_player_map_opcode_references(scenario_definition, world_definition):
		return null
	var start: Variant = manifest.get("start")
	if not start is Dictionary or not start.get("mapId") is String or _integer(start.get("x")) < 0 or _integer(start.get("y")) < 0:
		_reject("Manifest start location is malformed.")
		return null
	var start_coordinate := Vector2i(_integer(start["x"]), _integer(start["y"]))
	var start_map := world_definition.map_by_id(start["mapId"])
	if start_map == null or not trusted_install and start_map.topology.cell_at(start_coordinate) == null:
		_reject("Manifest start location does not identify a topology cell.")
		return null
	for trigger: TriggerDefinition in triggers if not trusted_install else []:
		if not trigger.map_id.is_empty():
			var map := world_definition.map_by_id(trigger.map_id)
			if map == null or map.topology.cell_at(trigger.coordinate) == null:
				_reject("Trigger '%s' references an unavailable topology coordinate." % trigger.id)
				return null
		if trigger.post_action_location != null:
			var destination_map := world_definition.map_by_id(trigger.post_action_location.map_id)
			if destination_map == null or destination_map.topology.cell_at(trigger.post_action_location.coordinate) == null:
				_reject("Trigger '%s' references an unavailable post-action location." % trigger.id)
				return null
	return RealmzContent.new(manifest["campaignId"], manifest["packageHash"], manifest["contentId"], manifest["engine"]["rulesVersion"], start["mapId"], start_coordinate, world_definition, scenario_definition, messages, triggers, simple_encounters, races, castes, items, spells, monsters, battles, treasures, shops, complex_encounters, thief_encounters, timed_encounters, option_labels, campaign_definition, appearance_options, monster_sets_value)


func _compose_catalogs(races_value: Variant, castes_value: Variant, items_value: Variant, spells_value: Variant, scenario_media: Array[MediaAsset], application_content: RealmzContent, application_media: Array[MediaAsset]) -> Dictionary:
	var races: Array[RaceDefinition] = []
	var castes: Array[CasteDefinition] = []
	var items: Array[ItemDefinition] = []
	var spells: Array[SpellDefinition] = []
	if application_content != null:
		races.assign(application_content.race_definitions())
		castes.assign(application_content.caste_definitions())
		items.assign(application_content.item_definitions())
		spells.assign(application_content.spell_definitions())
	_overlay_definitions(races, races_value)
	_overlay_definitions(castes, castes_value)
	_overlay_definitions(items, items_value)
	_overlay_definitions(spells, spells_value)
	if races.size() != 30 or castes.size() != 30:
		_reject("The effective application-plus-scenario Race and Caste catalogs must each contain all 30 Classic records.")
		return {}
	var effective_media: Array[MediaAsset] = scenario_media.duplicate()
	_overlay_media(effective_media, application_media)
	return {"races": races, "castes": castes, "items": items, "spells": spells, "media": effective_media}


func _overlay_definitions(effective: Array, local: Array) -> void:
	var indices: Dictionary = {}
	for index: int in effective.size():
		indices[effective[index].id] = index
	for definition: Variant in local:
		if indices.has(definition.id):
			effective[indices[definition.id]] = definition
		else:
			indices[definition.id] = effective.size()
			effective.append(definition)


func _overlay_media(effective: Array[MediaAsset], application: Array[MediaAsset]) -> void:
	var local_keys: Dictionary = {}
	for asset: MediaAsset in effective:
		local_keys["%s:%d" % [asset.resource_type, asset.resource_id]] = true
	for asset: MediaAsset in application:
		if not local_keys.has("%s:%d" % [asset.resource_type, asset.resource_id]):
			effective.append(asset)


func _normalize_missing_encounter_prompts(messages: Array[MessageDefinition], message_ids: Dictionary, simple_encounters: Array[SimpleEncounterDefinition], complex_encounters: Array[ComplexEncounterDefinition]) -> void:
	# Castle preloads an empty STR# value before its unchecked direct Data SD2 prompt read.
	for encounter: Variant in simple_encounters + complex_encounters:
		var prompt_id := absi(encounter.prompt_message_id)
		if message_ids.has(prompt_id):
			continue
		messages.append(MessageDefinition.new(prompt_id, ""))
		message_ids[prompt_id] = true
