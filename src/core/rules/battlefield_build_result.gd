class_name BattlefieldBuildResult
extends RefCounted

var battlefield: BattlefieldState
var error_code: StringName = &""
var error_message: String = ""


func is_ok() -> bool:
	return battlefield != null and error_code.is_empty()


static func succeeded(value: BattlefieldState) -> BattlefieldBuildResult:
	var result := BattlefieldBuildResult.new()
	result.battlefield = value
	return result


static func failed(code: StringName, message: String) -> BattlefieldBuildResult:
	var result := BattlefieldBuildResult.new()
	result.error_code = code
	result.error_message = message
	return result
