class_name ClassicEncounterOpcodeHandler
extends ClassicOpcodeHandler

var _content: RealmzContent
var _game_state: GameState


func _init(content: RealmzContent, game_state: GameState) -> void:
	_content = content
	_game_state = game_state


func opcode_ids() -> Array[int]:
	return [3, 4, 5, 34, 35, 41, 44, 54]


func execute(action: ClassicActionDefinition, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		3:
			return _request_classic_choice(action, request_id)
		4:
			return request_encounter(&"simple", action.operand_id, action.gosub, request_id, context)
		5:
			return _request_complex_encounter(action.operand_id, action.gosub, request_id, context)
		34:
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"encounter_loop_finished", {"source": "classic"})], ScenarioVmDirective.resume_after_encounter())
		35:
			var encounter_id := context.encounter_id
			if context.encounter_kind != &"simple" or not _game_state.eliminate_simple_option(encounter_id, action.operand_id - 1):
				return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_context", "Classic opcode 35 requires a Simple Encounter response context.")
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"encounter_option_eliminated", {"encounterId": encounter_id, "optionIndex": action.operand_id - 1})])
		41:
			return _eliminate_simple_option(action)
		44:
			return _eliminate_complex_result(action, context)
		54:
			return _mutate_timed_encounter(action)
	return super.execute(action, request_id, context)


func _eliminate_complex_result(action: ClassicActionDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	var result_index := action.operand_id - 1
	if context.encounter_kind != &"complex" or context.encounter_id < 0 or not _game_state.eliminate_complex_result(context.encounter_id, result_index):
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_context", "Classic opcode 44 requires result 1 through 4 in a Complex Encounter context.")
	return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"complex_encounter_result_eliminated", {"encounterId": context.encounter_id, "resultIndex": result_index, "source": "classic"})])


func request_encounter(kind: StringName, encounter_id: int, gosub: bool, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if kind == &"complex":
		return _request_complex_encounter(encounter_id, gosub, request_id, context)
	if kind != &"simple":
		return ScenarioRuntimeOperationResult.failed(&"unknown_encounter_kind", "Classic encounter kind '%s' is unavailable." % kind)
	var encounter := _content.simple_encounter_by_id(encounter_id)
	if encounter == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "Classic branch references unavailable Simple Encounter %d." % encounter_id)
	var prompt := _content.message_by_id(absi(encounter.prompt_message_id))
	if prompt == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Simple Encounter %d references unavailable prompt message %d." % [encounter.id, encounter.prompt_message_id])
	var options: Array[Dictionary] = []
	var option_indexes: Array[int] = []
	var responses := encounter.responses()
	for option_index: int in responses.size():
		if _game_state.simple_option_is_eliminated(encounter.id, option_index):
			continue
		var response: SimpleEncounterResponse = responses[option_index]
		options.append({"id": response.id, "label": response.label})
		option_indexes.append(option_index)
	if options.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"encounter_has_no_options", "Simple Encounter %d has no remaining responses." % encounter.id)
	var request := InteractionRequest.from_payload(request_id, &"encounter_choice", {"encounterKind": "simple", "encounterId": encounter.id, "prompt": prompt.text, "options": options, "canBackOut": encounter.can_back_out})
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.encounter(ScenarioRuntimeContinuation.CLASSIC_SIMPLE_ENCOUNTER, encounter.id, gosub, option_indexes, _encounter_attempt(context, &"simple", encounter.id)), [_encounter_open_sound(&"simple", encounter.id)])


func _request_complex_encounter(encounter_id: int, gosub: bool, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	var encounter := _content.complex_encounter_by_id(encounter_id)
	if encounter == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "Classic branch references unavailable Complex Encounter %d." % encounter_id)
	var request := complex_encounter_request(encounter, request_id)
	if request == null:
		return ScenarioRuntimeOperationResult.failed(&"encounter_has_no_options", "Complex Encounter %d has no available responses." % encounter.id)
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.encounter(ScenarioRuntimeContinuation.CLASSIC_COMPLEX_ENCOUNTER, encounter.id, gosub, [], _encounter_attempt(context, &"complex", encounter.id)), [_encounter_open_sound(&"complex", encounter.id)])


static func _encounter_open_sound(kind: StringName, encounter_id: int) -> DomainEvent:
	return DomainEvent.new(&"sound_requested", {"soundId": 20005, "waitForCompletion": false, "reducedSoundEligible": true, "source": "classic-%s-encounter-open" % String(kind), "encounterId": encounter_id})


static func _encounter_attempt(context: ScenarioExecutionContext, kind: StringName, encounter_id: int) -> int:
	if context != null and context.encounter_kind == kind and context.encounter_id == encounter_id:
		return maxi(0, context.encounter_attempt)
	return 0


func complex_encounter_request(encounter: ComplexEncounterDefinition, request_id: String) -> InteractionRequest:
	var prompt := _content.message_by_id(absi(encounter.prompt_message_id))
	if prompt == null:
		return null
	var actions: Array[Dictionary] = []
	if encounter.action_result != 0:
		var labels := encounter.action_labels()
		for slot: int in labels.size():
			var label := labels[slot].strip_edges()
			if not label.is_empty() and label != "*":
				actions.append({"id": "choice:%d" % slot, "kind": "choice", "slot": slot, "label": label})
	if encounter.word_result != 0:
		actions.append({"id": "word", "kind": "word", "label": "Speak a word"})
	for spell_id: int in encounter.spell_ids():
		if spell_id != 0:
			actions.append({"id": "spell", "kind": "spell", "label": "Cast a spell"})
			break
	for item_id: int in encounter.item_ids():
		if item_id != 0:
			actions.append({"id": "item", "kind": "item", "label": "Use an item"})
			break
	if encounter.thief:
		var thief_encounter := _content.thief_encounter_by_id(encounter.thief_success)
		if thief_encounter != null:
			actions.append({"id": "thief", "kind": "thief", "label": "Thief action"})
	if encounter.can_back_out:
		actions.append({"id": "back", "kind": "back", "label": "Back out"})
	if actions.is_empty():
		return null
	var characters: Array[Dictionary] = []
	var items: Array[Dictionary] = []
	var spells: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		if character.current_health <= 0:
			continue
		characters.append({"id": character.id, "name": character.name, "portraitId": character.portrait_id})
		for instance: ItemInstance in character.inventory():
			var item := _content.item_by_id(instance.definition_id)
			if item != null:
				items.append({"classicItemId": item.classic_id, "name": item.name if instance.identified else item.unidentified_name, "characterId": character.id, "instanceId": instance.id, "iconResourceType": "cicn", "iconId": item.visible_icon_id(instance.identified), "charges": instance.charges, "equipped": instance.equipped})
		for spell_id: String in character.known_spells():
			var spell := _content.spell_by_id(spell_id)
			if spell != null:
				spells.append({"classicSpellId": spell.classic_id, "name": spell.name, "characterId": character.id})
	return InteractionRequest.from_payload(request_id, &"complex_encounter", {"encounterKind": "complex", "encounterId": encounter.id, "prompt": prompt.text, "actions": actions, "characters": characters, "items": items, "spells": spells, "canBackOut": encounter.can_back_out, "actionSelectionCount": encounter.groups().filter(func(value: int) -> bool: return value != 0).size()})


func _request_classic_choice(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 3 requires a five-value Extra Code row.")
	var yes_id := action.extra_code[3]
	var no_id := action.extra_code[4]
	var yes_label_value: Variant
	var no_label_value: Variant
	if yes_id == 0:
		yes_label_value = "Yes"
		no_label_value = "No"
	else:
		yes_label_value = _classic_choice_label(yes_id)
		no_label_value = _classic_choice_label(no_id)
	if yes_label_value == null or no_label_value == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_option_label", "Classic opcode 3 references an unavailable option label.")
	var request := InteractionRequest.from_payload(request_id, &"yes_no", {"yesId": yes_id, "yesLabel": yes_label_value, "noId": no_id, "noLabel": no_label_value})
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.classic_choice(action.extra_code, action.gosub))


func _classic_choice_label(label_id: int) -> Variant:
	if _content.has_option_labels():
		var option_label := _content.option_label_by_id(absi(label_id))
		if option_label == null:
			return null
		return option_label.text
	var message := _content.message_by_id(absi(label_id))
	if message == null:
		return null
	return message.text


func _mutate_timed_encounter(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 54 requires a five-value Extra Code row.")
	var encounter_id := action.extra_code[0]
	var current := _game_state.timed_encounter_override(encounter_id)
	if action.extra_code[1] > -1:
		current["percent"] = action.extra_code[1]
	if action.extra_code[2] > -1:
		current["increment"] = action.extra_code[2]
	if action.extra_code[3] != 0:
		current["day"] = _game_state.clock.day()
	if action.extra_code[4] > -1:
		current["day"] = int(current.get("day", 0)) + action.extra_code[4]
	_game_state.set_timed_encounter_override(encounter_id, current)
	return ScenarioRuntimeOperationResult.completed(current, [DomainEvent.new(&"timed_encounter_changed", {"encounterId": encounter_id, "state": current})])


func _eliminate_simple_option(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 2:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 41 requires a five-value Extra Code row.")
	var encounter := _content.simple_encounter_by_id(action.extra_code[0])
	var option_index := action.extra_code[1] - 1
	if encounter == null or encounter.response_at(option_index) == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_encounter_option", "Classic opcode 41 references an unavailable Simple Encounter option.")
	_game_state.eliminate_simple_option(encounter.id, option_index)
	return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"encounter_option_eliminated", {"encounterId": encounter.id, "optionIndex": option_index, "source": "classic-opcode-41"})])
