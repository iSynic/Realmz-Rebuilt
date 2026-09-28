## Coordinates the session debug workflow against committed session state.

class_name SessionDebugWorkflow
extends RefCounted

const HARMFUL_CONDITIONS: Array[int] = [
	ConditionRules.RUNS_AWAY, ConditionRules.HELPLESS, ConditionRules.TANGLED,
	ConditionRules.CURSED, ConditionRules.STUPID, ConditionRules.SLOW,
	ConditionRules.POISONED, ConditionRules.TURNED_TO_STONE, ConditionRules.BLIND,
	ConditionRules.DISEASED, ConditionRules.CONFUSED, ConditionRules.ENERGY_DRAIN,
	ConditionRules.HINDERED_ATTACKS, ConditionRules.HINDERED_DEFENSE, ConditionRules.SILENCED,
]


static func warp(context: SessionWorkflowContext, map_id: String, coordinate: Vector2i) -> SessionWorkflowResult:
	var map := context.content.world.map_by_id(map_id)
	if map == null or map.topology.cell_at(coordinate) == null:
		return SessionWorkflowResult.failed(&"debug_location_unavailable", "The requested map coordinate is unavailable.")
	if context.state.combat != null or context.scenario_vm.is_active():
		return SessionWorkflowResult.failed(&"debug_exploration_required", "Warp is available only at a committed exploration boundary.")
	var source_map := context.state.party.map_id
	var source_coordinate := context.state.party.coordinate
	context.state.party.map_id = map.id
	context.state.party.coordinate = coordinate
	context.state.last_move_direction = Vector2i.ZERO
	context.state.world.exploration.mark_visited(map.id, coordinate)
	return SessionWorkflowResult.completed([DomainEvent.new(&"debug_party_warped", {"fromMapId": source_map, "fromX": source_coordinate.x, "fromY": source_coordinate.y, "mapId": map.id, "x": coordinate.x, "y": coordinate.y})])


static func noclip_step(context: SessionWorkflowContext, direction: Vector2i) -> SessionWorkflowResult:
	if not MapTopology.is_cardinal_direction(direction) and not MapTopology.is_diagonal_direction(direction):
		return SessionWorkflowResult.failed(&"debug_direction_invalid", "No-clip movement requires one adjacent direction.")
	var map := context.content.world.map_by_id(context.state.party.map_id)
	var source := context.state.party.coordinate
	var target := source + direction
	if map == null or map.topology.cell_at(target) == null:
		return SessionWorkflowResult.failed(&"debug_location_unavailable", "No-clip movement cannot leave the current map.")
	if context.state.combat != null or context.scenario_vm.is_active():
		return SessionWorkflowResult.failed(&"debug_exploration_required", "No-clip movement is available only at a committed exploration boundary.")
	context.state.party.coordinate = target
	context.state.last_move_direction = direction
	context.state.world.exploration.mark_visited(map.id, target)
	return SessionWorkflowResult.completed([DomainEvent.new(&"debug_party_noclip_moved", {"fromMapId": map.id, "fromX": source.x, "fromY": source.y, "mapId": map.id, "x": target.x, "y": target.y})])


static func restore_party(context: SessionWorkflowContext) -> SessionWorkflowResult:
	if context.state.party.characters().is_empty():
		return SessionWorkflowResult.failed(&"debug_party_unavailable", "The party has no characters to restore.")
	var item_definitions := context.content.items.definitions()
	var definitions_by_id: Dictionary = {}
	for definition: ItemDefinition in item_definitions:
		definitions_by_id[definition.id] = definition
	for character: CharacterState in context.state.party.characters():
		for condition: int in HARMFUL_CONDITIONS:
			if character.conditions.value(condition) != 0:
				character.conditions.set_value(condition, 0)
		var race := context.content.characters.race_by_id(character.race_id)
		for instance: ItemInstance in character.inventory():
			var definition := definitions_by_id.get(instance.definition_id) as ItemDefinition
			if instance.equipped and definition != null and not definition.cursed_item_id.is_empty():
				if not context.rules.equipment.force_unequip(character, instance, definition, item_definitions, race, context.state.party.conditions):
					return SessionWorkflowResult.failed(&"debug_cursed_item_unequip_failed", "The equipped cursed item could not be removed.")
		character.current_health = character.maximum_health
		character.spell_points = character.maximum_spell_points
	context.state.party.fatigue = 4
	return SessionWorkflowResult.completed([DomainEvent.new(&"debug_party_restored", {"characterCount": context.state.party.characters().size()})])


static func grant_item(context: SessionWorkflowContext, definition_id: String, character_id: String) -> SessionWorkflowResult:
	if context.state.combat != null or context.scenario_vm.is_active():
		return SessionWorkflowResult.failed(&"debug_exploration_required", "Giving an item is available only at a committed exploration boundary.")
	var character := context.state.party.character_by_id(character_id)
	if character == null:
		return SessionWorkflowResult.failed(&"debug_character_unavailable", "The selected party member is unavailable.")
	var definition := context.content.items.item_by_id(definition_id)
	if definition == null:
		return SessionWorkflowResult.failed(&"debug_item_unavailable", "The selected item is unavailable in this campaign.")
	if character.inventory().size() >= InventoryRules.MAX_ITEMS:
		return SessionWorkflowResult.failed(&"debug_inventory_full", "%s cannot carry another item." % character.name)
	if character.carried_load + definition.instance_weight(definition.initial_charges) > character.maximum_load:
		return SessionWorkflowResult.failed(&"debug_inventory_overweight", "%s cannot carry the weight of %s." % [character.name, definition.name])
	var instance_id := context.state.next_instance_id("inventory.item")
	var instance := context.rules.inventory.add_item(character, definition, instance_id, true)
	if instance == null:
		return SessionWorkflowResult.failed(&"debug_item_grant_failed", "The selected item could not be added to the pack.")
	return SessionWorkflowResult.completed([DomainEvent.new(&"debug_item_granted", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id, "classicId": definition.classic_id})])
