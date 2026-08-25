class_name MonsterState
extends RefCounted

var id: String
var definition_id: String
var name: String
var hit_dice: int
var current_health: int
var maximum_health: int
var agility: int
var armor: int
var magic_resistance: int
var spell_points: int
var maximum_spell_points: int
var traitor: bool
var summoned: bool = false
var icon_id: int = 0
var surrender_percent: int = 0
var weapon_id: String = ""
var target_id: String = ""
var conditions: ConditionSet
var _saves: Array[int] = []
var _saves_initialized: bool = false
var _loot_item_ids: Array[String] = []
var _loot_magic_detected: Array[bool] = []


func _init(instance_id: String, source_definition_id: String, display_name: String, health: int, max_health: int, hd: int = 1, dexterity: int = 1, armor_rating: int = 0, magic_resist: int = 0, spell_energy: int = 0, is_traitor: bool = true) -> void:
	id = instance_id
	definition_id = source_definition_id
	name = display_name
	current_health = health
	maximum_health = max_health
	hit_dice = hd
	agility = dexterity
	armor = armor_rating
	magic_resistance = magic_resist
	spell_points = spell_energy
	maximum_spell_points = spell_energy
	traitor = is_traitor
	conditions = ConditionSet.new()
	_saves.resize(8)
	_saves.fill(0)


func save_value(index: int) -> int:
	return 0 if index < 0 or index >= _saves.size() else _saves[index]


func set_save_value(index: int, value: int) -> bool:
	if index < 0 or index >= _saves.size() or value < -128 or value > 32767:
		return false
	_saves[index] = value
	_saves_initialized = true
	return true


func save_values() -> Array[int]:
	return _saves.duplicate()


func has_runtime_saves() -> bool:
	return _saves_initialized


func loot_item_ids() -> Array[String]:
	return _loot_item_ids.duplicate()


func set_loot_item_ids(values: Array[String]) -> bool:
	if values.size() > 6:
		return false
	_loot_item_ids = values.duplicate()
	_loot_magic_detected.resize(values.size())
	_loot_magic_detected.fill(false)
	return true


func loot_magic_detected() -> Array[bool]:
	return _loot_magic_detected.duplicate()


func set_loot_magic_detected(values: Array[bool]) -> bool:
	if values.size() != _loot_item_ids.size():
		return false
	for index: int in values.size():
		if values[index] and _loot_item_ids[index].is_empty():
			return false
	_loot_magic_detected = values.duplicate()
	return true


func mark_loot_magic_detected() -> int:
	var marked := 0
	for index: int in _loot_item_ids.size():
		if _loot_item_ids[index].is_empty() or _loot_magic_detected[index]:
			continue
		_loot_magic_detected[index] = true
		marked += 1
	return marked


func has_undetected_loot() -> bool:
	return undetected_loot_count() > 0


func undetected_loot_count() -> int:
	var result := 0
	for index: int in _loot_item_ids.size():
		if not _loot_item_ids[index].is_empty() and not _loot_magic_detected[index]:
			result += 1
	return result


func to_data() -> Dictionary:
	var result := {
		"id": id,
		"definitionId": definition_id,
		"name": name,
		"hitDice": hit_dice,
		"currentHealth": current_health,
		"maximumHealth": maximum_health,
		"agility": agility,
		"armor": armor,
		"magicResistance": magic_resistance,
		"spellPoints": spell_points,
		"maximumSpellPoints": maximum_spell_points,
		"traitor": traitor,
		"summoned": summoned,
		"iconId": icon_id,
		"surrenderPercent": surrender_percent,
		"weaponId": weapon_id,
		"targetId": target_id,
		"lootItemIds": _loot_item_ids.duplicate(),
		"lootMagicDetected": _loot_magic_detected.duplicate(),
		"conditions": conditions.to_data(),
	}
	if _saves_initialized:
		result["saves"] = _saves.duplicate()
	return result


static func from_data(data: Variant) -> MonsterState:
	if not data is Dictionary:
		return null
	for field: String in ["id", "definitionId", "name", "hitDice", "currentHealth", "maximumHealth", "agility", "armor", "magicResistance", "spellPoints", "maximumSpellPoints", "traitor", "weaponId", "conditions"]:
		if not data.has(field):
			return null
	if not data["id"] is String or data["id"].is_empty() or not data["definitionId"] is String or data["definitionId"].is_empty() or not data["name"] is String or not data["traitor"] is bool or not data["weaponId"] is String or data.has("summoned") and not data["summoned"] is bool:
		return null
	var values: Dictionary = {}
	for field: String in ["hitDice", "currentHealth", "maximumHealth", "agility", "armor", "magicResistance", "spellPoints", "maximumSpellPoints"]:
		var value := _integer(data[field])
		if value == -100_000:
			return null
		values[field] = value
	if values["hitDice"] < 0 or values["maximumHealth"] < 1 or values["maximumHealth"] > 32_767 or values["currentHealth"] < -32_768 or values["currentHealth"] > 32_767 or values["maximumSpellPoints"] < 0 or values["maximumSpellPoints"] > 32_767 or values["spellPoints"] < -32_768 or values["spellPoints"] > 32_767:
		return null
	var loaded_conditions := ConditionSet.from_data(data["conditions"], ConditionSet.CHARACTER_COUNT)
	if loaded_conditions == null:
		return null
	var result := MonsterState.new(data["id"], data["definitionId"], data["name"], values["currentHealth"], values["maximumHealth"], values["hitDice"], values["agility"], values["armor"], values["magicResistance"], values["maximumSpellPoints"], data["traitor"])
	result.spell_points = values["spellPoints"]
	result.summoned = bool(data.get("summoned", false))
	result.icon_id = _integer(data.get("iconId", 0))
	if result.icon_id == -100_000:
		return null
	result.surrender_percent = _integer(data.get("surrenderPercent", 0))
	if result.surrender_percent == -100_000:
		return null
	result.weapon_id = data["weaponId"]
	var loot_data: Variant = data.get("lootItemIds", [])
	if not loot_data is Array or loot_data.size() > 6:
		return null
	var loot_ids: Array[String] = []
	for loot_id: Variant in loot_data:
		if not loot_id is String:
			return null
		loot_ids.append(loot_id)
	if not result.set_loot_item_ids(loot_ids):
		return null
	var loot_detection_data: Variant = data.get("lootMagicDetected", [])
	if not loot_detection_data is Array or data.has("lootMagicDetected") and loot_detection_data.size() != loot_ids.size():
		return null
	var loot_detection: Array[bool] = []
	if data.has("lootMagicDetected"):
		for detected: Variant in loot_detection_data:
			if not detected is bool:
				return null
			loot_detection.append(detected)
	else:
		loot_detection.resize(loot_ids.size())
		loot_detection.fill(false)
	if not result.set_loot_magic_detected(loot_detection):
		return null
	if data.has("targetId"):
		if not data["targetId"] is String:
			return null
		result.target_id = data["targetId"]
	if data.has("saves"):
		var saves_data: Variant = data["saves"]
		if not saves_data is Array or saves_data.size() != 8:
			return null
		for index: int in 8:
			var save := _integer(saves_data[index])
			if save == -100_000 or not result.set_save_value(index, save):
				return null
	result.conditions = loaded_conditions
	return result


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
