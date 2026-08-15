class_name InventoryMagicServicesWorkflow
extends RefCounted


static func set_fast_spell(context: SessionWorkflowContext, payload: PlayerIntent.SpellPayload) -> SessionWorkflowResult:
	if context.state.combat != null and not context.state.combat.completed:
		return SessionWorkflowResult.failed(&"fast_spell_binding_in_battle", "Fast Spell bindings cannot be changed during battle.")
	var character := context.state.party.character_by_id(payload.caster_id)
	if character == null or payload.scroll_slot < 0 or payload.scroll_slot >= 10:
		return SessionWorkflowResult.failed(&"invalid_fast_spell_slot", "The selected Fast Spell slot is unavailable.")
	if payload.spell_id.is_empty():
		if not character.clear_fast_spell(payload.scroll_slot):
			return SessionWorkflowResult.failed(&"fast_spell_binding_failed", "The Fast Spell slot could not be cleared.")
		return SessionWorkflowResult.completed([DomainEvent.new(&"fast_spell_changed", {"characterId": character.id, "slot": payload.scroll_slot, "spellId": "", "power": 0, "source": "classic"})])
	var spell := context.content.spell_by_id(payload.spell_id)
	if spell == null or not character.known_spells().has(spell.id):
		return SessionWorkflowResult.failed(&"invalid_fast_spell", "Fast Spells must reference a spell known by this character.")
	if payload.power < 1 or payload.power > 7 or spell.cost < 0 and payload.power != 1:
		return SessionWorkflowResult.failed(&"invalid_fast_spell_power", "The selected spell does not support that Fast Spell power.")
	if not character.bind_fast_spell(payload.scroll_slot, spell.id, payload.power):
		return SessionWorkflowResult.failed(&"fast_spell_binding_failed", "The Fast Spell binding could not be committed.")
	return SessionWorkflowResult.completed([DomainEvent.new(&"fast_spell_changed", {"characterId": character.id, "slot": payload.scroll_slot, "spellId": spell.id, "power": payload.power, "source": "classic"})])


static func equip_item(context: SessionWorkflowContext, payload: PlayerIntent.ItemActionPayload) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(payload.actor_id)
	var instance := _item_instance(character, payload.item_id)
	var definition: ItemDefinition = null if instance == null else context.content.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionWorkflowResult.failed(&"unknown_item_instance", "The selected character does not carry that item instance.")
	var probe := context.rules.inventory.equip_classic(character, instance, definition, context.content.race_by_id(character.race_id), context.content.caste_by_id(character.caste_id), context.state.party.characters(), context.content.item_definitions())
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"item_cannot_equip", probe.reason)
	return SessionWorkflowResult.completed([DomainEvent.new(&"item_equipped", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id, "identified": instance.identified})])


static func unequip_item(context: SessionWorkflowContext, payload: PlayerIntent.ItemActionPayload) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(payload.actor_id)
	var instance := _item_instance(character, payload.item_id)
	var definition: ItemDefinition = null if instance == null else context.content.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionWorkflowResult.failed(&"unknown_item_instance", "The selected character does not carry that item instance.")
	var probe := context.rules.inventory.unequip_classic(character, instance, definition, context.content.item_definitions())
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"item_cannot_unequip", probe.reason)
	return SessionWorkflowResult.completed([DomainEvent.new(&"item_unequipped", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id})])


static func trade_item(context: SessionWorkflowContext, payload: PlayerIntent.ItemActionPayload) -> SessionWorkflowResult:
	var source := context.state.party.character_by_id(payload.actor_id)
	var destination := context.state.party.character_by_id(payload.destination_character_id)
	var instance := _item_instance(source, payload.item_id)
	var definition: ItemDefinition = null if instance == null else context.content.item_by_id(instance.definition_id)
	if source == null or destination == null or instance == null or definition == null:
		return SessionWorkflowResult.failed(&"invalid_item_trade", "Trade requires a carried item and two current party members.")
	var probe := context.rules.inventory.trade_classic(source, destination, instance, definition)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"item_cannot_trade", probe.reason)
	return SessionWorkflowResult.completed([DomainEvent.new(&"item_traded", {"fromCharacterId": source.id, "toCharacterId": destination.id, "instanceId": instance.id, "itemId": definition.id})])


static func _item_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null:
		return null
	for item: ItemInstance in character.inventory():
		if item.id == instance_id:
			return item
	return null
