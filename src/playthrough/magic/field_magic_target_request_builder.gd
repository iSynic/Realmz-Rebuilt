## Builds the typed character-selection requests shared by field magic sources.

class_name FieldMagicTargetRequestBuilder
extends RefCounted


static func item_target_request(request_id: String, character: CharacterState, instance_id: String, item: ItemDefinition, spell: SpellDefinition, power: int, required_count: int, party: Array[CharacterState]) -> InteractionRequest:
	var display_name := item.unidentified_name
	for carried: ItemInstance in character.inventory():
		if carried.id == instance_id:
			display_name = item.name if carried.identified else item.unidentified_name
			break
	var prompt := "%s uses %s. Choose %d target%s." % [character.name, display_name, required_count, "" if required_count == 1 else "s"]
	return _character_selection_request(request_id, character, prompt, required_count, party, &"item-use", instance_id, spell, power)


static func scroll_target_request(request_id: String, character: CharacterState, slot_index: int, spell: SpellDefinition, power: int, required_count: int, party: Array[CharacterState]) -> InteractionRequest:
	var prompt := "%s uses %s from scroll slot %d. Choose %d target%s." % [character.name, spell.name, slot_index + 1, required_count, "" if required_count == 1 else "s"]
	return _character_selection_request(request_id, character, prompt, required_count, party, &"scroll-use", "", spell, power, slot_index)


static func spell_target_request(request_id: String, character: CharacterState, spell: SpellDefinition, power: int, required_count: int, party: Array[CharacterState]) -> InteractionRequest:
	var prompt := "%s casts %s. Choose %d target%s." % [character.name, spell.name, required_count, "" if required_count == 1 else "s"]
	return _character_selection_request(request_id, character, prompt, required_count, party, &"field-spell", "", spell, power)


static func _character_selection_request(request_id: String, character: CharacterState, prompt: String, required_count: int, party: Array[CharacterState], mode: StringName, instance_id: String, spell: SpellDefinition, power: int, scroll_slot: int = -1) -> InteractionRequest:
	var body := CharacterSelectionRequestBody.new()
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
	result.actor_id = character.id
	result.actor_name = character.name
	result.spell_id = spell.id
	result.spell_name = spell.name
	result.description = spell.description
	result.icon_resource_type = "cicn"
	result.icon_id = spell.queue_icon
	result.power = power
	result.spell_point_cost = absi(spell.cost * power) if source_kind == &"field-spell" else 0
	result.target_type = spell.target_type
	result.target_size = spell.size
	result.target_count = target_count
	result.source_kind = source_kind
	return result


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
