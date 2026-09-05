## Strictly decodes Level Up and Treasure interaction request bodies.
class_name InteractionRewardRequestDecoder
extends RefCounted


static func parse(request_kind: StringName, payload: Dictionary) -> InteractionRequestBody:
	if request_kind == &"level_up":
		return _level_up_from_data(payload)
	if request_kind == &"treasure_distribution":
		return _treasure_from_data(payload)
	return null


static func _level_up_from_data(payload: Dictionary) -> LevelUpRequestBody:
	var allowed: Array = [
		"mode", "prompt", "characterId", "characterName", "level", "gains", "pointTotal", "spells",
	]
	var required: Array = ["mode", "prompt", "characterId", "characterName"]
	if not InteractionValueDecoderSupport.exact(payload, allowed, required):
		return null
	if not InteractionValueDecoderSupport.strings(payload, required):
		return null
	var result := LevelUpRequestBody.new()
	result.mode = StringName(payload["mode"])
	result.prompt = payload["prompt"]
	result.character_id = payload["characterId"]
	result.character_name = payload["characterName"]
	if result.mode == &"result":
		return _populate_level_result(result, payload)
	if result.mode == &"spell-selection":
		return _populate_spell_selection(result, payload)
	return null


static func _populate_level_result(result: LevelUpRequestBody, payload: Dictionary) -> LevelUpRequestBody:
	var fields: Array = ["mode", "prompt", "characterId", "characterName", "level", "gains"]
	if not InteractionValueDecoderSupport.exact(payload, fields, fields):
		return null
	if not InteractionValueDecoderSupport.whole(payload["level"]):
		return null
	result.level = int(payload["level"])
	result.gains = InteractionRewardValueDecoder.level_gains(payload["gains"])
	return result if result.gains != null else null


static func _populate_spell_selection(result: LevelUpRequestBody, payload: Dictionary) -> LevelUpRequestBody:
	var fields: Array = ["mode", "prompt", "characterId", "characterName", "pointTotal", "spells"]
	if not InteractionValueDecoderSupport.exact(payload, fields, fields):
		return null
	if not InteractionValueDecoderSupport.whole(payload["pointTotal"]) or not payload["spells"] is Array:
		return null
	result.point_total = int(payload["pointTotal"])
	for entry: Variant in payload["spells"]:
		var spell := InteractionRewardValueDecoder.spell_choice(entry)
		if spell == null:
			return null
		result.spells.append(spell)
	return result


static func _treasure_from_data(payload: Dictionary) -> TreasureRequestBody:
	var allowed: Array = [
		"mode", "prompt", "item", "items", "remaining", "characters", "wealth",
		"experienceShare", "detect", "identify", "hasShareCapacity", "summary", "battleId",
		"origin", "sourceId", "experiencePool",
	]
	if not InteractionValueDecoderSupport.exact(payload, allowed, ["mode"]):
		return null
	if not InteractionValueDecoderSupport.strings(payload, ["mode"]):
		return null
	if not InteractionValueDecoderSupport.optional_strings(payload, ["prompt", "summary", "battleId", "origin", "sourceId"]):
		return null
	if not InteractionValueDecoderSupport.optional_ints(payload, ["remaining", "experienceShare", "experiencePool"]):
		return null
	if not InteractionValueDecoderSupport.optional_bools(payload, ["hasShareCapacity"]):
		return null
	var result := TreasureRequestBody.new()
	result.mode = StringName(payload["mode"])
	if result.mode not in [&"fumbled-item-recovery", &"ordinary", &"completion-confirmation"]:
		return null
	result.prompt = String(payload.get("prompt", ""))
	if not _populate_treasure_items(result, payload):
		return null
	if not _populate_treasure_characters(result, payload):
		return null
	if not _populate_treasure_details(result, payload):
		return null
	return result


static func _populate_treasure_items(result: TreasureRequestBody, payload: Dictionary) -> bool:
	result.has_item = payload.has("item")
	if result.has_item and payload["item"] != null:
		result.item = InteractionRewardValueDecoder.reward_item(payload["item"])
		if result.item == null:
			return false
	result.has_items = payload.has("items")
	if result.has_items:
		if not payload["items"] is Array:
			return false
		for entry: Variant in payload["items"]:
			var reward_item := InteractionRewardValueDecoder.reward_item(entry)
			if reward_item == null:
				return false
			result.items.append(reward_item)
	if result.mode == &"ordinary":
		return result.has_items and not result.has_item
	if result.mode == &"fumbled-item-recovery":
		return result.has_item and not result.has_items
	return not result.has_item and not result.has_items


static func _populate_treasure_characters(result: TreasureRequestBody, payload: Dictionary) -> bool:
	result.remaining = int(payload.get("remaining", 0))
	result.has_remaining = payload.has("remaining")
	if payload.has("characters"):
		if not payload["characters"] is Array:
			return false
		for entry: Variant in payload["characters"]:
			var character := InteractionRewardValueDecoder.reward_character(entry, result.mode)
			if character == null:
				return false
			result.characters.append(character)
	if result.mode == &"ordinary":
		return _ordinary_assignments_are_valid(result)
	return result.mode != &"fumbled-item-recovery" or result.item == null or not result.item.has_assignments


static func _ordinary_assignments_are_valid(result: TreasureRequestBody) -> bool:
	var character_ids: Dictionary = {}
	for character: InteractionRequestValue.RewardCharacter in result.characters:
		if character_ids.has(character.id):
			return false
		character_ids[character.id] = true
	for item: InteractionRequestValue.RewardItem in result.items:
		if not item.has_assignments or item.assignments.size() != character_ids.size():
			return false
		var assignment_ids: Dictionary = {}
		for assignment: InteractionRequestValue.RewardAssignment in item.assignments:
			if not character_ids.has(assignment.character_id) or assignment_ids.has(assignment.character_id):
				return false
			assignment_ids[assignment.character_id] = true
	return true


static func _populate_treasure_details(result: TreasureRequestBody, payload: Dictionary) -> bool:
	if payload.has("wealth"):
		result.wealth = InteractionCommonValueDecoder.wealth(payload["wealth"])
		if result.wealth == null:
			return false
	result.experience_share = int(payload.get("experienceShare", 0))
	if payload.has("detect"):
		result.detect = InteractionRewardValueDecoder.reward_method(payload["detect"])
		if result.detect == null:
			return false
	if payload.has("identify"):
		result.identify = InteractionRewardValueDecoder.reward_method(payload["identify"])
		if result.identify == null:
			return false
	result.has_share_capacity = bool(payload.get("hasShareCapacity", false))
	result.summary = String(payload.get("summary", ""))
	result.battle_id = String(payload.get("battleId", ""))
	result.origin = StringName(payload.get("origin", ""))
	result.source_id = String(payload.get("sourceId", ""))
	result.experience_pool = int(payload.get("experiencePool", 0))
	return true
