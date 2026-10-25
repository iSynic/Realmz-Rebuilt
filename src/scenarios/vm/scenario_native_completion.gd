## Retains a native invocation's exit policy independently of committed events.
class_name ScenarioNativeCompletion
extends RefCounted

enum Exit { NONE, NATURAL, KEEP_CODES, NATIVE_RETURN, SAFE_HALT }
enum Backout { NONE, CHOICE, ENCOUNTER, BACKED_UP }

var exit_path: Exit = Exit.NONE
var backout: Backout = Backout.NONE
var remove_selected_ap: bool = false
var header_suppressed: bool = false
var recheck_suppressed: bool = false


func copy() -> ScenarioNativeCompletion:
	return from_data(to_data())


func to_data() -> Dictionary:
	return {"exitPath":exit_path,"backout":backout,"removeSelectedAp":remove_selected_ap,"headerSuppressed":header_suppressed,"recheckSuppressed":recheck_suppressed}


static func from_data(value: Variant) -> ScenarioNativeCompletion:
	if not ScenarioExecutionWire.fields(value,["exitPath","backout","removeSelectedAp","headerSuppressed","recheckSuppressed"]): return null
	var data: Dictionary = value
	var path := ScenarioExecutionWire.integer(data["exitPath"],Exit.NONE,Exit.SAFE_HALT)
	var reason := ScenarioExecutionWire.integer(data["backout"],Backout.NONE,Backout.BACKED_UP)
	if path < 0 or reason < 0 or reason != Backout.NONE and path != Exit.NATIVE_RETURN: return null
	for field: String in ["removeSelectedAp","headerSuppressed","recheckSuppressed"]:
		if not data[field] is bool: return null
	var result := ScenarioNativeCompletion.new()
	result.exit_path = path as Exit
	result.backout = reason as Backout
	result.remove_selected_ap = data["removeSelectedAp"]
	result.header_suppressed = data["headerSuppressed"]
	result.recheck_suppressed = data["recheckSuppressed"]
	if result.remove_selected_ap and result.exit_path not in [Exit.NATURAL,Exit.SAFE_HALT]: return null
	return result
