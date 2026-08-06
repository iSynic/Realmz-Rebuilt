class_name ClassicCharacterOperations
extends RefCounted

var _content: RealmzContent
var _game_state: GameState
var _rng: RealmzRng
var _rules: RealmzRules


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, rules: RealmzRules) -> void:
	_content = content
	_game_state = game_state
	_rng = rng
	_rules = rules


func apply_scenario_spell(action: ClassicActionDefinition, entire_party: bool) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode %d requires a four-value Extra Code row." % action.opcode)
	var spell := _content.spell_by_classic_id(int(action.extra_code[0]))
	if spell == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_spell", "Classic opcode %d references unavailable packed spell %d." % [action.opcode, int(action.extra_code[0])])
	var targets := _game_state.party.characters() if entire_party else _game_state.selected_characters()
	if targets.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"no_selected_characters", "Classic opcode %d has no selected character targets." % action.opcode)
	var events: Array[DomainEvent] = []
	for character: CharacterState in targets:
		var before_health := character.current_health
		var before_conditions := character.conditions.values()
		var caste := _content.caste_by_id(character.caste_id)
		var resolution := _rules.magic.resolve_scenario_spell(character, spell, int(action.extra_code[1]), int(action.extra_code[2]), int(action.extra_code[3]) != 0, _rng, caste)
		if resolution == null:
			return ScenarioRuntimeOperationResult.failed(&"invalid_spell_effect", "Classic scenario spell inputs are invalid.")
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
	return ScenarioRuntimeOperationResult.completed(targets.size(), events)
