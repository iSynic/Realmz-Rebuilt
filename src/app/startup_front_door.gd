class_name StartupFrontDoor
extends Control

signal application_loaded(elapsed_ms: float)

const APPLICATION_SCENE_PATH := "res://src/presentation/realmz_application.tscn"
const CampaignLibraryControllerScript := preload("res://src/presentation/controllers/campaign_library_controller.gd")
const SettingsRepositoryScript := preload("res://src/infrastructure/settings/settings_repository.gd")
const ClassicTypographyScript := preload("res://src/presentation/classic_typography.gd")
const UiLayoutProfileScript := preload("res://src/presentation/ui_layout_profile.gd")
const PresentationSettingsScript := preload("res://src/core/host/presentation_settings.gd")
const LAUNCH_TRANSITION_STREAM := preload("res://src/presentation/assets/classic-media/sounds/snd-624.wav")
const LAUNCH_MUSIC_STREAM := preload("res://src/presentation/assets/classic-media/sounds/snd-20.wav")

const SPLASH_DURATION_SECONDS: float = 3.0
const TRANSITION_SOUND_SECONDS: float = 1.513

const ACTION_SCENARIO: StringName = &"scenario"
const ACTION_LOAD: StringName = &"load"
const ACTION_VAULT: StringName = &"vault"
const ACTION_QUIT: StringName = &"quit"

@onready var _overlay_host: Control = %OverlayHost
@onready var _startup_splash: TextureRect = %StartupSplash
@onready var _startup_duration: Timer = %StartupDuration
@onready var _launch_music_delay: Timer = %LaunchMusicDelay
@onready var _launch_transition: AudioStreamPlayer = %StartupLaunchTransition
@onready var _launch_music: AudioStreamPlayer = %StartupLaunchMusic
@onready var _startup_failure: Control = %StartupFailure
@onready var _startup_failure_message: Label = %StartupFailureMessage
@onready var _startup_retry: Button = %RetryStartup

var _menu_controller: RefCounted
var _application: Control
var _load_started_at: int = 0
var _load_requested: bool = false
var _load_failed: bool = false
var _splash_complete: bool = false


func _ready() -> void:
	var presentation_settings: PresentationSettings = SettingsRepositoryScript.new().load_settings()
	theme = ClassicTypographyScript.themed_copy(theme, presentation_settings)
	_apply_launch_volume(presentation_settings)
	_launch_transition.stream = LAUNCH_TRANSITION_STREAM
	_launch_music.stream = LAUNCH_MUSIC_STREAM
	_menu_controller = CampaignLibraryControllerScript.new()
	_menu_controller.attach(_overlay_host)
	_menu_controller.set_presentation_settings(presentation_settings)
	_menu_controller.build_splash_overlay()
	_menu_controller.set_startup_actions_ready(false)
	_menu_controller.campaign_selection_requested.connect(func() -> void: _request_action(ACTION_SCENARIO))
	_menu_controller.load_adventure_requested.connect(func() -> void: _request_action(ACTION_LOAD))
	_menu_controller.vault_requested.connect(func() -> void: _request_action(ACTION_VAULT))
	_menu_controller.quit_requested.connect(func() -> void: _request_action(ACTION_QUIT))
	_menu_controller.hide_overlays()
	_startup_duration.timeout.connect(_on_startup_splash_timeout)
	_launch_music_delay.timeout.connect(_on_launch_music_delay_timeout)
	_startup_retry.pressed.connect(_retry_startup_load)
	_launch_transition.play()
	_startup_duration.start(SPLASH_DURATION_SECONDS)
	resized.connect(_apply_layout)
	_apply_layout()
	get_tree().process_frame.connect(_begin_application_load, CONNECT_ONE_SHOT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _application != null:
			_request_action(ACTION_QUIT)
		else:
			get_tree().quit()


func _exit_tree() -> void:
	if _menu_controller != null:
		_menu_controller.hide_overlays()
	_menu_controller = null
	_application = null


func menu_visible() -> bool:
	return _splash_complete and _menu_controller != null and _menu_controller.splash_visible()


func application_ready() -> bool:
	return _application != null


func _begin_application_load() -> void:
	if _load_requested or _application != null:
		return
	_load_started_at = Time.get_ticks_usec()
	_load_failed = false
	_load_requested = true
	var packed := ResourceLoader.load(APPLICATION_SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	if packed == null:
		_load_requested = false
		_load_failed = true
		_show_startup_failure("Application loading failed.")
		return
	_finish_application_load(packed)


func _finish_application_load(packed: PackedScene) -> void:
	_load_requested = false
	_application = packed.instantiate() as Control
	if _application == null:
		_load_failed = true
		_show_startup_failure("Application construction failed.")
		return
	_application.visible = false
	_application.set_process_input(false)
	_application.set_process_unhandled_input(false)
	_application.set_meta(&"startup_splash_suppressed", true)
	get_tree().root.add_child(_application)
	_load_failed = false
	_startup_failure.visible = false
	if _splash_complete:
		_menu_controller.set_startup_actions_ready(true)
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
	_splash_complete = true
	_startup_splash.visible = false
	_menu_controller.show_splash()
	_menu_controller.set_startup_actions_ready(_application != null)
	_launch_transition.play()
	_launch_music_delay.start(TRANSITION_SOUND_SECONDS)
	if _load_failed:
		_startup_failure.visible = true


func _on_launch_music_delay_timeout() -> void:
	if _splash_complete and is_inside_tree():
		_launch_music.play()


func _retry_startup_load() -> void:
	_startup_failure.visible = false
	_begin_application_load()


func _show_startup_failure(message: String) -> void:
	_startup_failure_message.text = message
	if _splash_complete:
		_startup_failure.visible = true


func _apply_launch_volume(settings: PresentationSettings) -> void:
	var linear_volume := clampf(settings.master_volume * settings.sound_volume, 0.0, 1.0)
	var volume_db := linear_to_db(linear_volume) if linear_volume > 0.0 else -80.0
	_launch_transition.volume_db = volume_db
	_launch_music.volume_db = volume_db


func _apply_layout() -> void:
	if _menu_controller == null:
		return
	var profile: RefCounted = UiLayoutProfileScript.for_viewport(size, PresentationSettingsScript.UI_SCALE_AUTO)
	_menu_controller.apply_layout(profile, profile.application_rect, profile.application_rect)
