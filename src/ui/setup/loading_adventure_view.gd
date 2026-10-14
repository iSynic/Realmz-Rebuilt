## Presents cancellable startup progress over one retained main-menu background.
class_name LoadingAdventureView
extends Control

signal cancel_requested

@export var background_paths: PackedStringArray

@onready var _background: TextureRect = %LoadingBackground
@onready var _title: Label = %LoadingTitle
@onready var _progress: Label = %LoadingProgress
@onready var _return_hint: Label = %ReturnHint
@onready var _cancel_button: Button = %CancelButton

var _rng := RandomNumberGenerator.new()
var _pending_path := ""
var _profile: UiLayoutProfile


func _ready() -> void:
	_rng.randomize()
	_cancel_button.pressed.connect(func() -> void: cancel_requested.emit())
	resized.connect(_fit_layout)
	visible = false
	set_process(false)
	if _profile != null:
		UiSizing.apply(_loading_panel, _profile)
	else:
		_profile = UiSizing.profile_for(self)
		if _profile != null:
			UiSizing.apply(_loading_panel, _profile)
	_fit_layout()


func show_wait(campaign_title: String, return_label: String) -> void:
	var entering := not visible
	_title.text = "Loading %s" % campaign_title
	_return_hint.text = "Cancel returns to %s." % return_label
	if entering:
		_request_background()
	visible = true
	set_process(not _pending_path.is_empty())
	call_deferred("_focus_cancel")


func update_progress(message: String) -> void:
	_progress.text = message


func hide_wait() -> void:
	visible = false
	set_process(not _pending_path.is_empty())


func _exit_tree() -> void:
	if not _pending_path.is_empty() and ResourceLoader.load_threaded_get_status(_pending_path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_get(_pending_path)
	_pending_path = ""


func set_layout_profile(profile: UiLayoutProfile) -> void:
	_profile = profile
	if is_node_ready():
		UiSizing.apply(_loading_panel, profile)
	_fit_layout()


func apply_ui_sizing(profile: UiLayoutProfile) -> void:
	set_layout_profile(profile)


func _request_background() -> void:
	if background_paths.is_empty() or not _pending_path.is_empty():
		return
	_pending_path = background_paths[_rng.randi_range(0, background_paths.size() - 1)]
	if ResourceLoader.load_threaded_request(_pending_path, "Texture2D") != OK:
		_pending_path = ""


func _process(_delta: float) -> void:
	var status := ResourceLoader.load_threaded_get_status(_pending_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var path := _pending_path
	_pending_path = ""
	set_process(false)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		return
	var texture := ResourceLoader.load_threaded_get(path) as Texture2D
	if texture != null:
		_background.texture = texture


func _focus_cancel() -> void:
	if is_visible_in_tree() and _cancel_button.is_visible_in_tree() and not _cancel_button.disabled:
		_cancel_button.grab_focus()


func _fit_layout() -> void:
	if not is_node_ready():
		return
	var scale := _profile.ui_scale if _profile != null else 1.0
	var font_scale := _profile.font_scale if _profile != null else scale
	var compact := _profile.id == UiLayoutProfile.COMPACT if _profile != null else size.x < 1280.0 or size.y < 720.0
	var panel_width := (640.0 if compact else 600.0) * scale
	var bottom_margin := (64.0 if compact else 84.0) * scale
	var panel_height := (208.0 * scale) + (64.0 * maxf(0.0, font_scale - scale))
	_loading_panel.offset_left = -panel_width * 0.5
	_loading_panel.offset_right = panel_width * 0.5
	_loading_panel.offset_top = -bottom_margin - panel_height
	_loading_panel.offset_bottom = -bottom_margin
	_loading_panel.custom_minimum_size = Vector2(panel_width, panel_height)
	_loading_content.add_theme_constant_override("separation", roundi(14.0 * scale))
	UiSizing.font_size(_title, &"font_size", 26)
	UiSizing.font_size(_progress, &"font_size", 20)
	UiSizing.font_size(_return_hint, &"font_size", 16)
	UiSizing.font_size(_cancel_button, &"font_size", 18)
	UiSizing.minimum_size(_cancel_button, Vector2(0.0, 42.0))


@onready var _loading_panel: PanelContainer = %LoadingPanel
@onready var _loading_content: VBoxContainer = %LoadingContent
