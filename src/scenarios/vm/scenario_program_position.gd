## Maps native slots to the immutable compiled timeline without losing Safe calls.
class_name ScenarioProgramPosition
extends RefCounted


static func cursor_for_slot(program: ScenarioProgramDefinition, slot: int) -> int:
	# FD-SCENARIO-027: a return beyond slot seven never fetches an unchecked
	# native opcode. Ordered trailing Safe calls remain compiled instructions.
	if slot > 8:
		return program.instruction_count()
	var cursor := 0
	for index: int in program.instruction_count():
		var instruction: Variant = program.instruction_at(index)
		if instruction is ClassicActionDefinition:
			var action: ClassicActionDefinition = instruction
			if action.slot >= slot:
				break
			cursor = index + 1
	return cursor


static func slot_for_cursor(program: ScenarioProgramDefinition, cursor: int) -> int:
	var slot := 0
	for index: int in mini(cursor, program.instruction_count()):
		var instruction: Variant = program.instruction_at(index)
		if instruction is ClassicActionDefinition:
			var action: ClassicActionDefinition = instruction
			slot = action.slot + 1
	return slot


static func is_valid(program: ScenarioProgramDefinition, cursor: int, slot: int) -> bool:
	return program != null and cursor >= 0 and cursor <= program.instruction_count() and slot >= 0 and slot <= 8 and (slot == slot_for_cursor(program, cursor) or cursor == cursor_for_slot(program, slot))
