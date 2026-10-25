## Retains a Safe Action's instruction position and its dedicated lexical state.
class_name ScenarioSafeExecutionRecord
extends RefCounted

var scope := ScenarioExpressionScope.new()
var cursor: int = 0
var return_target: String = ""
var invocation_owner_id: int = 0
var iterators: Array[ScenarioSafeIterator] = []


func to_data() -> Dictionary:
	var saved_iterators: Array[Dictionary] = []
	for iterator: ScenarioSafeIterator in iterators:
		saved_iterators.append(iterator.to_data())
	return {"scope": scope.to_data(), "cursor": cursor, "returnTarget": return_target, "invocationOwnerId": invocation_owner_id, "iterators": saved_iterators}


static func from_data(value: Variant) -> ScenarioSafeExecutionRecord:
	if not ScenarioExecutionWire.fields(value, ["scope", "cursor", "returnTarget", "invocationOwnerId", "iterators"]):
		return null
	var data: Dictionary = value
	if not data["returnTarget"] is String or not data["iterators"] is Array:
		return null
	var saved_iterators: Array = data["iterators"]
	if saved_iterators.size() > 32:
		return null
	var result := ScenarioSafeExecutionRecord.new()
	result.scope = ScenarioExpressionScope.from_data(data["scope"])
	result.cursor = ScenarioExecutionWire.integer(data["cursor"], 0, 4096)
	result.return_target = data["returnTarget"]
	result.invocation_owner_id = ScenarioExecutionWire.integer(data["invocationOwnerId"])
	if result.scope == null or result.cursor < 0 or result.invocation_owner_id < 0:
		return null
	for entry: Variant in saved_iterators:
		var iterator := ScenarioSafeIterator.from_data(entry)
		if iterator == null:
			return null
		result.iterators.append(iterator)
	return result
