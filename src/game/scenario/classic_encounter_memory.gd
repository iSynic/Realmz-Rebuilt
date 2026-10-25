## Save-owned copies of the native Simple/Complex buffers, stored structures and text rows.
class_name ClassicEncounterMemory
extends RefCounted

var simple := ClassicEncounterBuffer.new()
var complex := ClassicEncounterBuffer.new()
var texts: Array[ClassicEncounterTextReference] = []
var _stored_simple: Dictionary[int, ClassicEncounterCode] = {}
var _stored_complex: Dictionary[int, ClassicEncounterCode] = {}


func _init() -> void:
	for slot: int in 9: texts.append(ClassicEncounterTextReference.new())


func loaded(kind: StringName) -> ClassicEncounterBuffer:
	return simple if kind == &"simple" else complex if kind == &"complex" else null


func stored(kind: StringName, id: int) -> ClassicEncounterCode:
	var source := _stored_simple if kind == &"simple" else _stored_complex
	var code: ClassicEncounterCode = source.get(id)
	return code.copy() if code != null else null


func store(kind: StringName, id: int, code: ClassicEncounterCode) -> void:
	assert(kind in [&"simple", &"complex"] and id >= 0 and id <= 32767 and code != null)
	if kind == &"simple": _stored_simple[id] = code.copy()
	else: _stored_complex[id] = code.copy()


func load_record(kind: StringName, id: int, code: ClassicEncounterCode, marks: Array[bool], with_text: bool) -> void:
	var buffer := loaded(kind)
	buffer.record_id = id
	buffer.code = code.copy()
	buffer.marks = marks.duplicate()
	if with_text:
		for slot: int in (4 if kind == &"simple" else 9): texts[slot] = ClassicEncounterTextReference.new(kind, id, slot)


func is_bound_to(content: RealmzContent) -> bool:
	if simple.record_id >= 0 and content.scenario_records.simple_encounter_by_id(simple.record_id) == null: return false
	if complex.record_id >= 0 and content.scenario_records.complex_encounter_by_id(complex.record_id) == null: return false
	if not code_is_bound(simple.code, &"simple", content) or not code_is_bound(complex.code, &"complex", content): return false
	for code: ClassicEncounterCode in _stored_simple.values():
		if not code_is_bound(code, &"simple", content): return false
	for code: ClassicEncounterCode in _stored_complex.values():
		if not code_is_bound(code, &"complex", content): return false
	for id: int in _stored_simple:
		if content.scenario_records.simple_encounter_by_id(id) == null: return false
	for id: int in _stored_complex:
		if content.scenario_records.complex_encounter_by_id(id) == null: return false
	for row: ClassicEncounterTextReference in texts:
		if row.kind == &"simple" and content.scenario_records.simple_encounter_by_id(row.record_id) == null: return false
		if row.kind == &"complex" and content.scenario_records.complex_encounter_by_id(row.record_id) == null: return false
	return true


static func code_is_bound(code: ClassicEncounterCode, kind: StringName, content: RealmzContent) -> bool:
	if code == null or code.base_id == -1: return true
	if kind == &"simple" and content.scenario_records.simple_encounter_by_id(code.base_id) == null: return false
	if kind == &"complex" and content.scenario_records.complex_encounter_by_id(code.base_id) == null: return false
	for id: String in code.programs:
		if not id.is_empty() and content.scenario.program_by_id(id) == null and not content.scenario.native_program_is_unavailable(id): return false
	return true


func to_data() -> Dictionary:
	var rows: Array[Dictionary] = []
	for row: ClassicEncounterTextReference in texts: rows.append(row.to_data())
	return {"simple": simple.to_data(), "complex": complex.to_data(), "texts": rows, "storedSimple": stored_data(_stored_simple), "storedComplex": stored_data(_stored_complex)}


static func from_data(value: Variant) -> ClassicEncounterMemory:
	if not ClassicEncounterCode.fields(value, ["simple", "complex", "texts", "storedSimple", "storedComplex"]): return null
	var data: Dictionary = value
	if not data["texts"] is Array: return null
	var rows: Array = data["texts"]
	if rows.size() != 9: return null
	var result := ClassicEncounterMemory.new()
	result.simple = ClassicEncounterBuffer.from_data(data["simple"])
	result.complex = ClassicEncounterBuffer.from_data(data["complex"])
	if result.simple == null or result.complex == null: return null
	for slot: int in 9:
		result.texts[slot] = ClassicEncounterTextReference.from_data(rows[slot])
		if result.texts[slot] == null: return null
	if not result.read_stored(&"simple", data["storedSimple"]) or not result.read_stored(&"complex", data["storedComplex"]): return null
	return result


func read_stored(kind: StringName, value: Variant) -> bool:
	if not value is Dictionary: return false
	var data: Dictionary = value
	for key: Variant in data:
		if not key is String: return false
		var text: String = key
		if not text.is_valid_int(): return false
		var id := text.to_int()
		var code := ClassicEncounterCode.from_data(data[key])
		if id < 0 or id > 32767 or str(id) != text or code == null: return false
		store(kind, id, code)
	return true


static func stored_data(source: Dictionary[int, ClassicEncounterCode]) -> Dictionary:
	var result: Dictionary = {}
	var ids: Array[int] = []
	ids.assign(source.keys())
	ids.sort()
	for id: int in ids: result[str(id)] = source[id].to_data()
	return result
