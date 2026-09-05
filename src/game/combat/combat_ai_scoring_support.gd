## Shares deterministic combat-AI choice mechanics and actor queries.

class_name CombatAiScoringSupport
extends RefCounted

const INVALID_COORDINATE := Vector2i(-100_000, -100_000)
const MAX_WEIGHTED_DRAW: int = 32_767

var _context: CombatContext


func _init(context: CombatContext) -> void:
	_context = context

static func _prefer(current: Dictionary, candidate: Dictionary) -> Dictionary:
	return candidate if not candidate.is_empty() and int(candidate.get("score", -1)) > int(current.get("score", -1)) else current


static func _append_positive_choice(choices: Array[Dictionary], candidate: Dictionary) -> void:
	if not candidate.is_empty() and int(candidate.get("score", 0)) > 0:
		choices.append(candidate)


static func _weighted_choice(candidates: Array[Dictionary], rng: RealmzRng, semantic_tag: StringName) -> Dictionary:
	var choices: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		if not candidate.is_empty() and int(candidate.get("score", 0)) > 0:
			choices.append(candidate)
	if choices.is_empty():
		return {}
	choices.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_score := int(left.get("score", 0))
		var right_score := int(right.get("score", 0))
		return left_score > right_score or (left_score == right_score and _choice_key(left) < _choice_key(right))
	)
	if choices.size() == 1:
		return choices[0]
	var weights: Array[int] = []
	var total_weight := 0
	for choice: Dictionary in choices:
		var weight := maxi(1, int(choice.get("score", 0)))
		weights.append(weight)
		total_weight += weight
	while total_weight > MAX_WEIGHTED_DRAW:
		var divisor := (total_weight + MAX_WEIGHTED_DRAW - 1) / MAX_WEIGHTED_DRAW
		total_weight = 0
		for index: int in weights.size():
			weights[index] = maxi(1, weights[index] / divisor)
			total_weight += weights[index]
	var roll := rng.draw(total_weight, semantic_tag)
	var threshold := 0
	for index: int in choices.size():
		threshold += weights[index]
		if roll <= threshold:
			return choices[index]
	return choices.back()


static func _choice_key(choice: Dictionary) -> String:
	var target_ids: Array = choice.get("targetIds", [])
	var target_coordinates: Array = choice.get("targetCoordinates", [])
	return "%s|%s|%s|%s|%s|%s|%d" % [String(choice.get("action", "")), String(choice.get("spellId", "")), String(choice.get("targetId", "")), ",".join(target_ids), str(choice.get("coordinate", Vector2i(-1, -1))), str(target_coordinates), int(choice.get("rotation", 0))]


static func _condition_cure_score(state: GameState, target_id: String, condition_index: int) -> int:
	var character := state.party.character_by_id(target_id)
	var condition_value := character.conditions.value(condition_index) if character != null else state.combat.roster.monster_by_id(target_id).conditions.value(condition_index)
	var urgency := 900 if condition_index in [ConditionRules.POISONED, ConditionRules.DISEASED] else 720
	return urgency + mini(200, absi(condition_value) * 10)


static func _maximum_condition_duration(spell: SpellDefinition, power: int) -> int:
	return maxi(spell.duration_min, spell.duration_max) + power * maxi(spell.power_duration_min, spell.power_duration_max)
static func _actors_by_cell(battlefield: BattlefieldState) -> Dictionary:
	var result: Dictionary = {}
	for actor_id: String in battlefield.actors.actor_ids():
		for coordinate: Vector2i in battlefield.actors.actor_footprint(actor_id):
			result[coordinate] = actor_id
	return result


func _auto_group_target_is_safe(spell: SpellDefinition) -> bool:
	if spell.target_type not in [9, 10, 12]:
		return true
	if spell.target_type == 12:
		return false
	var condition_effect := ClassicSpellConditionRules.combat_condition_effect_index(spell) >= 0 or ClassicSpellConditionRules.combat_persistent_field_condition_index(spell) >= 0
	var friendly_effect: bool = MagicRules.is_condition_cure_spell(spell) or _context.automation().is_source_backed_combat_healing_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_spell_point_restore_spell(spell) or condition_effect and (spell.cannot == 4 or spell.target_type == 9)
	return spell.target_type == 9 if friendly_effect else spell.target_type == 10


func _opposed_actor_ids(state: GameState, actor: CharacterState) -> Array[String]:
	var result: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.id != actor.id and character.current_health > 0 and character.traitor != actor.traitor and state.combat.battlefield.actors.has_actor(character.id):
			result.append(character.id)
	for monster: MonsterState in state.combat.roster.monsters():
		if monster.current_health > 0 and monster.traitor != actor.traitor and state.combat.battlefield.actors.has_actor(monster.id):
			result.append(monster.id)
	return result


func _friendly_actor_ids(state: GameState, actor: CharacterState) -> Array[String]:
	var result: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and character.traitor == actor.traitor and state.combat.battlefield.actors.has_actor(character.id):
			result.append(character.id)
	for monster: MonsterState in state.combat.roster.monsters():
		if monster.current_health > 0 and monster.traitor == actor.traitor and state.combat.battlefield.actors.has_actor(monster.id):
			result.append(monster.id)
	return result


func _hostile_adjacent_ids(state: GameState, actor_id: String) -> Array[String]:
	var actor := state.party.character_by_id(actor_id)
	var result: Array[String] = []
	if actor == null:
		return result
	for target_id: String in _context.battlefield.adjacent_actor_ids(state.combat.battlefield, actor_id):
		if not _actor_is_friendly(state, actor, target_id):
			result.append(target_id)
	return result


func _hostile_adjacent_ids_for_monster(state: GameState, monster: MonsterState) -> Array[String]:
	var result: Array[String] = []
	for target_id: String in _context.battlefield.adjacent_actor_ids(state.combat.battlefield, monster.id):
		var character := state.party.character_by_id(target_id)
		var target_monster := state.combat.roster.monster_by_id(target_id)
		if (character != null and character.current_health > 0 and character.traitor != monster.traitor) or (target_monster != null and target_monster.current_health > 0 and target_monster.traitor != monster.traitor):
			result.append(target_id)
	return result


func _opposed_actor_ids_for_monster(state: GameState, monster: MonsterState) -> Array[String]:
	var result: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and character.traitor != monster.traitor and state.combat.battlefield.actors.has_actor(character.id):
			result.append(character.id)
	for candidate: MonsterState in state.combat.roster.monsters():
		if candidate.id != monster.id and candidate.current_health > 0 and candidate.traitor != monster.traitor and state.combat.battlefield.actors.has_actor(candidate.id):
			result.append(candidate.id)
	return result


func _friendly_actor_ids_for_monster(state: GameState, monster: MonsterState) -> Array[String]:
	var result: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and character.traitor == monster.traitor and state.combat.battlefield.actors.has_actor(character.id): result.append(character.id)
	for candidate: MonsterState in state.combat.roster.monsters():
		if candidate.current_health > 0 and candidate.traitor == monster.traitor and state.combat.battlefield.actors.has_actor(candidate.id): result.append(candidate.id)
	return result


func _everybody_actor_ids(state: GameState) -> Array[String]:
	var result: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.actors.has_actor(character.id): result.append(character.id)
	for monster: MonsterState in state.combat.roster.monsters():
		if monster.current_health > 0 and state.combat.battlefield.actors.has_actor(monster.id): result.append(monster.id)
	return result


static func expected_spell_effect(spell: SpellDefinition, power: int) -> int:
	return CombatAiTargetFacts.expected_spell_effect(spell, power)


static func _actor_is_friendly(state: GameState, actor: CharacterState, target_id: String) -> bool:
	return CombatAiTargetFacts.character_is_friendly(state, actor, target_id)


static func _actor_is_friendly_to_monster(state: GameState, actor: MonsterState, target_id: String) -> bool:
	return CombatAiTargetFacts.monster_is_friendly(state, actor, target_id)


static func _target_health(state: GameState, target_id: String) -> int:
	return CombatAiTargetFacts.health(state, target_id)


static func _target_maximum_health(state: GameState, target_id: String) -> int:
	return CombatAiTargetFacts.maximum_health(state, target_id)


static func _target_missing_health(state: GameState, target_id: String) -> int:
	return CombatAiTargetFacts.missing_health(state, target_id)


static func _target_missing_spell_points(state: GameState, target_id: String) -> int:
	return CombatAiTargetFacts.missing_spell_points(state, target_id)


static func _target_spell_points(state: GameState, target_id: String) -> int:
	return CombatAiTargetFacts.spell_points(state, target_id)


static func _target_condition_value(state: GameState, target_id: String, condition_index: int) -> int:
	return CombatAiTargetFacts.condition_value(state, target_id, condition_index)


func _destroy_magic_candidates(state: GameState, content: RealmzContent, caster_id: String, caster_traitor: bool, spell: SpellDefinition, power: int) -> Array[String]:
	var candidates: Array[String] = []
	for target_id: String in _all_actor_ids(state):
		if (target_id != caster_id and _target_reflects(state, target_id)) or _destroy_magic_target_score(state, caster_traitor, target_id) <= 0 or not _context.magic_flow().selection().spell_actor_target_is_valid(state, content, caster_id, target_id, spell, power):
			continue
		candidates.append(target_id)
	candidates.sort_custom(func(left: String, right: String) -> bool: return _destroy_magic_target_score(state, caster_traitor, left) > _destroy_magic_target_score(state, caster_traitor, right) or (_destroy_magic_target_score(state, caster_traitor, left) == _destroy_magic_target_score(state, caster_traitor, right) and left < right))
	return candidates


static func _destroy_magic_target_score(state: GameState, caster_traitor: bool, target_id: String) -> int:
	return CombatAiTargetFacts.destroy_magic_score(state, caster_traitor, target_id)


static func _all_actor_ids(state: GameState) -> Array[String]:
	return CombatAiTargetFacts.all_actor_ids(state)


static func _target_hard_immune(state: GameState, content: RealmzContent, target_id: String, spell: SpellDefinition) -> bool:
	return CombatAiTargetFacts.hard_immune(state, content, target_id, spell)


static func _target_reflects(state: GameState, target_id: String) -> bool:
	return CombatAiTargetFacts.reflects(state, target_id)


static func _lethal_bonus(state: GameState, target_id: String, expected: int) -> int:
	return CombatAiTargetFacts.lethal_bonus(state, target_id, expected)


static func _lethal_pressure(state: GameState, target_id: String) -> int:
	return CombatAiTargetFacts.lethal_pressure(state, target_id)
