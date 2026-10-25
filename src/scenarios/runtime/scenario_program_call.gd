## The closed program-call result scheduled by ScenarioVm, without another executor.
class_name ScenarioProgramCall
extends RefCounted

enum Kind { MACRO, TIMER, APPLICATION }

const TIMER_CALL_LIMIT: int = 32

var kind: Kind = Kind.MACRO
var macro: ScenarioMacroCall
var application: ScenarioApplicationCall
var timer_scan: ScenarioClockScanBody
var timer_program_id: String = ""
var timer_context: ScenarioExecutionContext


static func macro_call(value: ScenarioMacroCall) -> ScenarioProgramCall:
	var result := ScenarioProgramCall.new()
	result.macro = value.copy()
	return result


static func timer_call(scan: ScenarioClockScanBody, id: String, entry: ScenarioExecutionContext) -> ScenarioProgramCall:
	var result := ScenarioProgramCall.new()
	result.kind = Kind.TIMER
	result.timer_scan = scan.copy()
	result.timer_program_id = id
	result.timer_context = entry.copy()
	return result


static func application_call(program: String, entry: ScenarioExecutionContext) -> ScenarioProgramCall:
	var result := ScenarioProgramCall.new()
	result.kind = Kind.APPLICATION
	result.application = ScenarioApplicationCall.new()
	result.application.program_id = program
	result.application.context = entry.copy()
	return result


func program_id() -> String:
	if kind == Kind.APPLICATION: return application.program_id
	return macro.program_id if kind == Kind.MACRO else timer_program_id


func context() -> ScenarioExecutionContext:
	if kind == Kind.APPLICATION: return application.context.copy()
	return macro.entry_context() if kind == Kind.MACRO else timer_context.copy()


func restores_code() -> bool:
	# killbody.c copies code/IDs and Extra Code; getup.c's round call does not.
	return kind == Kind.MACRO and macro.kind == ScenarioMacroCall.Kind.DEATH


func copy() -> ScenarioProgramCall:
	return from_data(to_data())


func to_data() -> Dictionary:
	if kind == Kind.APPLICATION: return {"kind": kind, "data": application.to_data()}
	var data := macro.to_data() if kind == Kind.MACRO else {"programId": timer_program_id, "context": ScenarioExecutionContextCodec.encode(timer_context), "scan": timer_scan.wire_payload()}
	return {"kind": kind, "data": data}


static func from_data(value: Variant) -> ScenarioProgramCall:
	if not ScenarioExecutionWire.fields(value, ["kind", "data"]): return null
	var data: Dictionary = value
	var restored_kind := ScenarioExecutionWire.integer(data["kind"], Kind.MACRO, Kind.APPLICATION)
	if restored_kind < 0: return null
	if restored_kind == Kind.APPLICATION:
		var restored := ScenarioApplicationCall.from_data(data["data"])
		if restored == null: return null
		var result := application_call(restored.program_id, restored.context)
		result.application = restored
		return result
	if restored_kind == Kind.MACRO:
		var restored := ScenarioMacroCall.from_data(data["data"])
		return null if restored == null else macro_call(restored)
	if not ScenarioExecutionWire.fields(data["data"], ["programId", "context", "scan"]): return null
	var timer: Dictionary = data["data"]
	if not timer["programId"] is String: return null
	var id: String = timer["programId"]
	var entry := ScenarioExecutionContextCodec.decode(timer["context"])
	var scan := ScenarioClockScanBody.from_data(timer["scan"])
	if id.is_empty() or id.length() > 256 or entry == null or entry.timed_encounter_id < 0 or scan == null: return null
	if not scan.scan_pending or scan.timer_index < 1 or scan.age_index != scan.updates.size(): return null
	return timer_call(scan, id, entry)
