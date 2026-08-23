class_name CombatSpellOptionView
extends RefCounted

var spell_id: String
var spell_name: String
var power: int
var cost: int
var target_id: String
var target_name: String
var target_current_health: int
var target_maximum_health: int
var target_mode: StringName
var area_shape: int
var default_target_coordinate: Vector2i
var area_offsets: Array[Vector2i]
var area_rotation_offsets: Array
var legal_target_coordinates: Array[Vector2i]
var maximum_targets: int
var target_candidates: Array[CombatSpellTargetView]


func _init(spell: SpellDefinition, power_level: int, target: CombatSpellTargetView = null, automatic_target_label: String = "", targeting_mode: StringName = &"combatant", shape: int = 0, default_coordinate: Vector2i = Vector2i(-100_000, -100_000), offsets: Array[Vector2i] = [], maximum_target_count: int = 1, candidates: Array[CombatSpellTargetView] = [], legal_coordinates: Array[Vector2i] = [], rotation_offsets: Array = []) -> void:
	spell_id = spell.id
	spell_name = spell.name
	power = power_level
	cost = absi(spell.cost * power_level)
	target_id = target.id if target != null else ""
	target_name = target.name if target != null else automatic_target_label
	target_current_health = target.current_health if target != null else -1
	target_maximum_health = target.maximum_health if target != null else -1
	target_mode = targeting_mode
	area_shape = shape
	default_target_coordinate = default_coordinate
	area_offsets = offsets.duplicate()
	area_rotation_offsets = _duplicate_rotation_offsets(rotation_offsets)
	if area_rotation_offsets.is_empty() and not area_offsets.is_empty():
		area_rotation_offsets.append(area_offsets.duplicate())
	legal_target_coordinates = legal_coordinates.duplicate()
	maximum_targets = maximum_target_count
	target_candidates = candidates.duplicate()


func _duplicate_rotation_offsets(source: Array) -> Array:
	var result: Array = []
	for offsets: Variant in source:
		if offsets is Array:
			result.append((offsets as Array).duplicate())
	return result
