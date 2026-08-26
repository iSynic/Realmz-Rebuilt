class_name ScenarioFrame
extends RefCounted

const PROGRAM: StringName = &"program"
const ACTION: StringName = &"action"
const ENCOUNTER: StringName = &"encounter"

var kind: StringName
var definition_id: String
var cursor: int = 0
var return_target: String = ""
var counts_as_classic_call: bool = false
var _parameters: Dictionary = {}
var _locals: Dictionary = {}
var _context: ScenarioExecutionContext = ScenarioExecutionContext.empty()
var _iterators: Array[Dictionary] = []


func _init(frame_kind: StringName, id: String, start_cursor: int = 0) -> void:
	kind = frame_kind
	definition_id = id
	cursor = start_cursor


func set_parameters(values: Dictionary) -> void:
	_parameters = values.duplicate(true)


func parameter(name: String) -> Variant:
	return _parameters.get(name)


func has_local(name: String) -> bool:
	return _locals.has(name)


func local(name: String) -> Variant:
	return _locals.get(name)


func set_local(name: String, value: Variant) -> void:
	_locals[name] = value


func erase_local(name: String) -> void:
	_locals.erase(name)


func set_context(values: ScenarioExecutionContext) -> void:
	_context = ScenarioExecutionContext.empty() if values == null else values.copy()


func context_value(name: String) -> Variant:
	return _context.value(name)


func context() -> ScenarioExecutionContext:
	return _context.copy()


func push_iterator(iterator: Dictionary) -> void:
	_iterators.append(iterator.duplicate(true))


func has_iterator() -> bool:
	return not _iterators.is_empty()


func current_iterator() -> Dictionary:
	return {} if _iterators.is_empty() else _iterators.back().duplicate(true)


func update_current_iterator(iterator: Dictionary) -> void:
	assert(not _iterators.is_empty(), "An active iterator is required")
	_iterators[_iterators.size() - 1] = iterator.duplicate(true)


func pop_iterator() -> Dictionary:
	return {} if _iterators.is_empty() else _iterators.pop_back()


func to_data() -> Dictionary:
	return {
		"kind": String(kind),
		"definitionId": definition_id,
		"cursor": cursor,
		"returnTarget": return_target,
		"countsAsClassicCall": counts_as_classic_call,
		"parameters": _parameters.duplicate(true),
		"locals": _locals.duplicate(true),
		"context": _context.to_data(),
		"iterators": _iterators.duplicate(true),
	}


static func from_data(data: Variant) -> ScenarioFrame:
	if not data is Dictionary:
		return null
	for field: String in ["kind", "definitionId", "cursor", "returnTarget", "countsAsClassicCall", "parameters", "locals", "context", "iterators"]:
		if not data.has(field):
			return null
	var saved_cursor := _integer(data["cursor"])
	if data["kind"] not in ["program", "action", "encounter"] or not data["definitionId"] is String or data["definitionId"].is_empty() or saved_cursor < 0 or not data["returnTarget"] is String or not data["countsAsClassicCall"] is bool:
		return null
	if not data["parameters"] is Dictionary or not data["locals"] is Dictionary or not data["context"] is Dictionary or not data["iterators"] is Array:
		return null
	var context := ScenarioExecutionContext.from_data(data["context"])
	if context == null:
		return null
	var frame := ScenarioFrame.new(StringName(data["kind"]), data["definitionId"], saved_cursor)
	frame.return_target = data["returnTarget"]
	frame.counts_as_classic_call = data["countsAsClassicCall"]
	frame._parameters = data["parameters"].duplicate(true)
	frame._locals = data["locals"].duplicate(true)
	frame._context = context
	for iterator: Variant in data["iterators"]:
		if not iterator is Dictionary:
			return null
		frame._iterators.append(iterator.duplicate(true))
	return frame


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1
