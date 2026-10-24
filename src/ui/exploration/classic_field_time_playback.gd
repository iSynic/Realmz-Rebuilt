## Presents Classic field time playback through the Godot interface.

class_name ClassicFieldTimePlayback
extends RefCounted

const FRAME_SECONDS := 1.0 / 120.0

var _tween: Tween
var _label: Label


func present(host: Node, label: Label, events: Array[DomainEvent]) -> void:
	_label = label
	var timeclicks: Array[Dictionary] = []
	for event: DomainEvent in events:
		if event.kind == &"time_advanced" and event.payload.has("day") and event.payload.has("hour") and event.payload.has("minute"):
			timeclicks.append(event.payload.duplicate(true))
	if timeclicks.size() <= 1:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_set_clock(timeclicks[0])
	_tween = host.create_tween()
	for index: int in range(1, timeclicks.size()):
		_tween.tween_interval(FRAME_SECONDS)
		_tween.tween_callback(_set_clock.bind(timeclicks[index]))


func bind_label(label: Label) -> void:
	_label = label


func is_active() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


func _set_clock(payload: Dictionary) -> void:
	if is_instance_valid(_label):
		_label.text = "Day %d • %02d:%02d" % [int(payload["day"]), int(payload["hour"]), int(payload["minute"])]
