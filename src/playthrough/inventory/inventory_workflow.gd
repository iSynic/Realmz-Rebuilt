## Coordinates carried-item equipment, transfer, split, and join transactions.

class_name InventoryWorkflow
extends RefCounted


static func equip_item(context: SessionWorkflowContext, payload: InventoryIntentPayloads.Action) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(payload.actor_id)
	var instance := item_instance(character, payload.item_id)
	var definition: ItemDefinition = null if instance == null else context.content.items.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionWorkflowResult.failed(&"unknown_item_instance", "The selected character does not carry that item instance.")
	var probe := context.rules.equipment.equip_classic(character, instance, definition, context.content.characters.race_by_id(character.race_id), context.content.characters.caste_by_id(character.caste_id), context.state.party.characters(), context.content.items.definitions())
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"item_cannot_equip", probe.reason)
	return SessionWorkflowResult.completed([DomainEvent.new(&"item_equipped", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id, "identified": instance.identified})])


static func unequip_item(context: SessionWorkflowContext, payload: InventoryIntentPayloads.Action) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(payload.actor_id)
	var instance := item_instance(character, payload.item_id)
	var definition: ItemDefinition = null if instance == null else context.content.items.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionWorkflowResult.failed(&"unknown_item_instance", "The selected character does not carry that item instance.")
	var probe := context.rules.equipment.unequip_classic(character, instance, definition, context.content.items.definitions())
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"item_cannot_unequip", probe.reason)
	return SessionWorkflowResult.completed([DomainEvent.new(&"item_unequipped", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id})])


static func trade_item(context: SessionWorkflowContext, payload: InventoryIntentPayloads.Action) -> SessionWorkflowResult:
	var source := context.state.party.character_by_id(payload.actor_id)
	var destination := context.state.party.character_by_id(payload.destination_character_id)
	var instance := item_instance(source, payload.item_id)
	var definition: ItemDefinition = null if instance == null else context.content.items.item_by_id(instance.definition_id)
	if source == null or destination == null or instance == null or definition == null:
		return SessionWorkflowResult.failed(&"invalid_item_trade", "Trade requires a carried item and two current party members.")
	var probe := trade_item_probe(context, source, destination, instance, definition)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"item_cannot_trade", probe.reason)
	var transferred_scrolls: Array[SpellScrollState] = []
	var destination_scrolls: Array[SpellScrollState] = []
	var source_equipped := instance.equipped
	if absi(definition.item_type) == 13:
		for scroll: SpellScrollState in source.scroll_case():
			transferred_scrolls.append(SpellScrollState.from_data(scroll.to_data()))
		for scroll: SpellScrollState in destination.scroll_case():
			destination_scrolls.append(SpellScrollState.from_data(scroll.to_data()))
	probe = context.rules.inventory.trade_classic(source, destination, instance, definition)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"item_cannot_trade", probe.reason)
	if not transferred_scrolls.is_empty():
		var empty_scrolls: Array[SpellScrollState] = []
		for _index: int in 5:
			empty_scrolls.append(SpellScrollState.new())
		if not destination.set_scroll_case(transferred_scrolls) or not source.set_scroll_case(empty_scrolls):
			var returned := context.rules.inventory.remove_item(destination, instance.id, definition)
			if returned != null and context.rules.inventory.restore_item(source, returned, definition):
				returned.equipped = source_equipped
			source.set_scroll_case(transferred_scrolls)
			destination.set_scroll_case(destination_scrolls)
			return SessionWorkflowResult.failed(&"scroll_case_transfer_failed", "The scroll case records could not be transferred.")
	return SessionWorkflowResult.completed([DomainEvent.new(&"item_traded", {"fromCharacterId": source.id, "toCharacterId": destination.id, "instanceId": instance.id, "itemId": definition.id, "scrollsTransferred": transferred_scrolls.size()})])


static func trade_item_probe(context: SessionWorkflowContext, source: CharacterState, destination: CharacterState, instance: ItemInstance, definition: ItemDefinition) -> InventoryActionProbe:
	var probe := context.rules.inventory.classic_trade_probe(source, destination, instance, definition)
	if not probe.allowed or definition == null or absi(definition.item_type) != 13:
		return probe
	for carried: ItemInstance in destination.inventory():
		var carried_definition := context.content.items.item_by_id(carried.definition_id)
		if carried_definition != null and absi(carried_definition.item_type) == 13:
			return InventoryActionProbe.block("%s already carries a scroll case." % destination.name)
	for scroll: SpellScrollState in destination.scroll_case():
		if not scroll.is_empty():
			return InventoryActionProbe.block("%s already has scrolls assigned to a case." % destination.name)
	return probe


static func split_item(context: SessionWorkflowContext, payload: InventoryIntentPayloads.Action) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(payload.actor_id)
	var instance := item_instance(character, payload.item_id)
	var definition: ItemDefinition = null if instance == null else context.content.items.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionWorkflowResult.failed(&"unknown_item_instance", "The selected character does not carry that item instance.")
	var probe := context.rules.inventory.classic_split_probe(character, instance, definition)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"item_cannot_split", probe.reason)
	var previous_charges := instance.charges
	var new_instance_id := context.state.next_instance_id("inventory.item")
	probe = context.rules.inventory.split_classic(character, instance, definition, new_instance_id)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"item_split_failed", probe.reason)
	var split_instance := item_instance(character, new_instance_id)
	if split_instance == null:
		return SessionWorkflowResult.failed(&"item_split_failed", "The split item was not created.")
	return SessionWorkflowResult.completed([
		DomainEvent.new(&"item_split", {"characterId": character.id, "instanceId": instance.id, "newInstanceId": split_instance.id, "itemId": definition.id, "previousCharges": previous_charges, "remainingCharges": instance.charges, "splitCharges": split_instance.charges}),
		DomainEvent.new(&"sound_requested", {"soundId": 678, "waitForCompletion": false, "source": "classic-item"}),
	])


static func join_item(context: SessionWorkflowContext, payload: InventoryIntentPayloads.Action) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(payload.actor_id)
	var instance := item_instance(character, payload.item_id)
	var definition: ItemDefinition = null if instance == null else context.content.items.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionWorkflowResult.failed(&"unknown_item_instance", "The selected character does not carry that item instance.")
	var probe := context.rules.inventory.classic_join_probe(character, instance, definition)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"item_cannot_join", probe.reason)
	var removed_instance_ids: Array[String] = []
	for carried: ItemInstance in character.inventory():
		if carried != instance and carried.definition_id == instance.definition_id:
			removed_instance_ids.append(carried.id)
	probe = context.rules.inventory.join_classic(character, instance, definition)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"item_join_failed", probe.reason)
	return SessionWorkflowResult.completed([
		DomainEvent.new(&"item_joined", {"characterId": character.id, "instanceId": instance.id, "removedInstanceIds": removed_instance_ids, "itemId": definition.id, "charges": instance.charges}),
		DomainEvent.new(&"sound_requested", {"soundId": 663, "waitForCompletion": false, "source": "classic-item"}),
	])


static func item_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null:
		return null
	for item: ItemInstance in character.inventory():
		if item.id == instance_id:
			return item
	return null
