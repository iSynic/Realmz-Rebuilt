## Selects Castle's direction-specific missile icon before its traveling frame.
class_name CombatMissileArt
extends RefCounted


static func resource_id_for(look_start: int, from: Vector2i, to: Vector2i) -> int:
	if look_start < 1:
		return 0
	if look_start > 3:
		return 12_032
	var offset := to - from
	var direction := Vector2i(signi(offset.x) if absi(offset.x) > 1 else 0, signi(offset.y) if absi(offset.y) > 1 else 0)
	# Castle finddxdy leaves direction(0, 0) undefined. FD-COMBAT-020 uses
	# the actual travel direction for nearby shots, or north at zero distance.
	if direction == Vector2i.ZERO:
		direction = Vector2i(signi(offset.x), signi(offset.y))
	var directions := [Vector2i.UP, Vector2i(1, -1), Vector2i.RIGHT, Vector2i(1, 1), Vector2i.DOWN, Vector2i(-1, 1), Vector2i.LEFT, Vector2i(-1, -1)]
	return 11_992 + look_start * 8 + maxi(0, directions.find(direction))
