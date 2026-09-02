class_name ScriptedRng
extends RealmzRng

var _scripted_values: Array[int]
var _script_index: int = 0


func _init(values: Array[int]) -> void:
	# Scripted sources are explicit test/oracle fixtures and retain their complete
	# trace so a long source vector can be inspected without production limits.
	super(1, RealmzRng.UNLIMITED_TRACE)
	_scripted_values = values.duplicate()


func _next_raw() -> int:
	if _script_index >= _scripted_values.size():
		push_error("ScriptedRng exhausted its fixture values.")
		return 0
	var raw: int = _scripted_values[_script_index]
	_script_index += 1
	if raw < -32_767 or raw > 32_767:
		push_error("ScriptedRng values must match QuickDraw's signed 16-bit output contract.")
		return 0
	return raw


func _source_position() -> Variant:
	return _script_index


func _restore_source_position(value: Variant) -> bool:
	if not value is int or value < 0 or value > _scripted_values.size():
		return false
	_script_index = value
	return true
