## Carries typed Classic reward state data across the gameplay transaction boundary.

class_name ClassicRewardState
extends RefCounted

const MAX_PENDING_ITEMS: int = 1000
const INVALID_INTEGER: int = -2_147_483_648
const ITEM_PHASE: StringName = &"items"
const LEVEL_PHASE: StringName = &"levels"
const SPELL_PHASE: StringName = &"spells"
const NO_BATTLE_STAGE: StringName = &""
const ORDINARY_BATTLE_STAGE: StringName = &"ordinary"
const BONUS_BATTLE_STAGE: StringName = &"bonus"

var origin: StringName
var source_id: String
var experience_pool: int
var experience_share: int
var initial_wealth: WealthState
var magic_detected: bool = false
var identified: bool = false
var completion_pending: bool = false
var phase: StringName = ITEM_PHASE
var level_index: int = 0
var spell_index: int = 0
var pending_level_result: Dictionary = {}
var battle_stage: StringName = NO_BATTLE_STAGE
var bonus_treasure_classic_id: int = 0
var _items: Array[ItemInstance] = []
var _magic_detected_item_ids: Array[String] = []
var _experience_awards: Dictionary = {}
var _level_character_ids: Array[String] = []
var _spell_character_ids: Array[String] = []


func _init(reward_origin: StringName = &"scenario", reward_source_id: String = "", total_experience: int = 0, rolled_wealth: WealthState = null) -> void:
	origin = reward_origin
	source_id = reward_source_id
	experience_pool = total_experience
	initial_wealth = WealthState.new() if rolled_wealth == null else WealthState.new(rolled_wealth.gold, rolled_wealth.gems, rolled_wealth.jewelry)


func items() -> Array[ItemInstance]:
	return _items.duplicate()


func set_items(values: Array[ItemInstance]) -> bool:
	if values.size() > MAX_PENDING_ITEMS:
		return false
	var ids: Dictionary = {}
	for item: ItemInstance in values:
		if item == null or item.id.is_empty() or item.definition_id.is_empty() or item.equipped or ids.has(item.id):
			return false
		ids[item.id] = true
	_items = values.duplicate()
	_magic_detected_item_ids = _magic_detected_item_ids.filter(func(instance_id: String) -> bool: return ids.has(instance_id))
	return true


func first_item() -> ItemInstance:
	return null if _items.is_empty() else _items[0]


func remove_item(instance_id: String) -> ItemInstance:
	for index: int in _items.size():
		if _items[index].id == instance_id:
			_magic_detected_item_ids.erase(instance_id)
			return _items.pop_at(index)
	return null


func magic_detected_item_ids() -> Array[String]:
	return _magic_detected_item_ids.duplicate()


func set_magic_detected_item_ids(values: Array[String]) -> bool:
	if not _valid_unique_ids(values):
		return values.is_empty()
	var item_ids: Dictionary = {}
	for item: ItemInstance in _items:
		item_ids[item.id] = true
	for instance_id: String in values:
		if not item_ids.has(instance_id):
			return false
	_magic_detected_item_ids = values.duplicate()
	return true


func is_magic_detected(instance_id: String) -> bool:
	return _magic_detected_item_ids.has(instance_id)


func experience_awards() -> Dictionary:
	return _experience_awards.duplicate(true)


func set_experience_awards(values: Dictionary) -> bool:
	var result: Dictionary = {}
	for character_id: Variant in values:
		var amount: Variant = values[character_id]
		if not character_id is String or character_id.is_empty() or not amount is int:
			return false
		result[character_id] = amount
	_experience_awards = result
	return true


func level_character_ids() -> Array[String]:
	return _level_character_ids.duplicate()


func set_level_character_ids(values: Array[String]) -> bool:
	if not _valid_unique_ids(values):
		return false
	_level_character_ids = values.duplicate()
	level_index = mini(level_index, _level_character_ids.size())
	return true


func spell_character_ids() -> Array[String]:
	return _spell_character_ids.duplicate()


func set_spell_character_ids(values: Array[String]) -> bool:
	if not _valid_unique_ids(values):
		return false
	_spell_character_ids = values.duplicate()
	spell_index = mini(spell_index, _spell_character_ids.size())
	return true


func to_data() -> Dictionary:
	var item_data: Array[Dictionary] = []
	for item: ItemInstance in _items:
		item_data.append(item.to_data())
	var awards: Dictionary = {}
	var award_ids: Array = _experience_awards.keys()
	award_ids.sort()
	for character_id: Variant in award_ids:
		awards[String(character_id)] = _experience_awards[character_id]
	return {
		"origin": String(origin),
		"sourceId": source_id,
		"experiencePool": experience_pool,
		"experienceShare": experience_share,
		"initialWealth": initial_wealth.to_data(),
		"magicDetected": magic_detected,
		"identified": identified,
		"completionPending": completion_pending,
		"phase": String(phase),
		"items": item_data,
		"magicDetectedItemIds": _magic_detected_item_ids.duplicate(),
		"experienceAwards": awards,
		"levelCharacterIds": _level_character_ids.duplicate(),
		"levelIndex": level_index,
		"spellCharacterIds": _spell_character_ids.duplicate(),
		"spellIndex": spell_index,
		"pendingLevelResult": pending_level_result.duplicate(true),
		"battleStage": String(battle_stage),
		"bonusTreasureClassicId": bonus_treasure_classic_id,
	}


static func from_data(data: Variant) -> ClassicRewardState:
	if not data is Dictionary:
		return null
	var has_battle_sequence: bool = data.has("battleStage") or data.has("bonusTreasureClassicId")
	var has_item_detection: bool = data.has("magicDetectedItemIds")
	if not _serialized_shape_is_valid(data, has_battle_sequence, has_item_detection):
		return null
	var scalars_value: Variant = _scalar_values_from_data(data, has_battle_sequence)
	if scalars_value == null:
		return null
	var scalars: Dictionary = scalars_value
	var wealth := WealthState.from_data(data["initialWealth"])
	if wealth == null:
		return null
	var result := ClassicRewardState.new(StringName(data["origin"]), data["sourceId"], scalars["experiencePool"], wealth)
	result.experience_share = scalars["experienceShare"]
	result.magic_detected = data["magicDetected"]
	result.identified = data["identified"]
	result.completion_pending = data["completionPending"]
	result.phase = StringName(data["phase"])
	result.battle_stage = scalars["battleStage"]
	result.bonus_treasure_classic_id = scalars["bonusTreasureClassicId"]
	if not _restore_items_and_awards(result, data, has_item_detection):
		return null
	if not _restore_progress(result, data, scalars["levelIndex"], scalars["spellIndex"]):
		return null
	return result


static func _serialized_shape_is_valid(data: Dictionary, has_battle_sequence: bool, has_item_detection: bool) -> bool:
	var required: Array[String] = [
		"origin", "sourceId", "experiencePool", "experienceShare", "initialWealth",
		"magicDetected", "identified", "completionPending", "phase", "items",
		"experienceAwards", "levelCharacterIds", "levelIndex", "spellCharacterIds",
		"spellIndex", "pendingLevelResult",
	]
	if has_battle_sequence:
		required.append_array(["battleStage", "bonusTreasureClassicId"])
	if has_item_detection:
		required.append("magicDetectedItemIds")
	if data.size() != required.size():
		return false
	for field: String in required:
		if not data.has(field):
			return false
	if not data["origin"] is String or data["origin"].is_empty() or not data["sourceId"] is String:
		return false
	if not data["magicDetected"] is bool or not data["identified"] is bool or not data["completionPending"] is bool:
		return false
	if not data["phase"] is String or StringName(data["phase"]) not in [ITEM_PHASE, LEVEL_PHASE, SPELL_PHASE]:
		return false
	if not data["items"] is Array or not data["experienceAwards"] is Dictionary or not data["pendingLevelResult"] is Dictionary:
		return false
	if not data["levelCharacterIds"] is Array or not data["spellCharacterIds"] is Array:
		return false
	return (not has_battle_sequence or data["battleStage"] is String) and (not has_item_detection or data["magicDetectedItemIds"] is Array)


static func _scalar_values_from_data(data: Dictionary, has_battle_sequence: bool) -> Variant:
	var result := {
		"experiencePool": _integer(data["experiencePool"]),
		"experienceShare": _integer(data["experienceShare"]),
		"levelIndex": _integer(data["levelIndex"]),
		"spellIndex": _integer(data["spellIndex"]),
		"bonusTreasureClassicId": _integer(data["bonusTreasureClassicId"]) if has_battle_sequence else 0,
		"battleStage": StringName(data["battleStage"]) if has_battle_sequence else ORDINARY_BATTLE_STAGE if data["origin"] == "battle" else NO_BATTLE_STAGE,
	}
	if result["experiencePool"] < 0 or result["experienceShare"] < 0:
		return null
	if result["levelIndex"] < 0 or result["spellIndex"] < 0 or result["bonusTreasureClassicId"] < 0:
		return null
	if result["battleStage"] not in [NO_BATTLE_STAGE, ORDINARY_BATTLE_STAGE, BONUS_BATTLE_STAGE]:
		return null
	if data["origin"] == "battle" and result["battleStage"] == NO_BATTLE_STAGE:
		return null
	if data["origin"] != "battle" and (result["battleStage"] != NO_BATTLE_STAGE or result["bonusTreasureClassicId"] != 0):
		return null
	return null if result["battleStage"] == BONUS_BATTLE_STAGE and result["bonusTreasureClassicId"] != 0 else result


static func _restore_items_and_awards(result: ClassicRewardState, data: Dictionary, has_item_detection: bool) -> bool:
	var loaded_items: Array[ItemInstance] = []
	for entry: Variant in data["items"]:
		var item := ItemInstance.from_data(entry)
		if item == null:
			return false
		loaded_items.append(item)
	var awards: Dictionary = {}
	for character_id: Variant in data["experienceAwards"]:
		if not character_id is String or character_id.is_empty():
			return false
		var amount := _integer(data["experienceAwards"][character_id])
		if amount < 0:
			return false
		awards[character_id] = amount
	if not result.set_items(loaded_items) or not result.set_experience_awards(awards):
		return false
	var detected_item_ids: Array[String] = []
	if has_item_detection:
		for value: Variant in data["magicDetectedItemIds"]:
			if not value is String:
				return false
			detected_item_ids.append(value)
	return result.set_magic_detected_item_ids(detected_item_ids)


static func _restore_progress(result: ClassicRewardState, data: Dictionary, loaded_level_index: int, loaded_spell_index: int) -> bool:
	var level_ids_value: Variant = _string_array_from_data(data["levelCharacterIds"])
	var spell_ids_value: Variant = _string_array_from_data(data["spellCharacterIds"])
	if level_ids_value == null or spell_ids_value == null:
		return false
	var level_ids: Array[String] = level_ids_value
	var spell_ids: Array[String] = spell_ids_value
	result.level_index = loaded_level_index
	result.spell_index = loaded_spell_index
	if not result.set_level_character_ids(level_ids) or not result.set_spell_character_ids(spell_ids):
		return false
	if result.level_index < 0 or result.level_index > level_ids.size():
		return false
	if result.spell_index < 0 or result.spell_index > spell_ids.size():
		return false
	var level_result: Variant = _normalized_level_result(data["pendingLevelResult"])
	if level_result == null:
		return false
	result.pending_level_result = level_result
	return true


static func _string_array_from_data(data: Array) -> Variant:
	var result: Array[String] = []
	for value: Variant in data:
		if not value is String:
			return null
		result.append(value)
	return result


static func _valid_unique_ids(values: Array[String]) -> bool:
	var seen: Dictionary = {}
	for value: String in values:
		if value.is_empty() or seen.has(value):
			return false
		seen[value] = true
	return true


static func _normalized_level_result(data: Dictionary) -> Variant:
	if data.is_empty():
		return {}
	var fields: Array[String] = ["characterId", "characterName", "level", "stamina", "spellPoints", "toHit", "magicResistance"]
	if data.size() != fields.size():
		return null
	for field: String in fields:
		if not data.has(field):
			return null
	if not data["characterId"] is String or data["characterId"].is_empty() or not data["characterName"] is String:
		return null
	var result: Dictionary = {"characterId": data["characterId"], "characterName": data["characterName"]}
	for field: String in ["level", "stamina", "spellPoints", "toHit", "magicResistance"]:
		var value := _integer(data[field])
		if value == INVALID_INTEGER or field == "level" and value < 1:
			return null
		result[field] = value
	return result


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return INVALID_INTEGER
