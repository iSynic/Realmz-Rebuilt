class_name StartupFrontDoor
extends Control

signal application_loaded(elapsed_ms: float)

const APPLICATION_SCENE_PATH := "res://src/presentation/realmz_application.tscn"
const APPLICATION_SCRIPT_PATH := "res://src/app/realmz_application.gd"
const CAMPAIGN_LIBRARY_CONTROLLER_PATH := "res://src/presentation/controllers/campaign_library_controller.gd"
const SETTINGS_REPOSITORY_PATH := "res://src/infrastructure/settings/settings_repository.gd"
const CLASSIC_TYPOGRAPHY_PATH := "res://src/presentation/classic_typography.gd"
const UI_LAYOUT_PROFILE_PATH := "res://src/presentation/ui_layout_profile.gd"
const PRESENTATION_SETTINGS_PATH := "res://src/core/host/presentation_settings.gd"
const BASE_THEME_PATH := "res://src/presentation/classic_ui_theme.tres"
const STONE_TEXTURE_PATH := "res://src/presentation/assets/ui/classic-charcoal-slate-tile.png"

const SPLASH_HOLD_SECONDS: float = 3.0
const EXIT_CUE_SECONDS: float = 1.513

const ACTION_SCENARIO: StringName = &"scenario"
const ACTION_LOAD: StringName = &"load"
const ACTION_VAULT: StringName = &"vault"
const ACTION_QUIT: StringName = &"quit"

@onready var _overlay_host: Control = %OverlayHost
@onready var _stone_texture: TextureRect = %StoneTexture
@onready var _startup_splash_background: ColorRect = %StartupSplashBackground
@onready var _startup_splash: TextureRect = %StartupSplash
@onready var _startup_duration: Timer = %StartupDuration
@onready var _splash_exit_delay: Timer = %SplashExitDelay
@onready var _launch_transition: AudioStreamPlayer = %StartupLaunchTransition
@onready var _launch_music: AudioStreamPlayer = %StartupLaunchMusic
@onready var _startup_failure: Control = %StartupFailure
@onready var _startup_failure_message: Label = %StartupFailureMessage
@onready var _startup_retry: Button = %RetryStartup

var _menu_controller: RefCounted
var _presentation_settings: RefCounted
var _layout_profile_script: Script
var _presentation_settings_script: Script
var _application_script_prime: Script
var _application: Control
var _load_path: String = ""
var _load_started_at: int = 0
var _load_requested: bool = false
var _load_failed: bool = false
var _splash_complete: bool = false


func _ready() -> void:
	_startup_duration.timeout.connect(_on_startup_splash_timeout)
	_splash_exit_delay.timeout.connect(_on_splash_exit_delay_timeout)
	_startup_retry.pressed.connect(_retry_startup_load)
	_apply_initial_launch_volume()
	_launch_transition.play()
	_startup_duration.start(SPLASH_HOLD_SECONDS)
	resized.connect(_apply_layout)
	if DisplayServer.get_name() == "headless":
		_initialize_after_first_draw.call_deferred()
	else:
		RenderingServer.frame_post_draw.connect(_initialize_after_first_draw, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	if not _load_requested or _application != null:
		return
	var status := ResourceLoader.load_threaded_get_status(_load_path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var loaded := ResourceLoader.load_threaded_get(_load_path)
		if _load_path == APPLICATION_SCRIPT_PATH:
			_application_script_prime = loaded as Script
			if _application_script_prime == null:
				_fail_application_load("Application script preparation failed.")
			else:
				_request_application_scene_load()
		else:
			set_process(false)
			var packed := loaded as PackedScene
			if packed == null:
				_fail_application_load("Application loading failed.")
			else:
				_finish_application_load(packed)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		set_process(false)
		_fail_application_load("Application loading failed.")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _application != null:
			_request_action(ACTION_QUIT)
		else:
			get_tree().quit()


func _exit_tree() -> void:
	if _menu_controller != null:
		_menu_controller.release_intro_resources()
	if is_instance_valid(_application) and get_tree() != null and get_tree().current_scene != _application:
		_application.queue_free()
	_menu_controller = null
	_application = null


func menu_visible() -> bool:
	return _splash_complete and _menu_controller != null and _menu_controller.splash_visible()


func application_ready() -> bool:
	return is_instance_valid(_application) and _application.is_inside_tree()


func _begin_application_load() -> void:
	if _load_requested or _application != null:
		return
	_load_started_at = Time.get_ticks_usec()
	_load_failed = false
	_load_path = APPLICATION_SCRIPT_PATH
	var error := ResourceLoader.load_threaded_request(_load_path)
	if error != OK:
		_fail_application_load("Application script preparation failed.")
		return
	_load_requested = true
	set_process(true)


func _request_application_scene_load() -> void:
	_load_path = APPLICATION_SCENE_PATH
	if ResourceLoader.load_threaded_request(_load_path) != OK:
		_fail_application_load("Application loading failed.")


func _initialize_after_first_draw() -> void:
	var settings_repository_script := load(SETTINGS_REPOSITORY_PATH) as Script
	var typography_script := load(CLASSIC_TYPOGRAPHY_PATH) as Script
	var controller_script := load(CAMPAIGN_LIBRARY_CONTROLLER_PATH) as Script
	_layout_profile_script = load(UI_LAYOUT_PROFILE_PATH) as Script
	_presentation_settings_script = load(PRESENTATION_SETTINGS_PATH) as Script
	var base_theme := load(BASE_THEME_PATH) as Theme
	_stone_texture.texture = load(STONE_TEXTURE_PATH) as Texture2D
	_presentation_settings = settings_repository_script.new().load_settings()
	theme = typography_script.themed_copy(base_theme, _presentation_settings)
	_apply_launch_volume(_presentation_settings)
	_menu_controller = controller_script.new()
	_menu_controller.attach(_overlay_host)
	_menu_controller.set_presentation_settings(_presentation_settings)
	_menu_controller.build_splash_overlay()
	_menu_controller.set_startup_actions_ready(false)
	_menu_controller.campaign_selection_requested.connect(func() -> void: _request_action(ACTION_SCENARIO))
	_menu_controller.load_adventure_requested.connect(func() -> void: _request_action(ACTION_LOAD))
	_menu_controller.vault_requested.connect(func() -> void: _request_action(ACTION_VAULT))
	_menu_controller.quit_requested.connect(func() -> void: _request_action(ACTION_QUIT))
	_menu_controller.hide_overlays()
	_menu_controller.prepare_intro_behind_splash()
	_apply_layout()
	_begin_application_load()


func _fail_application_load(message: String) -> void:
	_load_requested = false
	_load_path = ""
	_application_script_prime = null
	_load_failed = true
	_show_startup_failure(message)


func _finish_application_load(packed: PackedScene) -> void:
	_application = packed.instantiate() as Control
	if _application == null:
		_load_requested = false
		_load_failed = true
		_show_startup_failure("Application construction failed.")
		return
	_application.visible = false
	_application.set_process_input(false)
	_application.set_process_unhandled_input(false)
	_application.set_meta(&"startup_splash_suppressed", true)
	_application.ready.connect(_on_application_ready, CONNECT_ONE_SHOT)
	get_tree().root.add_child.call_deferred(_application)


func _on_application_ready() -> void:
	_load_requested = false
	_load_path = ""
	_load_failed = false
	_application_script_prime = null
	_startup_failure.visible = false
	if _splash_complete:
		_menu_controller.set_startup_actions_ready(true)
		_application.set_meta(&"startup_front_door_revealed", true)
	var elapsed_ms := float(Time.get_ticks_usec() - _load_started_at) / 1000.0
	application_loaded.emit(elapsed_ms)


func _request_action(action: StringName) -> void:
	if _application == null:
		if action == ACTION_QUIT:
			get_tree().quit()
		return
	_enter_application(action)


func _enter_application(action: StringName) -> void:
	if _application == null:
		return
	_menu_controller.hide_overlays()
	_application.visible = true
	_application.set_process_input(true)
	_application.set_process_unhandled_input(true)
	_application.set_meta(&"startup_route_request", action)
	get_tree().current_scene = _application
	queue_free()


func _on_startup_splash_timeout() -> void:
	_launch_transition.play()
	_splash_exit_delay.start(EXIT_CUE_SECONDS)


func _on_splash_exit_delay_timeout() -> void:
	_splash_complete = true
	_startup_splash.visible = false
	_startup_splash_background.visible = false
	if _menu_controller == null:
		_show_startup_failure("Application menu construction failed.")
		return
	_menu_controller.show_splash()
	_menu_controller.set_startup_actions_ready(application_ready())
	if application_ready():
		_application.set_meta(&"startup_front_door_revealed", true)
	_launch_music.play()
	if _load_failed:
		_startup_failure.visible = true


func _retry_startup_load() -> void:
	_startup_failure.visible = false
	_begin_application_load()


func _show_startup_failure(message: String) -> void:
	_startup_failure_message.text = message
	_startup_failure.visible = true


func _apply_initial_launch_volume() -> void:
	var linear_volume := 1.0
	if FileAccess.file_exists("user://settings.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
		if parsed is Dictionary:
			linear_volume = clampf(float(parsed.get("masterVolume", 1.0)) * float(parsed.get("soundVolume", 1.0)), 0.0, 1.0)
	var volume_db := linear_to_db(linear_volume) if linear_volume > 0.0 else -80.0
	_launch_transition.volume_db = volume_db
	_launch_music.volume_db = volume_db


func _apply_launch_volume(settings: RefCounted) -> void:
	var linear_volume := clampf(settings.master_volume * settings.sound_volume, 0.0, 1.0)
	var volume_db := linear_to_db(linear_volume) if linear_volume > 0.0 else -80.0
	_launch_transition.volume_db = volume_db
	_launch_music.volume_db = volume_db


func _apply_layout() -> void:
	if _menu_controller == null or _layout_profile_script == null or _presentation_settings_script == null:
		return
	var profile: RefCounted = _layout_profile_script.for_viewport(size, _presentation_settings_script.UI_SCALE_AUTO)
	_menu_controller.apply_layout(profile, profile.application_rect, profile.application_rect)
