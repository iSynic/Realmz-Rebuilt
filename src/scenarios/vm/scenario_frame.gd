## Defines the scenario frame contract for scenario execution.

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
var native_return_destination: TriggerDestinationDefinition
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
	if _iterators.is_empty():
		return {}
	var iterator: Dictionary = _iterators.back()
	return iterator.duplicate(true)


func update_current_iterator(iterator: Dictionary) -> void:
	assert(not _iterators.is_empty(), "An active iterator is required")
	_iterators[_iterators.size() - 1] = iterator.duplicate(true)


func pop_iterator() -> Dictionary:
	return {} if _iterators.is_empty() else _iterators.pop_back()


func to_data(typed_values: bool = true) -> Dictionary:
	var data := {
		"kind": String(kind),
		"definitionId": definition_id,
		"cursor": cursor,
		"returnTarget": return_target,
		"countsAsClassicCall": counts_as_classic_call,
		"parameters": ScenarioValueCodec.encode(_parameters) if typed_values else _parameters.duplicate(true),
		"locals": ScenarioValueCodec.encode(_locals) if typed_values else _locals.duplicate(true),
		"context": ScenarioExecutionContextCodec.encode(_context),
		"iterators": ScenarioValueCodec.encode(_iterators) if typed_values else _iterators.duplicate(true),
		"nativeReturnDestination": null if native_return_destination == null else {"mapId": native_return_destination.map_id, "x": native_return_destination.coordinate.x, "y": native_return_destination.coordinate.y},
	}
	return data


## VM schema 4 frames carry type-tagged values (ADR 0026); `typed_values`
## false reads schema 2/3 raw JSON values.
static func from_data(value: Variant, typed_values: bool = true) -> ScenarioFrame:
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	if data.size() != 9 + (1 if data.has("nativeReturnDestination") else 0):
		return null
	for field: String in ["kind", "definitionId", "cursor", "returnTarget", "countsAsClassicCall", "parameters", "locals", "context", "iterators"]:
		if not data.has(field):
			return null
	var saved_cursor := _integer(data["cursor"])
	if data["kind"] not in ["program", "action", "encounter"] or not data["definitionId"] is String:
		return null
	var definition_id: String = data["definitionId"]
	if definition_id.is_empty() or saved_cursor < 0 or not data["returnTarget"] is String or not data["countsAsClassicCall"] is bool:
		return null
	var parameters: Variant = _decoded(data["parameters"], typed_values)
	var locals: Variant = _decoded(data["locals"], typed_values)
	var iterators: Variant = _decoded(data["iterators"], typed_values)
	if not parameters is Dictionary or not locals is Dictionary or not data["context"] is Dictionary or not iterators is Array:
		return null
	var context := ScenarioExecutionContextCodec.decode(data["context"])
	if context == null:
		return null
	var frame_kind: String = data["kind"]
	var frame := ScenarioFrame.new(StringName(frame_kind), definition_id, saved_cursor)
	frame.return_target = data["returnTarget"]
	frame.counts_as_classic_call = data["countsAsClassicCall"]
	frame._parameters = parameters
	frame._locals = locals
	frame._context = context
	if data.get("nativeReturnDestination") != null:
		frame.native_return_destination = _return_destination(data["nativeReturnDestination"])
		if frame.native_return_destination == null: return null
	for iterator_value: Variant in iterators:
		if not iterator_value is Dictionary:
			return null
		var iterator: Dictionary = iterator_value
		if not typed_values:
			# Legacy JSON returned the VM-owned loop counters as floats.
			for field: String in ["beginTarget", "index"]:
				if iterator.has(field): iterator[field] = _integer(iterator[field])
		frame._iterators.append(iterator.duplicate(true))
	return frame


## Restores declared int parameters that schema 2/3 JSON decoded as whole
## floats. Locals have no declared types and keep their decoded values.
func coerce_declared_parameters(action: ScenarioActionDefinition) -> void:
	for declared: ScenarioActionParameter in action.parameters():
		var value: Variant = _parameters.get(declared.name)
		if declared.value_type != &"int" or not value is float:
			continue
		var number: float = value
		if is_finite(number) and number == floorf(number):
			_parameters[declared.name] = int(number)


static func _decoded(value: Variant, typed_values: bool) -> Variant:
	if not typed_values:
		if value is Dictionary:
			var record: Dictionary = value
			return record.duplicate(true)
		if value is Array:
			var items: Array = value
			return items.duplicate(true)
		return value
	var decoded := ScenarioValueCodec.decode(value)
	return decoded["value"] if decoded["ok"] else null


static func _return_destination(value: Variant) -> TriggerDestinationDefinition:
	if not value is Dictionary: return null
	var data: Dictionary = value
	if data.size() != 3 or not data.get("mapId") is String: return null
	var map_id: String = data["mapId"]
	if map_id.is_empty(): return null
	for field: String in ["x", "y"]:
		var number: Variant = data.get(field)
		if not (number is int or number is float and _finite_whole(number)) or number < -2_147_483_648 or number > 2_147_483_647: return null
	var x: int = data["x"]
	var y: int = data["y"]
	return TriggerDestinationDefinition.new(map_id, Vector2i(x, y))


static func _finite_whole(value: Variant) -> bool:
	if not value is float:
		return false
	var number: float = value
	return is_finite(number) and number == floorf(number)


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		var number: float = value
		if is_equal_approx(number, roundf(number)):
			return int(number)
	return -1
