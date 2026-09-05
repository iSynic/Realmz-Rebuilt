## Decodes Treasure and Level Up request values.

class_name InteractionRewardValueDecoder
extends RefCounted


static func reward_item(data: Variant) -> InteractionRequestValue.RewardItem:
	var fields := ["instanceId", "definitionId", "name", "charges", "identified", "magical", "iconResourceType", "iconId", "description", "facts", "assignments"]
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, fields, ["instanceId", "definitionId", "name", "charges", "identified", "description", "facts"]) or not InteractionValueDecoderSupport.strings(data, ["instanceId", "definitionId", "name", "description"]) or not InteractionValueDecoderSupport.ints(data, ["charges"]) or not data["identified"] is bool or data.has("magical") and not data["magical"] is bool or not data["facts"] is Array:
		return null
	if not InteractionValueDecoderSupport.optional_resource_key(data):
		return null
	var result := InteractionRequestValue.RewardItem.new()
	result.instance_id = data["instanceId"]
	result.definition_id = data["definitionId"]
	result.name = data["name"]
	result.charges = int(data["charges"])
	result.identified = data["identified"]
	result.magical = bool(data.get("magical", false))
	result.has_magical = data.has("magical")
	result.icon_resource_type = String(data.get("iconResourceType", "cicn"))
	result.icon_id = int(data.get("iconId", 0))
	result.description = data["description"]
	result.has_assignments = data.has("assignments")
	if not _populate_reward_facts(data["facts"], result):
		return null
	if result.has_assignments and not _populate_reward_assignments(data["assignments"], result):
		return null
	return result


static func _populate_reward_facts(values: Array, result: InteractionRequestValue.RewardItem) -> bool:
	for entry: Variant in values:
		if not entry is Dictionary or not InteractionValueDecoderSupport.exact(entry, ["label", "value"], ["label", "value"]) or not InteractionValueDecoderSupport.strings(entry, ["label", "value"]):
			return false
		var fact := InteractionRequestValue.RewardFact.new()
		fact.label = entry["label"]
		fact.value = entry["value"]
		result.facts.append(fact)
	return true


static func _populate_reward_assignments(values: Variant, result: InteractionRequestValue.RewardItem) -> bool:
	if not values is Array:
		return false
	for entry: Variant in values:
		if not entry is Dictionary or not InteractionValueDecoderSupport.exact(entry, ["characterId", "enabled", "reason"], ["characterId", "enabled", "reason"]) or not InteractionValueDecoderSupport.strings(entry, ["characterId", "reason"]) or not entry["enabled"] is bool:
			return false
		var assignment := InteractionRequestValue.RewardAssignment.new()
		assignment.character_id = entry["characterId"]
		assignment.enabled = entry["enabled"]
		assignment.reason = entry["reason"]
		result.assignments.append(assignment)
	return true


static func reward_character(data: Variant, mode: StringName) -> InteractionRequestValue.RewardCharacter:
	if not data is Dictionary:
		return null
	var result := InteractionRequestValue.RewardCharacter.new()
	if mode == &"fumbled-item-recovery":
		var fields := ["id", "name", "currentHealth", "maximumHealth", "enabled", "reason"]
		if not InteractionValueDecoderSupport.exact(data, fields, fields) or not InteractionValueDecoderSupport.strings(data, ["id", "name", "reason"]) or not InteractionValueDecoderSupport.ints(data, ["currentHealth", "maximumHealth"]) or not data["enabled"] is bool:
			return null
		result.current_health = int(data["currentHealth"])
		result.maximum_health = int(data["maximumHealth"])
		result.has_health = true
	elif mode == &"ordinary":
		if not _populate_ordinary_character(data, result):
			return null
	else:
		return null
	result.id = data["id"]
	result.name = data["name"]
	result.enabled = data["enabled"]
	result.reason = data["reason"]
	return result


static func _populate_ordinary_character(data: Dictionary, result: InteractionRequestValue.RewardCharacter) -> bool:
	var fields := ["id", "name", "enabled", "reason", "wealth", "canTakeGold", "canTakeGems", "canTakeJewelry", "goldReason", "gemsReason", "jewelryReason", "itemCount", "maximumMovement", "load", "maximumLoad"]
	if not InteractionValueDecoderSupport.exact(data, fields, fields) or not InteractionValueDecoderSupport.strings(data, ["id", "name", "reason", "goldReason", "gemsReason", "jewelryReason"]) or not InteractionValueDecoderSupport.bools(data, ["enabled", "canTakeGold", "canTakeGems", "canTakeJewelry"]) or not InteractionValueDecoderSupport.ints(data, ["itemCount", "maximumMovement", "load", "maximumLoad"]):
		return false
	result.wealth = InteractionCommonValueDecoder.wealth(data["wealth"])
	if result.wealth == null:
		return false
	result.can_take_gold = data["canTakeGold"]
	result.can_take_gems = data["canTakeGems"]
	result.can_take_jewelry = data["canTakeJewelry"]
	result.gold_reason = data["goldReason"]
	result.gems_reason = data["gemsReason"]
	result.jewelry_reason = data["jewelryReason"]
	result.item_count = int(data["itemCount"])
	result.maximum_movement = int(data["maximumMovement"])
	result.carried_load = int(data["load"])
	result.maximum_load = int(data["maximumLoad"])
	return true


static func reward_method(data: Variant) -> InteractionRequestValue.RewardMethod:
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, ["visible", "casters", "reason"], ["visible", "casters", "reason"]) or not data["visible"] is bool or not data["casters"] is Array or not data["reason"] is String:
		return null
	var result := InteractionRequestValue.RewardMethod.new()
	result.visible = data["visible"]
	result.reason = data["reason"]
	for entry: Variant in data["casters"]:
		if not entry is Dictionary or not InteractionValueDecoderSupport.exact(entry, ["id", "name", "spellPoints", "cost"], ["id", "name", "spellPoints", "cost"]) or not InteractionValueDecoderSupport.strings(entry, ["id", "name"]) or not InteractionValueDecoderSupport.ints(entry, ["spellPoints", "cost"]):
			return null
		var caster := InteractionRequestValue.RewardCaster.new()
		caster.id = entry["id"]
		caster.name = entry["name"]
		caster.spell_points = int(entry["spellPoints"])
		caster.cost = int(entry["cost"])
		result.casters.append(caster)
	return result


static func level_gains(data: Variant) -> InteractionRequestValue.LevelGains:
	var fields := ["stamina", "spellPoints", "toHit", "magicResistance"]
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, fields, fields) or not InteractionValueDecoderSupport.ints(data, fields):
		return null
	var result := InteractionRequestValue.LevelGains.new()
	result.stamina = int(data["stamina"])
	result.spell_points = int(data["spellPoints"])
	result.to_hit = int(data["toHit"])
	result.magic_resistance = int(data["magicResistance"])
	return result


static func spell_choice(data: Variant) -> InteractionRequestValue.SpellChoice:
	var fields := ["id", "name", "description", "classicId", "cost", "selected"]
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, fields, ["id", "name", "classicId", "cost", "selected"]) or not InteractionValueDecoderSupport.strings(data, ["id", "name"]) or not InteractionValueDecoderSupport.optional_string(data, "description") or not InteractionValueDecoderSupport.ints(data, ["classicId", "cost"]) or not data["selected"] is bool:
		return null
	var result := InteractionRequestValue.SpellChoice.new()
	result.id = data["id"]
	result.name = data["name"]
	result.description = String(data.get("description", ""))
	result.classic_id = int(data["classicId"])
	result.cost = int(data["cost"])
	result.selected = data["selected"]
	return result
