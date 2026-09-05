## Coordinates deterministic combat AI collaborators without presentation dependencies.

class_name CombatAiScoring
extends RefCounted

var _party: CombatPartyActionPlanner
var _monster: CombatMonsterActionPlanner


func _init(context: CombatContext) -> void:
	_party = CombatPartyActionPlanner.new(context)
	_monster = CombatMonsterActionPlanner.new(context)


func choose_party_action(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng) -> Dictionary:
	return _party.choose_party_action(state, content, actor, rng)


func choose_monster_action(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, rng: RealmzRng, allow_missile: bool = true) -> StringName:
	return _monster.choose_monster_action(state, content, monster, definition, rng, allow_missile)


func best_monster_spell_plan(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition) -> Dictionary:
	return _monster.best_monster_spell_plan(state, content, monster, definition)


static func expected_spell_effect(spell: SpellDefinition, power: int) -> int:
	return CombatAiTargetFacts.expected_spell_effect(spell, power)
