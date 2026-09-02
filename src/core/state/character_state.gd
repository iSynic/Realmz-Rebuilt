class_name CharacterState
extends RefCounted

const CharacterLifetimeRecordType := preload("res://src/core/state/character_lifetime_record.gd")

var id: String
var name: String
var current_health: int
var maximum_health: int
var race_id: String = "realmz.race.human"
var caste_id: String = "realmz.caste.adventurer"
var gender: int = 1
var portrait_id: String = ""
var combat_icon_id: String = ""
var level: int = 1
var experience: int = 0
var age_days: int = 0
var age_group: int = 0
var brawn: int = 10
var knowledge: int = 10
var judgment: int = 10
var agility: int = 10
var vitality: int = 10
var luck: int = 10
var to_hit: int = 0
var dodge: int = 20
var missile: int = 0
var two_hand: int = 0
var hand_to_hand: int = 1
var damage_bonus: int = 0
var armor: int = 0
var magic_resistance: int = 0
var movement: int = 0
var maximum_movement: int = 10
var normal_attacks: int = 1
var attack_bonus: int = 0
var attacks_remaining: int = 1
var maximum_spell_attacks: int = 0
var spellcaster_type: int = 0
var spell_points: int = 0
var maximum_spell_points: int = 0
var carried_load: int = 0
var maximum_load: int = 0
var prestige_penalty: int = 0
var lifetime_record: CharacterLifetimeRecordType
var traitor: bool = false
var conditions: ConditionSet
var money: WealthState
var _saves: Array[int] = []
var _specials: Array[int] = []
var _abilities: Array[int] = []
var _inventory: Array[ItemInstance] = []
var _known_spells: Array[String] = []
var _scroll_case: Array[SpellScrollState] = []
var _fast_spells: Array[FastSpellBindingState] = []


func _init(character_id: String, character_name: String, health: int, max_health: int) -> void:
	id = character_id
	name = character_name
	current_health = health
	maximum_health = max_health
	conditions = ConditionSet.new()
	money = WealthState.new()
	lifetime_record = CharacterLifetimeRecordType.new()
	_saves.resize(8)
	_saves.fill(50)
	_specials.resize(12)
	_specials.fill(0)
	_abilities.resize(15)
	_abilities.fill(0)
	for index: int in 5:
		_scroll_case.append(SpellScrollState.new())
	for index: int in 10:
		_fast_spells.append(FastSpellBindingState.new())


func save_value(index: int) -> int:
	return 0 if index < 0 or index >= _saves.size() else _saves[index]


func set_save_value(index: int, value: int) -> bool:
	if index < 0 or index >= _saves.size():
		return false
	_saves[index] = clampi(value, -99, 120)
	return true


func set_save_value_raw(index: int, value: int) -> bool:
	if index < 0 or index >= _saves.size():
		return false
	_saves[index] = value
	return true


func special_value(index: int) -> int:
	return 0 if index < 0 or index >= _specials.size() else _specials[index]


func set_special_value(index: int, value: int) -> bool:
	if index < 0 or index >= _specials.size():
		return false
	_specials[index] = clampi(value, -32_768, 32_767)
	return true


func ability_value(index: int) -> int:
	return 0 if index < 0 or index >= _abilities.size() else _abilities[index]


func set_ability_value(index: int, value: int) -> bool:
	if index < 0 or index >= _abilities.size():
		return false
	_abilities[index] = clampi(value, -32_768, 32_767)
	return true


func inventory() -> Array[ItemInstance]:
	return _inventory.duplicate()


func set_inventory(items: Array[ItemInstance]) -> void:
	_inventory = items.duplicate()


func known_spells() -> Array[String]:
	return _known_spells.duplicate()


func set_known_spells(spell_ids: Array[String]) -> void:
	_known_spells = spell_ids.duplicate()


func scroll_case() -> Array[SpellScrollState]:
	return _scroll_case.duplicate()


func scroll_at(index: int) -> SpellScrollState:
	return null if index < 0 or index >= _scroll_case.size() else _scroll_case[index]


func set_scroll_case(scrolls: Array[SpellScrollState]) -> bool:
	if scrolls.size() != 5:
		return false
	for scroll: SpellScrollState in scrolls:
		if scroll == null:
			return false
	_scroll_case = scrolls.duplicate()
	return true


func write_scroll(index: int, spell_id: String, power: int) -> bool:
	if index < 0 or index >= _scroll_case.size() or spell_id.is_empty() or power < 1 or power > 7:
		return false
	_scroll_case[index] = SpellScrollState.new(spell_id, power)
	return true


func clear_scroll(index: int) -> bool:
	if index < 0 or index >= _scroll_case.size():
		return false
	_scroll_case[index] = SpellScrollState.new()
	return true


func fast_spells() -> Array[FastSpellBindingState]:
	return _fast_spells.duplicate()


func fast_spell_at(index: int) -> FastSpellBindingState:
	return null if index < 0 or index >= _fast_spells.size() else _fast_spells[index]


func set_fast_spells(bindings: Array[FastSpellBindingState]) -> bool:
	if bindings.size() != 10 or bindings.any(func(binding: FastSpellBindingState) -> bool: return binding == null):
		return false
	_fast_spells = bindings.duplicate()
	return true


func bind_fast_spell(index: int, spell_id: String, power: int) -> bool:
	if index < 0 or index >= _fast_spells.size() or spell_id.is_empty() or power < 1 or power > 7:
		return false
	_fast_spells[index] = FastSpellBindingState.new(spell_id, power)
	return true


func clear_fast_spell(index: int) -> bool:
	if index < 0 or index >= _fast_spells.size():
		return false
	_fast_spells[index] = FastSpellBindingState.new()
	return true


func to_data() -> Dictionary:
	var item_data: Array[Dictionary] = []
	for item: ItemInstance in _inventory:
		item_data.append(item.to_data())
	var scroll_data: Array[Dictionary] = []
	for scroll: SpellScrollState in _scroll_case:
		scroll_data.append(scroll.to_data())
	var fast_spell_data: Array[Dictionary] = []
	for binding: FastSpellBindingState in _fast_spells:
		fast_spell_data.append(binding.to_data())
	return {
		"id": id, "name": name, "currentHealth": current_health, "maximumHealth": maximum_health,
		"raceId": race_id, "casteId": caste_id, "gender": gender, "portraitId": portrait_id, "combatIconId": combat_icon_id, "level": level, "experience": experience, "ageDays": age_days, "ageGroup": age_group,
		"attributes": [brawn, knowledge, judgment, agility, vitality, luck],
		"toHit": to_hit, "dodge": dodge, "missile": missile, "twoHand": two_hand, "handToHand": hand_to_hand, "damageBonus": damage_bonus,
		"armor": armor, "magicResistance": magic_resistance, "movement": movement, "maximumMovement": maximum_movement,
		"normalAttacks": normal_attacks, "attackBonus": attack_bonus, "attacksRemaining": attacks_remaining, "maximumSpellAttacks": maximum_spell_attacks, "spellcasterType": spellcaster_type,
		"spellPoints": spell_points, "maximumSpellPoints": maximum_spell_points, "load": carried_load, "maximumLoad": maximum_load,
		"prestigePenalty": prestige_penalty,
		"lifetimeRecord": lifetime_record.to_data(),
		"traitor": traitor,
		"conditions": conditions.to_data(), "money": money.to_data(), "saves": _saves.duplicate(), "specials": _specials.duplicate(), "abilities": _abilities.duplicate(),
		"inventory": item_data, "knownSpells": _known_spells.duplicate(), "scrollCase": scroll_data, "fastSpells": fast_spell_data,
	}


static func from_data(data: Variant) -> CharacterState:
	if not data is Dictionary:
		return null
	for field: String in ["id", "name", "currentHealth", "maximumHealth"]:
		if not data.has(field):
			return null
	if not data["id"] is String or data["id"].is_empty() or not data["name"] is String:
		return null
	var health := _integer(data["currentHealth"])
	var maximum := _integer(data["maximumHealth"])
	if health < -32_768 or maximum < 1:
		return null
	if health > maximum:
		return null
	var result := CharacterState.new(data["id"], data["name"], health, maximum)
	if not data.has("raceId"):
		return result
	for field: String in ["raceId", "casteId", "gender", "level", "experience", "ageDays", "attributes", "toHit", "dodge", "missile", "handToHand", "damageBonus", "armor", "magicResistance", "movement", "maximumMovement", "normalAttacks", "attacksRemaining", "spellcasterType", "spellPoints", "maximumSpellPoints", "load", "maximumLoad", "conditions", "money", "saves", "specials", "inventory", "knownSpells"]:
		if not data.has(field):
			return null
	if not data["raceId"] is String or data["raceId"].is_empty() or not data["casteId"] is String or data["casteId"].is_empty() or not data["attributes"] is Array or data["attributes"].size() != 6 or not data["saves"] is Array or data["saves"].size() != 8 or not data["specials"] is Array or data["specials"].size() != 12 or not data["inventory"] is Array or not data["knownSpells"] is Array:
		return null
	if not _restore_numeric_fields(result, data) or not _restore_collections(result, data):
		return null
	return result


static func _restore_numeric_fields(result: CharacterState, data: Dictionary) -> bool:
	var numeric_values: Dictionary = {}
	for field: String in ["gender", "level", "experience", "ageDays", "toHit", "dodge", "missile", "handToHand", "damageBonus", "armor", "magicResistance", "movement", "maximumMovement", "normalAttacks", "attacksRemaining", "spellcasterType", "spellPoints", "maximumSpellPoints", "load", "maximumLoad"]:
		var value := _signed_integer(data[field])
		if value == -100_000:
			return false
		numeric_values[field] = value
	for field: String in ["attackBonus", "maximumSpellAttacks", "prestigePenalty", "twoHand"]:
		var value := _signed_integer(data.get(field, 0))
		if value == -100_000:
			return false
		numeric_values[field] = value
	var loaded_conditions := ConditionSet.from_data(data["conditions"], ConditionSet.CHARACTER_COUNT)
	var loaded_money := WealthState.from_data(data["money"])
	if loaded_conditions == null or loaded_money == null:
		return false
	result.race_id = data["raceId"]
	result.caste_id = data["casteId"]
	result.gender = numeric_values["gender"]
	result.portrait_id = String(data.get("portraitId", ""))
	result.combat_icon_id = String(data.get("combatIconId", ""))
	result.level = numeric_values["level"]
	result.experience = numeric_values["experience"]
	result.age_days = numeric_values["ageDays"]
	result.age_group = _signed_integer(data.get("ageGroup", 0))
	if result.age_group < 0 or result.age_group > 5:
		return false
	result.to_hit = numeric_values["toHit"]
	result.dodge = numeric_values["dodge"]
	result.missile = numeric_values["missile"]
	result.two_hand = numeric_values["twoHand"]
	result.hand_to_hand = numeric_values["handToHand"]
	result.damage_bonus = numeric_values["damageBonus"]
	result.armor = numeric_values["armor"]
	result.magic_resistance = numeric_values["magicResistance"]
	result.movement = numeric_values["movement"]
	result.maximum_movement = numeric_values["maximumMovement"]
	result.normal_attacks = numeric_values["normalAttacks"]
	result.attack_bonus = numeric_values["attackBonus"]
	result.attacks_remaining = numeric_values["attacksRemaining"]
	result.maximum_spell_attacks = numeric_values["maximumSpellAttacks"]
	result.spellcaster_type = numeric_values["spellcasterType"]
	result.spell_points = numeric_values["spellPoints"]
	result.maximum_spell_points = numeric_values["maximumSpellPoints"]
	result.carried_load = numeric_values["load"]
	result.maximum_load = numeric_values["maximumLoad"]
	result.prestige_penalty = numeric_values["prestigePenalty"]
	result.lifetime_record = CharacterLifetimeRecordType.from_data(data.get("lifetimeRecord", {}), CharacterLifetimeRecordType.new())
	if result.lifetime_record == null:
		return false
	if data.has("traitor") and not data["traitor"] is bool:
		return false
	result.traitor = bool(data.get("traitor", false))
	result.conditions = loaded_conditions
	result.money = loaded_money
	return true


static func _restore_collections(result: CharacterState, data: Dictionary) -> bool:
	var attributes: Array[int] = []
	var saves: Array[int] = []
	var specials: Array[int] = []
	var abilities: Array[int] = []
	for value: Variant in data["attributes"]:
		var parsed := _signed_integer(value)
		if parsed == -100_000:
			return false
		attributes.append(parsed)
	for value: Variant in data["saves"]:
		var parsed := _signed_integer(value)
		if parsed == -100_000:
			return false
		saves.append(parsed)
	for value: Variant in data["specials"]:
		var parsed := _signed_integer(value)
		if parsed == -100_000:
			return false
		specials.append(parsed)
	var ability_data: Variant = data.get("abilities", [])
	if not ability_data is Array or ability_data.size() not in [0, 15]:
		return false
	if ability_data.is_empty():
		abilities.resize(15)
		abilities.fill(0)
	else:
		for value: Variant in ability_data:
			var parsed := _signed_integer(value)
			if parsed == -100_000:
				return false
			abilities.append(parsed)
	var items: Array[ItemInstance] = []
	for item_data: Variant in data["inventory"]:
		var item := ItemInstance.from_data(item_data)
		if item == null:
			return false
		items.append(item)
	var spells: Array[String] = []
	for spell_id: Variant in data["knownSpells"]:
		if not spell_id is String or spell_id.is_empty():
			return false
		spells.append(spell_id)
	var scrolls: Array[SpellScrollState] = []
	var scroll_data: Variant = data.get("scrollCase", [])
	if not scroll_data is Array or scroll_data.size() not in [0, 5]:
		return false
	if scroll_data.is_empty():
		for index: int in 5:
			scrolls.append(SpellScrollState.new())
	else:
		for value: Variant in scroll_data:
			var scroll := SpellScrollState.from_data(value)
			if scroll == null:
				return false
			scrolls.append(scroll)
	var fast_spells: Array[FastSpellBindingState] = []
	var fast_spell_data: Variant = data.get("fastSpells", [])
	if not fast_spell_data is Array or fast_spell_data.size() not in [0, 10]:
		return false
	if fast_spell_data.is_empty():
		for index: int in 10:
			fast_spells.append(FastSpellBindingState.new())
	else:
		for value: Variant in fast_spell_data:
			var binding := FastSpellBindingState.from_data(value)
			if binding == null:
				return false
			fast_spells.append(binding)
	result.brawn = attributes[0]
	result.knowledge = attributes[1]
	result.judgment = attributes[2]
	result.agility = attributes[3]
	result.vitality = attributes[4]
	result.luck = attributes[5]
	result._saves = saves
	result._specials = specials
	result._abilities = abilities
	result._inventory = items
	result._known_spells = spells
	result._scroll_case = scrolls
	result._fast_spells = fast_spells
	return true


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
