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


func equipped_damage_bonus(character: CharacterState, definitions: Array[ItemDefinition]) -> int:
	var by_id: Dictionary = {}
	for definition: ItemDefinition in definitions:
		by_id[definition.id] = definition
	var total := 0
	for instance: ItemInstance in character.inventory():
		if instance.equipped and by_id.has(instance.definition_id):
			total += (by_id[instance.definition_id] as ItemDefinition).damage_bonus
	return total
