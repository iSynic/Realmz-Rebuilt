## Strictly decodes choice, character, ally, and Complex Encounter request bodies.
class_name InteractionSelectionRequestDecoder
extends RefCounted


static func parse(request_kind: StringName, payload: Dictionary) -> InteractionRequestBody:
	match request_kind:
		&"scenario_choice", &"encounter_choice":
			return _choice_from_data(payload)
		&"character_selection":
			return _character_selection_from_data(payload)
		&"ally_selection":
			return _ally_selection_from_data(payload)
		&"complex_encounter":
			return _complex_encounter_from_data(payload)
	return null


static func _choice_from_data(payload: Dictionary) -> ChoiceRequestBody:
	var allowed: Array = ["prompt", "options", "canBackOut", "encounterKind", "encounterId"]
	if not InteractionValueDecoderSupport.exact(payload, allowed, ["prompt", "options"]):
		return null
	if not InteractionValueDecoderSupport.strings(payload, ["prompt"]) or not payload["options"] is Array:
		return null
	if not InteractionValueDecoderSupport.optional_bools(payload, ["canBackOut"]):
		return null
	if not InteractionValueDecoderSupport.optional_strings(payload, ["encounterKind"]):
		return null
	if not InteractionValueDecoderSupport.optional_ints(payload, ["encounterId"]):
		return null
	var result := ChoiceRequestBody.new()
	result.prompt = payload["prompt"]
	for entry: Variant in payload["options"]:
		var option := InteractionSelectionValueDecoder.choice_option(entry)
		if option == null:
			return null
		result.options.append(option)
	result.can_back_out = bool(payload.get("canBackOut", false))
	result.encounter_kind = StringName(payload.get("encounterKind", ""))
	result.encounter_id = int(payload.get("encounterId", 0))
	result.has_can_back_out = payload.has("canBackOut")
	result.has_encounter = payload.has("encounterKind") or payload.has("encounterId")
	return result


static func _character_selection_from_data(payload: Dictionary) -> CharacterSelectionRequestBody:
	var allowed: Array = [
		"prompt", "count", "eligible", "allowDead", "mode", "itemInstanceId", "spellId",
		"scrollSlot", "spellContext",
	]
	if not InteractionValueDecoderSupport.exact(payload, allowed, ["count", "eligible"]):
		return null
	if not InteractionValueDecoderSupport.whole(payload["count"]) or not payload["eligible"] is Array:
		return null
	if not InteractionValueDecoderSupport.optional_strings(payload, ["prompt", "mode", "itemInstanceId", "spellId"]):
		return null
	if not InteractionValueDecoderSupport.optional_ints(payload, ["scrollSlot"]):
		return null
	if not InteractionValueDecoderSupport.optional_bools(payload, ["allowDead"]):
		return null
	var result := CharacterSelectionRequestBody.new()
	result.prompt = String(payload.get("prompt", ""))
	result.count = int(payload["count"])
	for entry: Variant in payload["eligible"]:
		var candidate := InteractionSelectionValueDecoder.selection_candidate(entry)
		if candidate == null:
			return null
		result.eligible.append(candidate)
	result.allow_dead = bool(payload.get("allowDead", false))
	result.mode = StringName(payload.get("mode", ""))
	result.item_instance_id = String(payload.get("itemInstanceId", ""))
	result.spell_id = String(payload.get("spellId", ""))
	result.scroll_slot = int(payload.get("scrollSlot", -1))
	if payload.has("spellContext"):
		result.spell_context = InteractionSelectionValueDecoder.spell_target_context(payload["spellContext"])
		if result.spell_context == null:
			return null
		if not result.spell_id.is_empty() and result.spell_context.spell_id != result.spell_id:
			return null
	return result


static func _ally_selection_from_data(payload: Dictionary) -> SelectionRequestBody:
	var fields: Array = ["prompt", "maximum", "selectedIds", "requiredIds", "candidates"]
	if not InteractionValueDecoderSupport.exact(payload, fields, fields):
		return null
	if not InteractionValueDecoderSupport.strings(payload, ["prompt"]):
		return null
	if not InteractionValueDecoderSupport.ints(payload, ["maximum"]):
		return null
	if not InteractionValueDecoderSupport.string_array(payload["selectedIds"]):
		return null
	if not InteractionValueDecoderSupport.string_array(payload["requiredIds"]) or not payload["candidates"] is Array:
		return null
	var result := SelectionRequestBody.new()
	result.prompt = payload["prompt"]
	result.maximum = int(payload["maximum"])
	result.selected_ids = InteractionValueDecoderSupport.string_values(payload["selectedIds"])
	result.required_ids = InteractionValueDecoderSupport.string_values(payload["requiredIds"])
	for entry: Variant in payload["candidates"]:
		var candidate := InteractionSelectionValueDecoder.selection_candidate(entry)
		if candidate == null:
			return null
		result.candidates.append(candidate)
	return result


static func _complex_encounter_from_data(payload: Dictionary) -> ComplexEncounterRequestBody:
	var fields: Array = [
		"encounterKind", "encounterId", "prompt", "actions", "characters", "items", "spells",
		"canBackOut", "actionSelectionCount",
	]
	if not InteractionValueDecoderSupport.exact(payload, fields, fields):
		return null
	if not InteractionValueDecoderSupport.strings(payload, ["encounterKind", "prompt"]):
		return null
	if not InteractionValueDecoderSupport.ints(payload, ["encounterId", "actionSelectionCount"]):
		return null
	if not payload["actions"] is Array or not payload["characters"] is Array:
		return null
	if not payload["items"] is Array or not payload["spells"] is Array or not payload["canBackOut"] is bool:
		return null
	var result := ComplexEncounterRequestBody.new()
	result.encounter_kind = StringName(payload["encounterKind"])
	if result.encounter_kind != &"complex":
		return null
	result.encounter_id = int(payload["encounterId"])
	result.prompt = payload["prompt"]
	for entry: Variant in payload["actions"]:
		var action := InteractionSelectionValueDecoder.encounter_action(entry)
		if action == null:
			return null
		result.actions.append(action)
	for entry: Variant in payload["characters"]:
		var character := InteractionSelectionValueDecoder.named_character(entry)
		if character == null:
			return null
		result.characters.append(character)
	for entry: Variant in payload["items"]:
		var item := InteractionSelectionValueDecoder.encounter_catalog_entry(entry, &"item")
		if item == null:
			return null
		result.items.append(item)
	for entry: Variant in payload["spells"]:
		var spell := InteractionSelectionValueDecoder.encounter_catalog_entry(entry, &"spell")
		if spell == null:
			return null
		result.spells.append(spell)
	result.can_back_out = payload["canBackOut"]
	result.action_selection_count = int(payload["actionSelectionCount"])
	return result if result.action_selection_count >= 0 and result.action_selection_count <= 8 else null
