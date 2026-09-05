## Coordinates field spell, scroll, and magic-item workflows against committed session state.

class_name FieldMagicWorkflow
extends RefCounted


static func set_fast_spell(context: SessionWorkflowContext, payload: SpellIntentPayload) -> SessionWorkflowResult:
	if context.state.combat != null and not context.state.combat.completed:
		return SessionWorkflowResult.failed(&"fast_spell_binding_in_battle", "Fast Spell bindings cannot be changed during battle.")
	var character := context.state.party.character_by_id(payload.caster_id)
	if character == null or payload.scroll_slot < 0 or payload.scroll_slot >= 10:
		return SessionWorkflowResult.failed(&"invalid_fast_spell_slot", "The selected Fast Spell slot is unavailable.")
	if payload.spell_id.is_empty():
		if not character.clear_fast_spell(payload.scroll_slot):
			return SessionWorkflowResult.failed(&"fast_spell_binding_failed", "The Fast Spell slot could not be cleared.")
		return SessionWorkflowResult.completed([DomainEvent.new(&"fast_spell_changed", {"characterId": character.id, "slot": payload.scroll_slot, "spellId": "", "power": 0, "source": "classic"})])
	var spell := context.content.magic.spell_by_id(payload.spell_id)
	if spell == null or not character.known_spells().has(spell.id):
		return SessionWorkflowResult.failed(&"invalid_fast_spell", "Fast Spells must reference a spell known by this character.")
	if payload.power < 1 or payload.power > 7 or spell.cost < 0 and payload.power != 1:
		return SessionWorkflowResult.failed(&"invalid_fast_spell_power", "The selected spell does not support that Fast Spell power.")
	if not character.bind_fast_spell(payload.scroll_slot, spell.id, payload.power):
		return SessionWorkflowResult.failed(&"fast_spell_binding_failed", "The Fast Spell binding could not be committed.")
	return SessionWorkflowResult.completed([DomainEvent.new(&"fast_spell_changed", {"characterId": character.id, "slot": payload.scroll_slot, "spellId": spell.id, "power": payload.power, "source": "classic"})])



static func make_scroll(context: SessionWorkflowContext, payload: SpellIntentPayload) -> SessionWorkflowResult:
	if context.state.combat != null and not context.state.combat.completed:
		return SessionWorkflowResult.failed(&"scroll_scribing_in_battle", "Classic scroll scribing is available only while camped.")
	var character := context.state.party.character_by_id(payload.caster_id)
	var spell := context.content.magic.spell_by_id(payload.spell_id)
	var probe := make_scroll_probe(context, character, spell, payload.power)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"scroll_scribing_unavailable", probe.reason)
	var slot_index := _first_empty_scroll_slot(character)
	var parchment := _parchment_instance(context, character)
	var parchment_definition: ItemDefinition = null if parchment == null else context.content.items.item_by_id(parchment.definition_id)
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
	if not context.rules.equipment.has_equipped_scroll_case(character, context.content):
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
		return InventoryActionProbe.block(ClassicSpellDispositionRules.unsupported_reason(spell, &"field-scroll"))
	return InventoryActionProbe.permit()


static func scroll_slot_probe(context: SessionWorkflowContext, character: CharacterState, slot_index: int, spell: SpellDefinition) -> InventoryActionProbe:
	if character == null or slot_index < 0 or slot_index >= 5:
		return InventoryActionProbe.block("The scroll slot is unavailable.")
	var scroll := character.scroll_at(slot_index)
	if scroll == null or scroll.is_empty() or spell == null or spell.id != scroll.spell_id or scroll.power < 1 or scroll.power > 7:
		return InventoryActionProbe.block("This scroll slot is empty or invalid.")
	if character.current_health < 1 or character.conditions.is_active(ConditionRules.ANIMATED):
		return InventoryActionProbe.block("The selected character cannot use a scroll.")
	if not context.rules.equipment.has_equipped_scroll_case(character, context.content):
		return InventoryActionProbe.block("Equip the scroll case before using its spells.")
	return InventoryActionProbe.permit()


static func begin_field_scroll(context: SessionWorkflowContext, payload: SpellIntentPayload, request_revision: int) -> MagicTransitionResult:
	var character := context.state.party.character_by_id(payload.caster_id)
	var scroll := character.scroll_at(payload.scroll_slot) if character != null else null
	var spell := context.content.magic.spell_by_id(scroll.spell_id) if scroll != null and not scroll.is_empty() else null
	var slot_probe := scroll_slot_probe(context, character, payload.scroll_slot, spell)
	if not slot_probe.allowed:
		return MagicTransitionResult.failed(&"scroll_unavailable", slot_probe.reason)
	if not spell.in_camp:
		var discard := TargetingContinuationBody.new()
		discard.character_id = character.id
		discard.scroll_slot = payload.scroll_slot
		discard.spell_id = spell.id
		discard.power = scroll.power
		var continuation := MagicContinuations.scroll_discard(discard)
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
	var targeting := TargetingContinuationBody.new()
	targeting.character_id = character.id
	targeting.scroll_slot = payload.scroll_slot
	targeting.spell_id = spell.id
	targeting.power = scroll.power
	targeting.target_count = required_count
	var continuation := MagicContinuations.scroll_target(targeting)
	var interaction := FieldMagicTargetRequestBuilder.scroll_target_request("session.scroll:%s:%d:%d" % [character.id, payload.scroll_slot, request_revision], character, payload.scroll_slot, spell, scroll.power, required_count, context.state.party.characters())
	return MagicTransitionResult.waiting(continuation, interaction, [DomainEvent.new(&"scroll_target_requested", {"characterId": character.id, "slot": payload.scroll_slot, "spellId": spell.id, "power": scroll.power, "targetCount": required_count, "source": "classic"})])


static func discard_field_scroll(context: SessionWorkflowContext, targeting: TargetingContinuationBody, accepted: bool) -> SessionWorkflowResult:
	if targeting == null:
		return SessionWorkflowResult.failed(&"invalid_session_continuation", "The scroll awaiting discard confirmation is unavailable.")
	var character := context.state.party.character_by_id(targeting.character_id)
	var scroll := character.scroll_at(targeting.scroll_slot) if character != null else null
	var spell := context.content.magic.spell_by_id(targeting.spell_id)
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


static func resume_field_scroll(context: SessionWorkflowContext, targeting: TargetingContinuationBody, target_ids: Array[String]) -> MagicTransitionResult:
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
	var spell := context.content.magic.spell_by_id(spell_id)
	var probe := scroll_use_probe(context, character, slot_index, spell)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"scroll_unavailable", probe.reason)
	var selected_value: Variant = FieldMagicResolver.selected_targets(context.state.party, requested_target_ids, spell.target_type in [3, 9])
	if selected_value == null:
		return SessionWorkflowResult.failed(&"invalid_scroll_target", "The scroll target selection contains an unavailable or duplicate character.")
	if (selected_value as Dictionary).size() != field_spell_target_count(context, spell, power):
		return SessionWorkflowResult.failed(&"invalid_scroll_target", "The scroll target selection has the wrong number of characters.")
	var selected: Dictionary = selected_value
	var allow_empty := spell.target_type == 7 or absi(spell.special) == 68
	var resolution := FieldMagicResolver.resolve(context, character, selected, spell, power, false, allow_empty)
	if resolution == null or not resolution.cast:
		return SessionWorkflowResult.failed(&"scroll_spell_failed", "The scroll spell could not be resolved.")
	if not character.clear_scroll(slot_index):
		return SessionWorkflowResult.failed(&"scroll_commit_failed", "The resolved scroll could not be removed from its case.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"scroll_used", {"characterId": character.id, "slot": slot_index, "spellId": spell.id, "power": power, "source": "classic"})]
	FieldMagicResolver.append_events(context, events, character, spell, power, resolution, &"classic-scroll", &"classic-scroll", &"scroll_spell_resolved")
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
		return InventoryActionProbe.block(ClassicSpellDispositionRules.unsupported_reason(spell, &"field-character"))
	return InventoryActionProbe.permit()


static func field_spell_effect_supported(spell: SpellDefinition) -> bool:
	return ClassicSpellDispositionRules.field_character_disposition(spell) == ClassicSpellDispositionRules.DISPOSITION_EXECUTABLE


static func field_spell_target_ids(context: SessionWorkflowContext, character: CharacterState, spell: SpellDefinition, requested_targets: Array[String], requested_target: String) -> Array[String]:
	if spell.target_type == 5:
		return [character.id]
	if spell.target_type > 2:
		if spell.target_type == 7 or absi(spell.special) == 68:
			return []
		return FieldMagicResolver.group_target_ids(context.state.party, spell)
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
		return FieldMagicResolver.group_target_ids(context.state.party, spell).size()
	return mini(power, context.state.party.characters().size()) if spell.target_type == 0 else 1


static func begin_field_spell(context: SessionWorkflowContext, payload: SpellIntentPayload, request_revision: int) -> MagicTransitionResult:
	var character := context.state.party.character_by_id(payload.caster_id)
	var spell := context.content.magic.spell_by_id(payload.spell_id)
	var probe := field_spell_probe(context, character, spell, payload.power)
	if not probe.allowed:
		return MagicTransitionResult.failed(&"field_spell_unavailable", probe.reason)
	var target_ids := field_spell_target_ids(context, character, spell, payload.target_ids, payload.target_id)
	var required_count := field_spell_target_count(context, spell, payload.power)
	if target_ids.size() == required_count:
		return MagicTransitionResult.committed(commit_field_spell(context, character.id, spell.id, payload.power, target_ids), true)
	if not target_ids.is_empty():
		return MagicTransitionResult.failed(&"invalid_field_spell_target", "The spell requires exactly %d valid party target%s." % [required_count, "" if required_count == 1 else "s"])
	var targeting := TargetingContinuationBody.new()
	targeting.character_id = character.id
	targeting.spell_id = spell.id
	targeting.power = payload.power
	targeting.target_count = required_count
	targeting.starting_spell_points = character.spell_points
	var continuation := MagicContinuations.field_spell_target(targeting)
	var interaction := FieldMagicTargetRequestBuilder.spell_target_request("session.field-spell:%s:%d" % [spell.id, request_revision], character, spell, payload.power, required_count, context.state.party.characters())
	return MagicTransitionResult.waiting(continuation, interaction, [DomainEvent.new(&"field_spell_target_requested", {"characterId": character.id, "spellId": spell.id, "power": payload.power, "targetCount": required_count, "source": "classic"})])


static func resume_field_spell(context: SessionWorkflowContext, targeting: TargetingContinuationBody, target_ids: Array[String]) -> MagicTransitionResult:
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
	var spell := context.content.magic.spell_by_id(spell_id)
	var probe := field_spell_probe(context, character, spell, power)
	if not probe.allowed:
		return SessionWorkflowResult.failed(&"field_spell_unavailable", probe.reason)
	var selected_value: Variant = FieldMagicResolver.selected_targets(context.state.party, requested_target_ids, spell.target_type in [3, 9])
	if selected_value == null:
		return SessionWorkflowResult.failed(&"invalid_field_spell_target", "The spell target selection contains an unavailable or duplicate character.")
	if (selected_value as Dictionary).size() != field_spell_target_count(context, spell, power):
		return SessionWorkflowResult.failed(&"invalid_field_spell_target", "The spell target selection has the wrong number of characters.")
	var selected: Dictionary = selected_value
	var allow_empty := spell.target_type == 7 or absi(spell.special) == 68
	var resolution := FieldMagicResolver.resolve(context, character, selected, spell, power, true, allow_empty)
	if resolution == null or not resolution.cast:
		return SessionWorkflowResult.failed(&"field_spell_failed", "The field spell could not be resolved.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"field_spell_cast", {"characterId": character.id, "spellId": spell.id, "power": power, "cost": resolution.cost, "source": "classic"})]
	character.lifetime_record.record_spell_cast()
	FieldMagicResolver.append_events(context, events, character, spell, power, resolution, &"classic-field-spell", &"classic", &"field_spell_resolved")
	return SessionWorkflowResult.completed(events)



static func _parchment_instance(context: SessionWorkflowContext, character: CharacterState) -> ItemInstance:
	if character == null:
		return null
	for instance: ItemInstance in character.inventory():
		var definition := context.content.items.item_by_id(instance.definition_id)
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
