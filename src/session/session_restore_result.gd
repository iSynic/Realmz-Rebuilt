class_name SessionRestoreResult
extends RefCounted

var ok: bool
var candidate: SessionRestoreCandidate
var error_code: StringName
var error_message: String


static func succeeded(value: SessionRestoreCandidate) -> SessionRestoreResult:
	return SessionRestoreResult.new(true, value, &"", "")


static func failed(code: StringName, message: String) -> SessionRestoreResult:
	return SessionRestoreResult.new(false, null, code, message)


func _init(success: bool, value: SessionRestoreCandidate, code: StringName, message: String) -> void:
	ok = success
	candidate = value
	error_code = code
	error_message = message
