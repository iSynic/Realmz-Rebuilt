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
	var base_fields: Array[String] = ["origin", "sourceId", "experiencePool", "experienceShare", "initialWealth", "magicDetected", "identified", "completionPending", "phase", "items", "experienceAwards", "levelCharacterIds", "levelIndex", "spellCharacterIds", "spellIndex", "pendingLevelResult"]
	var required := base_fields.duplicate()
	var has_battle_sequence: bool = data.has("battleStage") or data.has("bonusTreasureClassicId")
	var has_item_detection: bool = data.has("magicDetectedItemIds")
	if has_battle_sequence:
		required.append_array(["battleStage", "bonusTreasureClassicId"])
	if has_item_detection:
		required.append("magicDetectedItemIds")
	if data.size() != required.size():
		return null
	for field: String in required:
		if not data.has(field):
			return null
	if not data["origin"] is String or data["origin"].is_empty() or not data["sourceId"] is String or not data["magicDetected"] is bool or not data["identified"] is bool or not data["completionPending"] is bool or not data["phase"] is String or StringName(data["phase"]) not in [ITEM_PHASE, LEVEL_PHASE, SPELL_PHASE] or not data["items"] is Array or not data["experienceAwards"] is Dictionary or not data["levelCharacterIds"] is Array or not data["spellCharacterIds"] is Array or not data["pendingLevelResult"] is Dictionary or (has_battle_sequence and not data["battleStage"] is String) or (has_item_detection and not data["magicDetectedItemIds"] is Array):
		return null
	var loaded_experience_pool := _integer(data["experiencePool"])
	var loaded_experience_share := _integer(data["experienceShare"])
	var loaded_level_index := _integer(data["levelIndex"])
	var loaded_spell_index := _integer(data["spellIndex"])
	var loaded_bonus_treasure_id := _integer(data["bonusTreasureClassicId"]) if has_battle_sequence else 0
	var loaded_battle_stage := StringName(data["battleStage"]) if has_battle_sequence else ORDINARY_BATTLE_STAGE if data["origin"] == "battle" else NO_BATTLE_STAGE
	if loaded_experience_pool < 0 or loaded_experience_share < 0 or loaded_level_index < 0 or loaded_spell_index < 0 or loaded_bonus_treasure_id < 0 or loaded_battle_stage not in [NO_BATTLE_STAGE, ORDINARY_BATTLE_STAGE, BONUS_BATTLE_STAGE]:
		return null
	if (data["origin"] == "battle" and loaded_battle_stage == NO_BATTLE_STAGE) or (data["origin"] != "battle" and (loaded_battle_stage != NO_BATTLE_STAGE or loaded_bonus_treasure_id != 0)) or (loaded_battle_stage == BONUS_BATTLE_STAGE and loaded_bonus_treasure_id != 0):
		return null
	var wealth := WealthState.from_data(data["initialWealth"])
	if wealth == null:
		return null
	var result := ClassicRewardState.new(StringName(data["origin"]), data["sourceId"], loaded_experience_pool, wealth)
	result.experience_share = loaded_experience_share
	result.magic_detected = data["magicDetected"]
	result.identified = data["identified"]
	result.completion_pending = data["completionPending"]
	result.phase = StringName(data["phase"])
	result.battle_stage = loaded_battle_stage
	result.bonus_treasure_classic_id = loaded_bonus_treasure_id
	var loaded_items: Array[ItemInstance] = []
	for entry: Variant in data["items"]:
		var item := ItemInstance.from_data(entry)
		if item == null:
			return null
		loaded_items.append(item)
	var awards: Dictionary = {}
	for character_id: Variant in data["experienceAwards"]:
		if not character_id is String or character_id.is_empty():
			return null
		var amount := _integer(data["experienceAwards"][character_id])
		if amount < 0:
			return null
		awards[character_id] = amount
	if not result.set_items(loaded_items) or not result.set_experience_awards(awards):
		return null
	var detected_item_ids: Array[String] = []
	if has_item_detection:
		for value: Variant in data["magicDetectedItemIds"]:
			if not value is String:
				return null
			detected_item_ids.append(value)
	if not result.set_magic_detected_item_ids(detected_item_ids):
		return null
	var level_ids: Array[String] = []
	for value: Variant in data["levelCharacterIds"]:
		if not value is String:
			return null
		level_ids.append(value)
	var spell_ids: Array[String] = []
	for value: Variant in data["spellCharacterIds"]:
		if not value is String:
			return null
		spell_ids.append(value)
	result.level_index = loaded_level_index
	result.spell_index = loaded_spell_index
	if not result.set_level_character_ids(level_ids) or not result.set_spell_character_ids(spell_ids) or result.level_index < 0 or result.level_index > level_ids.size() or result.spell_index < 0 or result.spell_index > spell_ids.size():
		return null
	var level_result: Variant = _normalized_level_result(data["pendingLevelResult"])
	if level_result == null:
		return null
	result.pending_level_result = level_result
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
