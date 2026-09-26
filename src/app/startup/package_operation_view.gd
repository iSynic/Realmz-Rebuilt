## Coordinates package operation view within application startup and host integration.

class_name PackageOperationView
extends RefCounted

const IDLE: StringName = &"idle"
const RUNNING: StringName = &"running"
const SUCCEEDED: StringName = &"succeeded"
const FAILED: StringName = &"failed"
const CANCELLED: StringName = &"cancelled"

var state: StringName
var phase: StringName
var completed: int
var total: int
var message: String
var error_code: StringName
var package_path: String
var operation_name: StringName
var diagnostic_details: Array[String] = []
var startup_candidates: Array[String] = []


func _init(operation_state: StringName = IDLE, operation_phase: StringName = &"", completed_units: int = 0, total_units: int = 0, operation_message: String = "", operation_error_code: StringName = &"", affected_package_path: String = "", affected_operation_name: StringName = &"") -> void:
	state = operation_state
	phase = operation_phase
	completed = maxi(0, completed_units)
	total = maxi(0, total_units)
	message = operation_message
	error_code = operation_error_code
	package_path = affected_package_path
	operation_name = affected_operation_name


static func from_status(status: RefCounted, affected_package_path: String = "", affected_operation_name: StringName = &"install_scenario", operation_error_code: StringName = &"") -> PackageOperationView:
	if status == null:
		return PackageOperationView.new()
	return PackageOperationView.new(status.state, status.phase, status.completed, status.total, status.message, operation_error_code, affected_package_path, affected_operation_name)


func is_running() -> bool:
	return state == RUNNING


func progress_ratio() -> float:
	if total <= 0:
		return -1.0
	return clampf(float(completed) / float(total), 0.0, 1.0)
