extends SceneTree

const MAIN_SCENE := "res://src/presentation/startup_front_door.tscn"

var _started_at: int
var _loaded_at: int
var _instantiated_at: int
var _readied_at: int
var _first_frame_at: int
var _menu_visible_on_first_frame: bool
var _application_ready_at: int
var _background_load_ms: float
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
	_root.application_loaded.connect(_report_application_ready, CONNECT_ONE_SHOT)
	get_root().add_child(_root)
	process_frame.connect(_capture_first_frame, CONNECT_ONE_SHOT)


func _capture_first_frame() -> void:
	_first_frame_at = Time.get_ticks_usec()
	_menu_visible_on_first_frame = _root.menu_visible()
	var scenario_action := _root.find_child("ChooseScenario", true, false) as Button
	if scenario_action != null:
		scenario_action.pressed.emit()


func _report_application_ready(background_load_ms: float) -> void:
	_application_ready_at = Time.get_ticks_usec()
	_background_load_ms = background_load_ms
	call_deferred("_report_transition")


func _report_transition() -> void:
	await process_frame
	var current := current_scene
	var transitioned := current != null and current.name == "RealmzApplication"
	var campaign_setup := current.find_child("PartySetup", true, false) as Control if transitioned else null
	print(CanonicalJson.encode({
		"applicationReadyMs": _milliseconds(_started_at, _application_ready_at),
		"backgroundApplicationLoadMs": snappedf(_background_load_ms, 0.001),
		"firstFrameMs": _milliseconds(_started_at, _first_frame_at),
		"instantiateMs": _milliseconds(_loaded_at, _instantiated_at),
		"loadSceneMs": _milliseconds(_started_at, _loaded_at),
		"menuVisibleOnFirstFrame": _menu_visible_on_first_frame,
		"queuedScenarioTransitionSucceeded": transitioned and campaign_setup != null and campaign_setup.visible,
		"readyMs": _milliseconds(_instantiated_at, _readied_at),
		"readyToFrameMs": _milliseconds(_readied_at, _first_frame_at),
	}))
	for _frame: int in range(30):
		await process_frame
	for child: Node in get_root().get_children():
		child.queue_free()
	await process_frame
	await process_frame
	await process_frame
	quit(0)


static func _milliseconds(started_at: int, finished_at: int) -> float:
	return snappedf(float(finished_at - started_at) / 1000.0, 0.001)
