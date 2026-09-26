## Preserves a source-identified incomplete Extra Code row without inventing operands.
class_name ClassicExtraCodeFault
extends RefCounted

var row_id: int
var available_bytes: int


func _init(native_row: int, byte_count: int) -> void:
	row_id = native_row
	available_bytes = byte_count


func message() -> String:
	return "Data EDCD row %d at byte offset %d is incomplete: %d of 10 required bytes. The instruction was stopped before execution; repair the source row and reimport." % [row_id, row_id * 10, available_bytes]
