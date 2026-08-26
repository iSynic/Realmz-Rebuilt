class_name InventoryMagicServicesWorkflow
extends RefCounted


class MagicTransitionResult:
	extends RefCounted
	var ok: bool
	var completed: bool
	var process_age_updates: bool
	var events: Array[DomainEvent]
	var continuation: SessionContinuation
	var interaction: InteractionRequest
	var error_code: StringName
	var error_message: String

	static func failed(code: StringName, message: String) -> MagicTransitionResult:
		var result := MagicTransitionResult.new()
		result.error_code = code
		result.error_message = message
		return result

	static func committed(workflow_result: SessionWorkflowResult, should_process_age_updates: bool = false) -> MagicTransitionResult:
		if workflow_result == null:
			return failed(&"invalid_workflow_result", "The magic workflow returned no result.")
		if not workflow_result.ok:
			return failed(workflow_result.error_code, workflow_result.error_message)
		var result := MagicTransitionResult.new()
		result.ok = true
		result.completed = true
		result.process_age_updates = should_process_age_updates
		result.events = workflow_result.events
		return result

	static func waiting(pending_continuation: SessionContinuation, pending_interaction: InteractionRequest, pending_events: Array[DomainEvent]) -> MagicTransitionResult:
		var result := MagicTransitionResult.new()
		result.ok = true
		result.continuation = pending_continuation
		result.interaction = pending_interaction
		result.events = pending_events
		return result


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


static func classic_torch_item(context: SessionWorkflowContext) -> Array[String]:
	var torch := context.content.item_by_classic_id(805)
	if torch == null:
		return []
	for character: CharacterState in context.state.party.characters():
		for instance: ItemInstance in character.inventory():
			if instance.definition_id == torch.id:
				return [character.id, instance.id]
	return []


static func classic_torch_probe(context: SessionWorkflowContext) -> InventoryActionProbe:
	var identity := classic_torch_item(context)
	if identity.is_empty():
		return InventoryActionProbe.block("The party carries no usable torch.")
	var character := context.state.party.character_by_id(identity[0])
	var instance := _item_instance(character, identity[1])
	var item: ItemDefinition = null if instance == null else context.content.item_by_id(instance.definition_id)
	var spell: SpellDefinition = null if item == null else context.content.spell_by_classic_id(item.special_2)
	return field_spell_item_probe(context, character, instance, item, spell)


static func begin_classic_torch(context: SessionWorkflowContext, request_revision: int) -> MagicTransitionResult:
	var identity := classic_torch_item(context)
	if identity.is_empty():
		return MagicTransitionResult.failed(&"torch_unavailable", "The party carries no usable torch.")
	return begin_field_spell_item(context, identity[0], identity[1], "", [], request_revision)


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
		var carried_definition := context.content.item_by_id(carried.definition_id)
		if carried_definition != null and absi(carried_definition.item_type) == 13:
			return InventoryActionProbe.block("%s already carries a scroll case." % destination.name)
	for scroll: SpellScrollState in destination.scroll_case():
		if not scroll.is_empty():
			return InventoryActionProbe.block("%s already has scrolls assigned to a case." % destination.name)
	return probe


static func split_item(context: SessionWorkflowContext, payload: PlayerIntent.ItemActionPayload) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(payload.actor_id)
	var instance := _item_instance(character, payload.item_id)
	var definition: ItemDefinition = null if instance == null else context.content.item_by_id(instance.definition_id)
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
	var split_instance := _item_instance(character, new_instance_id)
	if split_instance == null:
		return SessionWorkflowResult.failed(&"item_split_failed", "The split item was not created.")
	return SessionWorkflowResult.completed([
		DomainEvent.new(&"item_split", {"characterId": character.id, "instanceId": instance.id, "newInstanceId": split_instance.id, "itemId": definition.id, "previousCharges": previous_charges, "remainingCharges": instance.charges, "splitCharges": split_instance.charges}),
		DomainEvent.new(&"sound_requested", {"soundId": 678, "waitForCompletion": false, "source": "classic-item"}),
	])


static func join_item(context: SessionWorkflowContext, payload: PlayerIntent.ItemActionPayload) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(payload.actor_id)
	var instance := _item_instance(character, payload.item_id)
	var definition: ItemDefinition = null if instance == null else context.content.item_by_id(instance.definition_id)
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


static func inventory_identify_probe(context: SessionWorkflowContext, target_id: String, caster_id: String, spell_id: String) -> InventoryActionProbe:
	var target := context.state.party.character_by_id(target_id)
	var caster := context.state.party.character_by_id(caster_id)
	var spell := context.content.spell_by_id(spell_id)
	if context.state.combat != null and not context.state.combat.completed:
		return InventoryActionProbe.block("Cast Identify is unavailable during battle.")
	if target == null or target.inventory().is_empty():
		return InventoryActionProbe.block("The selected character carries no items.")
	if caster == null or spell == null or absi(spell.special) != 48 or not caster.known_spells().has(spell.id) or caster.spellcaster_type < 1:
		return InventoryActionProbe.block("No party member knows Identify Objects.")
	if context.state.character_spellcasting_blocked:
		return InventoryActionProbe.block("Classic scenario state currently blocks character spellcasting.")
	if caster.current_health < 1 or caster.spell_points < 25:
		return InventoryActionProbe.block("No living Identify caster has 25 spell points.")
	for condition: int in [ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS, ConditionRules.STUPID, ConditionRules.ANIMATED]:
		if caster.conditions.is_active(condition):
			return InventoryActionProbe.block("The Identify caster's current condition prevents spellcasting.")
	return InventoryActionProbe.permit()


static func identify_inventory(context: SessionWorkflowContext, payload: PlayerIntent.SpellPayload) -> SessionWorkflowResult:
	var probe := inventory_identify_probe(context, payload.target_id, payload.caster_id, payload.spell_id)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"inventory_identification_unavailable", probe.reason)
	var target := context.state.party.character_by_id(payload.target_id)
	var caster := context.state.party.character_by_id(payload.caster_id)
	var instance_ids: Array[String] = []
	for instance: ItemInstance in target.inventory():
		instance.identified = true
		instance_ids.append(instance.id)
	caster.spell_points -= 25
	return SessionWorkflowResult.completed([
		DomainEvent.new(&"inventory_identified", {"characterId": target.id, "casterId": caster.id, "spellId": payload.spell_id, "instanceIds": instance_ids, "cost": 25, "source": "classic-items"}),
		DomainEvent.new(&"sound_requested", {"soundId": 683, "waitForCompletion": false, "source": "classic-items-identify"}),
	])


static func field_spell_item_probe(context: SessionWorkflowContext, character: CharacterState, instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition) -> InventoryActionProbe:
	var probe := context.rules.inventory.classic_spell_item_probe(character, instance, item, spell, context.content.race_by_id(character.race_id) if character != null else null, context.content.caste_by_id(character.caste_id) if character != null else null, false)
	if not probe.allowed:
		return probe
	if not field_spell_effect_supported(spell):
		return InventoryActionProbe.block(ClassicSpellCapabilityCatalog.unsupported_reason(spell, &"field-item"))
	if spell.target_type < 0 or spell.target_type > 12:
		return InventoryActionProbe.block("This item's Classic field target type is invalid.")
	return InventoryActionProbe.permit()


static func is_classic_door_item(item: ItemDefinition) -> bool:
	return item != null and (absi(item.item_type) == 23 or item.special_1 == -23)


static func door_item_probe(context: SessionWorkflowContext, character: CharacterState, instance: ItemInstance, item: ItemDefinition, in_combat: bool) -> InventoryActionProbe:
	var program_available := item != null and context.content.scenario.program_by_id("xap:%d" % item.special_5) != null
	var probe := context.rules.inventory.classic_door_item_probe(character, instance, item, context.content.race_by_id(character.race_id) if character != null else null, context.content.caste_by_id(character.caste_id) if character != null else null, in_combat, program_available)
	if not probe.allowed:
		return probe
	if in_combat and (context.state.combat == null or context.state.combat.completed or context.state.combat.active_actor_id() != character.id):
		return InventoryActionProbe.block("Only the active character may use a door item in combat.")
	return InventoryActionProbe.permit()


static func field_item_use_probe(context: SessionWorkflowContext, character: CharacterState, instance: ItemInstance, item: ItemDefinition) -> InventoryActionProbe:
	if is_classic_door_item(item):
		return door_item_probe(context, character, instance, item, false)
	return field_spell_item_probe(context, character, instance, item, context.content.spell_by_classic_id(item.special_2) if item != null else null)


static func field_item_target_ids(context: SessionWorkflowContext, character: CharacterState, spell: SpellDefinition, requested_targets: Array[String], requested_target: String) -> Array[String]:
	if spell.target_type == 7 or absi(spell.special) == 68:
		return []
	if spell.target_type == 5:
		return [character.id]
	if spell.target_type > 2:
		return _field_group_ids(context.state.party, spell)
	var values: Array[String] = requested_targets.duplicate()
	if values.is_empty() and not requested_target.is_empty():
		values.append(requested_target)
	return values


static func field_item_target_count(context: SessionWorkflowContext, spell: SpellDefinition, power: int) -> int:
	if spell.target_type == 7 or absi(spell.special) == 68:
		return 0
	if spell.target_type == 5:
		return 1
	if spell.target_type > 2:
		return _field_group_ids(context.state.party, spell).size()
	return mini(power, context.state.party.characters().size()) if spell.target_type == 0 else 1


static func begin_field_spell_item(context: SessionWorkflowContext, actor_id: String, instance_id: String, requested_target: String, requested_targets: Array[String], request_revision: int) -> MagicTransitionResult:
	var character := context.state.party.character_by_id(actor_id)
	if character == null:
		character = item_owner(context, instance_id)
	var instance := _item_instance(character, instance_id)
	var item: ItemDefinition = null if instance == null else context.content.item_by_id(instance.definition_id)
	var spell: SpellDefinition = null if item == null else context.content.spell_by_classic_id(item.special_2)
	var probe := field_spell_item_probe(context, character, instance, item, spell)
	if not probe.allowed:
		return MagicTransitionResult.failed(item_use_error_code(instance, item, spell), probe.reason)
	var power := absi(item.special_1)
	var random_power_checkpoint: Dictionary = {}
	if power == 8:
		random_power_checkpoint = context.rng.checkpoint()
		power = context.rng.draw(7, StringName("item.use.power.%s" % instance.id))
	var target_ids := field_item_target_ids(context, character, spell, requested_targets, requested_target)
	var required_count := field_item_target_count(context, spell, power)
	if target_ids.size() == required_count:
		var committed := MagicTransitionResult.committed(commit_field_spell_item(context, character.id, instance.id, spell.id, power, target_ids))
		if not committed.ok and not random_power_checkpoint.is_empty():
			context.rng.rollback(random_power_checkpoint)
		return committed
	if not target_ids.is_empty():
		if not random_power_checkpoint.is_empty():
			context.rng.rollback(random_power_checkpoint)
		return MagicTransitionResult.failed(&"invalid_item_use_target", "The item requires exactly %d valid party target%s." % [required_count, "" if required_count == 1 else "s"])
	var targeting := SessionContinuation.TargetingBody.new()
	targeting.character_id = character.id
	targeting.instance_id = instance.id
	targeting.spell_id = spell.id
	targeting.power = power
	targeting.target_count = required_count
	targeting.starting_charges = instance.charges
	var continuation := SessionContinuation.targeting_selection(&"item-use-target-selection", targeting)
	var interaction := item_target_request("session.item-use:%s:%d" % [instance.id, request_revision], character, instance.id, item, spell, power, required_count, context.state.party.characters())
	return MagicTransitionResult.waiting(continuation, interaction, [DomainEvent.new(&"item_target_requested", {"characterId": character.id, "instanceId": instance.id, "itemId": item.id, "spellId": spell.id, "power": power, "targetCount": required_count, "source": "classic"})])


static func resume_field_spell_item(context: SessionWorkflowContext, targeting: SessionContinuation.TargetingBody, target_ids: Array[String]) -> MagicTransitionResult:
	if targeting == null:
		return MagicTransitionResult.failed(&"invalid_session_continuation", "The item target continuation is unavailable.")
	if target_ids.size() != targeting.target_count:
		return MagicTransitionResult.failed(&"invalid_item_use_target", "The item requires exactly %d target%s." % [targeting.target_count, "" if targeting.target_count == 1 else "s"])
	var character := context.state.party.character_by_id(targeting.character_id)
	var instance := _item_instance(character, targeting.instance_id)
	if instance == null or instance.charges != targeting.starting_charges:
		return MagicTransitionResult.failed(&"invalid_session_continuation", "The item awaiting a target no longer matches its committed state.")
	return MagicTransitionResult.committed(commit_field_spell_item(context, targeting.character_id, targeting.instance_id, targeting.spell_id, targeting.power, target_ids))


static func commit_field_spell_item(context: SessionWorkflowContext, character_id: String, instance_id: String, spell_id: String, power: int, requested_target_ids: Array[String]) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(character_id)
	var instance := _item_instance(character, instance_id)
	var item: ItemDefinition = null if instance == null else context.content.item_by_id(instance.definition_id)
	var spell := context.content.spell_by_id(spell_id)
	var probe := field_spell_item_probe(context, character, instance, item, spell)
	if not probe.allowed:
		return SessionWorkflowResult.failed(item_use_error_code(instance, item, spell), probe.reason)
	var selected_value: Variant = _selected_field_targets(context.state.party, requested_target_ids, spell.target_type in [3, 9])
	if selected_value == null:
		return SessionWorkflowResult.failed(&"invalid_item_use_target", "The item target selection contains an unavailable or duplicate character.")
	if (selected_value as Dictionary).size() != field_item_target_count(context, spell, power):
		return SessionWorkflowResult.failed(&"invalid_item_use_target", "The item target selection has the wrong number of characters.")
	var selected: Dictionary = selected_value
	var targets := _ordered_party_targets(context.state.party, selected)
	var allies := _ordered_party_allies(context.state.party, selected)
	if not context.rules.inventory.use_charge(character, instance.id, item):
		return SessionWorkflowResult.failed(&"item_charge_commit_failed", "The validated item charge could not be committed.")
	var allow_empty := spell.target_type == 7 or absi(spell.special) == 68
	var resolution := _resolve_field_targets(context, character, targets, allies, spell, power, false, allow_empty)
	if resolution == null or not resolution.cast:
		return SessionWorkflowResult.failed(&"item_spell_failed", "The item spell could not be resolved.")
	var charges_remaining := -1
	var dropped := true
	for carried: ItemInstance in character.inventory():
		if carried.id == instance_id:
			charges_remaining = carried.charges
			dropped = false
			break
	var events: Array[DomainEvent] = [DomainEvent.new(&"item_used", {"characterId": character.id, "instanceId": instance_id, "itemId": item.id, "spellId": spell.id, "power": power, "chargesRemaining": charges_remaining, "droppedOnEmpty": dropped, "source": "classic"})]
	var native_sound_id := item.sound_id + 600
	if item.sound_id != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(native_sound_id), "waitForCompletion": native_sound_id < 0, "source": "classic-item"}))
	_append_field_spell_events(context, events, character, spell, power, resolution, &"classic-item", &"classic-item", &"item_spell_resolved", {"itemId": item.id, "instanceId": instance_id})
	return SessionWorkflowResult.completed(events)


static func item_owner(context: SessionWorkflowContext, instance_id: String) -> CharacterState:
	for character: CharacterState in context.state.party.characters():
		if _item_instance(character, instance_id) != null:
			return character
	return null


static func item_use_error_code(instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition) -> StringName:
	if instance == null or item == null:
		return &"unknown_item_instance"
	if instance.charges == 0:
		return &"item_has_no_charges"
	if item.special_2 <= 1100:
		return &"item_has_no_spell_effect"
	if spell == null:
		return &"unknown_item_spell"
	return &"item_cannot_be_used"


static func item_target_request(request_id: String, character: CharacterState, instance_id: String, item: ItemDefinition, spell: SpellDefinition, power: int, required_count: int, party: Array[CharacterState]) -> InteractionRequest:
	var display_name := item.unidentified_name
	for carried: ItemInstance in character.inventory():
		if carried.id == instance_id:
			display_name = item.name if carried.identified else item.unidentified_name
			break
	return _character_selection_request(request_id, character, "%s uses %s. Choose %d target%s." % [character.name, display_name, required_count, "" if required_count == 1 else "s"], required_count, party, &"item-use", instance_id, spell, power)


static func make_scroll(context: SessionWorkflowContext, payload: PlayerIntent.SpellPayload) -> SessionWorkflowResult:
	if context.state.combat != null and not context.state.combat.completed:
		return SessionWorkflowResult.failed(&"scroll_scribing_in_battle", "Classic scroll scribing is available only while camped.")
	var character := context.state.party.character_by_id(payload.caster_id)
	var spell := context.content.spell_by_id(payload.spell_id)
	var probe := make_scroll_probe(context, character, spell, payload.power)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"scroll_scribing_unavailable", probe.reason)
	var slot_index := _first_empty_scroll_slot(character)
	var parchment := _parchment_instance(context, character)
	var parchment_definition: ItemDefinition = null if parchment == null else context.content.item_by_id(parchment.definition_id)
	if slot_index < 0 or parchment == null or parchment_definition == null or not context.rules.inventory.use_charge(character, parchment.id, parchment_definition):
		return SessionWorkflowResult.failed(&"scroll_scribing_commit_failed", "The validated scroll materials could not be committed.")
	var cost := absi(spell.cost * payload.power * 2)
	character.spell_points -= cost
	if not character.write_scroll(slot_index, spell.id, payload.power):
		return SessionWorkflowResult.failed(&"scroll_scribing_commit_failed", "The validated scroll slot could not be committed.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"scroll_created", {"characterId": character.id, "slot": slot_index, "spellId": spell.id, "power": payload.power, "cost": cost, "parchmentInstanceId": parchment.id, "source": "classic"})]
	var sound_id := spell.sound_start + 600
	if sound_id != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(sound_id), "waitForCompletion": false, "source": "classic-scroll-scribing"}))
	return SessionWorkflowResult.completed(events)


static func make_scroll_probe(context: SessionWorkflowContext, character: CharacterState, spell: SpellDefinition, power: int) -> InventoryActionProbe:
	if character == null or spell == null or not character.known_spells().has(spell.id):
		return InventoryActionProbe.block("The character does not know that spell.")
	if not context.state.party_camping:
		return InventoryActionProbe.block("Enter camp before making a scroll.")
	if character.current_health < 1 or character.spellcaster_type < 1:
		return InventoryActionProbe.block("The selected character cannot scribe scrolls.")
	if not _has_equipped_scroll_case(context, character):
		return InventoryActionProbe.block("Equip a scroll case before making a scroll.")
	if _first_empty_scroll_slot(character) < 0:
		return InventoryActionProbe.block("The scroll case already contains five spells.")
	if _parchment_instance(context, character) == null:
		return InventoryActionProbe.block("The character has no parchment.")
	if power < 1 or power > 7 or spell.cost < 0 and power != 1:
		return InventoryActionProbe.block("This spell does not support the selected scroll power.")
	if character.spell_points < absi(spell.cost * power * 2):
		return InventoryActionProbe.block("Scribing requires twice the spell's normal spell-point cost.")
	return InventoryActionProbe.permit()


static func scroll_use_probe(context: SessionWorkflowContext, character: CharacterState, slot_index: int, spell: SpellDefinition) -> InventoryActionProbe:
	var base_probe := scroll_slot_probe(context, character, slot_index, spell)
	if not base_probe.allowed:
		return base_probe
	if not spell.in_camp:
		return InventoryActionProbe.block("This scroll cannot be used outside battle; Classic offers to discard it.")
	if spell.target_type < 0 or spell.target_type > 12:
		return InventoryActionProbe.block("This scroll has an invalid Classic field target type.")
	if not field_spell_effect_supported(spell):
		return InventoryActionProbe.block(ClassicSpellCapabilityCatalog.unsupported_reason(spell, &"field-scroll"))
	return InventoryActionProbe.permit()


static func scroll_slot_probe(context: SessionWorkflowContext, character: CharacterState, slot_index: int, spell: SpellDefinition) -> InventoryActionProbe:
	if character == null or slot_index < 0 or slot_index >= 5:
		return InventoryActionProbe.block("The scroll slot is unavailable.")
	var scroll := character.scroll_at(slot_index)
	if scroll == null or scroll.is_empty() or spell == null or spell.id != scroll.spell_id or scroll.power < 1 or scroll.power > 7:
		return InventoryActionProbe.block("This scroll slot is empty or invalid.")
	if character.current_health < 1 or character.conditions.is_active(ConditionRules.ANIMATED):
		return InventoryActionProbe.block("The selected character cannot use a scroll.")
	if not _has_equipped_scroll_case(context, character):
		return InventoryActionProbe.block("Equip the scroll case before using its spells.")
	return InventoryActionProbe.permit()


static func begin_field_scroll(context: SessionWorkflowContext, payload: PlayerIntent.SpellPayload, request_revision: int) -> MagicTransitionResult:
	var character := context.state.party.character_by_id(payload.caster_id)
	var scroll := character.scroll_at(payload.scroll_slot) if character != null else null
	var spell := context.content.spell_by_id(scroll.spell_id) if scroll != null and not scroll.is_empty() else null
	var slot_probe := scroll_slot_probe(context, character, payload.scroll_slot, spell)
	if not slot_probe.allowed:
		return MagicTransitionResult.failed(&"scroll_unavailable", slot_probe.reason)
	if not spell.in_camp:
		var discard := SessionContinuation.TargetingBody.new()
		discard.character_id = character.id
		discard.scroll_slot = payload.scroll_slot
		discard.spell_id = spell.id
		discard.power = scroll.power
		var continuation := SessionContinuation.targeting_selection(&"scroll-discard-confirmation", discard)
		var interaction := scroll_discard_request("session.scroll-discard:%s:%d:%d" % [character.id, payload.scroll_slot, request_revision], spell.name)
		return MagicTransitionResult.waiting(continuation, interaction, [DomainEvent.new(&"scroll_discard_requested", {"characterId": character.id, "slot": payload.scroll_slot, "spellId": spell.id, "power": scroll.power, "source": "classic"})])
	var probe := scroll_use_probe(context, character, payload.scroll_slot, spell)
	if not probe.allowed:
		return MagicTransitionResult.failed(&"scroll_unavailable", probe.reason)
	var target_ids := field_spell_target_ids(context, character, spell, payload.target_ids, payload.target_id)
	var required_count := field_spell_target_count(context, spell, scroll.power)
	if target_ids.size() == required_count:
		return MagicTransitionResult.committed(commit_field_scroll(context, character.id, payload.scroll_slot, spell.id, scroll.power, target_ids), true)
	if not target_ids.is_empty():
		return MagicTransitionResult.failed(&"invalid_scroll_target", "The scroll requires exactly %d valid party target%s." % [required_count, "" if required_count == 1 else "s"])
	var targeting := SessionContinuation.TargetingBody.new()
	targeting.character_id = character.id
	targeting.scroll_slot = payload.scroll_slot
	targeting.spell_id = spell.id
	targeting.power = scroll.power
	targeting.target_count = required_count
	var continuation := SessionContinuation.targeting_selection(&"scroll-target-selection", targeting)
	var interaction := scroll_target_request("session.scroll:%s:%d:%d" % [character.id, payload.scroll_slot, request_revision], character, payload.scroll_slot, spell, scroll.power, required_count, context.state.party.characters())
	return MagicTransitionResult.waiting(continuation, interaction, [DomainEvent.new(&"scroll_target_requested", {"characterId": character.id, "slot": payload.scroll_slot, "spellId": spell.id, "power": scroll.power, "targetCount": required_count, "source": "classic"})])


static func discard_field_scroll(context: SessionWorkflowContext, targeting: SessionContinuation.TargetingBody, accepted: bool) -> SessionWorkflowResult:
	if targeting == null:
		return SessionWorkflowResult.failed(&"invalid_session_continuation", "The scroll awaiting discard confirmation is unavailable.")
	var character := context.state.party.character_by_id(targeting.character_id)
	var scroll := character.scroll_at(targeting.scroll_slot) if character != null else null
	var spell := context.content.spell_by_id(targeting.spell_id)
	var probe := scroll_slot_probe(context, character, targeting.scroll_slot, spell)
	if not probe.allowed or scroll.spell_id != targeting.spell_id or scroll.power != targeting.power or spell.in_camp:
		return SessionWorkflowResult.failed(&"invalid_session_continuation", "The scroll awaiting discard confirmation no longer matches its committed state.")
	if not accepted:
		return SessionWorkflowResult.completed([DomainEvent.new(&"scroll_discard_declined", {"characterId": character.id, "slot": targeting.scroll_slot, "spellId": spell.id, "power": scroll.power, "source": "classic"})])
	if not character.clear_scroll(targeting.scroll_slot):
		return SessionWorkflowResult.failed(&"scroll_discard_failed", "The selected scroll could not be discarded.")
	return SessionWorkflowResult.completed([DomainEvent.new(&"scroll_discarded", {"characterId": character.id, "slot": targeting.scroll_slot, "spellId": spell.id, "power": targeting.power, "source": "classic"})])


static func scroll_discard_request(request_id: String, spell_name: String) -> InteractionRequest:
	return InteractionRequest.yes_no(request_id, "%s cannot be cast outside battle. Discard this scroll?" % spell_name, "Discard", "Keep")


static func resume_field_scroll(context: SessionWorkflowContext, targeting: SessionContinuation.TargetingBody, target_ids: Array[String]) -> MagicTransitionResult:
	if targeting == null:
		return MagicTransitionResult.failed(&"invalid_session_continuation", "The scroll target continuation is unavailable.")
	if target_ids.size() != targeting.target_count:
		return MagicTransitionResult.failed(&"invalid_scroll_target", "The scroll requires exactly %d target%s." % [targeting.target_count, "" if targeting.target_count == 1 else "s"])
	var character := context.state.party.character_by_id(targeting.character_id)
	var scroll := character.scroll_at(targeting.scroll_slot) if character != null else null
	if scroll == null or scroll.spell_id != targeting.spell_id or scroll.power != targeting.power:
		return MagicTransitionResult.failed(&"invalid_session_continuation", "The scroll awaiting a target no longer matches its committed state.")
	return MagicTransitionResult.committed(commit_field_scroll(context, targeting.character_id, targeting.scroll_slot, targeting.spell_id, targeting.power, target_ids), true)


static func commit_field_scroll(context: SessionWorkflowContext, character_id: String, slot_index: int, spell_id: String, power: int, requested_target_ids: Array[String]) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(character_id)
	var spell := context.content.spell_by_id(spell_id)
	var probe := scroll_use_probe(context, character, slot_index, spell)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"scroll_unavailable", probe.reason)
	var selected_value: Variant = _selected_field_targets(context.state.party, requested_target_ids, spell.target_type in [3, 9])
	if selected_value == null:
		return SessionWorkflowResult.failed(&"invalid_scroll_target", "The scroll target selection contains an unavailable or duplicate character.")
	if (selected_value as Dictionary).size() != field_spell_target_count(context, spell, power):
		return SessionWorkflowResult.failed(&"invalid_scroll_target", "The scroll target selection has the wrong number of characters.")
	var selected: Dictionary = selected_value
	var targets := _ordered_party_targets(context.state.party, selected)
	var allies := _ordered_party_allies(context.state.party, selected)
	var allow_empty := spell.target_type == 7 or absi(spell.special) == 68
	var resolution := _resolve_field_targets(context, character, targets, allies, spell, power, false, allow_empty)
	if resolution == null or not resolution.cast:
		return SessionWorkflowResult.failed(&"scroll_spell_failed", "The scroll spell could not be resolved.")
	if not character.clear_scroll(slot_index):
		return SessionWorkflowResult.failed(&"scroll_commit_failed", "The resolved scroll could not be removed from its case.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"scroll_used", {"characterId": character.id, "slot": slot_index, "spellId": spell.id, "power": power, "source": "classic"})]
	_append_field_spell_events(context, events, character, spell, power, resolution, &"classic-scroll", &"classic-scroll", &"scroll_spell_resolved")
	return SessionWorkflowResult.completed(events)


static func field_spell_probe(context: SessionWorkflowContext, character: CharacterState, spell: SpellDefinition, power: int) -> InventoryActionProbe:
	if character == null or spell == null or not character.known_spells().has(spell.id):
		return InventoryActionProbe.block("The character does not know that spell.")
	if context.state.character_spellcasting_blocked:
		return InventoryActionProbe.block("Classic scenario state currently blocks character spellcasting.")
	if character.current_health < 1 or character.spell_points < 1:
		return InventoryActionProbe.block("The character cannot cast in their current state.")
	for condition: int in [ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS, ConditionRules.STUPID, ConditionRules.ANIMATED]:
		if character.conditions.is_active(condition):
			return InventoryActionProbe.block("The character's current Classic condition prevents spellcasting.")
	if not spell.in_camp:
		return InventoryActionProbe.block("This spell cannot be cast outside battle.")
	if power < 1 or power > 7 or spell.cost < 0 and power != 1:
		return InventoryActionProbe.block("This spell does not support the selected power level.")
	if character.spell_points < absi(spell.cost * power):
		return InventoryActionProbe.block("The character does not have enough spell points.")
	if spell.target_type < 0 or spell.target_type > 12:
		return InventoryActionProbe.block("This spell has an invalid Classic field target type.")
	if not field_spell_effect_supported(spell):
		return InventoryActionProbe.block(ClassicSpellCapabilityCatalog.unsupported_reason(spell, &"field-character"))
	return InventoryActionProbe.permit()


static func field_spell_effect_supported(spell: SpellDefinition) -> bool:
	return ClassicSpellCapabilityCatalog.field_character_disposition(spell) == ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE


static func field_spell_target_ids(context: SessionWorkflowContext, character: CharacterState, spell: SpellDefinition, requested_targets: Array[String], requested_target: String) -> Array[String]:
	if spell.target_type == 5:
		return [character.id]
	if spell.target_type > 2:
		if spell.target_type == 7 or absi(spell.special) == 68:
			return []
		return _field_group_ids(context.state.party, spell)
	var values: Array[String] = requested_targets.duplicate()
	if values.is_empty() and not requested_target.is_empty():
		values.append(requested_target)
	return values


static func field_spell_target_count(context: SessionWorkflowContext, spell: SpellDefinition, power: int) -> int:
	if spell.target_type == 7 or absi(spell.special) == 68:
		return 0
	if spell.target_type == 5:
		return 1
	if spell.target_type > 2:
		return _field_group_ids(context.state.party, spell).size()
	return mini(power, context.state.party.characters().size()) if spell.target_type == 0 else 1


static func begin_field_spell(context: SessionWorkflowContext, payload: PlayerIntent.SpellPayload, request_revision: int) -> MagicTransitionResult:
	var character := context.state.party.character_by_id(payload.caster_id)
	var spell := context.content.spell_by_id(payload.spell_id)
	var probe := field_spell_probe(context, character, spell, payload.power)
	if not probe.allowed:
		return MagicTransitionResult.failed(&"field_spell_unavailable", probe.reason)
	var target_ids := field_spell_target_ids(context, character, spell, payload.target_ids, payload.target_id)
	var required_count := field_spell_target_count(context, spell, payload.power)
	if target_ids.size() == required_count:
		return MagicTransitionResult.committed(commit_field_spell(context, character.id, spell.id, payload.power, target_ids), true)
	if not target_ids.is_empty():
		return MagicTransitionResult.failed(&"invalid_field_spell_target", "The spell requires exactly %d valid party target%s." % [required_count, "" if required_count == 1 else "s"])
	var targeting := SessionContinuation.TargetingBody.new()
	targeting.character_id = character.id
	targeting.spell_id = spell.id
	targeting.power = payload.power
	targeting.target_count = required_count
	targeting.starting_spell_points = character.spell_points
	var continuation := SessionContinuation.targeting_selection(&"field-spell-target-selection", targeting)
	var interaction := field_spell_target_request("session.field-spell:%s:%d" % [spell.id, request_revision], character, spell, payload.power, required_count, context.state.party.characters())
	return MagicTransitionResult.waiting(continuation, interaction, [DomainEvent.new(&"field_spell_target_requested", {"characterId": character.id, "spellId": spell.id, "power": payload.power, "targetCount": required_count, "source": "classic"})])


static func resume_field_spell(context: SessionWorkflowContext, targeting: SessionContinuation.TargetingBody, target_ids: Array[String]) -> MagicTransitionResult:
	if targeting == null:
		return MagicTransitionResult.failed(&"invalid_session_continuation", "The field-spell target continuation is unavailable.")
	if target_ids.size() != targeting.target_count:
		return MagicTransitionResult.failed(&"invalid_field_spell_target", "The spell requires exactly %d target%s." % [targeting.target_count, "" if targeting.target_count == 1 else "s"])
	var character := context.state.party.character_by_id(targeting.character_id)
	if character == null or character.spell_points != targeting.starting_spell_points:
		return MagicTransitionResult.failed(&"invalid_session_continuation", "The field spell awaiting a target no longer matches its committed state.")
	return MagicTransitionResult.committed(commit_field_spell(context, targeting.character_id, targeting.spell_id, targeting.power, target_ids), true)


static func commit_field_spell(context: SessionWorkflowContext, character_id: String, spell_id: String, power: int, requested_target_ids: Array[String]) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(character_id)
	var spell := context.content.spell_by_id(spell_id)
	var probe := field_spell_probe(context, character, spell, power)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"field_spell_unavailable", probe.reason)
	var selected_value: Variant = _selected_field_targets(context.state.party, requested_target_ids, spell.target_type in [3, 9])
	if selected_value == null:
		return SessionWorkflowResult.failed(&"invalid_field_spell_target", "The spell target selection contains an unavailable or duplicate character.")
	if (selected_value as Dictionary).size() != field_spell_target_count(context, spell, power):
		return SessionWorkflowResult.failed(&"invalid_field_spell_target", "The spell target selection has the wrong number of characters.")
	var selected: Dictionary = selected_value
	var targets := _ordered_party_targets(context.state.party, selected)
	var allies := _ordered_party_allies(context.state.party, selected)
	var allow_empty := spell.target_type == 7 or absi(spell.special) == 68
	var resolution := _resolve_field_targets(context, character, targets, allies, spell, power, true, allow_empty)
	if resolution == null or not resolution.cast:
		return SessionWorkflowResult.failed(&"field_spell_failed", "The field spell could not be resolved.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"field_spell_cast", {"characterId": character.id, "spellId": spell.id, "power": power, "cost": resolution.cost, "source": "classic"})]
	character.lifetime_record.record_spell_cast()
	_append_field_spell_events(context, events, character, spell, power, resolution, &"classic-field-spell", &"classic", &"field_spell_resolved")
	return SessionWorkflowResult.completed(events)


static func scroll_target_request(request_id: String, character: CharacterState, slot_index: int, spell: SpellDefinition, power: int, required_count: int, party: Array[CharacterState]) -> InteractionRequest:
	return _character_selection_request(request_id, character, "%s uses %s from scroll slot %d. Choose %d target%s." % [character.name, spell.name, slot_index + 1, required_count, "" if required_count == 1 else "s"], required_count, party, &"scroll-use", "", spell, power, slot_index)


static func field_spell_target_request(request_id: String, character: CharacterState, spell: SpellDefinition, power: int, required_count: int, party: Array[CharacterState]) -> InteractionRequest:
	return _character_selection_request(request_id, character, "%s casts %s. Choose %d target%s." % [character.name, spell.name, required_count, "" if required_count == 1 else "s"], required_count, party, &"field-spell", "", spell, power)


static func _character_selection_request(request_id: String, character: CharacterState, prompt: String, required_count: int, party: Array[CharacterState], mode: StringName, instance_id: String, spell: SpellDefinition, power: int, scroll_slot: int = -1) -> InteractionRequest:
	var body := InteractionRequest.CharacterSelectionRequestBody.new()
	body.prompt = prompt
	body.count = required_count
	body.eligible = _eligible_party_candidates(party)
	body.mode = mode
	body.item_instance_id = instance_id
	body.spell_id = spell.id
	body.scroll_slot = scroll_slot
	body.spell_context = _spell_target_context(character, spell, power, required_count, mode)
	return InteractionRequest.new(request_id, InteractionRequest.CHARACTER_SELECTION, body)


static func _spell_target_context(character: CharacterState, spell: SpellDefinition, power: int, target_count: int, source_kind: StringName) -> InteractionRequestValue.SpellTargetContext:
	var result := InteractionRequestValue.SpellTargetContext.new()
	result.actor_id = character.id; result.actor_name = character.name; result.spell_id = spell.id; result.spell_name = spell.name; result.description = spell.description; result.icon_resource_type = "cicn"; result.icon_id = spell.queue_icon; result.power = power; result.spell_point_cost = absi(spell.cost * power) if source_kind == &"field-spell" else 0; result.target_type = spell.target_type; result.target_size = spell.size; result.target_count = target_count; result.source_kind = source_kind
	return result


static func _append_field_spell_events(context: SessionWorkflowContext, events: Array[DomainEvent], character: CharacterState, spell: SpellDefinition, power: int, resolution: GroupSpellResolution, sound_source: StringName, state_source: StringName, event_kind: StringName, event_context: Dictionary = {}) -> void:
	var start_sound := spell.sound_start + 600
	if start_sound != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(start_sound), "waitForCompletion": true, "source": String(sound_source)}))
	var special := absi(spell.special)
	if special == 68:
		context.state.party.fatigue = 4
		events.append(DomainEvent.new(&"party_fatigue_changed", {"fatigue": 4, "spellId": spell.id, "source": String(state_source)}))
	elif spell.target_type == 7:
		var condition_index := 0 if special == 50 else special
		var next_value := power * 30 - 1 if special == 50 else maxi(context.state.party.conditions.value(condition_index), resolution.duration)
		if special != 50 or power * 30 > context.state.party.conditions.value(condition_index):
			context.state.party.conditions.set_value(condition_index, next_value)
		events.append(DomainEvent.new(&"party_condition_changed", {"condition": condition_index, "value": context.state.party.conditions.value(condition_index), "spellId": spell.id, "source": String(state_source)}))
	for index: int in resolution.resolutions.size():
		var target_resolution := resolution.resolutions[index]
		var payload := {"characterId": character.id, "targetId": resolution.target_ids[index], "targetKind": String(resolution.target_kinds[index]), "spellId": spell.id, "power": power, "saved": target_resolution.saved, "damage": target_resolution.damage, "healing": maxi(0, -target_resolution.damage), "duration": target_resolution.duration, "source": "classic"}
		if target_resolution.cleared_condition >= 0:
			payload["clearedCondition"] = target_resolution.cleared_condition
		if not target_resolution.unequipped_item_ids.is_empty():
			payload["unequippedItemIds"] = target_resolution.unequipped_item_ids.duplicate()
		payload.merge(event_context, true)
		events.append(DomainEvent.new(event_kind, payload))
		if target_resolution.aging != null and target_resolution.aging.changed_group():
			var target := context.state.party.character_by_id(resolution.target_ids[index])
			events.append(DomainEvent.new(&"character_age_changed", target_resolution.aging.event_payload(target, context.content.race_by_id(target.race_id))))
	if spell.target_type == 11 and spell.sound_end + 600 != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(spell.sound_end + 600), "waitForCompletion": false, "source": String(sound_source)}))


static func _has_equipped_scroll_case(context: SessionWorkflowContext, character: CharacterState) -> bool:
	if character == null:
		return false
	for instance: ItemInstance in character.inventory():
		var definition := context.content.item_by_id(instance.definition_id)
		if instance.equipped and definition != null and absi(definition.item_type) == 13:
			return true
	return false


static func _parchment_instance(context: SessionWorkflowContext, character: CharacterState) -> ItemInstance:
	if character == null:
		return null
	for instance: ItemInstance in character.inventory():
		var definition := context.content.item_by_id(instance.definition_id)
		if definition != null and definition.classic_id == 806 and instance.charges != 0:
			return instance
	return null


static func _first_empty_scroll_slot(character: CharacterState) -> int:
	if character == null:
		return -1
	for index: int in character.scroll_case().size():
		if character.scroll_at(index).is_empty():
			return index
	return -1


static func _selected_field_targets(party: PartyState, target_ids: Array[String], include_allies: bool) -> Variant:
	var selected: Dictionary = {}
	var ally_ids: Dictionary = {}
	if include_allies:
		for ally: MonsterState in party.allies():
			ally_ids[ally.id] = true
	for target_id: String in target_ids:
		if target_id.is_empty() or selected.has(target_id) or party.character_by_id(target_id) == null and not ally_ids.has(target_id):
			return null
		selected[target_id] = true
	return selected


static func _ordered_party_targets(party: PartyState, selected: Dictionary) -> Array[CharacterState]:
	var targets: Array[CharacterState] = []
	for member: CharacterState in party.characters():
		if selected.has(member.id):
			targets.append(member)
	return targets


static func _ordered_party_allies(party: PartyState, selected: Dictionary) -> Array[MonsterState]:
	var targets: Array[MonsterState] = []
	for ally: MonsterState in party.allies():
		if selected.has(ally.id):
			targets.append(ally)
	return targets


static func _party_character_ids(party: PartyState) -> Array[String]:
	var ids: Array[String] = []
	for member: CharacterState in party.characters():
		ids.append(member.id)
	return ids


static func _field_group_ids(party: PartyState, spell: SpellDefinition) -> Array[String]:
	var ids := _party_character_ids(party)
	if spell.target_type in [3, 9]:
		for ally: MonsterState in party.allies():
			ids.append(ally.id)
	return ids


static func _resolve_field_targets(context: SessionWorkflowContext, caster: CharacterState, targets: Array[CharacterState], allies: Array[MonsterState], spell: SpellDefinition, power: int, spend_spell_points: bool, allow_empty: bool) -> GroupSpellResolution:
	var castes: Array[CasteDefinition] = []
	var races: Array[RaceDefinition] = []
	for target: CharacterState in targets:
		castes.append(context.content.caste_by_id(target.caste_id))
		races.append(context.content.race_by_id(target.race_id))
	var definitions: Array[MonsterDefinition] = []
	for ally: MonsterState in allies:
		var definition := context.content.monster_by_id(ally.definition_id)
		if definition == null:
			return null
		definitions.append(definition)
	return context.rules.magic.resolve_field_spell(caster, targets, spell, power, context.rng, castes, races, spend_spell_points, allow_empty, context.content.item_definitions(), allies, definitions)


static func _eligible_party_candidates(party: Array[CharacterState]) -> Array[InteractionRequestValue.SelectionCandidate]:
	var eligible: Array[InteractionRequestValue.SelectionCandidate] = []
	for member: CharacterState in party:
		var candidate := InteractionRequestValue.SelectionCandidate.new()
		candidate.id = member.id
		candidate.name = member.name
		candidate.current_health = member.current_health
		candidate.maximum_health = member.maximum_health
		candidate.has_current_health = true
		candidate.has_maximum_health = true
		eligible.append(candidate)
	return eligible


static func _item_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null:
		return null
	for item: ItemInstance in character.inventory():
		if item.id == instance_id:
			return item
	return null
