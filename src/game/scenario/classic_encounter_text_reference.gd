## Identifies one shared text row without copying or changing immutable authored text.
class_name ClassicEncounterTextReference
extends RefCounted

var kind: StringName = &""
var record_id: int = -1
var slot: int = 0


func _init(source_kind: StringName = &"", source_id: int = -1, source_slot: int = 0) -> void:
	kind = source_kind
	record_id = source_id
	slot = source_slot


func to_data() -> Dictionary:
	return {"kind": String(kind), "recordId": record_id, "slot": slot}


static func from_data(value: Variant) -> ClassicEncounterTextReference:
	if not ClassicEncounterCode.fields(value, ["kind", "recordId", "slot"]): return null
	var data: Dictionary = value
	if not data["kind"] is String or data["kind"] not in ["", "simple", "complex"]: return null
	var id := ClassicEncounterCode.integer(data["recordId"], -2, 32767)
	var source_slot := ClassicEncounterCode.integer(data["slot"], 0, 8)
	if id < -2 or source_slot < 0 or (data["kind"] == "") != (id < 0) or data["kind"] == "simple" and source_slot > 3: return null
	var kind_text: String = data["kind"]
	return ClassicEncounterTextReference.new(StringName(kind_text), id, source_slot)
