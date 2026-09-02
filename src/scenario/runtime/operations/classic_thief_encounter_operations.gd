class_name ClassicThiefEncounterOperations
extends RefCounted

const ClassicPickLockRulesScript := preload("res://src/core/rules/classic_pick_lock_rules.gd")

const LOCK_ACTIONS: Array[int] = [2, 4, 6, 7]

var _content: RealmzContent
var _state: GameState
var _rng: RealmzRng
var _rules: RealmzRules
var _encounters: ClassicEncounterOpcodeHandler


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, rules: RealmzRules, encounter_operations: ClassicEncounterOpcodeHandler) -> void:
	_content = content
	_state = game_state
	_rng = rng
	_rules = rules
	_encounters = encounter_operations


func begin(encounter: ComplexEncounterDefinition, gosub: bool, request_id: String, encounter_attempt: int = 0) -> ScenarioRuntimeOperationResult:
	var request := _thief_request(encounter, request_id, true)
	if request == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_thief_encounter", "The Thief Encounter has no available living character or prompt.")
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.thief_encounter(encounter.id, gosub, encounter_attempt), [DomainEvent.new(&"thief_encounter_opened", {"encounterId": encounter.id})])


func resume_thief(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var owner := continuation.body as ScenarioRuntimeContinuation.ThiefBody
	var selection := response.body as InteractionResponse.ThiefEncounterBody
	var encounter := _content.complex_encounter_by_id(owner.encounter_id) if owner != null else null
	if response.kind != InteractionRequest.THIEF_ENCOUNTER or selection == null or encounter == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Thief Encounter response does not match its source encounter.")
	if selection.action == &"back":
		var complex_request := _encounters.complex_encounter_request(encounter, request_id)
		if complex_request == null:
			return ScenarioRuntimeOperationResult.failed(&"encounter_has_no_options", "Complex Encounter has no available responses after leaving its Thief actions.")
		return ScenarioRuntimeOperationResult.waiting(complex_request, ScenarioRuntimeContinuation.encounter(ScenarioRuntimeContinuation.CLASSIC_COMPLEX_ENCOUNTER, encounter.id, owner.gosub, [], owner.encounter_attempt))
	return _attempt(encounter, owner.gosub, selection, request_id, owner.encounter_attempt)


func resume_pick_lock(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var owner := continuation.body as ScenarioRuntimeContinuation.ThiefBody
	var selection := response.body as InteractionResponse.PickLockBody
	var encounter := _content.complex_encounter_by_id(owner.encounter_id) if owner != null else null
	var thief := _thief_definition(encounter)
	var character := _state.party.character_by_id(owner.character_id) if owner != null else null
	if response.kind != InteractionRequest.PICK_LOCK or selection == null or encounter == null or thief == null or character == null or character.current_health <= 0:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Pick Lock response does not match its source character and encounter.")
	var chance := ClassicPickLockRulesScript.chance(character.ability_value(ClassicPickLockRulesScript.ability_index(owner.action_index)), thief.modifiers()[owner.action_index])
	var resolved := ClassicPickLockRulesScript.resolve(_rng, thief.tumblers, chance, selection.frame_index)
	if resolved.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Pick Lock response selected a frame outside the source timer.")
	var flags := _state.thief_encounter_type_flags(thief)
	var succeeded: bool = resolved["succeeded"]
	var event := _action_event(encounter, thief, character, owner.action_index, chance, succeeded)
	event.payload.merge({"frameIndex": selection.frame_index, "positions": resolved["positions"]}, true)
	if succeeded and owner.action_index == 2:
		flags[9] = false
	_state.set_thief_encounter_type_flags(thief, flags)
	return _present_action_result(encounter, thief, owner.gosub, character, owner.action_index, succeeded, not succeeded and flags[9], request_id, [event], owner.encounter_attempt)


func resume_resolution(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var owner := continuation.body as ScenarioRuntimeContinuation.ThiefBody
	var acknowledgement := response.body as InteractionResponse.AcknowledgeBody
	var encounter := _content.complex_encounter_by_id(owner.encounter_id) if owner != null else null
	var thief := _thief_definition(encounter)
	var character := _state.party.character_by_id(owner.character_id) if owner != null else null
	if response.kind != InteractionRequest.ACKNOWLEDGE or acknowledgement == null or acknowledgement.take_note or owner == null or encounter == null or thief == null or character == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Thief Encounter result acknowledgement does not match its source action.")
	if owner.phase == &"trap-message":
		return _apply_trap(encounter, thief, owner.gosub, character, request_id, owner.encounter_attempt)
	if owner.phase != &"action-message":
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Thief Encounter result has an unknown stage.")
	if owner.trap_pending:
		return _wait_for_trap_message(encounter, owner.gosub, character, owner.action_index, owner.succeeded, request_id, [], owner.encounter_attempt)
	return _finish_action(encounter, thief, owner.gosub, character, owner.action_index, owner.succeeded, request_id, [], owner.encounter_attempt)


func _attempt(encounter: ComplexEncounterDefinition, gosub: bool, selection: InteractionResponse.ThiefEncounterBody, request_id: String, encounter_attempt: int) -> ScenarioRuntimeOperationResult:
	var thief := _thief_definition(encounter)
	var character := _state.party.character_by_id(selection.character_id)
	var action_index := selection.action_index
	var flags := _state.thief_encounter_type_flags(thief) if thief != null else []
	if thief == null or character == null or not _character_eligible(character) or not _action_available(character, thief, flags, action_index):
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Thief Encounter action or character is unavailable.")
	flags[action_index] = false
	var trap_armed := flags[9]
	if trap_armed and action_index in [4, 6, 7]:
		if action_index == 4:
			flags[4] = true
		_state.set_thief_encounter_type_flags(thief, flags)
		return _wait_for_trap_message(encounter, gosub, character, action_index, false, request_id, [], encounter_attempt)
	_state.set_thief_encounter_type_flags(thief, flags)
	if action_index in LOCK_ACTIONS:
		return _start_pick_lock(encounter, thief, gosub, character, action_index, request_id, encounter_attempt)
	var chance := character.ability_value(ClassicPickLockRulesScript.ability_index(action_index)) + thief.modifiers()[action_index]
	var succeeded := _rng.draw(100, &"classic.thief-encounter") <= chance
	if succeeded and action_index == 1 and trap_armed:
		flags[2] = true
	_state.set_thief_encounter_type_flags(thief, flags)
	var event := _action_event(encounter, thief, character, action_index, chance, succeeded)
	return _present_action_result(encounter, thief, gosub, character, action_index, succeeded, not succeeded and trap_armed and action_index != 1, request_id, [event], encounter_attempt)


func _start_pick_lock(encounter: ComplexEncounterDefinition, thief: ThiefEncounterDefinition, gosub: bool, character: CharacterState, action_index: int, request_id: String, encounter_attempt: int) -> ScenarioRuntimeOperationResult:
	var chance := ClassicPickLockRulesScript.chance(character.ability_value(ClassicPickLockRulesScript.ability_index(action_index)), thief.modifiers()[action_index])
	var frames := ClassicPickLockRulesScript.preview(_rng.snapshot(), thief.tumblers, chance)
	if frames.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_pick_lock_state", "Pick Lock could not build its deterministic tumbler sequence.")
	var request := InteractionRequest.from_payload(request_id, InteractionRequest.PICK_LOCK, {
		"encounterId": encounter.id, "actionIndex": action_index, "actionLabel": ClassicPickLockRulesScript.action_label(action_index),
		"characterId": character.id, "characterName": character.name, "portraitId": character.portrait_id,
		"chancePercent": chance, "yellowThreshold": ClassicPickLockRulesScript.yellow_threshold(chance),
		"greenThreshold": ClassicPickLockRulesScript.green_threshold(chance), "frameRate": ClassicPickLockRulesScript.FRAME_RATE,
		"timeLimitFrames": ClassicPickLockRulesScript.time_limit_frames(thief.tumblers),
		"frames": frames,
	})
	if request == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_pick_lock_state", "Pick Lock generated an invalid typed interaction.")
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.pick_lock(encounter.id, gosub, action_index, character.id, encounter_attempt), [DomainEvent.new(&"pick_lock_started", {"encounterId": encounter.id, "characterId": character.id, "actionIndex": action_index, "chancePercent": chance, "tumblers": ClassicPickLockRulesScript.tumbler_count(thief.tumblers)})])


func _finish_action(encounter: ComplexEncounterDefinition, thief: ThiefEncounterDefinition, gosub: bool, character: CharacterState, action_index: int, succeeded: bool, request_id: String, events: Array[DomainEvent], encounter_attempt: int) -> ScenarioRuntimeOperationResult:
	var codes := thief.success_codes() if succeeded else thief.failure_codes()
	var outcome := codes[action_index]
	if succeeded and action_index in LOCK_ACTIONS and outcome != 0 and outcome != 4:
		var gained := 300 * thief.tumblers
		character.experience += gained
		events.append(DomainEvent.new(&"experience_awarded", {"characterId": character.id, "amount": gained, "source": "thief-encounter"}))
	if outcome == 0:
		return _wait_for_thief(encounter, gosub, request_id, events, encounter_attempt)
	var attempt := encounter_attempt + 1
	if outcome == 4 and encounter.max_times > 1 and attempt >= encounter.max_times:
		outcome = 3
	if outcome < 1 or outcome > 4:
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_outcome", "Thief Encounter produced invalid result %d." % outcome)
	_state.record_encounter_attempt(&"complex", encounter.id)
	var context := ScenarioExecutionContext.encounter(&"complex", encounter.id, "", -1, &"thief").set_thief_action(action_index, character.id).set_encounter_attempt(attempt)
	var program_id := encounter.result_program_id(outcome)
	return ScenarioRuntimeOperationResult.completed(outcome, events, ScenarioVmDirective.branch_encounter_result(program_id, gosub, context, attempt < encounter.max_times))


func _present_action_result(encounter: ComplexEncounterDefinition, thief: ThiefEncounterDefinition, gosub: bool, character: CharacterState, action_index: int, succeeded: bool, trap_pending: bool, request_id: String, events: Array[DomainEvent], encounter_attempt: int) -> ScenarioRuntimeOperationResult:
	var text_ids := thief.success_text() if succeeded else thief.failure_text()
	var sound_ids := thief.success_sounds() if succeeded else thief.failure_sounds()
	var signed_message_id := text_ids[action_index]
	var message_id := absi(signed_message_id)
	var message := _content.message_by_id(message_id)
	if message_id != 0 and message == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Thief Encounter references unavailable message %d." % signed_message_id)
	if message != null:
		events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-thief", "classicClick": signed_message_id > 0}))
	if sound_ids[action_index] != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": sound_ids[action_index], "waitForCompletion": false, "source": "classic-thief"}))
	if signed_message_id <= 0:
		if trap_pending:
			return _wait_for_trap_message(encounter, gosub, character, action_index, succeeded, request_id, events, encounter_attempt)
		return _finish_action(encounter, thief, gosub, character, action_index, succeeded, request_id, events, encounter_attempt)
	var request := InteractionRequest.from_payload(request_id, InteractionRequest.ACKNOWLEDGE, {"prompt": message.text if message != null else "", "messageId": message_id, "presentation": "classic-textbox", "soundId": sound_ids[action_index]})
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.thief_resolution(encounter.id, gosub, action_index, character.id, &"action-message", succeeded, trap_pending, encounter_attempt), events) if request != null else ScenarioRuntimeOperationResult.failed(&"invalid_thief_encounter", "Thief Encounter result could not create its textbox stage.")


func _wait_for_trap_message(encounter: ComplexEncounterDefinition, gosub: bool, character: CharacterState, action_index: int, succeeded: bool, request_id: String, events: Array[DomainEvent] = [], encounter_attempt: int = 0) -> ScenarioRuntimeOperationResult:
	# Castle uses application STR# class 3, item 55 here, not scenario Data SD2.
	# Rebuilt preserves that identity while using concise modern host wording.
	var request := InteractionRequest.from_payload(request_id, InteractionRequest.ACKNOWLEDGE, {"prompt": "A trap is sprung.", "presentation": "classic-textbox"})
	events.append(DomainEvent.new(&"thief_trap_warning", {"resourceStringClass": 3, "resourceStringId": 55}))
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.thief_resolution(encounter.id, gosub, action_index, character.id, &"trap-message", succeeded, true, encounter_attempt), events) if request != null else ScenarioRuntimeOperationResult.failed(&"invalid_thief_encounter", "Thief Encounter trap could not create its textbox stage.")


func _apply_trap(encounter: ComplexEncounterDefinition, thief: ThiefEncounterDefinition, gosub: bool, selected: CharacterState, request_id: String, encounter_attempt: int) -> ScenarioRuntimeOperationResult:
	var flags := _state.thief_encounter_type_flags(thief)
	flags[9] = false
	flags[1] = false
	flags[6] = true
	_state.set_thief_encounter_type_flags(thief, flags)
	var targets: Array[CharacterState] = [selected] if flags[8] else _state.party.characters()
	var damage_by_character: Dictionary = {}
	if thief.low_damage != 0 and thief.high_damage >= thief.low_damage:
		for target: CharacterState in targets:
			var damage := _rng.draw_between(thief.low_damage, thief.high_damage, &"classic.thief-trap-damage")
			target.current_health = _rules.arithmetic.signed_16(target.current_health - damage)
			damage_by_character[target.id] = damage
	var prompts := thief.prompts()
	var trap_sound := prompts[1] if prompts.size() > 1 else 0
	var spell_power := prompts[2] if prompts.size() > 2 else 0
	var events: Array[DomainEvent] = [DomainEvent.new(&"thief_trap_sprung", {"encounterId": encounter.id, "thiefEncounterId": thief.id, "characterId": selected.id, "targetIds": targets.map(func(value: CharacterState) -> String: return value.id), "damageByCharacter": damage_by_character, "spellId": thief.spell_id, "spellPower": spell_power, "soundId": trap_sound})]
	if thief.spell_id != 0:
		var spell := _content.spell_by_classic_id(thief.spell_id)
		var castes: Array[CasteDefinition] = []
		var races: Array[RaceDefinition] = []
		for target: CharacterState in targets:
			castes.append(_content.caste_by_id(target.caste_id))
			races.append(_content.race_by_id(target.race_id))
		var spell_result := _rules.magic.resolve_scenario_group_spell(targets, spell, spell_power, 0, false, _rng, castes, races)
		if spell_result == null:
			return ScenarioRuntimeOperationResult.failed(&"invalid_thief_trap_spell", "Thief Encounter references an unavailable or invalid trap spell.")
		for index: int in spell_result.resolutions.size():
			var resolution := spell_result.resolutions[index]
			events.append(DomainEvent.new(&"thief_trap_spell_resolved", {"encounterId": encounter.id, "thiefEncounterId": thief.id, "spellId": spell.id, "classicSpellId": spell.classic_id, "spellPower": spell_power, "characterId": spell_result.target_ids[index], "saved": resolution.saved, "damage": resolution.damage, "duration": resolution.duration, "defeated": resolution.target_defeated, "source": "classic-thief"}))
	return _wait_for_thief(encounter, gosub, request_id, events, encounter_attempt)


func _wait_for_thief(encounter: ComplexEncounterDefinition, gosub: bool, request_id: String, events: Array[DomainEvent], encounter_attempt: int) -> ScenarioRuntimeOperationResult:
	var request := _thief_request(encounter, request_id, false)
	if request == null:
		return ScenarioRuntimeOperationResult.failed(&"party_defeated", "No living party character remains for the Thief Encounter.")
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.thief_encounter(encounter.id, gosub, encounter_attempt), events)


func _thief_request(encounter: ComplexEncounterDefinition, request_id: String, play_opening_sound: bool) -> InteractionRequest:
	var thief := _thief_definition(encounter)
	if thief == null:
		return null
	var prompt_id := absi(thief.prompts()[0]) if not thief.prompts().is_empty() else 0
	var message := _content.message_by_id(prompt_id)
	var flags := _state.thief_encounter_type_flags(thief)
	var characters: Array[Dictionary] = []
	for character: CharacterState in _state.party.characters():
		if not _character_eligible(character):
			continue
		var actions: Array[Dictionary] = []
		for index: int in ClassicPickLockRulesScript.ACTION_LABELS.size():
			var ability := character.ability_value(ClassicPickLockRulesScript.ability_index(index))
			var value := ability + thief.modifiers()[index] if ability != 0 else 0
			var enabled := _action_available(character, thief, flags, index)
			var reason := "" if enabled else "This action is no longer available." if not flags[index] else "This character lacks the required ability." if ability == 0 else "The authored modifier reduces this action below zero."
			actions.append({"index": index, "label": ClassicPickLockRulesScript.action_label(index), "value": value, "enabled": enabled, "reason": reason})
		characters.append({"id": character.id, "name": character.name, "portraitId": character.portrait_id, "actions": actions})
	var sounds := thief.prompt_sounds()
	var opening_sound := sounds[0] if play_opening_sound and not sounds.is_empty() else 0
	return InteractionRequest.from_payload(request_id, InteractionRequest.THIEF_ENCOUNTER, {"encounterId": encounter.id, "prompt": message.text if message != null else "Choose a thief action.", "soundId": opening_sound, "characters": characters}) if not characters.is_empty() else null


func _thief_definition(encounter: ComplexEncounterDefinition) -> ThiefEncounterDefinition:
	return _content.thief_encounter_by_id(encounter.thief_success) if encounter != null and encounter.thief else null


static func _character_eligible(character: CharacterState) -> bool:
	return character != null and character.current_health > 0 and not character.conditions.is_active(ConditionRules.ANIMATED)


static func _action_available(character: CharacterState, thief: ThiefEncounterDefinition, flags: Array[bool], action_index: int) -> bool:
	var ability_index := ClassicPickLockRulesScript.ability_index(action_index)
	var ability := character.ability_value(ability_index)
	return ability_index >= 0 and flags.size() == 10 and flags[action_index] and ability != 0 and ability + thief.modifiers()[action_index] > 0


static func _action_event(encounter: ComplexEncounterDefinition, thief: ThiefEncounterDefinition, character: CharacterState, action_index: int, chance: int, succeeded: bool) -> DomainEvent:
	var text_ids := thief.success_text() if succeeded else thief.failure_text()
	var sound_ids := thief.success_sounds() if succeeded else thief.failure_sounds()
	return DomainEvent.new(&"thief_action_resolved", {"encounterId": encounter.id, "thiefEncounterId": thief.id, "characterId": character.id, "actionIndex": action_index, "chancePercent": chance, "succeeded": succeeded, "messageId": absi(text_ids[action_index]), "signedMessageId": text_ids[action_index], "classicClick": text_ids[action_index] > 0, "soundId": sound_ids[action_index]})
