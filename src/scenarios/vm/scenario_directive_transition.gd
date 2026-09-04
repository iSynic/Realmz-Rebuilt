## Describes one Classic control-flow mutation for the owning Scenario VM.

class_name ScenarioDirectiveTransition
extends RefCounted

enum Action {
	CONTINUE,
	RETURN_FRAME,
	FINISH_TIMELINE,
	HALT,
}

var action: Action
var trace_entries: Array[Dictionary] = []
var error_code: StringName
var error_message: String


static func completed(next_action: Action = Action.CONTINUE, traces: Array[Dictionary] = []) -> ScenarioDirectiveTransition:
	var transition := ScenarioDirectiveTransition.new()
	transition.action = next_action
	transition.trace_entries.assign(traces)
	return transition


static func failed(code: StringName, message: String) -> ScenarioDirectiveTransition:
	var transition := completed()
	transition.error_code = code
	transition.error_message = message
	return transition


func is_failed() -> bool:
	return not error_code.is_empty()
