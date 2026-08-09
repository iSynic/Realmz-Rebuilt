class_name InventoryRules
extends RefCounted

const MAX_ITEMS: int = 30


func can_equip(character: CharacterState, item: ItemDefinition) -> bool:
	if character == null or item == null:
		return false
	if not item.specific_race_id.is_empty() and item.specific_race_id != character.race_id:
		return false
	if not item.specific_caste_id.is_empty() and item.specific_caste_id != character.caste_id:
		return false
	return true


func add_item(character: CharacterState, item: ItemDefinition, instance_id: String, identified: bool = false) -> ItemInstance:
	if character == null or item == null or character.inventory().size() >= MAX_ITEMS:
		return null
	var instance := ItemInstance.new(instance_id, item.id, item.initial_charges, false, identified)
	var items := character.inventory()
	if character.carried_load + item.instance_weight(instance.charges) > character.maximum_load:
		return null
	items.append(instance)
	character.set_inventory(items)
	character.carried_load += item.instance_weight(instance.charges)
	return instance


func equip(character: CharacterState, instance_id: String, definition: ItemDefinition) -> bool:
	if not can_equip(character, definition):
		return false
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id and instance.definition_id == definition.id:
			instance.equipped = true
			return true
	return false


func use_charge(character: CharacterState, instance_id: String, definition: ItemDefinition) -> bool:
	var items := character.inventory()
	for index: int in items.size():
		var instance := items[index]
		if instance.id != instance_id or instance.definition_id != definition.id or instance.charges == 0:
			continue
		if instance.charges > 0:
			instance.charges -= 1
			character.carried_load = maxi(0, character.carried_load - definition.weight_per_charge)
		if instance.charges == 0 and definition.drop_on_empty:
			items.remove_at(index)
			character.carried_load = maxi(0, character.carried_load - definition.weight)
			character.set_inventory(items)
		return true
	return false


func remove_item(character: CharacterState, instance_id: String, definition: ItemDefinition) -> ItemInstance:
	if character == null or definition == null:
		return null
	var items := character.inventory()
	for index: int in items.size():
		var instance := items[index]
		if instance.id != instance_id or instance.definition_id != definition.id:
			continue
		items.remove_at(index)
		character.set_inventory(items)
		character.carried_load = maxi(0, character.carried_load - definition.instance_weight(instance.charges))
		return instance
	return null


func combat_equipment(character: CharacterState, definitions: Array[ItemDefinition]) -> CharacterCombatEquipment:
	var result := CharacterCombatEquipment.new()
	if character == null:
		result.reject(&"invalid_character", "Combat equipment requires a character.")
		return result
	var by_id: Dictionary = {}
	for definition: ItemDefinition in definitions:
		by_id[definition.id] = definition
	var equipped_count := 0
	var damage_sum := 0
	var positive_damage_sum := 0
	var has_negative_damage := false
	var luck_sum := 0
	var armor_sum := 0
	var has_positive_armor := false
	var has_negative_armor := false
	for instance: ItemInstance in character.inventory():
		if not instance.equipped:
			continue
		if not by_id.has(instance.definition_id):
			result.reject(&"unknown_equipped_item", "Equipped item '%s' has no immutable definition." % instance.definition_id)
			return result
		var definition: ItemDefinition = by_id[instance.definition_id]
		equipped_count += 1
		result.equipped_damage_bonus += definition.damage_bonus
		damage_sum += definition.damage_bonus
		if definition.damage_bonus < 0:
			has_negative_damage = true
		else:
			positive_damage_sum += definition.damage_bonus
		luck_sum += definition.luck_bonus
		armor_sum += definition.armor_bonus
		has_positive_armor = has_positive_armor or definition.armor_bonus > 0
		has_negative_armor = has_negative_armor or definition.armor_bonus < 0
		if absi(definition.item_type) == 2:
			if result.melee_weapon != null:
				result.reject(&"multiple_melee_weapons", "Classic combat has one melee weapon slot, but '%s' and '%s' are both equipped." % [result.melee_weapon.id, definition.id])
				return result
			result.melee_weapon = definition
			result.melee_weapon_instance_id = instance.id
	if has_positive_armor and has_negative_armor:
		result.reject(&"unsupported_equipment_order", "Classic mixed positive and negative armor modifiers require equipment-order state that is not available yet.")
		return result
	if has_negative_damage and character.damage_bonus + positive_damage_sum > 110:
		result.reject(&"unsupported_equipment_order", "Classic cap-sensitive positive and negative damage modifiers require equipment-order state that is not available yet.")
		return result
	result.effective_damage_bonus = mini(110, character.damage_bonus + damage_sum) if equipped_count > 0 else character.damage_bonus
	result.effective_luck = character.luck + luck_sum
	result.effective_armor = maxi(0, character.armor + armor_sum)
	return result
