## Binds the authored main menu and retains its cosmetic background rotation.
class_name MainMenuView
extends Control

@export var background_paths: PackedStringArray
@export_range(5.0, 60.0) var hold_seconds := 18.0
@export_range(0.1, 3.0) var fade_seconds := 1.25

@onready var _background: TextureRect = %MenuBackground
@onready var _next_background: TextureRect = %NextMenuBackground
@onready var _readability: TextureRect = %ReadabilityFade
@onready var _title: TextureRect = %MenuTitle
@onready var _commands: VBoxContainer = %MenuCommands
@onready var _hint: Label = %MenuInputHint
@onready var _hold: Timer = %BackgroundHold

var _order: Array[int] = []
var _rng := RandomNumberGenerator.new()
var _pending_path := ""
var _transition: Tween
var _active := false
var _remaining_hold := 0.0
var _profile: UiLayoutProfile
var _focused_action: StringName = &"ChooseScenario"


func _ready() -> void:
	_rng.randomize()
	_hold.timeout.connect(advance_background)
	resized.connect(_fit_layout)
	_commands.minimum_size_changed.connect(_fit_layout)
	for button: Button in _commands.get_children():
		button.focus_entered.connect(_remember_focus.bind(button.name))
	set_process(false)
	_fit_layout()
	set_menu_active(is_visible_in_tree())


func _remember_focus(action_name: StringName) -> void:
	_focused_action = action_name


func focus_current_action() -> void:
	var button := _commands.get_node_or_null(String(_focused_action)) as Button
	if button != null and not button.disabled:
		button.grab_focus()
		return
	for candidate: Button in _commands.get_children():
		if not candidate.disabled:
			candidate.grab_focus()
			return


func background_count() -> int:
	return background_paths.size()


func current_background_path() -> String:
	return _background.texture.resource_path if _background.texture != null else ""


func set_menu_active(active: bool) -> void:
	if _active == active: return
	_active = active
	if active:
		if _transition != null and _transition.is_valid(): _transition.play()
		elif _pending_path.is_empty(): _hold.start(_remaining_hold if _remaining_hold > 0.0 else hold_seconds)
		set_process(not _pending_path.is_empty())
	else:
		_remaining_hold = _hold.time_left
		_hold.stop()
		if _transition != null and _transition.is_valid(): _transition.pause()
		set_process(false)


func advance_background() -> void:
	if not _active or not _pending_path.is_empty() or _transition != null and _transition.is_valid(): return
	if _order.is_empty():
		for index: int in background_paths.size():
			if background_paths[index] != current_background_path(): _order.append(index)
		for index: int in range(_order.size() - 1, 0, -1):
			var other := _rng.randi_range(0, index)
			var value := _order[index]
			_order[index] = _order[other]
			_order[other] = value
	if _order.is_empty(): return
	_pending_path = background_paths[_order.pop_back()]
	if ResourceLoader.load_threaded_request(_pending_path, "Texture2D") != OK:
		_pending_path = ""
		_hold.start(hold_seconds)
		return
	set_process(true)


func _process(_delta: float) -> void:
	var status := ResourceLoader.load_threaded_get_status(_pending_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return
	set_process(false)
	var texture := ResourceLoader.load_threaded_get(_pending_path) as Texture2D if status == ResourceLoader.THREAD_LOAD_LOADED else null
	_pending_path = ""
	if texture == null:
		_hold.start(hold_seconds)
		return
	_next_background.texture = texture
	_next_background.modulate.a = 0.0
	_transition = create_tween()
	_transition.tween_property(_next_background, "modulate:a", 1.0, fade_seconds)
	_transition.tween_callback(_finish_transition)


func _finish_transition() -> void:
	_background.texture = _next_background.texture
	_next_background.texture = null
	_next_background.modulate.a = 0.0
	_transition = null
	_remaining_hold = hold_seconds
	if _active: _hold.start(hold_seconds)


func show_keyboard_hint() -> void:
	_hint.text = "↑ ↓ Navigate   Enter Select"


func show_controller_hint(family: String, preferences: ControllerPreferences) -> void:
	var confirm := ControllerBindingLabels.action(preferences, &"realmz_controller_confirm", family, ControllerBindingLabels.face(&"south", family))
	_hint.text = "D-pad Navigate   %s Select" % confirm


func _input(event: InputEvent) -> void:
	if _active and is_visible_in_tree() and (event is InputEventKey or event is InputEventMouseButton):
		show_keyboard_hint()


func apply_ui_sizing(profile: UiLayoutProfile) -> void:
	_profile = profile
	if is_node_ready(): _fit_layout()


func _fit_layout() -> void:
	if not is_node_ready(): return
	var scale := _profile.ui_scale if _profile != null else 1.0
	var compact := _profile.id == UiLayoutProfile.COMPACT if _profile != null else size.x < 1280.0 or size.y < 720.0
	var left := (48.0 if compact else 72.0) * scale
	var top := (28.0 if compact else 64.0) * scale
	var menu_top := (214.0 if compact else 272.0) * scale
	var bottom := (26.0 if compact else 36.0) * scale
	_hint.position = Vector2(left + 6.0 * scale, size.y - bottom - _hint.get_combined_minimum_size().y)
	_hint.size = Vector2(size.x - left * 2.0, _hint.get_combined_minimum_size().y)
	_commands.size.x = minf(size.x - left * 2.0, maxf(434.0 * scale, _commands.get_combined_minimum_size().x))
	var command_height := _commands.get_combined_minimum_size().y
	_commands.position = Vector2(left, minf(menu_top, _hint.position.y - 24.0 * scale - command_height))
	var title_size := Vector2(460.0, 168.0) * scale
	var title_space := maxf(1.0, _commands.position.y - top - 28.0 * scale)
	if title_size.y > title_space: title_size *= title_space / title_size.y
	_title.position = Vector2(left, top)
	_title.size = title_size
	_readability.size = Vector2(minf(size.x, (650.0 if compact else 752.0) * scale), size.y)
