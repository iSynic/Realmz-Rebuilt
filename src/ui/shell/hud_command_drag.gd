## Moves a command button between the command bars, or to another place in its own bar:
## hold Alt and drag it. A ghost of the button follows the pointer until it is dropped.

class_name HudCommandDrag
extends RefCounted

const RANK := &"hud_command_rank"

var _grids: Callable
var _apply: Callable
var _ghost: TextureRect
var _button: ClassicBitmapButton


## `grids` returns the command bars' grids in bar order; `apply` takes the command id, the
## bar it was dropped on and its new rank there.
func _init(grids: Callable, apply: Callable, ghost: TextureRect) -> void:
	_grids = grids
	_apply = apply
	_ghost = ghost


## Returns true when the event belonged to a button drag and must not reach the game.
func handle(event: InputEvent, pointer: Vector2) -> bool:
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed and click.alt_pressed and _button == null:
			_button = _button_at(pointer)
			if _button == null:
				return false
			_ghost.texture = _button.radial_art_texture()
			_ghost.size = _button.size
			_ghost.global_position = pointer - _ghost.size * 0.5
			_ghost.show()
			_button.modulate.a = 0.35
			return true
		if not click.pressed and _button != null:
			_drop(pointer)
			return true
	if event is InputEventMouseMotion and _button != null:
		_ghost.global_position = pointer - _ghost.size * 0.5
		return true
	return _button != null and event is InputEventMouse


## Puts every ranked button of each grid in rank order.
static func order(grids: Array) -> void:
	for grid: GridContainer in grids:
		var ranked: Array[Node] = []
		for child: Node in grid.get_children():
			if child.has_meta(RANK) and (child as Control).visible: ranked.append(child)
		ranked.sort_custom(func(first: Node, second: Node) -> bool: return float(first.get_meta(RANK)) < float(second.get_meta(RANK)))
		for index: int in ranked.size():
			grid.move_child(ranked[index], index)


## The rank that moves `button` one place earlier (-1) or later (1) among its bar's buttons.
static func shifted_rank(button: Control, direction: int) -> float:
	var ranks: Array[float] = []
	var place := -1
	for child: Node in button.get_parent().get_children():
		if child.has_meta(RANK) and (child as Control).visible:
			if child == button: place = ranks.size()
			ranks.append(float(child.get_meta(RANK)))
	var target := place + direction
	if place < 0 or target < 0 or target >= ranks.size():
		return float(button.get_meta(RANK, 0.0))
	var outer := target + direction
	if outer < 0 or outer >= ranks.size():
		return ranks[target] + direction
	return (ranks[target] + ranks[outer]) * 0.5


func _button_at(pointer: Vector2) -> ClassicBitmapButton:
	for grid: GridContainer in _grids.call():
		for child: Node in grid.get_children():
			var button := child as ClassicBitmapButton
			if button != null and button.is_visible_in_tree() and button.get_global_rect().has_point(pointer):
				return button
	return null


func _drop(pointer: Vector2) -> void:
	var button := _button
	_button = null
	_ghost.hide()
	button.modulate.a = 1.0
	var grids: Array = _grids.call()
	for bar: int in grids.size():
		var grid := grids[bar] as GridContainer
		if not grid.is_visible_in_tree() or not grid.get_global_rect().grow(16.0).has_point(pointer):
			continue
		var before := NAN
		var after := NAN
		for child: Node in grid.get_children():
			var sibling := child as ClassicBitmapButton
			if sibling == null or sibling == button or not sibling.visible:
				continue
			var rectangle := sibling.get_global_rect()
			# Reading order: a button on a lower row, or further along this row, comes after.
			if pointer.y < rectangle.position.y or (pointer.y <= rectangle.end.y and pointer.x < rectangle.get_center().x):
				after = float(sibling.get_meta(RANK, 0.0))
				break
			before = float(sibling.get_meta(RANK, 0.0))
		var rank := 0.0
		if not is_nan(before) and not is_nan(after): rank = (before + after) * 0.5
		elif not is_nan(before): rank = before + 1.0
		elif not is_nan(after): rank = after - 1.0
		_apply.call(String(button.command_id), bar, rank)
		return
