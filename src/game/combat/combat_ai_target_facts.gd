## Implements deterministic combat AI target facts rules without presentation dependencies.

class_name CombatAiTargetFacts
extends RefCounted

## Answers read-only combatant facts used by deterministic tactical scoring.


static func expected_spell_effect(spell: SpellDefinition, power: int) -> int:
	if ClassicSpellSpecialEffectRules.is_combat_death_spell(spell):
		return 128
	if absi(spell.special) == 28:
		var duration := maxi(spell.duration_min, spell.duration_max) + power * maxi(spell.power_duration_min, spell.power_duration_max)
		return absi(duration)
	return int((spell.damage_min + spell.damage_max) / 2.0 + (spell.power_damage_min + spell.power_damage_max) * power / 2.0)


static func character_is_friendly(state: GameState, actor: CharacterState, target_id: String) -> bool:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return character.traitor == actor.traitor
	var monster := state.combat.roster.monster_by_id(target_id)
	return monster != null and monster.traitor == actor.traitor


static func monster_is_friendly(state: GameState, actor: MonsterState, target_id: String) -> bool:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return character.traitor == actor.traitor
	var monster := state.combat.roster.monster_by_id(target_id)
	return monster != null and monster.traitor == actor.traitor


static func health(state: GameState, target_id: String) -> int:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return character.current_health
	var monster := state.combat.roster.monster_by_id(target_id)
	return monster.current_health if monster != null else 0x7fff_ffff


static func maximum_health(state: GameState, target_id: String) -> int:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return character.maximum_health
	var monster := state.combat.roster.monster_by_id(target_id)
	return monster.maximum_health if monster != null else 1


static func missing_health(state: GameState, target_id: String) -> int:
	return maxi(0, maximum_health(state, target_id) - health(state, target_id))


static func missing_spell_points(state: GameState, target_id: String) -> int:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return maxi(0, character.maximum_spell_points - character.spell_points)
	var monster := state.combat.roster.monster_by_id(target_id)
	return maxi(0, monster.maximum_spell_points - monster.spell_points) if monster != null else 0


static func spell_points(state: GameState, target_id: String) -> int:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return maxi(0, character.spell_points)
	var monster := state.combat.roster.monster_by_id(target_id)
	return maxi(0, monster.spell_points) if monster != null else 0


static func condition_value(state: GameState, target_id: String, condition_index: int) -> int:
	var character := state.party.character_by_id(target_id)
	var monster := state.combat.roster.monster_by_id(target_id) if character == null else null
	return character.conditions.value(condition_index) if character != null else monster.conditions.value(condition_index) if monster != null else 0


static func destroy_magic_score(state: GameState, caster_traitor: bool, target_id: String) -> int:
	var character := state.party.character_by_id(target_id)
	var monster := state.combat.roster.monster_by_id(target_id) if character == null else null
	var conditions: ConditionSet = character.conditions if character != null else monster.conditions if monster != null else null
	if conditions == null:
		return 0
	var target_traitor_before := character.traitor if character != null else monster.traitor
	var target_traitor_after := false if character != null else target_traitor_before
	var allied_before := target_traitor_before == caster_traitor
	var allied_after := target_traitor_after == caster_traitor
	var score := 0
	var harmful := [ConditionRules.RUNS_AWAY, ConditionRules.HELPLESS, ConditionRules.TANGLED, ConditionRules.CURSED, ConditionRules.STUPID, ConditionRules.SLOW, ConditionRules.POISONED, ConditionRules.TURNED_TO_STONE, ConditionRules.BLIND, ConditionRules.DISEASED, ConditionRules.CONFUSED, ConditionRules.ENERGY_DRAIN, ConditionRules.HINDERED_ATTACKS, ConditionRules.HINDERED_DEFENSE, ConditionRules.SILENCED]
	for index: int in conditions.size():
		if conditions.value(index) <= 0:
			continue
		var harmful_effect := index in harmful
		score += (300 if harmful_effect else -180) if allied_after else (-240 if harmful_effect else 240)
	if character != null and character.traitor:
		score += 1_200 if allied_after and not allied_before else -1_400 if allied_before and not allied_after else 0
	return score


static func all_actor_ids(state: GameState) -> Array[String]:
	var result: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.actors.has_actor(character.id):
			result.append(character.id)
	for monster: MonsterState in state.combat.roster.monsters():
		if monster.current_health > 0 and state.combat.battlefield.actors.has_actor(monster.id):
			result.append(monster.id)
	return result


static func hard_immune(state: GameState, content: RealmzContent, target_id: String, spell: SpellDefinition) -> bool:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return character.magic_resistance > 100
	var monster := state.combat.roster.monster_by_id(target_id)
	var definition := content.combat.monster_by_id(monster.definition_id) if monster != null else null
	return monster != null and (monster.magic_resistance > 100 or definition != null and definition.spell_immune(spell.spell_class))


static func reflects(state: GameState, target_id: String) -> bool:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return character.conditions.is_active(ConditionRules.REFLECTING_SPELLS)
	var monster := state.combat.roster.monster_by_id(target_id)
	return monster != null and monster.conditions.is_active(ConditionRules.REFLECTING_SPELLS)


static func lethal_bonus(state: GameState, target_id: String, expected: int) -> int:
	return 180 if health(state, target_id) <= expected else 0


static func lethal_pressure(state: GameState, target_id: String) -> int:
	return maxi(0, 100 - mini(100, health(state, target_id)))
