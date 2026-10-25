## One shared native structure; record identity and loaded marks are independent of disk.
class_name ClassicEncounterBuffer
extends RefCounted

var record_id: int = -1
var code := ClassicEncounterCode.new()
var marks: Array[bool] = [false, false, false, false]


func copy() -> ClassicEncounterBuffer:
	var result := ClassicEncounterBuffer.new()
	result.record_id = record_id
	result.code = code.copy() if code != null else null
	result.marks = marks.duplicate()
	return result


func to_data() -> Dictionary:
	return {"recordId": record_id, "code": code.to_data() if code != null else null, "marks": marks.duplicate()}


static func from_data(value: Variant) -> ClassicEncounterBuffer:
	if not ClassicEncounterCode.fields(value, ["recordId", "code", "marks"]): return null
	var data: Dictionary = value
	var id := ClassicEncounterCode.integer(data["recordId"], -2, 32767)
	if id < -2 or not data["marks"] is Array: return null
	var flags: Array = data["marks"]
	if flags.size() != 4: return null
	var result := ClassicEncounterBuffer.new()
	result.record_id = id
	result.code = ClassicEncounterCode.from_data(data["code"]) if data["code"] != null else null
	if data["code"] != null and result.code == null: return null
	if id == -2 and result.code != null or id == -1 and result.code == null: return null
	if id == -1 and result.code.base_id != -1: return null
	for index: int in 4:
		if not flags[index] is bool: return null
		result.marks[index] = flags[index]
	return result
