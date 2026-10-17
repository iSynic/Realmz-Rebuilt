## Presents the scene-authored pause pages within the application canvas.
class_name PauseMenuView
extends Control

signal action_requested(action_id: StringName)
@export var preferred_width: float = 560.0
var _page: StringName = &"main"
var _selected := 0
var _page_selection: Dictionary = {}
var _actions: Array[PauseMenuAction] = []
var _profile: UiLayoutProfile
var _selecting := false
var _controller_hints := ""
var _controller_detail_hints := ""

func _ready() -> void:
	for node: Node in find_children("*", "PauseMenuAction", true, false):
		var action := node as PauseMenuAction
		action.activated.connect(func(id: StringName) -> void: action_requested.emit(id))
		action.selected.connect(_on_selected)
	%Back.pressed.connect(func() -> void: action_requested.emit(&"back"))
	%Back.focus_entered.connect(_select_back)
	%Back.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion and not event.relative.is_zero_approx(): _select_back())
	visibility_changed.connect(func() -> void: $Layer.visible = visible)
	resized.connect(_layout)

func present(page: StringName, context: String, reasons: Dictionary, slot: String, has_quick_save: bool, details: String = "") -> void:
	var changed_page := _page != page
	_page = page
	_refresh_hints()
	%Heading.text = {&"main": "Paused", &"settings": "Settings", &"saves": "Save & Load", &"help": "Help", &"about": "About Realmz Rebuilt", &"scenario_info": "Scenario details"}.get(page, "Paused")
	%DetailText.text = details
	%PackageStatus.text = context
	%PackageStatus.visible = page == &"main"
	%SaveContext.visible = page == &"saves"
	%SaveContext.text = "Current quick slot: %s" % slot
	%SaveNotice.visible = page == &"saves" and has_quick_save
	%SaveNotice.text = "Quicksave replaces slot %s." % slot
	%Back.visible = page != &"main"
	%Back.text = "Back" if _is_detail() else "Back to Pause"
	%Resume.visible = page == &"main"
	_actions.clear()
	if page == &"main": _actions.append(%Resume as PauseMenuAction)
	for container: Node in %Pages.get_children():
		var active := StringName(container.name.to_lower()) == page or container == %Details and _is_detail()
		(container as Control).visible = active
		if active:
			for child: Node in container.get_children():
				if child is PauseMenuAction: _actions.append(child)
	for action: PauseMenuAction in _actions:
		action.set_availability(String(reasons.get(action.action_id, "")))
		if action.action_id == &"quick_save": action.button.text = "Quicksave %s" % slot
		if action.action_id == &"quick_load": action.button.text = "Quickload %s" % slot
	_selected = int(_page_selection.get(page, 0))
	show()
	_layout()
	_select(clampi(_selected, 0, _actions.size() - (0 if %Back.visible else 1)))
	if changed_page and _is_detail(): %EntriesScroll.set_deferred("scroll_vertical", 0)

func apply_ui_sizing(profile: UiLayoutProfile) -> void:
	_profile = profile
	%Surface.theme = get_parent_control().theme
	_layout()

func reset_selection() -> void:
	_selected = 0
	_page_selection.clear()

func set_controller_prompts(family: String, preferences: ControllerPreferences) -> void:
	if family.is_empty():
		_controller_hints = ""
		_controller_detail_hints = ""
		if visible: _refresh_hints()
		return
	var confirm := ControllerBindingLabels.action(preferences, &"realmz_controller_confirm", family, ControllerBindingLabels.face(&"south", family))
	var back := ControllerBindingLabels.action(preferences, &"realmz_controller_back", family, ControllerBindingLabels.face(&"east", family))
	_controller_hints = "D-pad Navigate   %s Select   %s Back" % [confirm, back]
	_controller_detail_hints = "D-pad Scroll   %s Back" % back
	if visible: _refresh_hints()

func _is_detail() -> bool:
	return _page in [&"about", &"scenario_info"]

func _refresh_hints() -> void:
	if _is_detail(): %Hints.text = _controller_detail_hints if not _controller_detail_hints.is_empty() else "Up / Down  Scroll     Esc  Back"
	else: %Hints.text = _controller_hints if not _controller_hints.is_empty() else "Esc / Start  Resume     Enter  Select" if _page == &"main" else "Enter  Select     Esc  Back"

func move_selection(direction: Vector2i) -> void:
	if _is_detail():
		%EntriesScroll.scroll_vertical += direction.y * 48
		return
	if direction.y != 0: _select(clampi(_selected + direction.y, 0, _actions.size() - (0 if %Back.visible else 1)))

func activate_selected() -> void:
	if _selected == _actions.size() and %Back.visible: action_requested.emit(&"back")
	elif _selected >= 0 and _selected < _actions.size() and not _actions[_selected].button.disabled:
		action_requested.emit(_actions[_selected].action_id)

func selected_label() -> String:
	return %Back.text if _selected == _actions.size() else _actions[_selected].button.text if not _actions.is_empty() else ""

func _on_selected(id: StringName) -> void:
	if _selecting: return
	for index: int in _actions.size():
		if _actions[index].action_id == id:
			_select(index)
			return

func _select_back() -> void:
	if not _selecting: _select(_actions.size())

func _select(index: int) -> void:
	_selecting = true
	_selected = index
	_page_selection[_page] = index
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
	var margin := (24.0 if compact else 64.0) * scale
	var extent := Vector2(minf((752.0 if compact else preferred_width) * scale, area.size.x - margin * 2.0), area.size.y - margin * 2.0)
	%Surface.position = area.position + Vector2(margin, margin)
	%Surface.size = extent
