extends SceneTree

const MAIN_SCENE := "res://src/presentation/startup_front_door.tscn"

var _started_at: int
var _loaded_at: int
var _instantiated_at: int
var _readied_at: int
var _first_frame_at: int
var _menu_visible_on_first_frame: bool
var _splash_visible_on_first_frame: bool
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
	var splash := _root.find_child("StartupSplash", true, false) as Control
	_splash_visible_on_first_frame = splash != null and splash.visible


func _report_application_ready(background_load_ms: float) -> void:
	_application_ready_at = Time.get_ticks_usec()
	_background_load_ms = background_load_ms
	call_deferred("_report_transition")


func _report_transition() -> void:
	while not _root.menu_visible():
		await process_frame
	var intro := _root.find_child("RealmzIntroAnimation", true, false) as ClassicIntroAnimation
	var prepared_decoder_count: int = 0
	for candidate: Node in get_root().find_children("RealmzIntroAnimation", "ClassicIntroAnimation", true, false):
		if (candidate as ClassicIntroAnimation).resources_prepared():
			prepared_decoder_count += 1
	var intro_prepared_once := intro != null and intro.resources_prepared() and intro.preparation_count() == 1
	var intro_playing_at_reveal := intro != null and intro.playback_active()
	var reveal_at := Time.get_ticks_usec()
	while Time.get_ticks_usec() - reveal_at < 5_000_000:
		await process_frame
	var intro_playing_after_five_seconds := intro != null and intro.playback_active()
	var prepared_decoder_count_after_five_seconds := 0
	for candidate: Node in get_root().find_children("RealmzIntroAnimation", "ClassicIntroAnimation", true, false):
		if (candidate as ClassicIntroAnimation).resources_prepared():
			prepared_decoder_count_after_five_seconds += 1
	var scenario_action := _root.find_child("ChooseScenario", true, false) as Button
	var scenario_action_enabled := scenario_action != null and not scenario_action.disabled
	if scenario_action_enabled:
		scenario_action.pressed.emit()
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
		"introPlayingAtMenuReveal": intro_playing_at_reveal,
		"introPlayingAfterFiveSeconds": intro_playing_after_five_seconds,
		"introPreparedOnce": intro_prepared_once,
		"preparedDecoderCountAtMenuReveal": prepared_decoder_count,
		"preparedDecoderCountAfterFiveSeconds": prepared_decoder_count_after_five_seconds,
		"scenarioActionEnabledAtTransition": scenario_action_enabled,
		"queuedScenarioTransitionSucceeded": transitioned and campaign_setup != null and campaign_setup.visible,
		"readyMs": _milliseconds(_instantiated_at, _readied_at),
		"readyToFrameMs": _milliseconds(_readied_at, _first_frame_at),
		"splashVisibleOnFirstFrame": _splash_visible_on_first_frame,
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
