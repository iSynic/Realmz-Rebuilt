## Coordinates Safe Action iterators and caller checks without owning VM scheduling.
class_name ScenarioVmActionRules
extends RefCounted


static func begin_for_each(frame: ScenarioFrame, instruction: SafeInstructionDefinition, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	var evaluated := SafeExpressionEvaluator.evaluate(instruction.collection, frame, runtime_api)
	if not evaluated["ok"] or not evaluated["value"] is Array:
		return expression_failure(evaluated, "For-each input is not an array.")
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
	var values: Array = iterator["values"]
	var item_name: String = iterator["itemName"]
	iterator["index"] += 1
	if iterator["index"] < values.size():
		frame.set_local(item_name, values[iterator["index"]])
		frame.update_current_iterator(iterator)
		frame.cursor = instruction.target + 1
		return ScenarioVmResult.completed()
	frame.pop_iterator()
	if iterator["hadPrevious"]:
		frame.set_local(item_name, iterator["previous"])
	else:
		frame.erase_local(item_name)
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
	if explicit is String:
		var explicit_text: String = explicit
		if not explicit_text.is_empty():
			return StringName(explicit_text)
	match program.owner_kind:
		&"simple-encounter-result", &"complex-encounter-result":
			return &"encounter"
		&"trigger", &"extra-action-point":
			return &"action"
	return &""


## Fails with an evaluator result's error, or with the fallback when that result carries none.
static func expression_failure(evaluated: Dictionary, fallback: String = "") -> ScenarioVmResult:
	var message: String = evaluated["error"] if fallback.is_empty() else evaluated.get("error", fallback)
	return ScenarioVmResult.failed(&"safe_expression_failed", message)


## Returns the evaluated argument record of a successful argument evaluation.
static func argument_values(evaluated: Dictionary) -> Dictionary:
	return evaluated["value"]
