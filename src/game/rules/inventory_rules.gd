## Implements deterministic inventory rules without presentation dependencies.

class_name InventoryRules
extends RefCounted

const MAX_ITEMS: int = 30


func classic_use_probe(character: CharacterState, item: ItemDefinition, race: RaceDefinition, caste: CasteDefinition) -> InventoryActionProbe:
	if character == null or item == null or race == null or caste == null:
		return InventoryActionProbe.block("The character or immutable item definition is unavailable.")
	if not item.specific_race_id.is_empty() and item.specific_race_id != character.race_id:
		return InventoryActionProbe.block("This item requires %s." % item.specific_race_id.replace("_", " ").capitalize())
	if not item.specific_caste_id.is_empty() and item.specific_caste_id != character.caste_id:
		return InventoryActionProbe.block("This item requires %s." % item.specific_caste_id.replace("_", " ").capitalize())
	var category := _first_category(item.item_category_mask_low, item.item_category_mask_high)
	if category < 0:
		return InventoryActionProbe.block("This item has no Classic usability category.")
	if not _mask_has(race.item_category_mask_low, race.item_category_mask_high, category):
		return InventoryActionProbe.block("This race cannot use this item category.")
	if not _mask_has(caste.item_category_mask_low, caste.item_category_mask_high, category):
		return InventoryActionProbe.block("This class cannot use this item category.")
	if (item.race_restrictions & race.descriptor_flags) != 0:
		return InventoryActionProbe.block("This item's race restrictions exclude the character.")
	if item.race_class_only != 0 and (item.race_class_only & race.descriptor_flags) != item.race_class_only:
		return InventoryActionProbe.block("This item requires race traits the character does not have.")
	var caste_class_index := caste.caste_class - 1
	if caste_class_index < 0 or caste_class_index > 15:
		return InventoryActionProbe.block("The character's Classic class group is invalid.")
	if (item.caste_restrictions & (1 << caste_class_index)) != 0:
		return InventoryActionProbe.block("This item's class restrictions exclude the character.")
	if item.caste_class_only != 0 and (item.caste_class_only & (1 << caste_class_index)) == 0:
		return InventoryActionProbe.block("This item requires another Classic class group.")
	return InventoryActionProbe.permit()


func classic_spell_item_probe(character: CharacterState, instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition, race: RaceDefinition, caste: CasteDefinition, in_combat: bool) -> InventoryActionProbe:
	if instance == null or item == null or instance.definition_id != item.id:
		return InventoryActionProbe.block("The carried item is unavailable.")
	var use_probe := classic_use_probe(character, item, race, caste)
	if not use_probe.allowed:
		return use_probe
	if item.special_2 <= 1100:
		return InventoryActionProbe.block("This item has no Classic spell effect.")
	if spell == null or spell.classic_id != item.special_2:
		return InventoryActionProbe.block("The item's Classic spell is unavailable.")
	if instance.charges == 0:
		return InventoryActionProbe.block("This item has no charges remaining.")
	if instance.charges < 0 and item.initial_charges >= 0:
		return InventoryActionProbe.block("The item's charge state does not match its immutable definition.")
	var power := absi(item.special_1)
	if power < 1 or power > 8:
		return InventoryActionProbe.block("The item's Classic spell power is invalid.")
	if in_combat and not spell.in_combat:
		return InventoryActionProbe.block("This item cannot be used in combat.")
	if not in_combat and not spell.in_camp:
		return InventoryActionProbe.block("This item cannot be used outside combat.")
	return InventoryActionProbe.permit()


func classic_door_item_probe(character: CharacterState, instance: ItemInstance, item: ItemDefinition, race: RaceDefinition, caste: CasteDefinition, in_combat: bool, program_available: bool) -> InventoryActionProbe:
	if instance == null or item == null or instance.definition_id != item.id:
		return InventoryActionProbe.block("The carried item is unavailable.")
	var use_probe := classic_use_probe(character, item, race, caste)
	if not use_probe.allowed:
		return use_probe
	if absi(item.item_type) != 23 and item.special_1 != -23:
		return InventoryActionProbe.block("This item has no Classic door action.")
	if in_combat and item.special_1 != -23:
		return InventoryActionProbe.block("This Classic door item cannot be used in combat.")
	if instance.charges == 0:
		return InventoryActionProbe.block("This item has no charges remaining.")
	if instance.charges < 0 and item.initial_charges >= 0:
		return InventoryActionProbe.block("The item's charge state does not match its immutable definition.")
	if not program_available:
		return InventoryActionProbe.block("The item's Classic scenario action is unavailable.")
	return InventoryActionProbe.permit()


func classic_drop_probe(character: CharacterState, instance: ItemInstance) -> InventoryActionProbe:
	if character == null or instance == null:
		return InventoryActionProbe.block("The carried item is unavailable.")
	if instance.equipped:
		return InventoryActionProbe.block("Unequip this item before dropping it.")
	return InventoryActionProbe.permit()


func classic_trade_probe(source: CharacterState, destination: CharacterState, instance: ItemInstance, item: ItemDefinition) -> InventoryActionProbe:
	if source == null or destination == null or source == destination or instance == null or item == null:
		return InventoryActionProbe.block("Choose another party member.")
	if instance.equipped and not item.cursed_item_id.is_empty():
		return InventoryActionProbe.block("This cursed equipped item cannot be traded away.")
	if destination.inventory().size() >= MAX_ITEMS:
		return InventoryActionProbe.block("%s already carries 30 items." % destination.name)
	if destination.carried_load + item.instance_weight(instance.charges) > destination.maximum_load:
		return InventoryActionProbe.block("%s cannot carry this item's weight." % destination.name)
	for carried: ItemInstance in destination.inventory():
		if carried.id == instance.id:
			return InventoryActionProbe.block("The destination already has this item instance.")
	return InventoryActionProbe.permit()


func classic_split_probe(character: CharacterState, instance: ItemInstance, item: ItemDefinition) -> InventoryActionProbe:
	if character == null or instance == null or item == null or instance.definition_id != item.id:
		return InventoryActionProbe.block("The carried item is unavailable.")
	if not character.inventory().has(instance):
		return InventoryActionProbe.block("The selected item is no longer carried.")
	if item.weight_per_charge == 0:
		return InventoryActionProbe.block("Classic allows Split only for an item with per-charge weight.")
	if instance.charges < 2:
		return InventoryActionProbe.block("At least two charges are required to split this item.")
	if character.inventory().size() >= MAX_ITEMS:
		return InventoryActionProbe.block("This character already carries 30 items.")
	return InventoryActionProbe.permit()


func classic_join_probe(character: CharacterState, instance: ItemInstance, item: ItemDefinition) -> InventoryActionProbe:
	if character == null or instance == null or item == null or instance.definition_id != item.id:
		return InventoryActionProbe.block("The carried item is unavailable.")
	if item.weight_per_charge == 0:
		return InventoryActionProbe.block("Classic allows Join only for an item with per-charge weight.")
	var matches := _matching_instances(character, instance.definition_id)
	if not matches.has(instance):
		return InventoryActionProbe.block("The selected item is no longer carried.")
	if matches.size() < 2:
		return InventoryActionProbe.block("No other matching stack is available to join.")
	var total_charges := 0
	for candidate: ItemInstance in matches:
		if candidate.charges < 0:
			return InventoryActionProbe.block("Infinite-charge items cannot be joined safely.")
		total_charges += candidate.charges
		if total_charges > 32_767:
			return InventoryActionProbe.block("Joining these stacks would exceed the supported charge limit.")
		if candidate != instance and candidate.equipped and not item.cursed_item_id.is_empty():
			return InventoryActionProbe.block("An equipped cursed stack cannot be absorbed into another item.")
	return InventoryActionProbe.permit()


func trade_classic(source: CharacterState, destination: CharacterState, instance: ItemInstance, item: ItemDefinition) -> InventoryActionProbe:
	var probe := classic_trade_probe(source, destination, instance, item)
	if not probe.allowed:
		return probe
	var removed := remove_item(source, instance.id, item)
	if removed == null or not restore_item(destination, removed, item):
		if removed != null:
			restore_item(source, removed, item)
		return InventoryActionProbe.block("The item transfer could not be committed.")
	return probe


func split_classic(character: CharacterState, instance: ItemInstance, item: ItemDefinition, new_instance_id: String) -> InventoryActionProbe:
	var probe := classic_split_probe(character, instance, item)
	if not probe.allowed:
		return probe
	if new_instance_id.is_empty():
		return InventoryActionProbe.block("The split item requires a stable instance identity.")
	var items := character.inventory()
	for carried: ItemInstance in items:
		if carried.id == new_instance_id:
			return InventoryActionProbe.block("The split item identity is already in use.")
	var source_index := items.find(instance)
	if source_index < 0:
		return InventoryActionProbe.block("The selected item is no longer carried.")
	var previous_weight := item.instance_weight(instance.charges)
	var split_charges := int(instance.charges / 2)
	instance.charges -= split_charges
	var split_instance := ItemInstance.new(new_instance_id, instance.definition_id, split_charges, false, instance.identified)
	items.insert(source_index + 1, split_instance)
	character.set_inventory(items)
	var updated_weight := item.instance_weight(instance.charges) + item.instance_weight(split_instance.charges)
	character.carried_load = maxi(0, character.carried_load + updated_weight - previous_weight)
	return probe


func join_classic(character: CharacterState, instance: ItemInstance, item: ItemDefinition) -> InventoryActionProbe:
	var probe := classic_join_probe(character, instance, item)
	if not probe.allowed:
		return probe
	var items := character.inventory()
	var matches := _matching_instances(character, instance.definition_id)
	var total_charges := 0
	var previous_weight := 0
	var merged_equipped := false
	var merged_identified := false
	for candidate: ItemInstance in matches:
		total_charges += candidate.charges
		previous_weight += item.instance_weight(candidate.charges)
		merged_equipped = merged_equipped or candidate.equipped
		merged_identified = merged_identified or candidate.identified
		if candidate != instance:
			items.erase(candidate)
	instance.charges = total_charges
	instance.equipped = merged_equipped
	instance.identified = merged_identified
	character.set_inventory(items)
	character.carried_load = maxi(0, character.carried_load + item.instance_weight(total_charges) - previous_weight)
	return probe


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


func calculated_load(character: CharacterState, definitions: Array[ItemDefinition]) -> int:
	if character == null:
		return -1
	var definitions_by_id := _definitions_by_id(definitions)
	var total := character.money.gold + character.money.gems + character.money.jewelry * 15
	for instance: ItemInstance in character.inventory():
		var definition: ItemDefinition = definitions_by_id.get(instance.definition_id)
		if definition == null:
			return -1
		total += definition.instance_weight(instance.charges)
	return maxi(0, total)


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


func can_restore_item(character: CharacterState, item: ItemInstance, definition: ItemDefinition) -> bool:
	if character == null or item == null or definition == null or item.definition_id != definition.id:
		return false
	var items := character.inventory()
	if items.size() >= MAX_ITEMS or character.carried_load + definition.instance_weight(item.charges) > character.maximum_load:
		return false
	for carried: ItemInstance in items:
		if carried.id == item.id:
			return false
	return true


func restore_item(character: CharacterState, item: ItemInstance, definition: ItemDefinition) -> bool:
	if not can_restore_item(character, item, definition):
		return false
	var items := character.inventory()
	item.equipped = false
	items.append(item)
	character.set_inventory(items)
	character.carried_load += definition.instance_weight(item.charges)
	return true


func _matching_instances(character: CharacterState, definition_id: String) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	if character == null or definition_id.is_empty():
		return result
	for carried: ItemInstance in character.inventory():
		if carried.definition_id == definition_id:
			result.append(carried)
	return result


static func _first_category(low: int, high: int) -> int:
	for index: int in 58:
		if _mask_has(low, high, index):
			return index
	return -1


static func _mask_has(low: int, high: int, index: int) -> bool:
	if index < 0 or index >= 64:
		return false
	return ((low if index < 32 else high) & (1 << (index if index < 32 else index - 32))) != 0


static func _definitions_by_id(definitions: Array[ItemDefinition]) -> Dictionary:
	var result: Dictionary = {}
	for definition: ItemDefinition in definitions:
		result[definition.id] = definition
	return result
