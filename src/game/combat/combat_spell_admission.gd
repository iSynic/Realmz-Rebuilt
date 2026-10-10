## Carries an admitted spell power without player-facing targeting records.
class_name CombatSpellAdmission
extends RefCounted

var spell: SpellDefinition
var spell_id: String
var power: int
var cost: int
var area_offsets: Array[Vector2i] = []
var area_rotation_offsets: Array = []


func _init(definition: SpellDefinition, power_level: int, offsets: Array[Vector2i] = [], rotations: Array = []) -> void:
	spell = definition
	spell_id = definition.id
	power = power_level
	cost = absi(definition.cost * power_level)
	area_offsets = offsets
	area_rotation_offsets = rotations


func rotations(areas: SpellAreaRules) -> Array:
	if area_rotation_offsets.is_empty():
		area_rotation_offsets = [area_offsets] if not area_offsets.is_empty() else areas.rotation_patterns(spell, power)
	return area_rotation_offsets
