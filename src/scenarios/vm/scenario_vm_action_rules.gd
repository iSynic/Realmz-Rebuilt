## Coordinates Safe Action iterators and caller checks without owning VM scheduling.
class_name ScenarioVmActionRules
extends RefCounted


static func begin_for_each(frame: ScenarioFrame, instruction: SafeInstructionDefinition, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	var evaluated := SafeExpressionEvaluator.evaluate(instruction.collection, frame, runtime_api)
	if not evaluated["ok"] or not evaluated["value"] is Array:
		return ScenarioVmResult.failed(&"safe_expression_failed", evaluated.get("error", "For-each input is not an array."))
	var values: Array = evaluated["value"]
	if values.size() > 256:
		return ScenarioVmResult.failed(&"safe_array_limit", "For-each input exceeds 256 entries.")
	if values.is_empty():
		frame.cursor = instruction.target
		return ScenarioVmResult.completed()
	frame.push_iterator({"beginTarget": frame.cursor, "index": 0, "values": values.duplicate(true), "itemName": instruction.item_name, "hadPrevious": frame.has_local(instruction.item_name), "previous": frame.local(instruction.item_name)})
	frame.set_local(instruction.item_name, values[0])
	frame.cursor += 1
	return ScenarioVmResult.completed()


static func next_for_each(frame: ScenarioFrame, instruction: SafeInstructionDefinition) -> ScenarioVmResult:
	if not frame.has_iterator():
		return ScenarioVmResult.failed(&"invalid_safe_program", "For-each continuation has no active iterator.")
	var iterator: Dictionary = frame.current_iterator()
	if iterator.get("beginTarget") != instruction.target:
		return ScenarioVmResult.failed(&"invalid_safe_program", "For-each continuation target does not match its iterator.")
	iterator["index"] += 1
	if iterator["index"] < iterator["values"].size():
		frame.set_local(iterator["itemName"], iterator["values"][iterator["index"]])
		frame.update_current_iterator(iterator)
		frame.cursor = instruction.target + 1
		return ScenarioVmResult.completed()
	frame.pop_iterator()
	if iterator["hadPrevious"]:
		frame.set_local(iterator["itemName"], iterator["previous"])
	else:
		frame.erase_local(iterator["itemName"])
	frame.cursor += 1
	return ScenarioVmResult.completed()


static func action_call_depth(frames: Array[ScenarioFrame]) -> int:
	var count := 0
	for frame: ScenarioFrame in frames:
		if frame.kind == ScenarioFrame.ACTION:
			count += 1
	return count


static func calling_context(frame: ScenarioFrame, program: ScenarioProgramDefinition) -> StringName:
	var explicit: Variant = frame.context_value("callingContext")
	if explicit is String and not explicit.is_empty():
		return StringName(explicit)
	match program.owner_kind:
		&"simple-encounter-result", &"complex-encounter-result":
			return &"encounter"
		&"trigger", &"extra-action-point":
			return &"action"
	return &""
