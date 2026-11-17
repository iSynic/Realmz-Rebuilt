## What a combat view asks of the combat engine. The view depends on this small surface, not on the engine,
## so screens that only show a battle do not load the rules that run one.
class_name CombatViewProbes
extends RefCounted


func probe_character_retreat(_combat: CombatState, _characters: Array[CharacterState], _actor_id: String) -> CombatRetreatProbe:
	return null


func probe_edge_retreat(_combat: CombatState, _actor_id: String, _destination: Vector2i) -> CombatRetreatProbe:
	return null


func probe_delay(_state: GameState, _actor_id: String) -> CombatCommandProbe:
	return null


func probe_bandage(_state: GameState, _actor_id: String) -> CombatCommandProbe:
	return null


func probe_turn_undead(_state: GameState, _content: RealmzContent, _actor_id: String) -> CombatCommandProbe:
	return null


func probe_undo(_state: GameState, _actor_id: String) -> CombatCommandProbe:
	return null


func bandage_candidate_ids(_state: GameState) -> Array[String]:
	return []


func turn_undead_target_ids(_state: GameState, _content: RealmzContent) -> Array[String]:
	return []


func character_projectile_profile(_character: CharacterState, _content: RealmzContent, _equipment: CharacterCombatEquipment, _state: GameState) -> ProjectileAttackProfile:
	return null


func character_item_spell_options(_state: GameState, _content: RealmzContent, _caster_id: String) -> Array[CombatItemOptionView]:
	return []


func projectile_target_is_valid(_combat: CombatState, _content: RealmzContent, _actor_id: String, _target_id: String, _maximum_range: int, _require_line_of_sight: bool) -> bool:
	return false


func friendly_collision_target_id(_state: GameState, _actor_id: String, _destination: Vector2i) -> String:
	return ""
