## A closed execution record with an explicit stable caller, never an inferred frame owner.
class_name ScenarioExecutionRecord
extends RefCounted

enum Kind { CLASSIC, SAFE, OPERATION }

var id: int = 0
var parent_id: int = 0
var kind: Kind = Kind.CLASSIC
var classic: ScenarioClassicInvocationRecord
var safe: ScenarioSafeExecutionRecord
var operation: ScenarioOperationExecutionRecord


func to_data() -> Dictionary:
	var payload: Dictionary
	match kind:
		Kind.CLASSIC: payload = classic.to_data()
		Kind.SAFE: payload = safe.to_data()
		Kind.OPERATION: payload = operation.to_data()
	return {"id": id, "parentId": parent_id, "kind": kind, "data": payload}


static func from_data(value: Variant, depth: int = 0) -> ScenarioExecutionRecord:
	if not ScenarioExecutionWire.fields(value, ["id", "parentId", "kind", "data"]):
		return null
	var data: Dictionary = value
	var record_id := ScenarioExecutionWire.integer(data["id"], 1)
	var parent := ScenarioExecutionWire.integer(data["parentId"])
	var restored_kind := ScenarioExecutionWire.integer(data["kind"], Kind.CLASSIC, Kind.OPERATION)
	if record_id < 1 or parent < 0 or parent >= record_id or restored_kind < 0:
		return null
	var result := ScenarioExecutionRecord.new()
	result.id = record_id
	result.parent_id = parent
	result.kind = restored_kind as Kind
	match result.kind:
		Kind.CLASSIC:
			result.classic = ScenarioClassicInvocationRecord.from_data(data["data"])
			if result.classic == null: return null
		Kind.SAFE:
			result.safe = ScenarioSafeExecutionRecord.from_data(data["data"])
			if result.safe == null: return null
		Kind.OPERATION:
			result.operation = ScenarioOperationExecutionRecord.from_data(data["data"], depth)
			if result.operation == null: return null
	return result
