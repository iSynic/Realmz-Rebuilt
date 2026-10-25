## The detached schema-5 state of the single execution runner.
class_name ScenarioExecutionState
extends RefCounted

const SCHEMA_VERSION: int = 5
const MAX_RECORDS: int = 256

var records: Array[ScenarioExecutionRecord] = []
var classic := ScenarioClassicExecutionState.new()
var pending_request: InteractionRequest
var pending_owner_id: int = 0
var request_counter: int = 0
var record_counter: int = 0
var trace: Array[Dictionary] = []
var halted: bool = true
var last_outcome: Variant
var completion := ScenarioNativeCompletion.new()


func append_record(kind: ScenarioExecutionRecord.Kind) -> ScenarioExecutionRecord:
	var record := ScenarioExecutionRecord.new()
	record_counter += 1
	record.id = record_counter
	record.parent_id = 0 if records.is_empty() else records.back().id
	record.kind = kind
	records.append(record)
	return record


func next_request_id() -> String:
	request_counter += 1
	return "scenario:%d" % request_counter


func append_trace(entry: Dictionary) -> void:
	if trace.size() < 4096: trace.append(entry.duplicate(true))


func to_data() -> Dictionary:
	var saved_records: Array[Dictionary] = []
	for record: ScenarioExecutionRecord in records:
		saved_records.append(record.to_data())
	return {"schemaVersion": SCHEMA_VERSION, "records": saved_records, "classic": classic.to_data(), "pendingRequest": null if pending_request == null else pending_request.to_data(), "pendingOwnerId": pending_owner_id, "requestCounter": request_counter, "recordCounter": record_counter, "trace": trace.duplicate(true), "halted": halted, "lastOutcome": ScenarioValueCodec.encode(last_outcome, true), "completion": completion.to_data()}


static func from_data(value: Variant, depth: int = 0) -> ScenarioExecutionState:
	if depth > 32 or not ScenarioExecutionWire.fields(value, ["schemaVersion", "records", "classic", "pendingRequest", "pendingOwnerId", "requestCounter", "recordCounter", "trace", "halted", "lastOutcome", "completion"]):
		return null
	var data: Dictionary = value
	if ScenarioExecutionWire.integer(data["schemaVersion"]) != SCHEMA_VERSION or not data["records"] is Array or not data["trace"] is Array or not data["halted"] is bool:
		return null
	var result := ScenarioExecutionState.new()
	result.classic = ScenarioClassicExecutionState.from_data(data["classic"])
	result.pending_owner_id = ScenarioExecutionWire.integer(data["pendingOwnerId"])
	result.request_counter = ScenarioExecutionWire.integer(data["requestCounter"])
	result.record_counter = ScenarioExecutionWire.integer(data["recordCounter"])
	result.halted = data["halted"]
	var outcome := ScenarioValueCodec.decode(data["lastOutcome"], 0, true)
	if result.classic == null or result.pending_owner_id < 0 or result.request_counter < 0 or result.record_counter < 0 or not outcome["ok"]:
		return null
	result.last_outcome = outcome["value"]
	var saved_records: Array = data["records"]
	var saved_trace: Array = data["trace"]
	if not result.read_records(saved_records, depth) or not result.read_trace(saved_trace) or not result.read_completion(data["completion"]):
		return null
	if data["pendingRequest"] != null:
		result.pending_request = InteractionRequest.from_data(data["pendingRequest"])
		if result.pending_request == null:
			return null
	return result if result.pending_owner_is_valid() else null


func read_records(values: Array, depth: int) -> bool:
	if values.size() > MAX_RECORDS or halted != values.is_empty():
		return false
	var parent_id := 0
	var parent: ScenarioExecutionRecord
	for entry: Variant in values:
		var record := ScenarioExecutionRecord.from_data(entry, depth)
		if record == null or record.id <= parent_id or record.id > record_counter or record.parent_id != parent_id:
			return false
		if not _record_owner_matches(record, parent):
			return false
		if record.kind == ScenarioExecutionRecord.Kind.CLASSIC and classic.code == null and record.classic.phase not in [ScenarioClassicInvocationRecord.Phase.ENCOUNTER, ScenarioClassicInvocationRecord.Phase.COMPLETE]:
			return false
		records.append(record)
		parent = record
		parent_id = record.id
	return true


static func _record_owner_matches(record: ScenarioExecutionRecord, parent: ScenarioExecutionRecord) -> bool:
	match record.kind:
		ScenarioExecutionRecord.Kind.CLASSIC:
			if parent == null: return true
			if parent.kind != ScenarioExecutionRecord.Kind.OPERATION or parent.operation.phase != ScenarioOperationExecutionRecord.Phase.CHILD: return false
			var call := parent.operation.child_call
			if call.kind == ScenarioProgramCall.Kind.MACRO:
				var source := record.classic.queued_source
				var declared := call.macro.queued_source
				if (source == null) != (declared == null) or source != null and source.to_data() != declared.to_data(): return false
			var mode := ScenarioClassicInvocationRecord.Mode.MACRO if call.kind == ScenarioProgramCall.Kind.MACRO else ScenarioClassicInvocationRecord.Mode.MODE_ONE
			return record.classic.entry_program_id == call.program_id() and record.classic.mode == mode and ScenarioExecutionContextCodec.encode(record.classic.context) == ScenarioExecutionContextCodec.encode(call.context())
		ScenarioExecutionRecord.Kind.SAFE:
			if parent == null: return record.safe.invocation_owner_id == 0
			if parent.kind == ScenarioExecutionRecord.Kind.CLASSIC: return record.safe.invocation_owner_id == parent.id
			return parent.kind == ScenarioExecutionRecord.Kind.SAFE and record.safe.invocation_owner_id == parent.safe.invocation_owner_id
		ScenarioExecutionRecord.Kind.OPERATION:
			match record.operation.return_kind:
				ScenarioOperationExecutionRecord.ReturnKind.APPLICATION:
					if record.operation.child_call == null or record.operation.child_call.kind != ScenarioProgramCall.Kind.APPLICATION: return false
					var control := record.operation.child_call.application.caller_control
					return control == null if parent == null else control != null and parent.kind == ScenarioExecutionRecord.Kind.OPERATION and parent.operation.phase == ScenarioOperationExecutionRecord.Phase.HOST_RETURN
				ScenarioOperationExecutionRecord.ReturnKind.DIRECT: return parent == null
				ScenarioOperationExecutionRecord.ReturnKind.CLASSIC:
					if parent == null or parent.kind != ScenarioExecutionRecord.Kind.CLASSIC: return false
					return record.operation.phase != ScenarioOperationExecutionRecord.Phase.RESPONSE or parent.classic.phase in [ScenarioClassicInvocationRecord.Phase.CODE,ScenarioClassicInvocationRecord.Phase.ENCOUNTER]
				ScenarioOperationExecutionRecord.ReturnKind.SAFE: return parent != null and parent.kind == ScenarioExecutionRecord.Kind.SAFE
	return false


func read_trace(values: Array) -> bool:
	if values.size() > 4096:
		return false
	for entry: Variant in values:
		if not entry is Dictionary:
			return false
		var record: Dictionary = entry
		trace.append(record.duplicate(true))
	return true


func read_completion(value: Variant) -> bool:
	completion = ScenarioNativeCompletion.from_data(value)
	return completion != null and not completion.remove_selected_ap


func pending_owner_is_valid() -> bool:
	if records.is_empty():
		return pending_request == null and pending_owner_id == 0
	var owner: ScenarioExecutionRecord = records.back()
	if pending_request == null:
		return pending_owner_id == 0 and (owner.kind != ScenarioExecutionRecord.Kind.OPERATION or owner.operation.phase in [ScenarioOperationExecutionRecord.Phase.CHILD_RETURN, ScenarioOperationExecutionRecord.Phase.HOST_RETURN])
	if halted:
		return false
	return owner.id == pending_owner_id and owner.kind == ScenarioExecutionRecord.Kind.OPERATION and owner.operation.phase == ScenarioOperationExecutionRecord.Phase.RESPONSE
