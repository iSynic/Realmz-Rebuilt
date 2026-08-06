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
var _messages: Dictionary = {}
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
var _battles: Dictionary = {}
var _treasures: Dictionary = {}
var _shops: Dictionary = {}


func _init(campaign: String, package_identity: String, content_identity: String, rules: String, start_map: String, start_position: Vector2i, world_definition: WorldDefinition, scenario_definition: ScenarioDefinition, messages: Array[MessageDefinition], triggers: Array[TriggerDefinition], simple_encounters: Array[SimpleEncounterDefinition] = [], races: Array[RaceDefinition] = [], castes: Array[CasteDefinition] = [], items: Array[ItemDefinition] = [], spells: Array[SpellDefinition] = [], monsters: Array[MonsterDefinition] = [], battles: Array[BattleDefinition] = [], treasures: Array[TreasureDefinition] = [], shops: Array[ShopDefinition] = [], complex_encounters: Array[ComplexEncounterDefinition] = [], thief_encounters: Array[ThiefEncounterDefinition] = [], authored_timed_encounters: Array[TimedEncounterDefinition] = []) -> void:
	campaign_id = campaign
	package_hash = package_identity
	content_id = content_identity
	rules_version = rules
	start_map_id = start_map
	start_coordinate = start_position
	world = world_definition
	scenario = scenario_definition
	for message: MessageDefinition in messages:
		_messages[message.id] = message
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
	for battle: BattleDefinition in battles:
		_battles[battle.id] = battle
	for treasure: TreasureDefinition in treasures:
		_treasures[treasure.id] = treasure
	for shop: ShopDefinition in shops:
		_shops[shop.id] = shop


func message_by_id(message_id: int) -> MessageDefinition:
	return _messages.get(message_id) as MessageDefinition


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


func monster_by_classic_id(classic_id: int) -> MonsterDefinition:
	for value: Variant in _monsters.values():
		var definition := value as MonsterDefinition
		if definition.classic_id == classic_id:
			return definition
	return null


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
