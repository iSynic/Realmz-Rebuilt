## Loads and copies Castle encounter structures without aliasing stored records or package data.
class_name ClassicEncounterMemoryOperations
extends RefCounted

var _content: RealmzContent
var _state: ScenarioEncounterState


func _init(content: RealmzContent, state: ScenarioEncounterState) -> void:
	_content = content
	_state = state


func load_record(kind: StringName, id: int, with_text: bool = true) -> bool:
	var code := _state.memory.stored(kind, id)
	if code == null:
		code = source_code(kind, id)
	if code == null: return false
	var marks: Array[bool] = []
	for index: int in 4:
		marks.append(_state.simple_option_is_eliminated(id, index) if kind == &"simple" else _state.complex_result_is_eliminated(id, index))
	_state.memory.load_record(kind, id, code, marks, with_text)
	return true


func source_code(kind: StringName, id: int) -> ClassicEncounterCode:
	var simple := _content.scenario_records.simple_encounter_by_id(id) if kind == &"simple" else null
	var complex := _content.scenario_records.complex_encounter_by_id(id) if kind == &"complex" else null
	if simple == null and complex == null: return null
	var result := ClassicEncounterCode.new()
	result.base_id = id
	for index: int in 4:
		var source := "%s:%d:result:%d" % [kind, id, index]
		if simple != null and simple.native_facts == null:
			var response := simple.response_at(index)
			source = response.result_program_id if response != null else ""
		result.programs[index] = _state.program_id(source) if not source.is_empty() else ""
	return result


func copy_result(kind: StringName, index: int, context: ScenarioExecutionContext = null, slot: int = 0, gosub: bool = false) -> ScenarioRuntimeOperationResult:
	if kind not in [&"simple", &"complex"] or index < 0 or index > 3:
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_result", "Classic result copy requires a kind and native result index 0 through 3.")
	var buffer := _state.memory.loaded(kind)
	if buffer.code == null and not (kind == &"complex" and buffer.marks[index]):
		return ScenarioRuntimeOperationResult.failed(&"missing_loaded_encounter", "The loaded %s structure is historically unavailable." % kind)
	var program_id := buffer.code.programs[index] if buffer.code != null else ""
	var code_kind := ScenarioClassicProgramState.Kind.PROGRAM
	if kind == &"complex" and buffer.marks[index]: code_kind = ScenarioClassicProgramState.Kind.KEEP_CODES
	elif program_id.is_empty() or _content.scenario.native_program_is_unavailable(program_id): code_kind = ScenarioClassicProgramState.Kind.EMPTY
	var code := ScenarioClassicProgramState.new(program_id, context, code_kind)
	return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.copy_record(code, slot, gosub))


func simple_definition() -> SimpleEncounterDefinition:
	var buffer := _state.memory.simple
	if buffer.code == null: return null
	var base := _content.scenario_records.simple_encounter_by_id(buffer.code.base_id)
	if base == null: return null
	for index: int in 4:
		if _state.memory.texts[index].record_id == -2: return null
	var responses: Array[SimpleEncounterResponse] = []
	for index: int in base.responses().size():
		var source := base.response_at(index)
		var response_id := "simple:%d:choice:%d" % [buffer.record_id, index] if base.native_facts != null else source.id
		var response := SimpleEncounterResponse.new(response_id, text(index), source.result_program_id)
		if buffer.marks[index] or source.is_classic_eliminated(base.id): response.result_program_id = "simple:%d:result:-1" % buffer.record_id
		responses.append(response)
	var result := SimpleEncounterDefinition.new(buffer.record_id, base.prompt_message_id, responses, base.can_back_out, base.max_times, base.caste_success)
	result.native_facts = base.native_facts
	return result


func simple_result(index: int, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	var buffer := _state.memory.simple
	var base := _content.scenario_records.simple_encounter_by_id(buffer.code.base_id) if buffer.code != null else null
	if base == null or index < 0 or index >= base.responses().size():
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_result", "The loaded Simple result is unavailable.")
	var result_index := index
	if base.native_facts != null: result_index = base.native_facts.choice_results[index] - 1
	return copy_result(&"simple", result_index, context)


func complex_definition() -> ComplexEncounterDefinition:
	var buffer := _state.memory.complex
	if buffer.code == null: return null
	var base := _content.scenario_records.complex_encounter_by_id(buffer.code.base_id)
	if base == null: return null
	for row: ClassicEncounterTextReference in _state.memory.texts:
		if row.record_id == -2: return null
	var rows: Array[String] = []
	for index: int in 9: rows.append(text(index))
	return ComplexEncounterDefinition.new(buffer.record_id, base.prompt_message_id, base.action_result, base.word_result, base.groups(), base.spell_ids(), base.spell_results(), base.item_ids(), base.item_results(), base.can_back_out, base.thief, base.max_times, base.caste_success, base.thief_success, base.thief_fail, rows)


func text(index: int) -> String:
	var source := _state.memory.texts[index]
	if source.kind == &"simple":
		var encounter := _content.scenario_records.simple_encounter_by_id(source.record_id)
		var response := encounter.response_at(source.slot) if encounter != null else null
		return response.label if response != null else ""
	if source.kind == &"complex":
		var encounter := _content.scenario_records.complex_encounter_by_id(source.record_id)
		if encounter != null: return encounter.action_labels()[source.slot] if source.slot < 8 else encounter.expected_word()
	return ""


func prepare_simple_text() -> void:
	var buffer := _state.memory.simple
	var base := _content.scenario_records.simple_encounter_by_id(buffer.code.base_id) if buffer.code != null else null
	if base == null: return
	for index: int in base.responses().size():
		if buffer.marks[index] or base.response_at(index).is_classic_eliminated(base.id): _state.memory.texts[index] = ClassicEncounterTextReference.new()


func replace_result(kind: StringName, id: int, index: int, program_id: String) -> bool:
	if index < 0 or index > 3 or not load_record(kind, id, false): return false
	var buffer := _state.memory.loaded(kind)
	buffer.code.programs[index] = program_id
	if kind == &"complex": buffer.marks[index] = false
	return _state.store_loaded(kind, id)


func save_loaded(kind: StringName, id: int) -> bool:
	if kind == &"simple" and _content.scenario_records.simple_encounter_by_id(id) == null: return false
	if kind == &"complex" and _content.scenario_records.complex_encounter_by_id(id) == null: return false
	return _state.store_loaded(kind, id)
