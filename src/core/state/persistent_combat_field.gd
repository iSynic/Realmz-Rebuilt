class_name PersistentCombatField
extends RefCounted

const INVALID_INTEGER := -100_000
const MAX_QUEUE_SLOTS := 60

var slot: int
var spell_id: String
var caster_id: String
var center: Vector2i
var rotation: int
var shape: int
var queue_icon: int
var power_level: int
var cast_level: int
var remaining_duration: int
var phase_turn_index: int


func _init(source_slot: int, source_spell_id: String, source_caster_id: String, source_center: Vector2i, source_rotation: int, source_shape: int, source_queue_icon: int, source_power_level: int, source_cast_level: int, source_duration: int, source_phase_turn_index: int) -> void:
	slot = source_slot
	spell_id = source_spell_id
	caster_id = source_caster_id
	center = source_center
	rotation = source_rotation
	shape = source_shape
	queue_icon = source_queue_icon
	power_level = source_power_level
	cast_level = source_cast_level
	remaining_duration = source_duration
	phase_turn_index = source_phase_turn_index


func to_data() -> Dictionary:
	return {"slot": slot, "spellId": spell_id, "casterId": caster_id, "center": [center.x, center.y], "rotation": rotation, "shape": shape, "queueIcon": queue_icon, "power": power_level, "castLevel": cast_level, "remainingDuration": remaining_duration, "phaseTurnIndex": phase_turn_index}


static func from_data(data: Variant) -> RefCounted:
	if not data is Dictionary or data.size() != 11:
		return null
	for field: String in ["slot", "spellId", "casterId", "center", "rotation", "shape", "queueIcon", "power", "castLevel", "remainingDuration", "phaseTurnIndex"]:
		if not data.has(field):
			return null
	var loaded_slot := _integer(data["slot"])
	var loaded_rotation := _integer(data["rotation"])
	var loaded_shape := _integer(data["shape"])
	var loaded_icon := _signed_integer(data["queueIcon"])
	var loaded_power := _integer(data["power"])
	var loaded_cast_level := _integer(data["castLevel"])
	var loaded_duration := _integer(data["remainingDuration"])
	var loaded_phase := _integer(data["phaseTurnIndex"])
	var center_data: Variant = data["center"]
	if not data["spellId"] is String or data["spellId"].is_empty() or not data["casterId"] is String or data["casterId"].is_empty() or not center_data is Array or center_data.size() != 2:
		return null
	var x := _signed_integer(center_data[0])
	var y := _signed_integer(center_data[1])
	var loaded_center := Vector2i(x, y)
	if loaded_slot < 0 or loaded_slot >= MAX_QUEUE_SLOTS or loaded_rotation < 0 or loaded_rotation > 3 or loaded_shape < 1 or loaded_shape > 127 or loaded_icon < -128 or loaded_icon > 127 or loaded_icon == 0 or loaded_power < 1 or loaded_power > 7 or loaded_cast_level < 0 or loaded_cast_level > 7 or loaded_duration < 1 or loaded_duration > 32_767 or loaded_phase < 0 or x == INVALID_INTEGER or y == INVALID_INTEGER or not BattlefieldState.contains(loaded_center):
		return null
	return load("res://src/core/state/persistent_combat_field.gd").new(loaded_slot, data["spellId"], data["casterId"], loaded_center, loaded_rotation, loaded_shape, loaded_icon, loaded_power, loaded_cast_level, loaded_duration, loaded_phase)


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return INVALID_INTEGER
