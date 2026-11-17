## Answers a combat view's questions from the combat engine's own collaborators.
class_name CombatFlowViewProbes
extends CombatViewProbes

var _actions: CombatFlowActions
var _reactions: CombatFlowReactions
var _magic: CombatFlowMagic


func _init(actions: CombatFlowActions, reactions: CombatFlowReactions, magic: CombatFlowMagic) -> void:
	_actions = actions
	_reactions = reactions
	_magic = magic


func probe_character_retreat(combat: CombatState, characters: Array[CharacterState], actor_id: String) -> CombatRetreatProbe:
	return _reactions.probe_character_retreat(combat, characters, actor_id)


func probe_edge_retreat(combat: CombatState, actor_id: String, destination: Vector2i) -> CombatRetreatProbe:
	return _reactions.probe_edge_retreat(combat, actor_id, destination)


func probe_delay(state: GameState, actor_id: String) -> CombatCommandProbe:
	return _actions.probe_delay(state, actor_id)


func probe_bandage(state: GameState, actor_id: String) -> CombatCommandProbe:
	return _actions.probe_bandage(state, actor_id)


func probe_turn_undead(state: GameState, content: RealmzContent, actor_id: String) -> CombatCommandProbe:
	return _actions.probe_turn_undead(state, content, actor_id)


func probe_undo(state: GameState, actor_id: String) -> CombatCommandProbe:
	return _actions.probe_undo(state, actor_id)


func bandage_candidate_ids(state: GameState) -> Array[String]:
	return _actions.bandage_candidate_ids(state)


func turn_undead_target_ids(state: GameState, content: RealmzContent) -> Array[String]:
	return _actions.turn_undead_target_ids(state, content)


func character_projectile_profile(character: CharacterState, content: RealmzContent, equipment: CharacterCombatEquipment, state: GameState) -> ProjectileAttackProfile:
	return _reactions.character_projectile_profile(character, content, equipment, state)


func character_item_spell_options(state: GameState, content: RealmzContent, caster_id: String) -> Array[CombatItemOptionView]:
	return _magic.character_item_spell_options(state, content, caster_id)


func projectile_target_is_valid(combat: CombatState, content: RealmzContent, actor_id: String, target_id: String, maximum_range: int, require_line_of_sight: bool) -> bool:
	return _reactions.projectile_target_is_valid(combat, content, actor_id, target_id, maximum_range, require_line_of_sight)


func friendly_collision_target_id(state: GameState, actor_id: String, destination: Vector2i) -> String:
	return _reactions.friendly_collision_target_id(state, actor_id, destination)
