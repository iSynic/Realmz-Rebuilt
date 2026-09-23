## Applies Classic health opcodes with their saveable total-party-loss boundary.

class_name ClassicHealthOperations
extends RefCounted


static func apply(content: RealmzContent, state: GameState, rng: RealmzRng, action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"invalid_health_effect", "Classic health action requires a valid Extra Code roll range.")
	var targets := state.party.characters() if action.opcode == 16 else state.scenario_progress.selected_characters()
	var target_ids: Array[String] = []
	for character: CharacterState in targets:
		target_ids.append(character.id)
	var operands: Array[int] = []
	for index: int in 5:
		operands.append(action.extra_code[index])
	return _continue(content, state, rng, action.opcode, operands, target_ids, 0)


static func handoff_is_valid(state: GameState, handoff: ScenarioRuntimeHandoff) -> bool:
	if state == null or state.party == null or state.combat != null or handoff == null or handoff.source_kind != ScenarioRuntimeHandoff.CLASSIC_HEALTH or handoff.to_data().is_empty():
		return false
	var party_ids: Array[String] = []
	for character: CharacterState in state.party.characters():
		party_ids.append(character.id)
	if handoff.health_opcode == 16 and party_ids != handoff.health_target_ids:
		return false
	for id: String in handoff.health_target_ids:
		if not party_ids.has(id):
			return false
	return true


static func resume(content: RealmzContent, state: GameState, rng: RealmzRng, handoff: ScenarioRuntimeHandoff) -> ScenarioRuntimeOperationResult:
	if not handoff_is_valid(state, handoff):
		return ScenarioRuntimeOperationResult.failed(&"invalid_party_defeat_handoff", "The suspended Classic health effect no longer matches the party.")
	return _continue(content, state, rng, handoff.health_opcode, handoff.health_extra_code, handoff.health_target_ids, handoff.health_next_index)


static func _continue(content: RealmzContent, state: GameState, rng: RealmzRng, opcode: int, extra_code: Array[int], target_ids: Array[String], start_index: int) -> ScenarioRuntimeOperationResult:
	var message: MessageDefinition = null
	if extra_code[4] != 0:
		message = content.scenario_records.message_by_id(absi(extra_code[4]))
		if message == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode %d references unavailable message %d." % [opcode, extra_code[4]])
	var hits: Array[Dictionary] = []
	var events: Array[DomainEvent] = []
	for index: int in range(start_index, target_ids.size()):
		var character := state.party.character_by_id(target_ids[index])
		if character == null:
			return ScenarioRuntimeOperationResult.failed(&"invalid_party_defeat_handoff", "Classic health effect target is unavailable.")
		if extra_code[3] != 0:
			events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(extra_code[3]), "waitForCompletion": extra_code[3] < 0, "source": "classic-opcode-15"}))
		var roll := rng.draw_between_classic(extra_code[1], extra_code[2], &"classic.health-effect")
		var amount := extra_code[0] * roll
		var previous := character.current_health
		if not character.conditions.is_active(ConditionRules.TURNED_TO_STONE) and character.current_health > -10:
			character.current_health = mini(character.maximum_health, maxi(-10, character.current_health + amount))
		hits.append({"characterId": character.id, "previousHealth": previous, "health": character.current_health, "amount": character.current_health - previous})
		events.append(DomainEvent.new(&"character_effect_requested", {"characterId": character.id, "resourceType": "cicn", "firstResourceId": 12112, "frameCount": 8, "source": "classic-opcode-15"}))
		if state.party.characters().all(func(member: CharacterState) -> bool: return member.current_health <= 0):
			events.append(DomainEvent.new(&"party_health_changed", {"targets": "party" if opcode == 16 else "selected", "hits": hits}))
			return ScenarioRuntimeOperationResult.suspended(ScenarioRuntimeHandoff.health_defeat(opcode, extra_code, target_ids, index + 1), events)
	events.append(DomainEvent.new(&"party_health_changed", {"targets": "party" if opcode == 16 else "selected", "hits": hits}))
	if message != null:
		events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-opcode-15", "classicClick": extra_code[4] > 0}))
	return ScenarioRuntimeOperationResult.completed(hits, events)
