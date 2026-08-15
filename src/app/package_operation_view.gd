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


func _init(operation_state: StringName = IDLE, operation_phase: StringName = &"", completed_units: int = 0, total_units: int = 0, operation_message: String = "") -> void:
	state = operation_state
	phase = operation_phase
	completed = maxi(0, completed_units)
	total = maxi(0, total_units)
	message = operation_message


static func from_status(status: RefCounted) -> PackageOperationView:
	if status == null:
		return PackageOperationView.new()
	return PackageOperationView.new(status.state, status.phase, status.completed, status.total, status.message)


func is_running() -> bool:
	return state == RUNNING


func progress_ratio() -> float:
	if total <= 0:
		return -1.0
	return clampf(float(completed) / float(total), 0.0, 1.0)
