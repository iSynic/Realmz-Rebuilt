## Moves a HUD element while the adventure keeps running: hold Ctrl and drag. The layout
## previews under the pointer and the placement is saved when the button is released.

class_name HudLiveDrag
extends RefCounted

var _rectangles: Callable
var _apply: Callable
var _index := -1
var _draft: HudPreferences
var _grab := Vector2.ZERO
var _extent := Vector2.ZERO


## `rectangles` returns every movable element's rectangle in placement order (empty when
## hidden); `apply` takes the edited preferences and whether the drag has finished.
func _init(rectangles: Callable, apply: Callable) -> void:
	_rectangles = rectangles
	_apply = apply


func is_active() -> bool:
	return _index >= 0


## Returns true when the event belonged to a drag and must not reach the game.
func handle(event: InputEvent, pointer: Vector2, area: Rect2, ui_scale: float, current: HudPreferences) -> bool:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed and button.ctrl_pressed and _index < 0:
			return _begin(pointer, current)
		if not button.pressed and _index >= 0:
			HudPlacement.drop(_draft, _index, pointer - _grab, _extent, area, HudPlacement.SNAP_DISTANCE * ui_scale)
			_index = -1
			_apply.call(_draft, true)
			return true
	if event is InputEventMouseMotion and _index >= 0:
		HudPlacement.drop(_draft, _index, pointer - _grab, _extent, area, 0.0)
		_apply.call(_draft, false)
		return true
	return _index >= 0 and event is InputEventMouse


func _begin(pointer: Vector2, current: HudPreferences) -> bool:
	var rectangles: Array[Rect2] = _rectangles.call()
	for index: int in range(rectangles.size() - 1, -1, -1):
		if rectangles[index].has_point(pointer):
			_index = index
			_grab = pointer - rectangles[index].position
			_extent = rectangles[index].size
			_draft = current.duplicate_value()
			return true
	return false
