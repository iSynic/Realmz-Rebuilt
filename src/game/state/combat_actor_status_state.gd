## Owns battle-scoped actor modes and status markers.

class_name CombatActorStatusState
extends RefCounted

var _actor_ids: Dictionary = {}
var _monster_ids: Dictionary = {}
var _weapon_modes: Dictionary = {}
var _guarding: Dictionary = {}
var _retreated: Dictionary = {}
var _attacked: Dictionary = {}
var _bleeding: Dictionary = {}
var _turned_undead: Dictionary = {}


func replace_actor_registry(actor_ids: Array[String], roster: CombatRosterState) -> void:
	_actor_ids.clear()
	_monster_ids.clear()
	for actor_id: String in actor_ids:
		_actor_ids[actor_id] = true
		if roster != null and roster.monster_by_id(actor_id) != null:
			_monster_ids[actor_id] = true


func set_character_weapon_mode(actor_id: String, mode: StringName) -> bool:
	if not _is_character(actor_id) or mode not in [&"melee", &"missile"]:
		return false
	_weapon_modes[actor_id] = String(mode)
	return true


func character_weapon_mode(actor_id: String) -> StringName:
	return StringName(_weapon_modes.get(actor_id, "melee"))


func set_guarding(actor_id: String, guarding: bool) -> bool:
	if not _has_actor(actor_id):
		return false
	_set_marker(_guarding, actor_id, guarding)
	return true


func is_guarding(actor_id: String) -> bool:
	return bool(_guarding.get(actor_id, false))


func guarding_actor_ids() -> Array[String]:
	return _sorted_ids(_guarding)


func mark_attacked(actor_id: String) -> bool:
	if not _has_actor(actor_id):
		return false
	_attacked[actor_id] = true
	return true


func was_attacked(actor_id: String) -> bool:
	return bool(_attacked.get(actor_id, false))


func attacked_actor_ids() -> Array[String]:
	return _sorted_ids(_attacked)


func clear_attacked() -> void:
	_attacked.clear()


func set_character_bleeding(actor_id: String, bleeding: bool) -> bool:
	if not _is_character(actor_id):
		return false
	_set_marker(_bleeding, actor_id, bleeding)
	return true


func is_character_bleeding(actor_id: String) -> bool:
	return bool(_bleeding.get(actor_id, false))


func bleeding_character_ids() -> Array[String]:
	return _sorted_ids(_bleeding)


func mark_turn_undead_used(actor_id: String) -> bool:
	if not _is_character(actor_id):
		return false
	_turned_undead[actor_id] = true
	return true


func has_used_turn_undead(actor_id: String) -> bool:
	return bool(_turned_undead.get(actor_id, false))


func turn_undead_actor_ids() -> Array[String]:
	return _sorted_ids(_turned_undead)


func mark_character_retreated(actor_id: String) -> bool:
	if not _is_character(actor_id):
		return false
	_retreated[actor_id] = true
	return true


func has_character_retreated(actor_id: String) -> bool:
	return bool(_retreated.get(actor_id, false))


func retreated_character_ids() -> Array[String]:
	return _sorted_ids(_retreated)


func weapon_modes_data() -> Dictionary:
	var result: Dictionary = {}
	var actor_ids: Array = _weapon_modes.keys()
	actor_ids.sort()
	for actor_id: Variant in actor_ids:
		result[String(actor_id)] = _weapon_modes[actor_id]
	return result


func _has_actor(actor_id: String) -> bool:
	return not actor_id.is_empty() and _actor_ids.has(actor_id)


func _is_character(actor_id: String) -> bool:
	return _has_actor(actor_id) and not _monster_ids.has(actor_id)


func _set_marker(target: Dictionary, actor_id: String, enabled: bool) -> void:
	if enabled:
		target[actor_id] = true
	else:
		target.erase(actor_id)


func _sorted_ids(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for actor_id: Variant in source:
		result.append(String(actor_id))
	result.sort()
	return result
