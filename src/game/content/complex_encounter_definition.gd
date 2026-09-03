class_name ComplexEncounterDefinition
extends RefCounted

const ACTION_TEXT_COUNT: int = 8
const WORD_TEXT_INDEX: int = 8

var id: int
var prompt_message_id: int
var action_result: int
var word_result: int
var can_back_out: bool
var thief: bool
var max_times: int
var caste_success: int
var thief_success: int
var thief_fail: int
var _groups: Array[int]
var _spell_ids: Array[int]
var _spell_results: Array[int]
var _item_ids: Array[int]
var _item_results: Array[int]
var _texts: Array[String]


func _init(encounter_id: int, prompt_id: int, choice_result: int, spoken_word_result: int, authored_groups: Array[int], authored_spell_ids: Array[int], authored_spell_results: Array[int], authored_item_ids: Array[int], authored_item_results: Array[int], back_out: bool, uses_thief_encounter: bool, maximum_times: int, success_caste: int, thief_success_value: int, thief_failure_value: int, texts: Array[String]) -> void:
	id = encounter_id
	prompt_message_id = prompt_id
	action_result = choice_result
	word_result = spoken_word_result
	_groups = authored_groups.duplicate()
	_spell_ids = authored_spell_ids.duplicate()
	_spell_results = authored_spell_results.duplicate()
	_item_ids = authored_item_ids.duplicate()
	_item_results = authored_item_results.duplicate()
	can_back_out = back_out
	thief = uses_thief_encounter
	max_times = maximum_times
	caste_success = success_caste
	thief_success = thief_success_value
	thief_fail = thief_failure_value
	_texts = texts.duplicate()


func groups() -> Array[int]:
	return _groups.duplicate()


func spell_ids() -> Array[int]:
	return _spell_ids.duplicate()


func spell_results() -> Array[int]:
	return _spell_results.duplicate()


func item_ids() -> Array[int]:
	return _item_ids.duplicate()


func item_results() -> Array[int]:
	return _item_results.duplicate()


func action_labels() -> Array[String]:
	return _texts.slice(0, ACTION_TEXT_COUNT)


func expected_word() -> String:
	return _texts[WORD_TEXT_INDEX] if _texts.size() > WORD_TEXT_INDEX else ""


func result_program_id(outcome: int) -> String:
	return "complex:%d:result:%d" % [id, outcome - 1] if outcome >= 1 and outcome <= 4 else ""
