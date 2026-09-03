class_name ThiefEncounterDefinition
extends RefCounted

var id: int
var spell_id: int
var low_damage: int
var high_damage: int
var tumblers: int
var _type_flags: Array[bool]
var _modifiers: Array[int]
var _success_codes: Array[int]
var _failure_codes: Array[int]
var _success_text: Array[int]
var _failure_text: Array[int]
var _success_sounds: Array[int]
var _failure_sounds: Array[int]
var _prompts: Array[int]
var _prompt_sounds: Array[int]


func _init(encounter_id: int, authored_type_flags: Array[bool], authored_modifiers: Array[int], authored_success_codes: Array[int], authored_failure_codes: Array[int], authored_success_text: Array[int], authored_failure_text: Array[int], authored_success_sounds: Array[int], authored_failure_sounds: Array[int], trap_spell_id: int, minimum_damage: int, maximum_damage: int, tumbler_count: int, authored_prompts: Array[int], authored_prompt_sounds: Array[int]) -> void:
	id = encounter_id
	_type_flags = authored_type_flags.duplicate()
	_modifiers = authored_modifiers.duplicate()
	_success_codes = authored_success_codes.duplicate()
	_failure_codes = authored_failure_codes.duplicate()
	_success_text = authored_success_text.duplicate()
	_failure_text = authored_failure_text.duplicate()
	_success_sounds = authored_success_sounds.duplicate()
	_failure_sounds = authored_failure_sounds.duplicate()
	spell_id = trap_spell_id
	low_damage = minimum_damage
	high_damage = maximum_damage
	tumblers = tumbler_count
	_prompts = authored_prompts.duplicate()
	_prompt_sounds = authored_prompt_sounds.duplicate()


func type_flags() -> Array[bool]:
	return _type_flags.duplicate()


func modifiers() -> Array[int]:
	return _modifiers.duplicate()


func success_codes() -> Array[int]:
	return _success_codes.duplicate()


func failure_codes() -> Array[int]:
	return _failure_codes.duplicate()


func success_text() -> Array[int]:
	return _success_text.duplicate()


func failure_text() -> Array[int]:
	return _failure_text.duplicate()


func success_sounds() -> Array[int]:
	return _success_sounds.duplicate()


func failure_sounds() -> Array[int]:
	return _failure_sounds.duplicate()


func prompts() -> Array[int]:
	return _prompts.duplicate()


func prompt_sounds() -> Array[int]:
	return _prompt_sounds.duplicate()
