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


static func field_spell_item_probe(context: SessionWorkflowContext, character: CharacterState, instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition) -> InventoryActionProbe:
	var probe := context.rules.inventory.classic_spell_item_probe(character, instance, item, spell, context.content.race_by_id(character.race_id) if character != null else null, context.content.caste_by_id(character.caste_id) if character != null else null, false)
	if not probe.allowed:
		return probe
	var ordinary := spell.special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) <= 6 and absi(spell.spell_class) != 9
	var healing := absi(spell.special) == 57
	if not ordinary and not healing:
		return InventoryActionProbe.block("This item's Classic field spell effect is not implemented yet.")
	if spell.target_type == 7:
		return InventoryActionProbe.block("This item changes party-wide field state that is not implemented yet.")
	if spell.target_type < 0 or spell.target_type > 12:
		return InventoryActionProbe.block("This item's Classic field target type is invalid.")
	return InventoryActionProbe.permit()


static func field_item_target_ids(context: SessionWorkflowContext, character: CharacterState, spell: SpellDefinition, requested_targets: Array[String], requested_target: String) -> Array[String]:
	if spell.target_type == 5:
		return [character.id]
	if spell.target_type > 2:
		return _party_character_ids(context.state.party)
	var values: Array[String] = requested_targets.duplicate()
	if values.is_empty() and not requested_target.is_empty():
		values.append(requested_target)
	return values


static func field_item_target_count(context: SessionWorkflowContext, spell: SpellDefinition, power: int) -> int:
	if spell.target_type == 5:
		return 1
	if spell.target_type > 2:
		return context.state.party.characters().size()
	return mini(power, context.state.party.characters().size()) if spell.target_type == 0 else 1


static func commit_field_spell_item(context: SessionWorkflowContext, character_id: String, instance_id: String, spell_id: String, power: int, requested_target_ids: Array[String]) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(character_id)
	var instance := _item_instance(character, instance_id)
	var item: ItemDefinition = null if instance == null else context.content.item_by_id(instance.definition_id)
	var spell := context.content.spell_by_id(spell_id)
	var probe := field_spell_item_probe(context, character, instance, item, spell)
	if not probe.allowed:
		return SessionWorkflowResult.failed(item_use_error_code(instance, item, spell), probe.reason)
	var selected_value: Variant = _selected_party_targets(context.state.party, requested_target_ids)
	if selected_value == null:
		return SessionWorkflowResult.failed(&"invalid_item_use_target", "The item target selection contains an unavailable or duplicate character.")
	if (selected_value as Dictionary).size() != field_item_target_count(context, spell, power):
		return SessionWorkflowResult.failed(&"invalid_item_use_target", "The item target selection has the wrong number of characters.")
	var selected: Dictionary = selected_value
	var targets := _ordered_party_targets(context.state.party, selected)
	if targets.size() != selected.size():
		return SessionWorkflowResult.failed(&"invalid_item_use_target", "The item target selection is unavailable.")
	if not context.rules.inventory.use_charge(character, instance.id, item):
		return SessionWorkflowResult.failed(&"item_charge_commit_failed", "The validated item charge could not be committed.")
	var castes: Array[CasteDefinition] = []
	var races: Array[RaceDefinition] = []
	for target: CharacterState in targets:
		castes.append(context.content.caste_by_id(target.caste_id))
		races.append(context.content.race_by_id(target.race_id))
	var resolution := context.rules.magic.resolve_field_spell(character, targets, spell, power, context.rng, castes, races, false)
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
	for index: int in resolution.resolutions.size():
		var target_resolution := resolution.resolutions[index]
		events.append(DomainEvent.new(&"item_spell_resolved", {"characterId": character.id, "targetId": resolution.target_ids[index], "itemId": item.id, "instanceId": instance_id, "spellId": spell.id, "power": power, "resisted": target_resolution.resisted, "saved": target_resolution.saved, "damage": target_resolution.damage, "healing": maxi(0, -target_resolution.damage), "duration": target_resolution.duration, "source": "classic"}))
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


static func item_target_request(request_id: String, character: CharacterState, instance_id: String, item: ItemDefinition, spell: SpellDefinition, required_count: int, party: Array[CharacterState]) -> InteractionRequest:
	var display_name := item.unidentified_name
	for carried: ItemInstance in character.inventory():
		if carried.id == instance_id:
			display_name = item.name if carried.identified else item.unidentified_name
			break
	return InteractionRequest.from_payload(request_id, InteractionRequest.CHARACTER_SELECTION, {"prompt": "%s uses %s. Choose %d target%s." % [character.name, display_name, required_count, "" if required_count == 1 else "s"], "count": required_count, "eligible": _eligible_party_payload(party), "mode": "item-use", "itemInstanceId": instance_id, "spellId": spell.id})


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
	if character == null or slot_index < 0 or slot_index >= 5:
		return InventoryActionProbe.block("The scroll slot is unavailable.")
	var scroll := character.scroll_at(slot_index)
	if scroll == null or scroll.is_empty() or spell == null or spell.id != scroll.spell_id or scroll.power < 1 or scroll.power > 7:
		return InventoryActionProbe.block("This scroll slot is empty or invalid.")
	if character.current_health < 1 or character.conditions.is_active(ConditionRules.ANIMATED):
		return InventoryActionProbe.block("The selected character cannot use a scroll.")
	if not _has_equipped_scroll_case(context, character):
		return InventoryActionProbe.block("Equip the scroll case before using its spells.")
	if not spell.in_camp:
		return InventoryActionProbe.block("This scroll cannot be used outside battle; Classic offers to discard it.")
	if spell.target_type < 0 or spell.target_type > 12:
		return InventoryActionProbe.block("This scroll has an invalid Classic field target type.")
	if spell.target_type in [3, 7, 9] and not context.state.party.allies().is_empty():
		return InventoryActionProbe.block("This scroll also targets allied creatures; that Classic field branch is not implemented yet.")
	if not field_spell_effect_supported(spell):
		return InventoryActionProbe.block("This scroll's Classic field effect is not implemented yet.")
	return InventoryActionProbe.permit()


static func commit_field_scroll(context: SessionWorkflowContext, character_id: String, slot_index: int, spell_id: String, power: int, requested_target_ids: Array[String]) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(character_id)
	var spell := context.content.spell_by_id(spell_id)
	var probe := scroll_use_probe(context, character, slot_index, spell)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"scroll_unavailable", probe.reason)
	var selected_value: Variant = _selected_party_targets(context.state.party, requested_target_ids)
	if selected_value == null:
		return SessionWorkflowResult.failed(&"invalid_scroll_target", "The scroll target selection contains an unavailable or duplicate character.")
	if (selected_value as Dictionary).size() != field_spell_target_count(context, spell, power):
		return SessionWorkflowResult.failed(&"invalid_scroll_target", "The scroll target selection has the wrong number of characters.")
	var selected: Dictionary = selected_value
	var targets := _ordered_party_targets(context.state.party, selected)
	var castes: Array[CasteDefinition] = []
	var races: Array[RaceDefinition] = []
	for target: CharacterState in targets:
		castes.append(context.content.caste_by_id(target.caste_id))
		races.append(context.content.race_by_id(target.race_id))
	var allow_empty := spell.target_type == 7 or absi(spell.special) == 68
	var resolution := context.rules.magic.resolve_field_spell(character, targets, spell, power, context.rng, castes, races, false, allow_empty)
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
	if spell.target_type in [3, 7, 9] and not context.state.party.allies().is_empty():
		return InventoryActionProbe.block("This spell also targets allied creatures; that Classic field branch is not implemented yet.")
	if not field_spell_effect_supported(spell):
		return InventoryActionProbe.block("This spell's Classic field effect is not implemented yet.")
	return InventoryActionProbe.permit()


static func field_spell_effect_supported(spell: SpellDefinition) -> bool:
	var special := absi(spell.special)
	if spell.target_type == 7:
		return special == 50 or special >= 1 and special < ConditionSet.PARTY_COUNT
	if special == 68:
		return true
	if special > 0 and special < 41 or special in [48, 57, 59, 60, 61, 64, 66, 91, 92] or special > 99:
		return true
	return special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) < 8 and (spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0)


static func field_spell_target_ids(context: SessionWorkflowContext, character: CharacterState, spell: SpellDefinition, requested_targets: Array[String], requested_target: String) -> Array[String]:
	if spell.target_type == 5:
		return [character.id]
	if spell.target_type > 2:
		if spell.target_type == 7 or absi(spell.special) == 68:
			return []
		return _party_character_ids(context.state.party)
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
		return context.state.party.characters().size()
	return mini(power, context.state.party.characters().size()) if spell.target_type == 0 else 1


static func commit_field_spell(context: SessionWorkflowContext, character_id: String, spell_id: String, power: int, requested_target_ids: Array[String]) -> SessionWorkflowResult:
	var character := context.state.party.character_by_id(character_id)
	var spell := context.content.spell_by_id(spell_id)
	var probe := field_spell_probe(context, character, spell, power)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"field_spell_unavailable", probe.reason)
	var selected_value: Variant = _selected_party_targets(context.state.party, requested_target_ids)
	if selected_value == null:
		return SessionWorkflowResult.failed(&"invalid_field_spell_target", "The spell target selection contains an unavailable or duplicate character.")
	if (selected_value as Dictionary).size() != field_spell_target_count(context, spell, power):
		return SessionWorkflowResult.failed(&"invalid_field_spell_target", "The spell target selection has the wrong number of characters.")
	var selected: Dictionary = selected_value
	var targets := _ordered_party_targets(context.state.party, selected)
	var castes: Array[CasteDefinition] = []
	var races: Array[RaceDefinition] = []
	for target: CharacterState in targets:
		castes.append(context.content.caste_by_id(target.caste_id))
		races.append(context.content.race_by_id(target.race_id))
	var allow_empty := spell.target_type == 7 or absi(spell.special) == 68
	var resolution := context.rules.magic.resolve_field_spell(character, targets, spell, power, context.rng, castes, races, true, allow_empty)
	if resolution == null or not resolution.cast:
		return SessionWorkflowResult.failed(&"field_spell_failed", "The field spell could not be resolved.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"field_spell_cast", {"characterId": character.id, "spellId": spell.id, "power": power, "cost": resolution.cost, "source": "classic"})]
	_append_field_spell_events(context, events, character, spell, power, resolution, &"classic-field-spell", &"classic", &"field_spell_resolved")
	return SessionWorkflowResult.completed(events)


static func scroll_target_request(request_id: String, character: CharacterState, slot_index: int, spell: SpellDefinition, required_count: int, party: Array[CharacterState]) -> InteractionRequest:
	return InteractionRequest.from_payload(request_id, InteractionRequest.CHARACTER_SELECTION, {"prompt": "%s uses %s from scroll slot %d. Choose %d target%s." % [character.name, spell.name, slot_index + 1, required_count, "" if required_count == 1 else "s"], "count": required_count, "eligible": _eligible_party_payload(party), "mode": "scroll-use", "scrollSlot": slot_index, "spellId": spell.id})


static func field_spell_target_request(request_id: String, character: CharacterState, spell: SpellDefinition, required_count: int, party: Array[CharacterState]) -> InteractionRequest:
	return InteractionRequest.from_payload(request_id, InteractionRequest.CHARACTER_SELECTION, {"prompt": "%s casts %s. Choose %d target%s." % [character.name, spell.name, required_count, "" if required_count == 1 else "s"], "count": required_count, "eligible": _eligible_party_payload(party), "mode": "field-spell", "spellId": spell.id})


static func _append_field_spell_events(context: SessionWorkflowContext, events: Array[DomainEvent], character: CharacterState, spell: SpellDefinition, power: int, resolution: GroupSpellResolution, sound_source: StringName, state_source: StringName, event_kind: StringName) -> void:
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
		events.append(DomainEvent.new(event_kind, {"characterId": character.id, "targetId": resolution.target_ids[index], "spellId": spell.id, "power": power, "saved": target_resolution.saved, "damage": target_resolution.damage, "healing": maxi(0, -target_resolution.damage), "duration": target_resolution.duration, "source": "classic"}))
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


static func _selected_party_targets(party: PartyState, target_ids: Array[String]) -> Variant:
	var selected: Dictionary = {}
	for target_id: String in target_ids:
		if target_id.is_empty() or selected.has(target_id) or party.character_by_id(target_id) == null:
			return null
		selected[target_id] = true
	return selected


static func _ordered_party_targets(party: PartyState, selected: Dictionary) -> Array[CharacterState]:
	var targets: Array[CharacterState] = []
	for member: CharacterState in party.characters():
		if selected.has(member.id):
			targets.append(member)
	return targets


static func _party_character_ids(party: PartyState) -> Array[String]:
	var ids: Array[String] = []
	for member: CharacterState in party.characters():
		ids.append(member.id)
	return ids


static func _eligible_party_payload(party: Array[CharacterState]) -> Array[Dictionary]:
	var eligible: Array[Dictionary] = []
	for member: CharacterState in party:
		eligible.append({"id": member.id, "name": member.name, "currentHealth": member.current_health, "maximumHealth": member.maximum_health})
	return eligible


static func _item_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null:
		return null
	for item: ItemInstance in character.inventory():
		if item.id == instance_id:
			return item
	return null
