## Detached structure identity and the four code copies held by a native encounter.
class_name ClassicEncounterCode
extends RefCounted

var base_id: int = -1
var programs: Array[String] = ["", "", "", ""]


func copy() -> ClassicEncounterCode:
	var result := ClassicEncounterCode.new()
	result.base_id = base_id
	result.programs = programs.duplicate()
	return result


func to_data() -> Dictionary:
	return {"baseId": base_id, "programs": programs.duplicate()}


static func from_data(value: Variant) -> ClassicEncounterCode:
	if not fields(value, ["baseId", "programs"]): return null
	var data: Dictionary = value
	var id := integer(data["baseId"], -1, 32767)
	if id < -1 or not data["programs"] is Array: return null
	var rows: Array = data["programs"]
	if rows.size() != 4: return null
	var result := ClassicEncounterCode.new()
	result.base_id = id
	for index: int in 4:
		if not rows[index] is String: return null
		var program: String = rows[index]
		if program.length() > 256 or id == -1 and not program.is_empty(): return null
		result.programs[index] = program
	return result


static func fields(value: Variant, names: Array[String]) -> bool:
	if not value is Dictionary: return false
	var data: Dictionary = value
	return data.size() == names.size() and data.has_all(names)


static func integer(value: Variant, minimum: int, maximum: int) -> int:
	if value is int:
		var number: int = value
		return number if number >= minimum and number <= maximum else minimum - 1
	if value is float:
		var number: float = value
		if is_finite(number) and number == floorf(number) and number >= minimum and number <= maximum: return int(number)
	return minimum - 1
