## Resolves battle magnitudes and surprise signs before catalog lookup.
class_name ClassicBattleSelection
extends RefCounted


static func select(action: ClassicActionDefinition, schema_version: int, rng: RealmzRng) -> int:
	if action.extra_code.is_empty():
		return action.operand_id
	var low := action.extra_code[0]
	var high := action.extra_code[1] if action.extra_code.size() > 1 else 0
	var tag := StringName("classic.opcode-%d.battle" % action.opcode)
	if schema_version < 7:
		return rng.draw_between(absi(low), absi(high), tag) if high != 0 else absi(low)
	if high == 0:
		return low
	# newland.c case 2 ranges over magnitudes and restores EC0's sign.
	# Cases 48, 56 and 107 pass signed endpoints directly to randrange.
	var selected := rng.draw_between_classic(absi(low) if action.opcode == 2 else low, absi(high) if action.opcode == 2 else high, tag)
	return -selected if action.opcode == 2 and low < 0 else selected
