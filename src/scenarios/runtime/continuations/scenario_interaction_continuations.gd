## Creates interaction-owned scenario runtime continuations.

class_name ScenarioInteractionContinuations
extends RefCounted


static func acknowledge() -> ScenarioRuntimeContinuation:
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_ACKNOWLEDGE, ScenarioRuntimeContinuationBody.new())


static func textbox(message_id: int) -> ScenarioRuntimeContinuation:
	var body := ScenarioTextContinuationBody.new()
	body.message_id = message_id
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_TEXTBOX, body)


static func player_map(player_map_id: String) -> ScenarioRuntimeContinuation:
	var body := ScenarioTextContinuationBody.new()
	body.player_map_id = player_map_id
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_PLAYER_MAP, body)


static func safe_choice(option_count: int) -> ScenarioRuntimeContinuation:
	var body := ScenarioChoiceContinuationBody.new()
	body.option_count = option_count
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.SAFE_CHOICE, body)


static func classic_choice(values: Array[int], gosub: bool) -> ScenarioRuntimeContinuation:
	var body := ScenarioChoiceContinuationBody.new()
	body.values.assign(values)
	body.gosub = gosub
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_CHOICE, body)


static func encounter(kind: StringName, encounter_id: int, gosub: bool, option_indexes: Array[int] = [], encounter_attempt: int = 0) -> ScenarioRuntimeContinuation:
	assert(kind in [ScenarioRuntimeContinuation.CLASSIC_SIMPLE_ENCOUNTER, ScenarioRuntimeContinuation.CLASSIC_COMPLEX_ENCOUNTER])
	var body := ScenarioChoiceContinuationBody.new()
	body.encounter_id = encounter_id
	body.encounter_attempt = encounter_attempt
	body.gosub = gosub
	body.option_indexes.assign(option_indexes)
	return ScenarioRuntimeContinuation.new(kind, body)


static func character_selection(count: int, allow_dead: bool, invert: bool) -> ScenarioRuntimeContinuation:
	var body := ScenarioCharacterContinuationBody.new()
	body.count = count
	body.allow_dead = allow_dead
	body.invert = invert
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_CHARACTER_SELECTION, body)


static func character_ability(values: Array[int], gosub: bool) -> ScenarioRuntimeContinuation:
	var body := ScenarioCharacterContinuationBody.new()
	body.values.assign(values)
	body.gosub = gosub
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_CHARACTER_ABILITY, body)


static func thief_encounter(encounter_id: int, gosub: bool, encounter_attempt: int = 0) -> ScenarioRuntimeContinuation:
	var body := ScenarioThiefContinuationBody.new()
	body.encounter_id = encounter_id
	body.encounter_attempt = encounter_attempt
	body.gosub = gosub
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_THIEF_ENCOUNTER, body)


static func pick_lock(encounter_id: int, gosub: bool, action_index: int, character_id: String, encounter_attempt: int = 0) -> ScenarioRuntimeContinuation:
	var body := ScenarioThiefContinuationBody.new()
	body.encounter_id = encounter_id
	body.encounter_attempt = encounter_attempt
	body.gosub = gosub
	body.action_index = action_index
	body.character_id = character_id
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_PICK_LOCK, body)


static func thief_resolution(encounter_id: int, gosub: bool, action_index: int, character_id: String, phase: StringName, succeeded: bool, trap_pending: bool, encounter_attempt: int = 0) -> ScenarioRuntimeContinuation:
	var body := ScenarioThiefContinuationBody.new()
	body.encounter_id = encounter_id
	body.encounter_attempt = encounter_attempt
	body.gosub = gosub
	body.action_index = action_index
	body.character_id = character_id
	body.phase = phase
	body.succeeded = succeeded
	body.trap_pending = trap_pending
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_THIEF_RESOLUTION, body)
