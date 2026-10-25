## Saves clock work without retaining another execution runner or its snapshot.
class_name ScenarioClockScanBody
extends ScenarioRuntimeContinuationBody

var updates: Array[AgeUpdateRequestBody] = []
var age_index: int = 0
var scan_pending: bool = false
var timer_index: int = 0


func as_continuation() -> ScenarioRuntimeContinuation:
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_CLOCK, self)


func wire_payload() -> Dictionary:
	var rows: Array[Dictionary] = []
	for update: AgeUpdateRequestBody in updates: rows.append(update.to_data())
	return {"updates": rows, "ageIndex": age_index, "scanPending": scan_pending, "timerIndex": timer_index}


func copy() -> ScenarioClockScanBody:
	return from_data(wire_payload())


static func from_data(value: Variant) -> ScenarioClockScanBody:
	if not ScenarioExecutionWire.fields(value, ["updates", "ageIndex", "scanPending", "timerIndex"]): return null
	var data: Dictionary = value
	if not data["updates"] is Array or not data["scanPending"] is bool: return null
	var rows: Array = data["updates"]
	if rows.size() > 6: return null
	var result := ScenarioClockScanBody.new()
	result.age_index = ScenarioExecutionWire.integer(data["ageIndex"], 0, rows.size())
	result.timer_index = ScenarioExecutionWire.integer(data["timerIndex"], 0, 151)
	result.scan_pending = data["scanPending"]
	if result.age_index < 0 or result.timer_index < 0: return null
	var characters: Dictionary[String, bool] = {}
	for row: Variant in rows:
		var update := ScenarioAgeContinuations.update_from_data(row)
		if update == null or characters.has(update.character_id): return null
		characters[update.character_id] = true
		result.updates.append(update)
	return result
