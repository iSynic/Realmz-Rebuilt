class_name ClassicActionDefinition
extends RefCounted

var slot: int
var raw_opcode: int
var opcode: int
var operand_id: int
var gosub: bool
var extra_code: Array[int]


func _init(action_slot: int, raw: int, normalized: int, id_value: int, is_gosub: bool, e_code: Array[int]) -> void:
	slot = action_slot
	raw_opcode = raw
	opcode = normalized
	operand_id = id_value
	gosub = is_gosub
	extra_code = e_code.duplicate()
