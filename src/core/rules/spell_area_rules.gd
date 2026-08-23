class_name SpellAreaRules
extends RefCounted

# Castle loads eighteen 7x7 masks from Data AD. These relative coordinates
# preserve that table's row-major orientation without retaining its native bytes.
const PATTERNS: Array = [
	[Vector2i(0, 0)],
	[Vector2i(0, 0), Vector2i(0, 1)],
	[Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
	[
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
	],
	[
		Vector2i(0, -2),
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
		Vector2i(0, 2),
	],
	[
		Vector2i(0, -3),
		Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2),
		Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(2, -1),
		Vector2i(-3, 0), Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 2),
		Vector2i(0, 3),
	],
	[
		Vector2i(-1, -3), Vector2i(0, -3), Vector2i(1, -3),
		Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2), Vector2i(2, -2),
		Vector2i(-3, -1), Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(2, -1), Vector2i(3, -1),
		Vector2i(-3, 0), Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(-3, 1), Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
		Vector2i(-2, 2), Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
		Vector2i(-1, 3), Vector2i(0, 3), Vector2i(1, 3),
	],
	[
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
	],
	[
		Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2),
		Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(2, -1),
		Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 2),
	],
	[
		Vector2i(-3, -1), Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(2, -1), Vector2i(3, -1),
		Vector2i(-3, 0), Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	],
	[
		Vector2i(3, -3), Vector2i(2, -2), Vector2i(3, -2), Vector2i(1, -1), Vector2i(2, -1),
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1),
		Vector2i(-2, 2), Vector2i(-1, 2), Vector2i(-3, 3), Vector2i(-2, 3),
	],
	[
		Vector2i(0, -3), Vector2i(1, -3), Vector2i(0, -2), Vector2i(1, -2),
		Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2),
		Vector2i(0, 3), Vector2i(1, 3),
	],
	[
		Vector2i(-3, -3), Vector2i(-3, -2), Vector2i(-2, -2), Vector2i(-2, -1), Vector2i(-1, -1),
		Vector2i(-1, 0), Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1),
		Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 3),
	],
	[
		Vector2i(-1, -3), Vector2i(0, -3), Vector2i(1, -3),
		Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2), Vector2i(2, -2),
		Vector2i(-3, -1), Vector2i(-2, -1), Vector2i(2, -1), Vector2i(3, -1),
		Vector2i(-3, 0), Vector2i(-2, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(-3, 1), Vector2i(-2, 1), Vector2i(2, 1), Vector2i(3, 1),
		Vector2i(-2, 2), Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
		Vector2i(-1, 3), Vector2i(0, 3), Vector2i(1, 3),
	],
	[Vector2i(0, 0)],
	[Vector2i(0, -1), Vector2i(0, 0)],
	[Vector2i(-1, 0), Vector2i(0, 0)],
	[Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)],
]


func pattern(shape: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if shape < 1 or shape > PATTERNS.size():
		return result
	for coordinate: Vector2i in PATTERNS[shape - 1]:
		result.append(coordinate)
	return result


func shape_for(spell: SpellDefinition, power_level: int, rotation: int = 0) -> int:
	if spell == null or rotation < 0 or rotation > 3:
		return 0
	if not spell.can_rotate and rotation != 0:
		return 0
	var base := power_level if spell.target_type == 4 else spell.size if spell.target_type == 3 else 0
	return base + rotation


func rotation_patterns(spell: SpellDefinition, power_level: int) -> Array:
	var result: Array = []
	var count := 4 if spell != null and spell.can_rotate else 1
	for rotation: int in count:
		result.append(pattern(shape_for(spell, power_level, rotation)))
	return result


func pattern_fits(center: Vector2i, shape: int) -> bool:
	var offsets := pattern(shape)
	if offsets.is_empty():
		return false
	for offset: Vector2i in offsets:
		if not BattlefieldState.contains(center + offset):
			return false
	return true
