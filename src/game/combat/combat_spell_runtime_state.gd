## Owns persistent field lifetimes and per-activation collision slots.

class_name CombatSpellRuntimeState
extends RefCounted

const MAX_PERSISTENT_FIELDS := 60

var _turns: CombatTurnSequenceState
var _persistent_fields: Array[PersistentCombatField] = []
var _field_collision_slots: Dictionary = {}


func bind(turns: CombatTurnSequenceState) -> void:
	_turns = turns


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
