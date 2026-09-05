## Validates and loads package domain assembler data at the immutable package boundary.

class_name PackageDomainAssembler
extends PackageDecoderBase

## Builds the typed game domain from already verified package documents.


class StoryContent extends RefCounted:
	var campaign: CampaignDefinition
	var messages: Array[MessageDefinition]
	var option_labels: Array[OptionLabelDefinition]
	var message_ids: Dictionary
	var simple_encounters: Array[SimpleEncounterDefinition]
	var complex_encounters: Array[ComplexEncounterDefinition]
	var thief_encounters: Array[ThiefEncounterDefinition]
	var timed_encounters: Array[TimedEncounterDefinition]


class RulesContent extends RefCounted:
	var races: Array[RaceDefinition]
	var castes: Array[CasteDefinition]
	var items: Array[ItemDefinition]
	var spells: Array[SpellDefinition]
	var monsters: Array[MonsterDefinition]
	var monster_sets: Dictionary
	var battles: Array[BattleDefinition]
	var treasures: Array[TreasureDefinition]
	var shops: Array[ShopDefinition]
	var media: Array[MediaAsset]
	var appearance_options: Array[CharacterAppearanceDefinition]


class WorldContent extends RefCounted:
	var definition: WorldDefinition
	var triggers: Array[TriggerDefinition]


func assemble(manifest: Dictionary, content: Dictionary, world: Dictionary, scenario: Dictionary, media_assets: Array[MediaAsset] = [], trusted_install: bool = false, application_content: RealmzContent = null, application_media_assets: Array[MediaAsset] = []) -> RealmzContent:
	clear_error()
	if application_content != null and application_content.rules_version != manifest["engine"]["rulesVersion"]:
		_reject("The scenario rules version does not match the loaded application definition catalog.")
		return null
	if not content.has("campaign") or not content["campaign"] is Dictionary or content["campaign"].get("id") != manifest["campaignId"]:
		_reject("Content campaign identity does not match the manifest.")
		return null
	var content_decoder := PackageContentDecoder.new(_diagnostic)
	var story_content := _decode_story_content(content_decoder, content, world, trusted_install)
	if story_content == null:
		return null
	var media_validator := PackageMediaValidatorResolver.new(_diagnostic)
	var rules_content := _decode_rules_content(content_decoder, media_validator, content, media_assets, trusted_install, application_content, application_media_assets)
	if rules_content == null:
		return null
	var scenario_decoder := PackageScenarioDecoder.new(_diagnostic)
	var scenario_definition := scenario_decoder.decode_scenario(scenario, manifest["campaignId"])
	if scenario_definition == null:
		return null
	var reference_validator := PackageCrossReferenceValidator.new(_diagnostic)
	if not _validate_content_references(reference_validator, scenario_definition, story_content, rules_content, trusted_install):
		return null
	var world_content := _decode_world_content(PackageWorldDecoder.new(_diagnostic), reference_validator, world, scenario_definition, rules_content, trusted_install)
	if world_content == null:
		return null
	var start_coordinate_value: Variant = _validate_start(manifest, world_content, trusted_install)
	if start_coordinate_value == null:
		return null
	var start_coordinate: Vector2i = start_coordinate_value
	return RealmzContent.new(manifest["campaignId"], manifest["packageHash"], manifest["contentId"], manifest["engine"]["rulesVersion"], manifest["start"]["mapId"], start_coordinate, world_content.definition, scenario_definition, story_content.messages, world_content.triggers, story_content.simple_encounters, rules_content.races, rules_content.castes, rules_content.items, rules_content.spells, rules_content.monsters, rules_content.battles, rules_content.treasures, rules_content.shops, story_content.complex_encounters, story_content.thief_encounters, story_content.timed_encounters, story_content.option_labels, story_content.campaign, rules_content.appearance_options, rules_content.monster_sets)


func _decode_story_content(decoder: PackageContentDecoder, content: Dictionary, world: Dictionary, trusted_install: bool) -> StoryContent:
	var result := StoryContent.new()
	result.campaign = decoder.decode_campaign_definition(content["campaign"])
	var messages_value: Variant = decoder.decode_messages(content.get("messages"))
	var option_labels_value: Variant = decoder.decode_option_labels(content.get("optionLabels"))
	var simple_value: Variant = decoder.decode_simple_encounters(content.get("simpleEncounters"))
	var complex_value: Variant = decoder.decode_complex_encounters(content.get("complexEncounters"))
	var thief_value: Variant = decoder.decode_thief_encounters(content.get("thiefEncounters"))
	var timed_value: Variant = decoder.decode_timed_encounters(content.get("timedEncounters"))
	if result.campaign == null or messages_value == null or option_labels_value == null or simple_value == null or complex_value == null or thief_value == null or timed_value == null:
		return null
	if not trusted_install and CanonicalJson.encode(content.get("timedEncounters")) != CanonicalJson.encode(world.get("timedEncounters")):
		_reject("Content and world timed-encounter inventories do not match.")
		return null
	result.messages = messages_value
	result.option_labels = option_labels_value
	result.simple_encounters = simple_value
	result.complex_encounters = complex_value
	result.thief_encounters = thief_value
	result.timed_encounters = timed_value
	result.message_ids = {}
	for message: MessageDefinition in result.messages:
		result.message_ids[message.id] = true
	_normalize_missing_encounter_prompts(result.messages, result.message_ids, result.simple_encounters, result.complex_encounters)
	return result


func _decode_rules_content(decoder: PackageContentDecoder, media_validator: PackageMediaValidatorResolver, content: Dictionary, scenario_media: Array[MediaAsset], trusted_install: bool, application_content: RealmzContent, application_media: Array[MediaAsset]) -> RulesContent:
	var races_value: Variant = decoder.decode_races(content.get("races"))
	var castes_value: Variant = decoder.decode_castes(content.get("castes"))
	var items_value: Variant = decoder.decode_items(content.get("items"))
	var spells_value: Variant = decoder.decode_spells(content.get("spells"))
	var monsters_value: Variant = decoder.decode_monsters(content.get("monsters"))
	var monster_sets_value: Variant = decoder.decode_monster_sets(content.get("monsterSets"))
	var battles_value: Variant = decoder.decode_battles(content.get("battles"))
	var treasures_value: Variant = decoder.decode_treasures(content.get("treasures"))
	var shops_value: Variant = decoder.decode_shops(content.get("shops"))
	if races_value == null or castes_value == null or items_value == null or spells_value == null or monsters_value == null or monster_sets_value == null or battles_value == null or treasures_value == null or shops_value == null:
		return null
	var catalogs := _compose_catalogs(races_value, castes_value, items_value, spells_value, scenario_media, application_content, application_media)
	if catalogs.is_empty():
		return null
	var result := RulesContent.new()
	result.races = catalogs["races"]
	result.castes = catalogs["castes"]
	result.items = catalogs["items"]
	result.spells = catalogs["spells"]
	result.media = catalogs["media"]
	result.monsters = monsters_value
	result.monster_sets = monster_sets_value
	result.battles = battles_value
	result.treasures = treasures_value
	result.shops = shops_value
	var all_monsters: Variant = _all_monsters(result.monsters, result.monster_sets, trusted_install)
	if all_monsters == null:
		return null
	if not trusted_install and not media_validator.validate_monster_media(all_monsters, result.media):
		return null
	result.appearance_options = media_validator.resolve_character_appearance_options(result.media, result.races)
	return result


func _all_monsters(monsters: Array[MonsterDefinition], monster_sets: Dictionary, trusted_install: bool) -> Variant:
	var result: Array[MonsterDefinition] = monsters.duplicate()
	var base_ids := _definition_ids(monsters)
	for set_id: Variant in monster_sets:
		var set_monsters: Array[MonsterDefinition] = monster_sets[set_id]
		var covered_ids: Dictionary = {}
		for monster: MonsterDefinition in set_monsters:
			covered_ids["classic.monster.%d" % monster.classic_id] = true
			result.append(monster)
		if trusted_install:
			continue
		if covered_ids.size() != base_ids.size():
			_reject("Monster set %d does not define every packaged Classic monster." % int(set_id))
			return null
		for base_id: Variant in base_ids:
			if not covered_ids.has(base_id):
				_reject("Monster set %d is missing Classic monster '%s'." % [int(set_id), base_id])
				return null
	return result


func _validate_content_references(validator: PackageCrossReferenceValidator, scenario: ScenarioDefinition, story: StoryContent, rules: RulesContent, trusted_install: bool) -> bool:
	if trusted_install:
		return true
	if not validator.validate_scenario_references(scenario, story.message_ids, story.simple_encounters, story.complex_encounters, story.thief_encounters, rules.items, rules.spells, rules.media):
		return false
	if not validator.validate_timed_encounter_references(scenario, story.timed_encounters):
		return false
	if not validator.validate_rule_references(rules.races, rules.castes, rules.items, rules.spells, rules.monsters, rules.battles, rules.treasures, rules.shops, story.message_ids):
		return false
	for set_id: Variant in rules.monster_sets:
		if not validator.validate_monster_record_references(rules.monster_sets[set_id], rules.items, rules.spells):
			return false
	return true


func _decode_world_content(decoder: PackageWorldDecoder, validator: PackageCrossReferenceValidator, world: Dictionary, scenario: ScenarioDefinition, rules: RulesContent, trusted_install: bool) -> WorldContent:
	var triggers_value: Variant = decoder.decode_triggers(world.get("triggers"), scenario)
	if triggers_value == null:
		return null
	var result := WorldContent.new()
	result.triggers = triggers_value
	var trigger_ids: Variant = _trigger_ids(result.triggers)
	if trigger_ids == null:
		return null
	var terrain_value: Variant = decoder.decode_battle_terrain_sets(world.get("battleTerrainSets"))
	if terrain_value == null:
		return null
	var terrain_sets: Array[BattleTerrainSetDefinition] = terrain_value
	var terrain_by_id: Dictionary = {}
	for terrain_set: BattleTerrainSetDefinition in terrain_sets:
		terrain_by_id[terrain_set.id] = terrain_set
	var maps_value: Variant = decoder.decode_maps(world.get("maps"), trigger_ids, terrain_by_id, not rules.battles.is_empty(), not trusted_install)
	if maps_value == null:
		return null
	var maps: Array[MapDefinition] = maps_value
	var player_maps_value: Variant = decoder.decode_player_maps(world.get("playerMaps"), maps, rules.media)
	if player_maps_value == null:
		return null
	var transitions_value: Variant = decoder.decode_transitions(world.get("transitions"), maps)
	if transitions_value == null:
		return null
	var player_maps: Array[PlayerMapDefinition] = player_maps_value
	var transitions: Array[MapTransition] = transitions_value
	result.definition = WorldDefinition.new(maps, transitions, terrain_sets, player_maps)
	if not trusted_install and not validator.validate_random_region_references(maps, scenario, rules.battles):
		return null
	if not trusted_install and not validator.validate_player_map_opcode_references(scenario, result.definition):
		return null
	return result


func _trigger_ids(triggers: Array[TriggerDefinition]) -> Variant:
	var result: Dictionary = {}
	for trigger: TriggerDefinition in triggers:
		if result.has(trigger.id):
			_reject("Trigger ID '%s' is duplicated." % trigger.id)
			return null
		result[trigger.id] = true
	return result


func _validate_start(manifest: Dictionary, world: WorldContent, trusted_install: bool) -> Variant:
	var start: Variant = manifest.get("start")
	if not start is Dictionary or not start.get("mapId") is String or _integer(start.get("x")) < 0 or _integer(start.get("y")) < 0:
		_reject("Manifest start location is malformed.")
		return null
	var start_coordinate := Vector2i(_integer(start["x"]), _integer(start["y"]))
	var start_map := world.definition.map_by_id(start["mapId"])
	if start_map == null or not trusted_install and start_map.topology.cell_at(start_coordinate) == null:
		_reject("Manifest start location does not identify a topology cell.")
		return null
	for trigger: TriggerDefinition in world.triggers if not trusted_install else []:
		if not trigger.map_id.is_empty():
			var map := world.definition.map_by_id(trigger.map_id)
			if map == null or map.topology.cell_at(trigger.coordinate) == null:
				_reject("Trigger '%s' references an unavailable topology coordinate." % trigger.id)
				return null
		if trigger.post_action_location != null:
			var destination_map := world.definition.map_by_id(trigger.post_action_location.map_id)
			if destination_map == null or destination_map.topology.cell_at(trigger.post_action_location.coordinate) == null:
				_reject("Trigger '%s' references an unavailable post-action location." % trigger.id)
				return null
	return start_coordinate


func _compose_catalogs(races_value: Variant, castes_value: Variant, items_value: Variant, spells_value: Variant, scenario_media: Array[MediaAsset], application_content: RealmzContent, application_media: Array[MediaAsset]) -> Dictionary:
	var races: Array[RaceDefinition] = []
	var castes: Array[CasteDefinition] = []
	var items: Array[ItemDefinition] = []
	var spells: Array[SpellDefinition] = []
	if application_content != null:
		races.assign(application_content.characters.race_definitions())
		castes.assign(application_content.characters.caste_definitions())
		items.assign(application_content.items.definitions())
		spells.assign(application_content.magic.definitions())
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
