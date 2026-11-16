## Item operations for the Character Files editor. Equipping uses Classic wear rules;
## the editor may remove or unequip cursed items, which play itself never allows.

class_name CharacterEditItems
extends RefCounted

var _context: CharacterEditContext


func _init(context: CharacterEditContext) -> void:
	_context = context


func apply(character: CharacterState, operation: Dictionary) -> String:
	if not _context.rules_available():
		return _context.rules_unavailable_reason
	match operation.get("kind", &"") as StringName:
		&"add_item": return _add(character, String(operation.definition_id), String(operation.instance_id))
		&"remove_item": return _remove(character, String(operation.instance_id))
		&"equip": return _equip(character, String(operation.instance_id), bool(operation.equipped))
		&"identify": return _identify(character, String(operation.instance_id))
	return "This change isn't supported."


## Why `definition` can't be added right now, or "".
func add_reason(character: CharacterState, definition: ItemDefinition) -> String:
	if not _context.rules_available():
		return _context.rules_unavailable_reason
	if character.inventory().size() >= InventoryRules.MAX_ITEMS:
		return "%s carries the most items allowed (%d)." % [character.name, InventoryRules.MAX_ITEMS]
	var weight := definition.instance_weight(definition.initial_charges)
	if character.carried_load + weight > character.maximum_load:
		return "Too heavy: %s would bring the load to %s of %s." % [InventoryRules.presentation_definition(null, definition, _context.items).name, CharacterEditLimits.group_digits(character.carried_load + weight), CharacterEditLimits.group_digits(character.maximum_load)]
	return ""


## Why the carried item can't be equipped or unequipped, or "". A wear change that would
## carry a value outside the editor's Classic ranges (such as Brawn past 57) is refused
## with that range as the reason.
func equip_reason(character: CharacterState, instance: ItemInstance) -> String:
	var definition := _definition(instance)
	if definition == null:
		return "This item comes from its scenario, not the Classic library."
	var reason := ""
	if instance.equipped:
		if definition.cursed_item_id.is_empty():
			reason = _context.rules.equipment.classic_unequip_probe(character, instance, definition, _context.item_definitions()).reason
	else:
		reason = _context.rules.equipment.classic_equip_probe(character, instance, definition, _context.race, _context.caste, [character] as Array[CharacterState], _context.item_definitions()).reason
	if not reason.is_empty():
		return reason
	var trial := CharacterStateCodec.copy(character)
	var error := _wear(trial, _instance(trial, instance.id), definition, not instance.equipped)
	return error if not error.is_empty() else CharacterEditLimits.range_error(trial, character)


func _add(character: CharacterState, definition_id: String, instance_id: String) -> String:
	var definition := _context.items.item_by_id(definition_id)
	if definition == null or instance_id.is_empty():
		return "That item isn't in the loaded rules."
	for carried: ItemInstance in character.inventory():
		if carried.id == instance_id:
			return "That item is already carried."
	var reason := add_reason(character, definition)
	if not reason.is_empty():
		return reason
	return "" if _context.rules.inventory.add_item(character, definition, instance_id, true) != null else "The item couldn't be added."


func _remove(character: CharacterState, instance_id: String) -> String:
	var instance := _instance(character, instance_id)
	if instance == null:
		return "That item isn't carried."
	var definition := _definition(instance)
	if definition == null:
		return "This item comes from its scenario, not the Classic library."
	var before := CharacterStateCodec.copy(character)
	if instance.equipped and not _context.rules.equipment.force_unequip(character, instance, definition, _context.item_definitions(), _context.race):
		return "The item couldn't be unequipped."
	if _context.rules.inventory.remove_item(character, instance_id, definition) == null:
		return "The item couldn't be removed."
	return CharacterEditLimits.range_error(character, before)


func _equip(character: CharacterState, instance_id: String, equipped: bool) -> String:
	var instance := _instance(character, instance_id)
	if instance == null:
		return "That item isn't carried."
	var definition := _definition(instance)
	if definition == null:
		return "This item comes from its scenario, not the Classic library."
	if instance.equipped == equipped:
		return "The item is already %s." % ("equipped" if equipped else "carried")
	var reason := equip_reason(character, instance)
	if not reason.is_empty():
		return reason
	var before := CharacterStateCodec.copy(character)
	var error := _wear(character, instance, definition, equipped)
	return error if not error.is_empty() else CharacterEditLimits.range_error(character, before)


func _wear(character: CharacterState, instance: ItemInstance, definition: ItemDefinition, equipped: bool) -> String:
	if equipped:
		return _context.rules.equipment.equip_classic(character, instance, definition, _context.race, _context.caste, [character] as Array[CharacterState], _context.item_definitions()).reason
	if _context.rules.equipment.force_unequip(character, instance, definition, _context.item_definitions(), _context.race):
		return ""
	return "The item couldn't be unequipped."


func _identify(character: CharacterState, instance_id: String) -> String:
	var instance := _instance(character, instance_id)
	if instance == null:
		return "That item isn't carried."
	if instance.identified:
		return "The item is already identified."
	instance.identified = true
	return ""


func _instance(character: CharacterState, instance_id: String) -> ItemInstance:
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id:
			return instance
	return null


func _definition(instance: ItemInstance) -> ItemDefinition:
	return _context.items.item_by_id(instance.definition_id) if instance != null and _context.items != null else null
