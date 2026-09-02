class_name HeldMovementController
extends Node

signal movement_requested(direction: Vector2i)

const BASE_INTERVAL_SECONDS: float = 0.05
const INITIAL_REPEAT_DELAY_SECONDS: float = 0.15

var _speed_percent: int = 100
var _source: StringName = &""
var _direction: Vector2i = Vector2i.ZERO
var _remaining: float = 0.0
var _request_in_progress: bool = false


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not is_active():
		set_process(false)
		return
	_remaining -= delta
	if _remaining > 0.0:
		return
	# Never catch up missed intervals. A slow frame produces one request and the
	# next interval begins after the synchronous transaction settles.
	_emit_request()


func set_speed_percent(value: int) -> void:
	_speed_percent = clampi(snappedi(value, 25), 25, 400)
	if is_active():
		_remaining = interval_seconds()


func speed_percent() -> int:
	return _speed_percent


func interval_seconds() -> float:
	return BASE_INTERVAL_SECONDS * 100.0 / float(_speed_percent)


func initial_repeat_delay_seconds() -> float:
	return maxf(INITIAL_REPEAT_DELAY_SECONDS, interval_seconds())


func start(source: StringName, direction: Vector2i) -> void:
	if source.is_empty() or direction == Vector2i.ZERO or _request_in_progress:
		return
	_source = source
	_direction = direction
	set_process(true)
	_emit_request(initial_repeat_delay_seconds(), false)


func update(source: StringName, direction: Vector2i) -> void:
	if source != _source or direction == Vector2i.ZERO:
		return
	if direction == _direction:
		return
	_direction = direction
	_emit_request(interval_seconds(), false)


func stop(source: StringName = &"") -> void:
	if not source.is_empty() and source != _source:
		return
	_source = &""
	_direction = Vector2i.ZERO
	_remaining = 0.0
	set_process(false)


func is_active() -> bool:
	return not _source.is_empty() and _direction != Vector2i.ZERO


func active_direction() -> Vector2i:
	return _direction


func active_source() -> StringName:
	return _source


func request_in_progress() -> bool:
	return _request_in_progress


func _emit_request(repeat_delay_seconds: float = -1.0, consume_transaction_time: bool = true) -> void:
	if not is_active() or _request_in_progress:
		return
	var started_at := Time.get_ticks_usec()
	_request_in_progress = true
	movement_requested.emit(_direction)
	_request_in_progress = false
	if is_active():
		# The speed setting describes visible step cadence, so synchronous view and
		# presentation work consumes later intervals. The initial hold threshold begins
		# only after the immediate transaction settles so an ordinary click stays one step.
		var elapsed_seconds := float(Time.get_ticks_usec() - started_at) / 1_000_000.0
		var delay_seconds := interval_seconds() if repeat_delay_seconds < 0.0 else repeat_delay_seconds
		_remaining = maxf(delay_seconds - elapsed_seconds, 0.0) if consume_transaction_time else delay_seconds
