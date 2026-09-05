## Owns battle-scoped spell continuations and persistent field state.

class_name CombatSpellRuntimeState
extends RefCounted

const MAX_DEATH_MACROS := 100
const MAX_PERSISTENT_FIELDS := 60

var _roster: CombatRosterState
var _turns: CombatTurnSequenceState
var _death_macro_queue: Array[String] = []
var _macro_actor_id: String = ""
var _macro_advances_turn: bool = false
var _persistent_fields: Array[PersistentCombatField] = []
var _field_collision_slots: Dictionary = {}


func bind(roster: CombatRosterState, turns: CombatTurnSequenceState) -> void:
	_roster = roster
	_turns = turns


func queue_death_macro(combatant_id: String) -> bool:
	if combatant_id.is_empty() or _roster == null or _roster.monster_by_id(combatant_id) == null or _death_macro_queue.size() >= MAX_DEATH_MACROS:
		return false
	_death_macro_queue.append(combatant_id)
	return true


func begin_death_macro_sequence(actor_id: String, advances_turn: bool) -> bool:
	if _turns == null or _death_macro_queue.is_empty() or actor_id.is_empty() or actor_id != _turns.active_actor_id() or not _macro_actor_id.is_empty():
		return false
	_macro_actor_id = actor_id
	_macro_advances_turn = advances_turn
	return true


func pending_death_macro_id() -> String:
	return "" if _death_macro_queue.is_empty() else _death_macro_queue[0]


func complete_death_macro(combatant_id: String) -> bool:
	if combatant_id.is_empty() or pending_death_macro_id() != combatant_id:
		return false
	_death_macro_queue.pop_front()
	return true


func death_macro_queue() -> Array[String]:
	return _death_macro_queue.duplicate()


func macro_actor_id() -> String:
	return _macro_actor_id


func macro_advances_turn() -> bool:
	return _macro_advances_turn


func clear_death_macro_sequence() -> void:
	_death_macro_queue.clear()
	_macro_actor_id = ""
	_macro_advances_turn = false


func restore_death_macro_sequence(queue: Array[String], actor_id: String, advances_turn: bool) -> void:
	_death_macro_queue = queue.duplicate()
	_macro_actor_id = actor_id
	_macro_advances_turn = advances_turn


func persistent_fields() -> Array[PersistentCombatField]:
	var result := _persistent_fields.duplicate()
	result.sort_custom(func(left: PersistentCombatField, right: PersistentCombatField) -> bool: return left.slot < right.slot)
	return result


func can_queue_persistent_field() -> bool:
	return _persistent_fields.size() < MAX_PERSISTENT_FIELDS


func queue_persistent_field(spell_id: String, caster_id: String, center: Vector2i, rotation: int, shape: int, queue_icon: int, power_level: int, cast_level: int, duration: int) -> PersistentCombatField:
	if not _valid_new_field(spell_id, caster_id, center, rotation, shape, queue_icon, power_level, cast_level, duration):
		return null
	var used_slots: Dictionary = {}
	for field: PersistentCombatField in _persistent_fields:
		used_slots[field.slot] = true
	var slot := 0
	while used_slots.has(slot):
		slot += 1
	var result := PersistentCombatField.new(slot, spell_id, caster_id, center, rotation, shape, queue_icon, power_level, cast_level, duration, _turns.turn_index)
	_persistent_fields.append(result)
	return result


func decay_persistent_fields_for_phase(phase_turn_index: int) -> Array[PersistentCombatField]:
	var expired: Array[PersistentCombatField] = []
	for index: int in range(_persistent_fields.size() - 1, -1, -1):
		var field: PersistentCombatField = _persistent_fields[index]
		if field.phase_turn_index != phase_turn_index:
			continue
		field.remaining_duration -= 1
		if field.remaining_duration <= 0:
			expired.push_front(_persistent_fields.pop_at(index))
	return expired


func has_field_collision(slot: int) -> bool:
	return bool(_field_collision_slots.get(slot, false))


func mark_field_collision(slot: int) -> bool:
	if slot < 0 or slot >= MAX_PERSISTENT_FIELDS or has_field_collision(slot) or not persistent_fields().any(func(field: PersistentCombatField) -> bool: return field.slot == slot):
		return false
	_field_collision_slots[slot] = true
	return true


func field_collision_slots() -> Array[int]:
	var result: Array[int] = []
	for slot: Variant in _field_collision_slots:
		result.append(int(slot))
	result.sort()
	return result


func clear_field_collisions() -> void:
	_field_collision_slots.clear()


func restore_persistent_fields(fields: Array[PersistentCombatField], collision_slots: Array[int]) -> void:
	_persistent_fields = fields.duplicate()
	_field_collision_slots.clear()
	for slot: int in collision_slots:
		_field_collision_slots[slot] = true


func _valid_new_field(spell_id: String, caster_id: String, center: Vector2i, rotation: int, shape: int, queue_icon: int, power_level: int, cast_level: int, duration: int) -> bool:
	return _turns != null and can_queue_persistent_field() and not spell_id.is_empty() and not caster_id.is_empty() and BattlefieldGrid.contains(center) and rotation >= 0 and rotation <= 3 and shape >= 1 and shape <= 127 and queue_icon != 0 and queue_icon >= -128 and queue_icon <= 127 and power_level >= 1 and power_level <= 7 and cast_level >= 0 and cast_level <= 7 and duration >= 1 and duration <= 32_767 and not _turns.turn_order().is_empty() and _turns.turn_index >= 0 and _turns.turn_index < _turns.turn_order().size()
