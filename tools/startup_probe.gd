extends SceneTree

const MAIN_SCENE := "res://src/presentation/realmz_application.tscn"

var _started_at: int
var _loaded_at: int
var _instantiated_at: int
var _readied_at: int
var _root: Node


func _initialize() -> void:
	_started_at = Time.get_ticks_usec()
	var packed := ResourceLoader.load(MAIN_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_loaded_at = Time.get_ticks_usec()
	if packed == null:
		printerr("Could not load the main scene.")
		quit(1)
		return
	_root = packed.instantiate()
	_instantiated_at = Time.get_ticks_usec()
	_root.ready.connect(func() -> void: _readied_at = Time.get_ticks_usec(), CONNECT_ONE_SHOT)
	get_root().add_child(_root)
	process_frame.connect(_report_first_frame, CONNECT_ONE_SHOT)


func _report_first_frame() -> void:
	var framed_at := Time.get_ticks_usec()
	print(CanonicalJson.encode({
		"firstFrameMs": _milliseconds(_started_at, framed_at),
		"instantiateMs": _milliseconds(_loaded_at, _instantiated_at),
		"loadSceneMs": _milliseconds(_started_at, _loaded_at),
		"readyMs": _milliseconds(_instantiated_at, _readied_at),
		"readyToFrameMs": _milliseconds(_readied_at, framed_at),
	}))
	_root.queue_free()
	process_frame.connect(func() -> void: quit(0), CONNECT_ONE_SHOT)


static func _milliseconds(started_at: int, finished_at: int) -> float:
	return snappedf(float(finished_at - started_at) / 1000.0, 0.001)
