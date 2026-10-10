## Starts each visual frame only after discarding the preceding action's time.
class_name CombatPlaybackDrawGate
extends RefCounted

var _started: CombatPlaybackFrame
var _pending := false
var _generation := 0


func advance(playback: CombatPlaybackController, delta: float, sound_blocking: bool, tree: SceneTree) -> void:
	if _pending:
		return
	var frame := playback.current_frame()
	if frame == null or frame.kind in [&"sound", &"settle", &"move_end"]:
		playback.advance(delta, sound_blocking)
		return
	if frame != _started:
		if sound_blocking:
			return
		_started = frame
		playback.advance(0.0, false)
		_wait_for_draw(tree)
		return
	playback.advance(delta, sound_blocking)


func reset() -> void:
	_started = null
	_pending = false
	_generation += 1


func _wait_for_draw(tree: SceneTree) -> void:
	_pending = true
	_generation += 1
	var generation := _generation
	if DisplayServer.get_name() == "headless":
		await tree.process_frame
	else:
		await RenderingServer.frame_post_draw
	if generation == _generation:
		_pending = false
