## Presents the scene-authored pause pages within the application canvas.
class_name PauseMenuView
extends Control

signal action_requested(action_id: StringName)
@export var preferred_width: float = 520.0
@export var preferred_height: float = 592.0
var _page: StringName = &"main"
var _selected := 0
var _actions: Array[PauseMenuAction] = []
var _profile: UiLayoutProfile
var _selecting := false

func _ready() -> void:
	for node: Node in find_children("*", "PauseMenuAction", true, false):
		var action := node as PauseMenuAction
		action.activated.connect(func(id: StringName) -> void: action_requested.emit(id))
		action.selected.connect(_on_selected)
	%Back.pressed.connect(func() -> void: action_requested.emit(&"back"))
	%Back.focus_entered.connect(func() -> void: _selected = _actions.size())
	visibility_changed.connect(func() -> void: $Layer.visible = visible)
	resized.connect(_layout)

func present(page: StringName, context: String, reasons: Dictionary, slot: String, has_quick_save: bool) -> void:
	var same_page := page == _page and visible
	_page = page
	%Hints.text = "Esc / Start  Resume     Enter  Select" if page == &"main" else "Enter  Select     Esc  Back"
	%Heading.text = {&"main": "Paused", &"settings": "Settings", &"saves": "Save & Load", &"help": "Help & About"}.get(page, "Paused")
	%PackageStatus.text = context
	%PackageStatus.visible = page == &"main"
	%SaveContext.visible = page == &"saves"
	%SaveContext.text = "Current quick slot: %s" % slot
	%SaveNotice.visible = page == &"saves" and has_quick_save
	%SaveNotice.text = "Quicksave replaces slot %s." % slot
	%Back.visible = page != &"main"
	%Resume.visible = page == &"main"
	_actions.clear()
	if page == &"main": _actions.append(%Resume as PauseMenuAction)
	for container: Node in %Pages.get_children():
		var active := StringName(container.name.to_lower()) == page
		(container as Control).visible = active
		if active:
			for child: Node in container.get_children():
				if child is PauseMenuAction: _actions.append(child)
	for action: PauseMenuAction in _actions:
		action.set_availability(String(reasons.get(action.action_id, "")))
		if action.action_id == &"quick_save": action.button.text = "Quicksave %s" % slot
		if action.action_id == &"quick_load": action.button.text = "Quickload %s" % slot
	if not same_page: _selected = 0
	show()
	_layout()
	_select(clampi(_selected, 0, _actions.size() - (0 if %Back.visible else 1)))

func apply_ui_sizing(profile: UiLayoutProfile) -> void:
	_profile = profile
	%Surface.theme = get_parent_control().theme
	_layout()

func move_selection(direction: Vector2i) -> void:
	if direction.y != 0: _select(clampi(_selected + direction.y, 0, _actions.size() - (0 if %Back.visible else 1)))

func activate_selected() -> void:
	if _selected == _actions.size() and %Back.visible: action_requested.emit(&"back")
	elif _selected >= 0 and _selected < _actions.size() and not _actions[_selected].button.disabled:
		action_requested.emit(_actions[_selected].action_id)

func selected_label() -> String:
	return "Back to Pause" if _selected == _actions.size() else _actions[_selected].button.text if not _actions.is_empty() else ""

func _on_selected(id: StringName) -> void:
	if _selecting: return
	for index: int in _actions.size():
		if _actions[index].action_id == id:
			_select(index)
			return

func _select(index: int) -> void:
	_selecting = true
	_selected = index
	for position: int in _actions.size(): _actions[position].set_selected(position == index)
	if index == _actions.size() and %Back.visible: %Back.grab_focus()
	elif index >= 0 and index < _actions.size() and _actions[index] != %Resume:
		%EntriesScroll.ensure_control_visible(_actions[index])
	_selecting = false

func _layout() -> void:
	if not is_node_ready(): return
	var area := _profile.application_rect if _profile != null else Rect2(Vector2.ZERO, size)
	var scale := _profile.ui_scale if _profile != null else 1.0
	var compact := area.size.x < 1280.0
	var margin := 20.0 * scale
	var height := (536.0 if compact else preferred_height) * scale
	if _page == &"saves": height = (472.0 if compact else 500.0) * scale
	if _page == &"help": height = (376.0 if compact else 404.0) * scale
	height *= maxf(1.0, _profile.font_scale / scale if _profile != null else 1.0)
	var extent := Vector2(minf((460.0 if compact else preferred_width) * scale, area.size.x - margin * 2.0), minf(height, area.size.y - margin * 2.0))
	%Surface.position = area.position + (area.size - extent) * 0.5
	%Surface.size = extent
