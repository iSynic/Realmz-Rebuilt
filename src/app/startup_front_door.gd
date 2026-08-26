class_name StartupFrontDoor
extends Control

signal application_loaded(elapsed_ms: float)

const APPLICATION_SCENE_PATH := "res://src/presentation/realmz_application.tscn"
const CampaignLibraryControllerScript := preload("res://src/presentation/controllers/campaign_library_controller.gd")
const SettingsRepositoryScript := preload("res://src/infrastructure/settings/settings_repository.gd")
const ClassicTypographyScript := preload("res://src/presentation/classic_typography.gd")
const UiLayoutProfileScript := preload("res://src/presentation/ui_layout_profile.gd")
const PresentationSettingsScript := preload("res://src/core/host/presentation_settings.gd")

const ACTION_SCENARIO: StringName = &"scenario"
const ACTION_LOAD: StringName = &"load"
const ACTION_VAULT: StringName = &"vault"
const ACTION_QUIT: StringName = &"quit"

@onready var _overlay_host: Control = %OverlayHost
@onready var _loading_status: Label = %LoadingStatus

var _menu_controller: RefCounted
var _application: Control
var _pending_action: StringName = &""
var _load_started_at: int = 0
var _load_requested: bool = false
var _load_failed: bool = false
var _load_thread := Thread.new()


func _ready() -> void:
	var presentation_settings: PresentationSettings = SettingsRepositoryScript.new().load_settings()
	theme = ClassicTypographyScript.themed_copy(theme, presentation_settings)
	_menu_controller = CampaignLibraryControllerScript.new()
	_menu_controller.attach(_overlay_host)
	_menu_controller.set_presentation_settings(presentation_settings)
	_menu_controller.build_splash_overlay()
	_menu_controller.campaign_selection_requested.connect(func() -> void: _request_action(ACTION_SCENARIO))
	_menu_controller.load_adventure_requested.connect(func() -> void: _request_action(ACTION_LOAD))
	_menu_controller.vault_requested.connect(func() -> void: _request_action(ACTION_VAULT))
	_menu_controller.quit_requested.connect(func() -> void: _request_action(ACTION_QUIT))
	_menu_controller.show_splash()
	resized.connect(_apply_layout)
	_apply_layout()
	get_tree().process_frame.connect(_begin_application_load, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	if not _load_requested or _application != null or _load_thread.is_alive():
		return
	_finish_application_load()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _application != null:
		_request_action(ACTION_QUIT)


func _exit_tree() -> void:
	if _load_requested and _load_thread.is_started():
		_load_thread.wait_to_finish()
		_load_requested = false
	if _menu_controller != null:
		_menu_controller.hide_overlays()
	_menu_controller = null
	_application = null


func menu_visible() -> bool:
	return _menu_controller != null and _menu_controller.splash_visible()


func application_ready() -> bool:
	return _application != null


func _begin_application_load() -> void:
	if _load_requested or _application != null:
		return
	_load_started_at = Time.get_ticks_usec()
	_load_failed = false
	var error := _load_thread.start(_load_application_scene)
	if error != OK:
		_load_failed = true
		_loading_status.text = "Application loading failed · choose an action to retry"
		return
	_load_requested = true
	_loading_status.text = "Preparing game data…"


func _finish_application_load() -> void:
	_load_requested = false
	var packed := _load_thread.wait_to_finish() as PackedScene
	if packed == null:
		_load_failed = true
		_loading_status.text = "Application loading failed · choose an action to retry"
		return
	_application = packed.instantiate() as Control
	if _application == null:
		_load_failed = true
		_loading_status.text = "Application construction failed · choose an action to retry"
		return
	_application.visible = false
	_application.set_process_input(false)
	_application.set_process_unhandled_input(false)
	_application.set_meta(&"startup_splash_suppressed", true)
	get_tree().root.add_child(_application)
	_loading_status.text = "Ready"
	var elapsed_ms := float(Time.get_ticks_usec() - _load_started_at) / 1000.0
	application_loaded.emit(elapsed_ms)
	if not _pending_action.is_empty():
		_enter_application(_pending_action)


func _load_application_scene() -> Resource:
	return ResourceLoader.load(APPLICATION_SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)


func _request_action(action: StringName) -> void:
	_pending_action = action
	if _application == null:
		_loading_status.text = "Preparing your selection…"
		if _load_failed or not _load_requested:
			_begin_application_load()
		return
	_enter_application(action)


func _enter_application(action: StringName) -> void:
	if _application == null:
		return
	_pending_action = &""
	_menu_controller.hide_overlays()
	_application.visible = true
	_application.set_process_input(true)
	_application.set_process_unhandled_input(true)
	_application.set_meta(&"startup_route_request", action)
	get_tree().current_scene = _application
	queue_free()


func _apply_layout() -> void:
	if _menu_controller == null:
		return
	var profile: RefCounted = UiLayoutProfileScript.for_viewport(size, PresentationSettingsScript.UI_SCALE_AUTO)
	_menu_controller.apply_layout(profile, profile.application_rect, profile.application_rect)
