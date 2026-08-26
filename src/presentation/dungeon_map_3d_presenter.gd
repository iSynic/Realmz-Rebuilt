class_name DungeonMap3DPresenter
extends Control

signal turn_requested(delta: int)
signal movement_requested(direction: Vector2i)
signal movement_hold_started(direction: Vector2i)
signal movement_hold_stopped

const MeshBuilder := preload("res://src/presentation/dungeon_scene_mesh_builder.gd")
const ATLAS_PATH := "res://src/presentation/assets/classic-dungeon/classic-dungeon-atlas.png"
const CURSOR_FORWARD_PATH := "res://src/presentation/assets/classic-dungeon/cursor-forward.png"
const CURSOR_REVERSE_PATH := "res://src/presentation/assets/classic-dungeon/cursor-reverse.png"
const CURSOR_LEFT_PATH := "res://src/presentation/assets/classic-dungeon/cursor-left.png"
const CURSOR_RIGHT_PATH := "res://src/presentation/assets/classic-dungeon/cursor-right.png"
const INTERNAL_SIZE := Vector2i(400, 225)
const MOVE_TWEEN_SECONDS := 0.14
const TURN_TWEEN_SECONDS := 0.11

var _enabled: bool = false
var _projection: DungeonGeometryProjection
var _previous_projection: DungeonGeometryProjection
var _viewport: SubViewport
var _display: TextureRect
var _geometry: MeshInstance3D
var _camera: Camera3D
var _active_tween: Tween
var _keyboard_direction: Vector2i = Vector2i.ZERO
var _atlas: Texture2D = load(ATLAS_PATH) as Texture2D
var _cursor_forward: Texture2D = load(CURSOR_FORWARD_PATH) as Texture2D
var _cursor_reverse: Texture2D = load(CURSOR_REVERSE_PATH) as Texture2D
var _cursor_left: Texture2D = load(CURSOR_LEFT_PATH) as Texture2D
var _cursor_right: Texture2D = load(CURSOR_RIGHT_PATH) as Texture2D


func _ready() -> void:
	z_index = 6
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	visible = false
	_viewport = SubViewport.new()
	_viewport.name = "DungeonViewport"
	_viewport.size = INTERNAL_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var world := Node3D.new()
	world.name = "DungeonWorld"
	_viewport.add_child(world)
	_geometry = MeshInstance3D.new()
	_geometry.name = "DungeonSceneMesh"
	world.add_child(_geometry)
	_camera = Camera3D.new()
	_camera.name = "DungeonCamera"
	_camera.fov = 70.0
	_camera.near = 0.04
	_camera.far = 12.0
	_camera.position = Vector3(0.0, 0.72, 0.0)
	world.add_child(_camera)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.fog_enabled = true
	environment.fog_light_color = Color.BLACK
	environment.fog_density = 0.072
	environment_node.environment = environment
	world.add_child(environment_node)
	_display = TextureRect.new()
	_display.name = "DungeonDisplay"
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.texture = _viewport.get_texture()
	add_child(_display)
	resized.connect(_layout_internal_view)
	mouse_exited.connect(_clear_navigation_cursor)
	_layout_internal_view()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_update_visibility()


func present(game_view: GameView) -> void:
	_previous_projection = _projection
	_projection = null
	if game_view != null and game_view.session_started:
		_projection = DungeonGeometryProjection.from_map_view(game_view.map_view)
	_rebuild_geometry()
	_update_visibility()
	_animate_authoritative_change()


func is_active() -> bool:
	return _enabled and _projection != null


func projection() -> DungeonGeometryProjection:
	return _projection


func _gui_input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventMouseMotion:
		_set_navigation_cursor(_action_at_position(event.position))
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	var action := _action_at_position(mouse_event.position)
	if action.is_empty():
		return
	accept_event()
	_request_navigation(action, false)


func handle_keyboard_press(direction: Vector2i) -> void:
	var action := action_for_direction(direction)
	if action == &"":
		return
	_keyboard_direction = direction if action == &"forward" or action == &"reverse" else Vector2i.ZERO
	_request_navigation(action, true)


func handle_keyboard_release(direction: Vector2i) -> bool:
	if direction != _keyboard_direction:
		return false
	_keyboard_direction = Vector2i.ZERO
	movement_hold_stopped.emit()
	return true


func _request_navigation(action: StringName, held: bool) -> void:
	var turn := turn_delta(action)
	if turn != 0:
		turn_requested.emit(turn)
		return
	if _projection == null:
		return
	var movement := relative_movement(_projection.heading, action)
	if movement == Vector2i.ZERO:
		return
	if held:
		movement_hold_started.emit(movement)
	else:
		movement_requested.emit(movement)


func _update_visibility() -> void:
	visible = is_active()
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	if not visible:
		_clear_navigation_cursor()


func _rebuild_geometry() -> void:
	if _geometry == null:
		return
	_geometry.mesh = null if _projection == null else MeshBuilder.build(_projection, _atlas)


func _animate_authoritative_change() -> void:
	if _projection == null or _camera == null:
		return
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	var target_yaw := heading_yaw(_projection.heading)
	if _previous_projection != null and _previous_projection.map_id == _projection.map_id:
		var offset := _previous_projection.party_coordinate - _projection.party_coordinate
		if absi(offset.x) + absi(offset.y) == 1 and _previous_projection.heading == _projection.heading:
			_camera.position = Vector3(float(offset.x), 0.72, float(offset.y))
			_camera.rotation = Vector3(0.0, target_yaw, 0.0)
			_start_camera_tween(&"position", Vector3(0.0, 0.72, 0.0), MOVE_TWEEN_SECONDS)
			return
		if _previous_projection.party_coordinate == _projection.party_coordinate and _previous_projection.heading != _projection.heading:
			_camera.position = Vector3(0.0, 0.72, 0.0)
			var current_yaw := heading_yaw(_previous_projection.heading)
			_camera.rotation = Vector3(0.0, current_yaw, 0.0)
			_start_camera_tween(&"rotation:y", current_yaw + wrapf(target_yaw - current_yaw, -PI, PI), TURN_TWEEN_SECONDS)
			return
	_camera.position = Vector3(0.0, 0.72, 0.0)
	_camera.rotation = Vector3(0.0, target_yaw, 0.0)


func _start_camera_tween(property: StringName, target: Variant, duration: float) -> void:
	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_QUAD)
	_active_tween.set_ease(Tween.EASE_IN_OUT)
	_active_tween.tween_property(_camera, NodePath(property), target, duration)


func _layout_internal_view() -> void:
	if _display == null:
		return
	var available_scale := minf(size.x / float(INTERNAL_SIZE.x), size.y / float(INTERNAL_SIZE.y))
	var display_scale := float(floori(available_scale)) if available_scale >= 1.0 else (0.5 if available_scale >= 0.5 else 0.25)
	var display_size := Vector2(INTERNAL_SIZE) * display_scale
	_display.size = display_size
	_display.position = (size - display_size) * 0.5


func _action_at_position(local_position: Vector2) -> StringName:
	if _display == null or not Rect2(_display.position, _display.size).has_point(local_position):
		return &""
	var position_in_display := local_position - _display.position
	var horizontal_third := _display.size.x / 3.0
	if position_in_display.x < horizontal_third:
		return &"turn_left"
	if position_in_display.x >= horizontal_third * 2.0:
		return &"turn_right"
	return &"forward" if position_in_display.y < _display.size.y * (2.0 / 3.0) else &"reverse"


func _set_navigation_cursor(action: StringName) -> void:
	match action:
		&"forward": Input.set_custom_mouse_cursor(_cursor_forward, Input.CURSOR_ARROW, Vector2(8.0, 0.0))
		&"reverse": Input.set_custom_mouse_cursor(_cursor_reverse, Input.CURSOR_ARROW, Vector2(8.0, 15.0))
		&"turn_left": Input.set_custom_mouse_cursor(_cursor_left, Input.CURSOR_ARROW, Vector2(0.0, 8.0))
		&"turn_right": Input.set_custom_mouse_cursor(_cursor_right, Input.CURSOR_ARROW, Vector2(15.0, 8.0))
		_: _clear_navigation_cursor()


func _clear_navigation_cursor() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


static func heading_yaw(heading: int) -> float:
	match DungeonGeometryProjection.normalize_heading(heading):
		DungeonGeometryProjection.HEADING_EAST: return -PI * 0.5
		DungeonGeometryProjection.HEADING_SOUTH: return PI
		DungeonGeometryProjection.HEADING_WEST: return PI * 0.5
	return 0.0


static func relative_movement(heading: int, action: StringName) -> Vector2i:
	var forward := DungeonGeometryProjection.heading_vector(heading)
	if action == &"forward":
		return forward
	if action == &"reverse":
		return -forward
	return Vector2i.ZERO


static func turn_delta(action: StringName) -> int:
	return -1 if action == &"turn_left" else 1 if action == &"turn_right" else 0


static func action_for_direction(direction: Vector2i) -> StringName:
	match direction:
		Vector2i.UP: return &"forward"
		Vector2i.DOWN: return &"reverse"
		Vector2i.LEFT: return &"turn_left"
		Vector2i.RIGHT: return &"turn_right"
	return &""
