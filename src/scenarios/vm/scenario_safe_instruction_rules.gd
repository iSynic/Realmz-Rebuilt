## Applies Safe instruction transitions without owning VM scheduling.
class_name ScenarioSafeInstructionRules
extends RefCounted


static func begin_for_each(record: ScenarioSafeExecutionRecord, instruction: SafeInstructionDefinition, values: Array) -> ScenarioVmResult:
	if values.size() > 256:
		return ScenarioVmResult.failed(&"safe_array_limit", "For-each input exceeds 256 entries.")
	if values.is_empty():
		record.cursor = instruction.target
		return ScenarioVmResult.completed()
	var iterator := ScenarioSafeIterator.new()
	iterator.begin_target = record.cursor
	iterator.index = 0
	iterator.values = values.duplicate(true)
	iterator.item_name = instruction.item_name
	iterator.had_previous = record.scope.has_local(instruction.item_name)
	iterator.previous = record.scope.local(instruction.item_name)
	record.iterators.append(iterator)
	record.scope.set_local(instruction.item_name, values[0])
	record.cursor += 1
	return ScenarioVmResult.completed()


static func next_for_each(record: ScenarioSafeExecutionRecord, instruction: SafeInstructionDefinition) -> ScenarioVmResult:
	if record.iterators.is_empty():
		return ScenarioVmResult.failed(&"invalid_safe_program", "For-each continuation has no active iterator.")
	var iterator: ScenarioSafeIterator = record.iterators.back()
	if iterator.begin_target != instruction.target:
		return ScenarioVmResult.failed(&"invalid_safe_program", "For-each continuation target does not match its iterator.")
	iterator.index += 1
	if iterator.index < iterator.values.size():
		record.scope.set_local(iterator.item_name, iterator.values[iterator.index])
		record.cursor = instruction.target + 1
		return ScenarioVmResult.completed()
	record.iterators.pop_back()
	if iterator.had_previous:
		record.scope.set_local(iterator.item_name, iterator.previous)
	else:
		record.scope.erase_local(iterator.item_name)
	record.cursor += 1
	return ScenarioVmResult.completed()
