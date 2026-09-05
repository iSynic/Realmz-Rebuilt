## Encodes and strictly restores the stable character-state save representation.

class_name CharacterStateCodec
extends RefCounted


static func encode(state: CharacterState) -> Dictionary:
	if state == null:
		return {}
	var item_data: Array[Dictionary] = []
	for item: ItemInstance in state.inventory():
		item_data.append(item.to_data())
	var scroll_data: Array[Dictionary] = []
	for scroll: SpellScrollState in state.scroll_case():
		scroll_data.append(scroll.to_data())
	var fast_spell_data: Array[Dictionary] = []
	for binding: FastSpellBindingState in state.fast_spells():
		fast_spell_data.append(binding.to_data())
	return {
		"id": state.id, "name": state.name, "currentHealth": state.current_health, "maximumHealth": state.maximum_health,
		"raceId": state.race_id, "casteId": state.caste_id, "gender": state.gender, "portraitId": state.portrait_id, "combatIconId": state.combat_icon_id, "level": state.level, "experience": state.experience, "ageDays": state.age_days, "ageGroup": state.age_group,
		"attributes": [state.brawn, state.knowledge, state.judgment, state.agility, state.vitality, state.luck],
		"toHit": state.to_hit, "dodge": state.dodge, "missile": state.missile, "twoHand": state.two_hand, "handToHand": state.hand_to_hand, "damageBonus": state.damage_bonus,
		"armor": state.armor, "magicResistance": state.magic_resistance, "movement": state.movement, "maximumMovement": state.maximum_movement,
		"normalAttacks": state.normal_attacks, "attackBonus": state.attack_bonus, "attacksRemaining": state.attacks_remaining, "maximumSpellAttacks": state.maximum_spell_attacks, "spellcasterType": state.spellcaster_type,
		"spellPoints": state.spell_points, "maximumSpellPoints": state.maximum_spell_points, "load": state.carried_load, "maximumLoad": state.maximum_load,
		"prestigePenalty": state.prestige_penalty,
		"lifetimeRecord": state.lifetime_record.to_data(),
		"traitor": state.traitor,
		"conditions": state.conditions.to_data(), "money": state.money.to_data(), "saves": state.save_values, "specials": state.special_values, "abilities": state.ability_values,
		"inventory": item_data, "knownSpells": state.known_spells(), "scrollCase": scroll_data, "fastSpells": fast_spell_data,
	}


static func decode(data: Variant) -> CharacterState:
	if not data is Dictionary or not _base_fields_are_valid(data):
		return null
	var health := _integer(data["currentHealth"])
	var maximum := _integer(data["maximumHealth"])
	if health < -32_768 or maximum < 1 or health > maximum:
		return null
	var result := CharacterState.new(data["id"], data["name"], health, maximum)
	if not data.has("raceId"):
		return result
	if not _extended_shape_is_valid(data):
		return null
	if not _restore_numeric_fields(result, data):
		return null
	if not _restore_attributes_and_checks(result, data):
		return null
	if not _restore_inventory_and_spells(result, data):
		return null
	if not _restore_scrolls(result, data) or not _restore_fast_spells(result, data):
		return null
	return result


static func copy(state: CharacterState) -> CharacterState:
	return null if state == null else decode(encode(state))


static func _base_fields_are_valid(data: Dictionary) -> bool:
	for field: String in ["id", "name", "currentHealth", "maximumHealth"]:
		if not data.has(field):
			return false
	return data["id"] is String and not data["id"].is_empty() and data["name"] is String


static func _extended_shape_is_valid(data: Dictionary) -> bool:
	for field: String in ["raceId", "casteId", "gender", "level", "experience", "ageDays", "attributes", "toHit", "dodge", "missile", "handToHand", "damageBonus", "armor", "magicResistance", "movement", "maximumMovement", "normalAttacks", "attacksRemaining", "spellcasterType", "spellPoints", "maximumSpellPoints", "load", "maximumLoad", "conditions", "money", "saves", "specials", "inventory", "knownSpells"]:
		if not data.has(field):
			return false
	return data["raceId"] is String and not data["raceId"].is_empty() and data["casteId"] is String and not data["casteId"].is_empty() and data["attributes"] is Array and data["attributes"].size() == 6 and data["saves"] is Array and data["saves"].size() == 8 and data["specials"] is Array and data["specials"].size() == 12 and data["inventory"] is Array and data["knownSpells"] is Array


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
	result.lifetime_record = CharacterLifetimeRecord.from_data(data.get("lifetimeRecord", {}), CharacterLifetimeRecord.new())
	if result.lifetime_record == null or data.has("traitor") and not data["traitor"] is bool:
		return false
	result.traitor = bool(data.get("traitor", false))
	result.conditions = loaded_conditions
	result.money = loaded_money
	return true


static func _restore_attributes_and_checks(result: CharacterState, data: Dictionary) -> bool:
	var attributes := _signed_array(data["attributes"], 6)
	var saves := _signed_array(data["saves"], 8)
	var specials := _signed_array(data["specials"], 12)
	var ability_data: Variant = data.get("abilities", [])
	if not ability_data is Array or ability_data.size() not in [0, 15]:
		return false
	var abilities := _signed_array(ability_data, 15) if not ability_data.is_empty() else _zeroes(15)
	if attributes.is_empty() or saves.is_empty() or specials.is_empty() or abilities.is_empty():
		return false
	result.brawn = attributes[0]
	result.knowledge = attributes[1]
	result.judgment = attributes[2]
	result.agility = attributes[3]
	result.vitality = attributes[4]
	result.luck = attributes[5]
	for index: int in saves.size():
		result.set_save_value(index, saves[index], false)
	for index: int in specials.size():
		result.set_special_value(index, specials[index], false)
	for index: int in abilities.size():
		result.set_ability_value(index, abilities[index], false)
	return true


static func _restore_inventory_and_spells(result: CharacterState, data: Dictionary) -> bool:
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
	result.set_inventory(items)
	result.set_known_spells(spells)
	return true


static func _restore_scrolls(result: CharacterState, data: Dictionary) -> bool:
	var values: Variant = data.get("scrollCase", [])
	if not values is Array or values.size() not in [0, 5]:
		return false
	var scrolls: Array[SpellScrollState] = []
	if values.is_empty():
		for index: int in 5:
			scrolls.append(SpellScrollState.new())
	else:
		for value: Variant in values:
			var scroll := SpellScrollState.from_data(value)
			if scroll == null:
				return false
			scrolls.append(scroll)
	return result.set_scroll_case(scrolls)


static func _restore_fast_spells(result: CharacterState, data: Dictionary) -> bool:
	var values: Variant = data.get("fastSpells", [])
	if not values is Array or values.size() not in [0, 10]:
		return false
	var bindings: Array[FastSpellBindingState] = []
	if values.is_empty():
		for index: int in 10:
			bindings.append(FastSpellBindingState.new())
	else:
		for value: Variant in values:
			var binding := FastSpellBindingState.from_data(value)
			if binding == null:
				return false
			bindings.append(binding)
	return result.set_fast_spells(bindings)


static func _signed_array(values: Array, expected_size: int) -> Array[int]:
	if values.size() != expected_size:
		return []
	var result: Array[int] = []
	for value: Variant in values:
		var parsed := _signed_integer(value)
		if parsed == -100_000:
			return []
		result.append(parsed)
	return result


static func _zeroes(size: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(size)
	result.fill(0)
	return result


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
