## Names an application-hook child and its explicit safety return values.
class_name ScenarioApplicationCall
extends RefCounted

var program_id: String = ""
var context: ScenarioExecutionContext
var caller_control: ScenarioClassicCallerState


func to_data() -> Dictionary:
	return {"programId": program_id, "context": ScenarioExecutionContextCodec.encode(context), "callerControl": null if caller_control == null else caller_control.to_data()}


static func from_data(value: Variant) -> ScenarioApplicationCall:
	if not ScenarioExecutionWire.fields(value, ["programId", "context", "callerControl"]): return null
	var data: Dictionary = value
	if not data["programId"] is String: return null
	var result := ScenarioApplicationCall.new()
	result.program_id = data["programId"]
	result.context = ScenarioExecutionContextCodec.decode(data["context"])
	if result.program_id.is_empty() or result.program_id.length() > 256 or result.context == null or result.context.application_hook.is_empty() or result.context.calling_context != &"lifecycle" or result.context.timed_encounter_id >= 0: return null
	if data["callerControl"] != null:
		result.caller_control = ScenarioClassicCallerState.from_data(data["callerControl"])
		if result.caller_control == null: return null
	return result
