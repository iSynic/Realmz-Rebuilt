## Resolves Classic character spells and their retained party-defeat cursor.
class_name ClassicScenarioSpellOperations
extends RefCounted


static func apply(content: RealmzContent, state: GameState, rng: RealmzRng, rules: RealmzRules, action: ClassicActionDefinition, entire_party: bool, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode %d requires a four-value Extra Code row." % action.opcode)
	var spell := content.magic.spell_by_classic_id(int(action.extra_code[0]))
	if spell == null:
		if ClassicCompatibility.spell_reference_unusable(content, action.extra_code[0]):
			return ClassicCompatibility.cancel_interaction(&"unavailable-scenario-spell", "Data Spell", action.extra_code[0], context)
		return ScenarioRuntimeOperationResult.failed(&"unknown_spell", "Classic opcode %d references unavailable packed spell %d." % [action.opcode, int(action.extra_code[0])])
	if not entire_party and not context.combatant_id.is_empty():
		var result := rules.combat_flow.magic.cast_macro_spell(state, content, context.combatant_id, spell, int(action.extra_code[1]), int(action.extra_code[2]), int(action.extra_code[3]) != 0, rng)
		return ScenarioRuntimeOperationResult.completed(true, result.events) if result.ok else ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	var targets := state.party.characters() if entire_party else state.scenario_progress.selected_characters()
	if targets.is_empty() or spell.target_type == 7 or absi(spell.special) == 68:
		return _without_character_targets(state, rng, rules, action, spell)
	return _continue(content, state, rng, rules, action, targets, 0)


static func _without_character_targets(state: GameState, rng: RealmzRng, rules: RealmzRules, action: ClassicActionDefinition, spell: SpellDefinition) -> ScenarioRuntimeOperationResult:
	var result := rules.magic.resolve_scenario_empty_spell(state.party, spell, action.extra_code[1], rng)
	if result == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_spell_effect", "Classic scenario spell has unsafe party-effect inputs.")
	if not result.cast:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	var events: Array[DomainEvent] = []
	var special := absi(spell.special)
	if special == 48 or special == 50 and spell.target_type == 7:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 647 if special == 48 else 601, "waitForCompletion": false, "source": "classic-scenario-spell"}))
	if special == 68:
		events.append(DomainEvent.new(&"party_fatigue_changed", {"fatigue": state.party.fatigue, "source": "classic"}))
	elif spell.target_type == 7:
		var index := ConditionRules.PARTY_TORCH_LIT if special == 50 else special
		events.append(DomainEvent.new(&"party_condition_changed", {"condition": index, "value": state.party.conditions.value(index), "source": "classic"}))
	return ScenarioRuntimeOperationResult.completed(0, events)


static func resume(content: RealmzContent, state: GameState, rng: RealmzRng, rules: RealmzRules, handoff: ScenarioRuntimeHandoff) -> ScenarioRuntimeOperationResult:
	var targets: Array[CharacterState] = []
	for id: String in handoff.effect_target_ids:
		targets.append(state.party.character_by_id(id))
	var action := ClassicActionDefinition.new(0, handoff.effect_opcode, handoff.effect_opcode, 0, false, handoff.effect_extra_code)
	return _continue(content, state, rng, rules, action, targets, handoff.effect_next_index)


static func _continue(content: RealmzContent, state: GameState, rng: RealmzRng, rules: RealmzRules, action: ClassicActionDefinition, targets: Array[CharacterState], start_index: int) -> ScenarioRuntimeOperationResult:
	var spell := content.magic.spell_by_classic_id(action.extra_code[0])
	var events: Array[DomainEvent] = []
	for index: int in range(start_index, targets.size()):
		var character := targets[index]
		var before_health := character.current_health
		var before_conditions := character.conditions.values()
		var race := content.characters.race_by_id(character.race_id)
		var resolution := rules.magic.resolve_scenario_spell(character, spell, int(action.extra_code[1]), int(action.extra_code[2]), int(action.extra_code[3]) != 0, rng, content.characters.caste_by_id(character.caste_id), race)
		if resolution == null:
			return ScenarioRuntimeOperationResult.failed(&"invalid_spell_effect", "Classic scenario spell inputs are invalid.")
		var event_source := "classic-opcode-%d" % action.opcode
		if spell.sound_end + 600 != 0:
			events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(spell.sound_end + 600), "waitForCompletion": false, "source": event_source}))
		var first_effect_resource := 12032 if spell.look_start == 0 else 11992 + spell.look_start * 8
		events.append(DomainEvent.new(&"character_effect_requested", {"characterId": character.id, "resourceType": "cicn", "firstResourceId": first_effect_resource, "frameCount": 8, "source": event_source}))
		events.append(DomainEvent.new(&"scenario_spell_applied", {
			"spellId": spell.id,
			"classicSpellId": spell.classic_id,
			"characterId": character.id,
			"powerLevel": int(action.extra_code[1]),
			"saved": resolution.saved,
			"damage": resolution.damage,
			"duration": resolution.duration,
			"healthBefore": before_health,
			"healthAfter": character.current_health,
			"conditionsChanged": before_conditions != character.conditions.values(),
			"source": "classic",
		}))
		if resolution.aging != null and resolution.aging.changed_group():
			events.append(DomainEvent.new(&"character_age_changed", resolution.aging.event_payload(character, race)))
		# Castle resolvespell -> killbody -> partyloss interrupts the target loop here.
		if state.combat == null and state.party.characters().all(func(member: CharacterState) -> bool: return member.current_health <= 0):
			var target_ids: Array[String] = []
			for target: CharacterState in targets:
				target_ids.append(target.id)
			return ScenarioRuntimeOperationResult.suspended(ScenarioRuntimeHandoff.character_defeat(action.opcode, action.extra_code, target_ids, index + 1), events)
	return ScenarioRuntimeOperationResult.completed(targets.size(), events)
