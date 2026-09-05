## Coordinates Identify, Torch, door-item, and charged field-item operations.

class_name FieldItemWorkflow
extends RefCounted


static func classic_torch_item(context: SessionWorkflowContext) -> Array[String]:
	var torch := context.content.items.item_by_classic_id(805)
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
	var instance := InventoryWorkflow.item_instance(character, identity[1])
	var item: ItemDefinition = null if instance == null else context.content.items.item_by_id(instance.definition_id)
	var spell: SpellDefinition = null if item == null else context.content.magic.spell_by_classic_id(item.special_2)
	return field_spell_item_probe(context, character, instance, item, spell)


static func begin_classic_torch(context: SessionWorkflowContext, request_revision: int) -> MagicTransitionResult:
	var identity := classic_torch_item(context)
	if identity.is_empty():
		return MagicTransitionResult.failed(&"torch_unavailable", "The party carries no usable torch.")
	return begin_field_spell_item(context, identity[0], identity[1], "", [], request_revision)


static func inventory_identify_probe(context: SessionWorkflowContext, target_id: String, caster_id: String, spell_id: String) -> InventoryActionProbe:
	var target := context.state.party.character_by_id(target_id)
	var caster := context.state.party.character_by_id(caster_id)
	var spell := context.content.magic.spell_by_id(spell_id)
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


static func identify_inventory(context: SessionWorkflowContext, payload: SpellIntentPayload) -> SessionWorkflowResult:
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
	var probe := context.rules.inventory.classic_spell_item_probe(character, instance, item, spell, context.content.characters.race_by_id(character.race_id) if character != null else null, context.content.characters.caste_by_id(character.caste_id) if character != null else null, false)
	if not probe.allowed:
		return probe
	if ClassicSpellDispositionRules.field_character_disposition(spell) != ClassicSpellDispositionRules.DISPOSITION_EXECUTABLE:
		return InventoryActionProbe.block(ClassicSpellDispositionRules.unsupported_reason(spell, &"field-item"))
	if spell.target_type < 0 or spell.target_type > 12:
		return InventoryActionProbe.block("This item's Classic field target type is invalid.")
	return InventoryActionProbe.permit()


static func is_classic_door_item(item: ItemDefinition) -> bool:
	return item != null and (absi(item.item_type) == 23 or item.special_1 == -23)


static func door_item_probe(context: SessionWorkflowContext, character: CharacterState, instance: ItemInstance, item: ItemDefinition, in_combat: bool) -> InventoryActionProbe:
	var program_available := item != null and context.content.scenario.program_by_id("xap:%d" % item.special_5) != null
	var probe := context.rules.inventory.classic_door_item_probe(character, instance, item, context.content.characters.race_by_id(character.race_id) if character != null else null, context.content.characters.caste_by_id(character.caste_id) if character != null else null, in_combat, program_available)
	if not probe.allowed:
		return probe
	if in_combat and (context.state.combat == null or context.state.combat.completed or context.state.combat.turns.active_actor_id() != character.id):
		return InventoryActionProbe.block("Only the active character may use a door item in combat.")
	return InventoryActionProbe.permit()


static func field_item_use_probe(context: SessionWorkflowContext, character: CharacterState, instance: ItemInstance, item: ItemDefinition) -> InventoryActionProbe:
	if is_classic_door_item(item):
		return door_item_probe(context, character, instance, item, false)
	return field_spell_item_probe(context, character, instance, item, context.content.magic.spell_by_classic_id(item.special_2) if item != null else null)


static func field_item_target_ids(context: SessionWorkflowContext, character: CharacterState, spell: SpellDefinition, requested_targets: Array[String], requested_target: String) -> Array[String]:
	if spell.target_type == 7 or absi(spell.special) == 68:
		return []
	if spell.target_type == 5:
		return [character.id]
	if spell.target_type > 2:
		return FieldMagicResolver.group_target_ids(context.state.party, spell)
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
		return FieldMagicResolver.group_target_ids(context.state.party, spell).size()
	return mini(power, context.state.party.characters().size()) if spell.target_type == 0 else 1


static func begin_field_spell_item(context: SessionWorkflowContext, actor_id: String, instance_id: String, requested_target: String, requested_targets: Array[String], request_revision: int) -> MagicTransitionResult:
	var character := context.state.party.character_by_id(actor_id)
	if character == null:
		character = item_owner(context, instance_id)
	var instance := InventoryWorkflow.item_instance(character, instance_id)
	var item: ItemDefinition = null if instance == null else context.content.items.item_by_id(instance.definition_id)
	var spell: SpellDefinition = null if item == null else context.content.magic.spell_by_classic_id(item.special_2)
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
	var targeting := TargetingContinuationBody.new()
	targeting.character_id = character.id
	targeting.instance_id = instance.id
	targeting.spell_id = spell.id
	targeting.power = power
	targeting.target_count = required_count
	targeting.starting_charges = instance.charges
	var continuation := InventoryContinuations.item_target(targeting)
	var interaction := FieldMagicTargetRequestBuilder.item_target_request("session.item-use:%s:%d" % [instance.id, request_revision], character, instance.id, item, spell, power, required_count, context.state.party.characters())
	return MagicTransitionResult.waiting(continuation, interaction, [DomainEvent.new(&"item_target_requested", {"characterId": character.id, "instanceId": instance.id, "itemId": item.id, "spellId": spell.id, "power": power, "targetCount": required_count, "source": "classic"})])


static func resume_field_spell_item(context: SessionWorkflowContext, targeting: TargetingContinuationBody, target_ids: Array[String]) -> MagicTransitionResult:
	if targeting == null:
		return MagicTransitionResult.failed(&"invalid_session_continuation", "The item target continuation is unavailable.")
	if target_ids.size() != targeting.target_count:
		return MagicTransitionResult.failed(&"invalid_item_use_target", "The item requires exactly %d target%s." % [targeting.target_count, "" if targeting.target_count == 1 else "s"])
	var character := context.state.party.character_by_id(targeting.character_id)
	var instance := InventoryWorkflow.item_instance(character, targeting.instance_id)
	if instance == null or instance.charges != targeting.starting_charges:
		return MagicTransitionResult.failed(&"invalid_session_continuation", "The item awaiting a target no longer matches its committed state.")
	return MagicTransitionResult.committed(commit_field_spell_item(context, targeting.character_id, targeting.instance_id, targeting.spell_id, targeting.power, target_ids))


static func commit_field_spell_item(context: SessionWorkflowContext, character_id: String, instance_id: String, spell_id: String, power: int, requested_target_ids: Array[String]) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(character_id)
	var instance := InventoryWorkflow.item_instance(character, instance_id)
	var item: ItemDefinition = null if instance == null else context.content.items.item_by_id(instance.definition_id)
	var spell := context.content.magic.spell_by_id(spell_id)
	var probe := field_spell_item_probe(context, character, instance, item, spell)
	if not probe.allowed:
		return SessionWorkflowResult.failed(item_use_error_code(instance, item, spell), probe.reason)
	var selected_value: Variant = FieldMagicResolver.selected_targets(context.state.party, requested_target_ids, spell.target_type in [3, 9])
	if selected_value == null:
		return SessionWorkflowResult.failed(&"invalid_item_use_target", "The item target selection contains an unavailable or duplicate character.")
	if (selected_value as Dictionary).size() != field_item_target_count(context, spell, power):
		return SessionWorkflowResult.failed(&"invalid_item_use_target", "The item target selection has the wrong number of characters.")
	var selected: Dictionary = selected_value
	if not context.rules.inventory.use_charge(character, instance.id, item):
		return SessionWorkflowResult.failed(&"item_charge_commit_failed", "The validated item charge could not be committed.")
	var allow_empty := spell.target_type == 7 or absi(spell.special) == 68
	var resolution := FieldMagicResolver.resolve(context, character, selected, spell, power, false, allow_empty)
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
	FieldMagicResolver.append_events(context, events, character, spell, power, resolution, &"classic-item", &"classic-item", &"item_spell_resolved", {"itemId": item.id, "instanceId": instance_id})
	return SessionWorkflowResult.completed(events)


static func item_owner(context: SessionWorkflowContext, instance_id: String) -> CharacterState:
	for character: CharacterState in context.state.party.characters():
		if InventoryWorkflow.item_instance(character, instance_id) != null:
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
