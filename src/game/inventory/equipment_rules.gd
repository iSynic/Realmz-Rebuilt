## Owns wearable-item admission, equipment mutation, and combat loadout projection.

class_name EquipmentRules
extends RefCounted

var _inventory: InventoryRules
var _characters: CharacterRules


class CombatEquipmentSummary extends CharacterCombatEquipment:
	var equipped_count: int = 0
	var damage_sum: int = 0
	var positive_damage_sum: int = 0
	var has_negative_damage: bool = false
	var luck_sum: int = 0
	var armor_sum: int = 0
	var has_positive_armor: bool = false
	var has_negative_armor: bool = false


func _init(inventory_rules: InventoryRules, character_rules: CharacterRules) -> void:
	_inventory = inventory_rules
	_characters = character_rules


func has_equipped_scroll_case(character: CharacterState, content: RealmzContent) -> bool:
	if character == null or content == null:
		return false
	for instance: ItemInstance in character.inventory():
		var definition := content.items.item_by_id(instance.definition_id)
		if instance.equipped and definition != null and absi(definition.item_type) == 13:
			return true
	return false


func can_equip(character: CharacterState, item: ItemDefinition) -> bool:
	if character == null or item == null:
		return false
	if not item.specific_race_id.is_empty() and item.specific_race_id != character.race_id:
		return false
	if not item.specific_caste_id.is_empty() and item.specific_caste_id != character.caste_id:
		return false
	return true


func classic_equip_probe(character: CharacterState, instance: ItemInstance, item: ItemDefinition, race: RaceDefinition, caste: CasteDefinition, party: Array[CharacterState], definitions: Array[ItemDefinition]) -> InventoryActionProbe:
	if character == null or instance == null or item == null or instance.definition_id != item.id:
		return InventoryActionProbe.block("The carried item is unavailable.")
	if instance.equipped:
		return InventoryActionProbe.block("This item is already equipped.")
	var use_probe := _inventory.classic_use_probe(character, item, race, caste)
	if not use_probe.allowed:
		return use_probe
	var item_type := absi(item.item_type)
	if item_type > 19:
		return InventoryActionProbe.block("Classic treats this as a usable item, not wearable equipment.")
	if not _passive_effects_supported(item):
		return InventoryActionProbe.block("This item's passive equipment effects are not implemented yet.")
	if item.cost < 0 and _party_carries_definition(party, character, item.id):
		return InventoryActionProbe.block("Only one party member may equip this unique item.")
	return _equipment_slot_probe(character, item, definitions)


func classic_unequip_probe(character: CharacterState, instance: ItemInstance, item: ItemDefinition, definitions: Array[ItemDefinition]) -> InventoryActionProbe:
	if character == null or instance == null or item == null or instance.definition_id != item.id:
		return InventoryActionProbe.block("The carried item is unavailable.")
	if not instance.equipped:
		return InventoryActionProbe.block("This item is not equipped.")
	if not item.cursed_item_id.is_empty():
		return InventoryActionProbe.block("This cursed item cannot be removed.")
	if absi(item.item_type) == 10:
		var by_id := _definitions_by_id(definitions)
		for carried: ItemInstance in character.inventory():
			var definition: ItemDefinition = by_id.get(carried.definition_id)
			if carried.equipped and definition != null and absi(definition.item_type) == 15:
				return InventoryActionProbe.block("Unequip the missile weapon before removing its quiver.")
	return InventoryActionProbe.permit()


func equip_classic(character: CharacterState, instance: ItemInstance, item: ItemDefinition, race: RaceDefinition, caste: CasteDefinition, party: Array[CharacterState], definitions: Array[ItemDefinition], party_conditions: ConditionSet = null) -> InventoryActionProbe:
	var probe := classic_equip_probe(character, instance, item, race, caste, party, definitions)
	if not probe.allowed:
		return probe
	character.equipment_order.record_equipped(instance, character.inventory())
	_apply_wear_effects(character, item, race, definitions, party_conditions)
	if not item.cursed_item_id.is_empty():
		instance.identified = true
	return probe


func unequip_classic(character: CharacterState, instance: ItemInstance, item: ItemDefinition, definitions: Array[ItemDefinition], race: RaceDefinition = null, party_conditions: ConditionSet = null) -> InventoryActionProbe:
	var probe := classic_unequip_probe(character, instance, item, definitions)
	if probe.allowed:
		character.equipment_order.record_unequipped(instance, character.inventory())
		_apply_remove_effects(character, item, race, definitions, party_conditions)
	return probe


func force_unequip(character: CharacterState, instance: ItemInstance, item: ItemDefinition, definitions: Array[ItemDefinition], race: RaceDefinition = null, party_conditions: ConditionSet = null) -> bool:
	if character == null or instance == null or item == null or instance.definition_id != item.id or not instance.equipped:
		return false
	if not character.equipment_order.record_unequipped(instance, character.inventory()):
		return false
	_apply_remove_effects(character, item, race, definitions, party_conditions)
	if race == null and item.movement_bonus != 0:
		character.maximum_movement = maxi(2, character.maximum_movement - item.movement_bonus)
		character.movement = mini(character.movement, character.maximum_movement)
	return true


func equip(character: CharacterState, instance_id: String, definition: ItemDefinition) -> bool:
	if not can_equip(character, definition):
		return false
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id and instance.definition_id == definition.id:
			return character.equipment_order.record_equipped(instance, character.inventory())
	return false


func combat_equipment(character: CharacterState, definitions: Array[ItemDefinition]) -> CharacterCombatEquipment:
	if character == null:
		var invalid := CharacterCombatEquipment.new()
		invalid.reject(&"invalid_character", "Combat equipment requires a character.")
		return invalid
	var definitions_by_id := _definitions_by_id(definitions)
	var summary := _summarize_equipment(character, definitions_by_id)
	if not summary.valid:
		return summary
	if summary.equipped_count == 0:
		summary.effective_damage_bonus = character.damage_bonus
		summary.effective_armor = character.armor
		summary.effective_luck = character.luck
		return summary
	var ordered_definitions := _ordered_equipped_definitions(character, definitions_by_id)
	summary.effective_damage_bonus = character.damage_bonus
	summary.effective_armor = character.armor
	for definition: ItemDefinition in ordered_definitions:
		summary.effective_damage_bonus = mini(110, summary.effective_damage_bonus + definition.damage_bonus)
		summary.effective_armor = maxi(0, summary.effective_armor + definition.armor_bonus)
	summary.effective_luck = character.luck + summary.luck_sum
	return summary


static func _ordered_equipped_definitions(character: CharacterState, definitions_by_id: Dictionary) -> Array[ItemDefinition]:
	var by_instance: Dictionary = {}
	for item: ItemInstance in character.inventory():
		if item.equipped:
			by_instance[item.id] = item
	var result: Array[ItemDefinition] = []
	var consumed: Dictionary = {}
	for instance_id: String in character.equipment_order.ids():
		var instance := by_instance.get(instance_id) as ItemInstance
		var definition := definitions_by_id.get(instance.definition_id) as ItemDefinition if instance != null else null
		if definition != null:
			result.append(definition)
			consumed[instance_id] = true
	for instance: ItemInstance in character.inventory():
		if not instance.equipped or consumed.has(instance.id):
			continue
		var definition := definitions_by_id.get(instance.definition_id) as ItemDefinition
		if definition != null:
			result.append(definition)
	return result


func _apply_wear_effects(character: CharacterState, item: ItemDefinition, race: RaceDefinition, definitions: Array[ItemDefinition], party_conditions: ConditionSet) -> void:
	character.brawn += item.strength_bonus
	character.magic_resistance += item.magic_resistance_bonus
	character.maximum_spell_points += item.spell_point_bonus
	character.spell_points += item.spell_point_bonus
	if item.special_1 >= 60 and item.special_1 < 100:
		character.conditions.set_value(item.special_2, 0)
	if item.special_1 == 122:
		character.attack_bonus += item.special_2
	if item.special_1 >= 20 and item.special_1 < 60:
		var condition_index := item.special_1 - 20
		if character.conditions.value(condition_index) >= 0:
			character.conditions.set_value(condition_index, 0)
		character.conditions.add(condition_index, item.special_2)
	_apply_special_effect(character, party_conditions, item.special_3, item.special_5, true)
	_apply_special_effect(character, party_conditions, item.special_4, item.special_5, true)
	_recalculate_movement(character, race, definitions)


func _apply_remove_effects(character: CharacterState, item: ItemDefinition, race: RaceDefinition, definitions: Array[ItemDefinition], party_conditions: ConditionSet) -> void:
	if item.special_1 == 122:
		character.attack_bonus -= item.special_2
	_apply_special_effect(character, party_conditions, item.special_3, item.special_5, false)
	_apply_special_effect(character, party_conditions, item.special_4, item.special_5, false)
	character.brawn -= item.strength_bonus
	character.magic_resistance -= item.magic_resistance_bonus
	character.maximum_spell_points -= item.spell_point_bonus
	character.spell_points -= item.spell_point_bonus
	if item.special_1 >= 60 and item.special_1 < 100:
		character.conditions.set_value(item.special_2, 0)
	if item.special_1 >= 20 and item.special_1 < 60:
		var condition_index := item.special_1 - 20
		var value := character.conditions.value(condition_index)
		if value < 0:
			value -= item.special_2
		if value > 0:
			value = 0
		character.conditions.set_value(condition_index, value)
	_recalculate_movement(character, race, definitions)


static func _apply_special_effect(character: CharacterState, party_conditions: ConditionSet, special: int, amount: int, wearing: bool) -> void:
	if special == 0:
		return
	if special < 0:
		character.set_special_value(absi(special) - 1, character.special_value(absi(special) - 1) + amount * (1 if wearing else -1), false)
	elif special <= 15:
		character.set_ability_value(special - 1, character.ability_value(special - 1) + amount * (1 if wearing else -1), false)
	elif party_conditions != null:
		var index := special - 30
		party_conditions.set_value(index, party_conditions.value(index) - absi(amount) if wearing else 0)


func _recalculate_movement(character: CharacterState, race: RaceDefinition, definitions: Array[ItemDefinition]) -> void:
	if race == null:
		character.maximum_load = maxi(500, character.brawn * character.brawn * 20)
		character.movement = mini(character.movement, character.maximum_movement)
		return
	var movement_bonus := 0
	var by_id := _definitions_by_id(definitions)
	for definition: ItemDefinition in _ordered_equipped_definitions(character, by_id):
		movement_bonus += definition.movement_bonus
	_characters.recalculate_movement(character, race, movement_bonus)


func _equipment_slot_probe(character: CharacterState, item: ItemDefinition, definitions: Array[ItemDefinition]) -> InventoryActionProbe:
	var definitions_by_id := _definitions_by_id(definitions)
	var occupied_types: Dictionary = {}
	var used_hands := 0
	var equipped_ring_ids: Array[int] = []
	var has_quiver := false
	for carried: ItemInstance in character.inventory():
		if not carried.equipped:
			continue
		var equipped: ItemDefinition = definitions_by_id.get(carried.definition_id)
		if equipped == null:
			return InventoryActionProbe.block("An equipped item has no immutable definition.")
		var equipped_type := absi(equipped.item_type)
		occupied_types[equipped_type] = true
		if equipped_type == 2:
			used_hands += maxi(0, equipped.hands)
		elif equipped_type == 3:
			used_hands += 1
		elif equipped_type == 0:
			equipped_ring_ids.append(equipped.classic_id)
		elif equipped_type == 10:
			has_quiver = true
	var item_type := absi(item.item_type)
	if item_type == 0:
		if equipped_ring_ids.size() >= 2:
			return InventoryActionProbe.block("Both Classic ring slots are occupied.")
		if equipped_ring_ids.has(item.classic_id):
			return InventoryActionProbe.block("Classic does not allow the same ring in both slots.")
		return InventoryActionProbe.permit()
	if item_type > 1 and occupied_types.has(item_type):
		return InventoryActionProbe.block("The Classic equipment slot for this item is occupied.")
	if item_type == 2 and used_hands + maxi(0, item.hands) > 2:
		return InventoryActionProbe.block("The character does not have enough free hands.")
	if item_type == 3 and used_hands + maxi(1, item.hands) > 2:
		return InventoryActionProbe.block("The character does not have enough free hands for this shield.")
	if item_type == 15 and _mask_has(item.item_category_mask_low, item.item_category_mask_high, 12) and not has_quiver:
		return InventoryActionProbe.block("This missile weapon requires an equipped quiver.")
	return InventoryActionProbe.permit()


func _summarize_equipment(character: CharacterState, definitions_by_id: Dictionary) -> CombatEquipmentSummary:
	var summary := CombatEquipmentSummary.new()
	for instance: ItemInstance in character.inventory():
		if not instance.equipped:
			continue
		if not definitions_by_id.has(instance.definition_id):
			summary.reject(&"unknown_equipped_item", "Equipped item '%s' has no immutable definition." % instance.definition_id)
			return summary
		var definition: ItemDefinition = definitions_by_id[instance.definition_id]
		summary.equipped_count += 1
		summary.equipped_damage_bonus += definition.damage_bonus
		summary.damage_sum += definition.damage_bonus
		if definition.damage_bonus < 0:
			summary.has_negative_damage = true
		else:
			summary.positive_damage_sum += definition.damage_bonus
		summary.luck_sum += definition.luck_bonus
		summary.armor_sum += definition.armor_bonus
		summary.has_positive_armor = summary.has_positive_armor or definition.armor_bonus > 0
		summary.has_negative_armor = summary.has_negative_armor or definition.armor_bonus < 0
		if not _assign_combat_slot(summary, instance, definition):
			return summary
	return summary


func _assign_combat_slot(equipment: CharacterCombatEquipment, instance: ItemInstance, definition: ItemDefinition) -> bool:
	var item_type := absi(definition.item_type)
	if item_type == 2:
		if equipment.melee_weapon != null:
			equipment.reject(&"multiple_melee_weapons", "Classic combat has one melee weapon slot, but '%s' and '%s' are both equipped." % [equipment.melee_weapon.id, definition.id])
			return false
		equipment.melee_weapon = definition
		equipment.melee_weapon_instance_id = instance.id
	elif item_type == 15:
		if equipment.missile_weapon != null:
			equipment.reject(&"multiple_missile_weapons", "Classic combat has one missile weapon slot, but '%s' and '%s' are both equipped." % [equipment.missile_weapon.id, definition.id])
			return false
		equipment.missile_weapon = definition
		equipment.missile_weapon_instance_id = instance.id
	elif item_type == 10:
		if equipment.missile_ammunition != null:
			equipment.reject(&"multiple_missile_ammunition", "Classic combat has one missile ammunition slot, but '%s' and '%s' are both equipped." % [equipment.missile_ammunition.id, definition.id])
			return false
		equipment.missile_ammunition = definition
		equipment.missile_ammunition_instance_id = instance.id
	return true


static func _party_carries_definition(party: Array[CharacterState], character: CharacterState, definition_id: String) -> bool:
	for member: CharacterState in party:
		if member == character:
			continue
		for carried: ItemInstance in member.inventory():
			if carried.definition_id == definition_id:
				return true
	return false


static func _passive_effects_supported(item: ItemDefinition) -> bool:
	if item.special_1 >= 60 and item.special_1 < 100 and (item.special_2 < 0 or item.special_2 >= ConditionSet.CHARACTER_COUNT):
		return false
	return _special_effect_supported(item.special_3) and _special_effect_supported(item.special_4)


static func _special_effect_supported(special: int) -> bool:
	return special == 0 or special >= -12 and special <= -1 or special >= 1 and special <= 15 or special >= 30 and special < 30 + ConditionSet.PARTY_COUNT


static func _mask_has(low: int, high: int, index: int) -> bool:
	if index < 0 or index >= 64:
		return false
	return ((low if index < 32 else high) & (1 << (index if index < 32 else index - 32))) != 0


static func _definitions_by_id(definitions: Array[ItemDefinition]) -> Dictionary:
	var result: Dictionary = {}
	for definition: ItemDefinition in definitions:
		result[definition.id] = definition
	return result
