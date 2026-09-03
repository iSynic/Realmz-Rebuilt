class_name RealmzContent
extends RefCounted

var campaign_id: String
var package_hash: String
var content_id: String
var rules_version: String
var start_map_id: String
var start_coordinate: Vector2i
var world: WorldDefinition
var scenario: ScenarioDefinition
var campaign: CampaignDefinition
var _messages: Dictionary = {}
var _option_labels: Dictionary = {}
var _triggers: Dictionary = {}
var _simple_encounters: Dictionary = {}
var _complex_encounters: Dictionary = {}
var _thief_encounters: Dictionary = {}
var _timed_encounters: Dictionary = {}
var _races: Dictionary = {}
var _castes: Dictionary = {}
var _items: Dictionary = {}
var _spells: Dictionary = {}
var _monsters: Dictionary = {}
var _base_monsters: Dictionary = {}
var _monster_sets: Dictionary = {}
var _battles: Dictionary = {}
var _treasures: Dictionary = {}
var _shops: Dictionary = {}
var _appearance_options: Dictionary = {}
var _appearance_by_resource: Dictionary = {}
var _application_appearance_options: Dictionary = {}
var _application_appearance_by_resource: Dictionary = {}


func _init(campaign: String, package_identity: String, content_identity: String, rules: String, start_map: String, start_position: Vector2i, world_definition: WorldDefinition, scenario_definition: ScenarioDefinition, messages: Array[MessageDefinition], triggers: Array[TriggerDefinition], simple_encounters: Array[SimpleEncounterDefinition] = [], races: Array[RaceDefinition] = [], castes: Array[CasteDefinition] = [], items: Array[ItemDefinition] = [], spells: Array[SpellDefinition] = [], monsters: Array[MonsterDefinition] = [], battles: Array[BattleDefinition] = [], treasures: Array[TreasureDefinition] = [], shops: Array[ShopDefinition] = [], complex_encounters: Array[ComplexEncounterDefinition] = [], thief_encounters: Array[ThiefEncounterDefinition] = [], authored_timed_encounters: Array[TimedEncounterDefinition] = [], authored_option_labels: Array[OptionLabelDefinition] = [], campaign_definition: CampaignDefinition = null, appearance_options: Array[CharacterAppearanceDefinition] = [], monster_sets: Dictionary = {}) -> void:
	campaign_id = campaign
	package_hash = package_identity
	content_id = content_identity
	rules_version = rules
	start_map_id = start_map
	start_coordinate = start_position
	world = world_definition
	scenario = scenario_definition
	self.campaign = campaign_definition if campaign_definition != null else CampaignDefinition.new()
	self.campaign.id = campaign_id if self.campaign.id.is_empty() else self.campaign.id
	for message: MessageDefinition in messages:
		_messages[message.id] = message
	for option_label: OptionLabelDefinition in authored_option_labels:
		_option_labels[option_label.id] = option_label
	for trigger: TriggerDefinition in triggers:
		_triggers[trigger.id] = trigger
	for encounter: SimpleEncounterDefinition in simple_encounters:
		_simple_encounters[encounter.id] = encounter
	for encounter: ComplexEncounterDefinition in complex_encounters:
		_complex_encounters[encounter.id] = encounter
	for encounter: ThiefEncounterDefinition in thief_encounters:
		_thief_encounters[encounter.id] = encounter
	for encounter: TimedEncounterDefinition in authored_timed_encounters:
		_timed_encounters[encounter.id] = encounter
	for race: RaceDefinition in races:
		_races[race.id] = race
	for caste: CasteDefinition in castes:
		_castes[caste.id] = caste
	for item: ItemDefinition in items:
		_items[item.id] = item
	for spell: SpellDefinition in spells:
		_spells[spell.id] = spell
	for monster: MonsterDefinition in monsters:
		_monsters[monster.id] = monster
		_base_monsters[monster.id] = monster
	for set_id: Variant in monster_sets:
		var records: Dictionary = {}
		for monster: MonsterDefinition in monster_sets[set_id]:
			records["classic.monster.%d" % monster.classic_id] = monster
			_monsters[monster.id] = monster
		_monster_sets[int(set_id)] = records
	for battle: BattleDefinition in battles:
		_battles[battle.id] = battle
	for treasure: TreasureDefinition in treasures:
		_treasures[treasure.id] = treasure
	for shop: ShopDefinition in shops:
		_shops[shop.id] = shop
	for option: CharacterAppearanceDefinition in appearance_options:
		_appearance_options[option.id] = option
		_appearance_by_resource[_appearance_resource_key(option.kind, option.classic_resource_id)] = option


func message_by_id(message_id: int) -> MessageDefinition:
	return _messages.get(message_id) as MessageDefinition


func option_label_by_id(option_label_id: int) -> OptionLabelDefinition:
	return _option_labels.get(option_label_id) as OptionLabelDefinition


func has_option_labels() -> bool:
	return not _option_labels.is_empty()


func campaign_definition() -> CampaignDefinition:
	return campaign


func trigger_by_id(trigger_id: String) -> TriggerDefinition:
	return _triggers.get(trigger_id) as TriggerDefinition


func trigger_by_map_record(map_id: String, record_index: int) -> TriggerDefinition:
	for value: Variant in _triggers.values():
		var trigger := value as TriggerDefinition
		if trigger.map_id == map_id and trigger.classic_record_index == record_index:
			return trigger
	return null


func simple_encounter_by_id(encounter_id: int) -> SimpleEncounterDefinition:
	return _simple_encounters.get(encounter_id) as SimpleEncounterDefinition


func complex_encounter_by_id(encounter_id: int) -> ComplexEncounterDefinition:
	return _complex_encounters.get(encounter_id) as ComplexEncounterDefinition


func thief_encounter_by_id(encounter_id: int) -> ThiefEncounterDefinition:
	return _thief_encounters.get(encounter_id) as ThiefEncounterDefinition


func timed_encounter_by_id(encounter_id: int) -> TimedEncounterDefinition:
	return _timed_encounters.get(encounter_id) as TimedEncounterDefinition


func timed_encounters() -> Array[TimedEncounterDefinition]:
	var result: Array[TimedEncounterDefinition] = []
	var ids: Array = _timed_encounters.keys()
	ids.sort()
	for id: Variant in ids:
		result.append(_timed_encounters[id] as TimedEncounterDefinition)
	return result


func race_by_id(definition_id: String) -> RaceDefinition:
	return _races.get(definition_id) as RaceDefinition


func caste_by_id(definition_id: String) -> CasteDefinition:
	return _castes.get(definition_id) as CasteDefinition


func appearance_by_id(definition_id: String) -> CharacterAppearanceDefinition:
	var local := _appearance_options.get(definition_id) as CharacterAppearanceDefinition
	return local if local != null else _application_appearance_options.get(definition_id) as CharacterAppearanceDefinition


func appearance_by_resource(kind: StringName, classic_resource_id: int) -> CharacterAppearanceDefinition:
	var key := _appearance_resource_key(kind, classic_resource_id)
	var local := _appearance_by_resource.get(key) as CharacterAppearanceDefinition
	return local if local != null else _application_appearance_by_resource.get(key) as CharacterAppearanceDefinition


func appearance_definitions(kind: StringName) -> Array[CharacterAppearanceDefinition]:
	var result: Array[CharacterAppearanceDefinition] = []
	var occupied_resources: Dictionary = {}
	for value: Variant in _appearance_options.values():
		var option := value as CharacterAppearanceDefinition
		if option.kind == kind:
			result.append(option)
			occupied_resources[option.classic_resource_id] = true
	for value: Variant in _application_appearance_options.values():
		var option := value as CharacterAppearanceDefinition
		if option.kind == kind and not occupied_resources.has(option.classic_resource_id):
			result.append(option)
	result.sort_custom(func(left: CharacterAppearanceDefinition, right: CharacterAppearanceDefinition) -> bool: return left.classic_resource_id < right.classic_resource_id)
	return result


func set_application_appearance_catalog(application_content: RealmzContent) -> void:
	_application_appearance_options.clear()
	_application_appearance_by_resource.clear()
	if application_content == null or application_content == self:
		return
	for kind: StringName in [CharacterAppearanceDefinition.PORTRAIT, CharacterAppearanceDefinition.COMBAT_ICON]:
		for option: CharacterAppearanceDefinition in application_content.appearance_definitions(kind):
			_application_appearance_options[option.id] = option
			_application_appearance_by_resource[_appearance_resource_key(option.kind, option.classic_resource_id)] = option


func has_character_appearance_catalog() -> bool:
	return not appearance_definitions(CharacterAppearanceDefinition.PORTRAIT).is_empty() and not appearance_definitions(CharacterAppearanceDefinition.COMBAT_ICON).is_empty()


func item_by_id(definition_id: String) -> ItemDefinition:
	return _items.get(definition_id) as ItemDefinition


func item_by_classic_id(classic_id: int) -> ItemDefinition:
	for value: Variant in _items.values():
		var definition := value as ItemDefinition
		if definition.classic_id == classic_id:
			return definition
	return null


func spell_by_classic_id(classic_id: int) -> SpellDefinition:
	for value: Variant in _spells.values():
		var definition := value as SpellDefinition
		if definition.classic_id == classic_id:
			return definition
	return null


func spell_by_id(definition_id: String) -> SpellDefinition:
	return _spells.get(definition_id) as SpellDefinition


func monster_by_id(definition_id: String) -> MonsterDefinition:
	return _monsters.get(definition_id) as MonsterDefinition


func monster_by_id_for_set(definition_id: String, set_id: int) -> MonsterDefinition:
	var records: Variant = _monster_sets.get(set_id)
	if records is Dictionary and records.has(definition_id):
		return records[definition_id] as MonsterDefinition
	return monster_by_id(definition_id)


func available_monster_sets() -> Array[int]:
	var result: Array[int] = [0]
	for classic_set_id: int in [-1, 1]:
		if _monster_sets.has(classic_set_id):
			result.append(classic_set_id)
	var extension_sets: Array[int] = []
	for value: Variant in _monster_sets.keys():
		var set_id := int(value)
		if set_id not in [0, -1, 1]:
			extension_sets.append(set_id)
	extension_sets.sort()
	result.append_array(extension_sets)
	return result


func bestiary_definitions_for_set(set_id: int) -> Array[MonsterDefinition]:
	var result: Array[MonsterDefinition] = []
	for value: Variant in _base_monsters.values():
		var base := value as MonsterDefinition
		var definition := monster_by_id_for_set(base.id, set_id)
		if definition != null and definition.hit_dice > 0 and definition.hit_dice != 255 and not definition.not_on_menu:
			result.append(definition)
	result.sort_custom(func(left: MonsterDefinition, right: MonsterDefinition) -> bool: return left.classic_id < right.classic_id)
	return result


func monster_by_classic_id(classic_id: int) -> MonsterDefinition:
	for value: Variant in _monsters.values():
		var definition := value as MonsterDefinition
		if definition.classic_id == classic_id:
			return definition
	return null


func monster_by_classic_id_for_set(classic_id: int, set_id: int) -> MonsterDefinition:
	return monster_by_id_for_set("classic.monster.%d" % classic_id, set_id)


func battle_by_id(definition_id: String) -> BattleDefinition:
	return _battles.get(definition_id) as BattleDefinition


func battle_by_classic_id(classic_id: int) -> BattleDefinition:
	for value: Variant in _battles.values():
		var definition := value as BattleDefinition
		if definition.classic_id == classic_id:
			return definition
	return null


func treasure_by_id(definition_id: String) -> TreasureDefinition:
	return _treasures.get(definition_id) as TreasureDefinition


func treasure_by_classic_id(classic_id: int) -> TreasureDefinition:
	for value: Variant in _treasures.values():
		var definition := value as TreasureDefinition
		if definition.classic_id == classic_id:
			return definition
	return null


func shop_by_id(definition_id: String) -> ShopDefinition:
	return _shops.get(definition_id) as ShopDefinition


func shop_by_classic_id(classic_id: int) -> ShopDefinition:
	for value: Variant in _shops.values():
		var definition := value as ShopDefinition
		if definition.classic_id == classic_id:
			return definition
	return null


func item_definitions() -> Array[ItemDefinition]:
	var result: Array[ItemDefinition] = []
	var ids: Array = _items.keys()
	ids.sort()
	for id: Variant in ids:
		result.append(_items[id] as ItemDefinition)
	return result


func race_definitions() -> Array[RaceDefinition]:
	var result: Array[RaceDefinition] = []
	var ids: Array = _races.keys()
	ids.sort()
	for id: Variant in ids:
		result.append(_races[id] as RaceDefinition)
	return result


func caste_definitions() -> Array[CasteDefinition]:
	var result: Array[CasteDefinition] = []
	var ids: Array = _castes.keys()
	ids.sort()
	for id: Variant in ids:
		result.append(_castes[id] as CasteDefinition)
	return result


func spell_definitions() -> Array[SpellDefinition]:
	var result: Array[SpellDefinition] = []
	var ids: Array = _spells.keys()
	ids.sort()
	for id: Variant in ids:
		result.append(_spells[id] as SpellDefinition)
	return result


static func _appearance_resource_key(kind: StringName, classic_resource_id: int) -> String:
	return "%s:%d" % [kind, classic_resource_id]
