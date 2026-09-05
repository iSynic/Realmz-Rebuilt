## Owns battlefield camera focus, tactical aids, targeting, and input translation.

class_name BattlefieldInteractionController
extends RefCounted


signal combat_body_submitted(body: InteractionResponse.CombatBody)
signal combatant_inspected(combatant_id: String)
signal targeting_changed(selection: CombatTargetingState)
signal targeting_cancelled
signal redraw_requested

var movement_costs_visible: bool:
	get:
		return _movement_costs_visible
var hovered_coordinate: Vector2i:
	get:
		return _hovered_coordinate
var focused_combatant_id: String:
	get:
		return _camera_focus_id
var reveal_friends: bool:
	get:
		return _reveal_friends
var targeting: CombatTargetingState:
	get:
		return _targeting

var _view: GameView
var _movement_costs_visible: bool = false
var _hovered_coordinate := Vector2i(-1, -1)
var _camera_focus_id: String = ""
var _last_active_actor_id: String = ""
var _reveal_friends: bool = false
var _targeting: CombatTargetingState
var _playback_frame: CombatPlaybackFrame


func present(game_view: GameView) -> bool:
	var next_active_actor_id := ""
	if game_view != null and game_view.combat_view != null:
		next_active_actor_id = game_view.combat_view.active_actor_id
	var active_actor_changed := next_active_actor_id != _last_active_actor_id
	if active_actor_changed:
		_camera_focus_id = ""
	_last_active_actor_id = next_active_actor_id
	_view = game_view
	_playback_frame = null
	if _view == null or _view.combat_view == null:
		_movement_costs_visible = false
		_hovered_coordinate = Vector2i(-1, -1)
		_camera_focus_id = ""
		_last_active_actor_id = ""
		_reveal_friends = false
	elif not _camera_focus_id.is_empty() and BattlefieldPresentationGeometry.actor_position(_view.combat_view, _view.party_members, _camera_focus_id).x < 0:
		_camera_focus_id = ""
	return active_actor_changed


func playback_changed(previous: CombatPlaybackFrame, current: CombatPlaybackFrame) -> bool:
	if previous == null and current != null:
		_camera_focus_id = ""
	_playback_frame = current
	return current != previous and current != null and current.kind == &"actor_cue"


func set_movement_costs_visible(visible_costs: bool) -> void:
	if _movement_costs_visible == visible_costs:
		return
	_movement_costs_visible = visible_costs
	redraw_requested.emit()


func focus_combatant(combatant_id: String) -> void:
	_camera_focus_id = combatant_id
	redraw_requested.emit()


func toggle_reveal_friends() -> void:
	_reveal_friends = not _reveal_friends
	redraw_requested.emit()


func dismiss_reveal_friends() -> bool:
	if not _reveal_friends:
		return false
	_reveal_friends = false
	redraw_requested.emit()
	return true


func submit_movement_direction(direction: Vector2i) -> bool:
	if _playback_frame != null or _targeting != null:
		return false
	return _submit_movement_option(_movement_option_for_direction(direction))


func handle_input(event: InputEvent, viewport_size: Vector2, render_camera_top_left: Vector2i, render_camera_visible_cells: Vector2i) -> bool:
	if _playback_frame != null or _view == null or _view.combat_view == null or _view.combat_view.battlefield == null:
		return false
	if _targeting != null:
		return _handle_targeting_input(event, viewport_size, render_camera_top_left, render_camera_visible_cells)
	if event is InputEventMouseMotion:
		var hover_option := _movement_option_toward_local_position((event as InputEventMouseMotion).position, viewport_size, render_camera_top_left, render_camera_visible_cells)
		var next_hover := hover_option.destination if hover_option != null else Vector2i(-1, -1)
		if next_hover != _hovered_coordinate:
			_hovered_coordinate = next_hover
			redraw_requested.emit()
		return false
	if not event is InputEventMouseButton:
		return false
	var mouse_button := event as InputEventMouseButton
	if mouse_button.button_index != MOUSE_BUTTON_LEFT or not mouse_button.pressed:
		return false
	if dismiss_reveal_friends():
		return true
	if mouse_button.ctrl_pressed or mouse_button.meta_pressed:
		var inspected_id := BattlefieldPresentationGeometry.combatant_at(_view.combat_view, _view.party_members, _coordinate_at_local_position(mouse_button.position, viewport_size, render_camera_top_left, render_camera_visible_cells))
		if inspected_id.is_empty():
			return false
		focus_combatant(inspected_id)
		combatant_inspected.emit(inspected_id)
		return true
	return _submit_movement_option(_movement_option_toward_local_position(mouse_button.position, viewport_size, render_camera_top_left, render_camera_visible_cells))


func handle_mouse_exit() -> void:
	var changed := false
	if _hovered_coordinate != Vector2i(-1, -1):
		_hovered_coordinate = Vector2i(-1, -1)
		changed = true
	if _targeting != null and _targeting.selected_coordinate.x < 0 and _targeting.hovered_coordinate != Vector2i(-1, -1):
		_targeting.hovered_coordinate = Vector2i(-1, -1)
		changed = true
	if changed:
		redraw_requested.emit()


func begin_targeting(configuration: CombatTargetingRequest) -> bool:
	if _playback_frame != null or _view == null or _view.combat_view == null or configuration == null or not configuration.is_valid():
		return false
	_targeting = CombatTargetingState.new(configuration)
	_reveal_friends = false
	targeting_changed.emit(_targeting)
	redraw_requested.emit()
	return true


func confirm_targeting() -> bool:
	if _targeting == null:
		return false
	var body := _targeting.committed_body()
	if body == null:
		targeting_changed.emit(_targeting)
		return false
	_targeting = null
	redraw_requested.emit()
	combat_body_submitted.emit(body)
	return true


func cancel_targeting() -> bool:
	if _targeting == null:
		return false
	_targeting = null
	redraw_requested.emit()
	targeting_cancelled.emit()
	return true


func target_with_keyboard() -> bool:
	if _targeting == null or not _targeting.target_with_keyboard():
		return false
	if not _targeting.selected_ids.is_empty():
		_camera_focus_id = _targeting.selected_ids[-1]
	targeting_changed.emit(_targeting)
	redraw_requested.emit()
	return true


func rotate_targeting() -> bool:
	if _targeting == null or not _targeting.rotate_area():
		return false
	targeting_changed.emit(_targeting)
	redraw_requested.emit()
	return true


func _handle_targeting_input(event: InputEvent, viewport_size: Vector2, render_camera_top_left: Vector2i, render_camera_visible_cells: Vector2i) -> bool:
	if event is InputEventMouseMotion:
		_targeting.hovered_coordinate = _coordinate_at_local_position((event as InputEventMouseMotion).position, viewport_size, render_camera_top_left, render_camera_visible_cells)
		redraw_requested.emit()
		return false
	if not event is InputEventMouseButton or not (event as InputEventMouseButton).pressed:
		return false
	var mouse_button := event as InputEventMouseButton
	if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
		return cancel_targeting()
	if mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return false
	var coordinate := _coordinate_at_local_position(mouse_button.position, viewport_size, render_camera_top_left, render_camera_visible_cells)
	if coordinate.x < 0:
		return false
	if _targeting.mode in [&"area", &"coordinate_sequence"]:
		_targeting.select_coordinate(coordinate)
	else:
		var combatant_id := BattlefieldPresentationGeometry.combatant_at(_view.combat_view, _view.party_members, coordinate)
		_targeting.select_combatant(combatant_id)
	targeting_changed.emit(_targeting)
	redraw_requested.emit()
	return true


func _coordinate_at_local_position(local_position: Vector2, viewport_size: Vector2, render_camera_top_left: Vector2i, render_camera_visible_cells: Vector2i) -> Vector2i:
	var combat := _view.combat_view
	var active_position := BattlefieldPresentationGeometry.actor_position(combat, _view.party_members, combat.active_actor_id)
	if active_position.x < 0:
		active_position = combat.battlefield.party_anchor
	var visible_cells := BattlefieldPresentationGeometry.viewport_cells_for(viewport_size)
	return BattlefieldPresentationGeometry.coordinate_for_point(local_position, _camera_for_input(active_position, visible_cells, render_camera_top_left, render_camera_visible_cells), visible_cells, viewport_size)


func _movement_option_for_direction(direction: Vector2i) -> CombatMoveOptionView:
	if _view == null or _view.combat_view == null:
		return null
	for option: CombatMoveOptionView in _view.combat_view.movement_options:
		if option.direction == direction:
			return option
	return null


func _movement_option_toward_local_position(local_position: Vector2, viewport_size: Vector2, render_camera_top_left: Vector2i, render_camera_visible_cells: Vector2i) -> CombatMoveOptionView:
	if _view == null or _view.combat_view == null or _view.combat_view.battlefield == null:
		return null
	var combat := _view.combat_view
	var origin := BattlefieldPresentationGeometry.actor_position(combat, _view.party_members, combat.active_actor_id)
	var visible_cells := BattlefieldPresentationGeometry.viewport_cells_for(viewport_size)
	var camera := _camera_for_input(origin, visible_cells, render_camera_top_left, render_camera_visible_cells)
	var draw_origin := BattlefieldPresentationGeometry.battlefield_draw_origin(viewport_size, visible_cells)
	return _movement_option_for_direction(BattlefieldPresentationGeometry.click_direction_for_point(BattlefieldPresentationGeometry.cell_rect(origin, camera, draw_origin), local_position))


func _camera_for_input(fallback_focus: Vector2i, visible_cells: Vector2i, render_camera_top_left: Vector2i, render_camera_visible_cells: Vector2i) -> Vector2i:
	if render_camera_top_left.x >= 0 and render_camera_visible_cells == visible_cells:
		return render_camera_top_left
	return BattlefieldPresentationGeometry.camera_top_left(fallback_focus, visible_cells)


func _submit_movement_option(option: CombatMoveOptionView) -> bool:
	if option == null or not option.enabled or _view == null or _view.combat_view == null:
		return false
	var body := InteractionResponse.CombatBody.new(&"retreat_edge" if option.retreats_from_battle else &"move", _view.combat_view.active_actor_id)
	body.destination = option.destination
	body.has_destination = true
	combat_body_submitted.emit(body)
	return true
