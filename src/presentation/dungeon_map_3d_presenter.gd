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
const MOVE_TWEEN_SECONDS := 0.045
const TURN_TWEEN_SECONDS := 0.0
const MESH_CACHE_CAPACITY := 24

var _enabled: bool = false
var _projection: DungeonGeometryProjection
var _previous_projection: DungeonGeometryProjection
var _viewport: SubViewport
var _display: TextureRect
var _world: Node3D
var _geometry: MeshInstance3D
var _camera: Camera3D
var _active_tween: Tween
var _speed_percent: int = 100
var _reduced_motion: bool = false
var _mesh_cache: Dictionary = {}
var _mesh_cache_order: Array[String] = []
var _projection_geometry_cache: Dictionary = {}
var _projection_geometry_cache_order: Array[String] = []
var _geometry_rebuild_count: int = 0
var _geometry_cache_hit_count: int = 0
var _last_geometry_build_usec: int = 0
var _retained_map_id: String = ""
var _retained_coordinates: Dictionary = {}
var _retained_doorways: Dictionary = {}
var _retained_pillar_corners: Dictionary = {}
var _geometry_batches: Array[MeshInstance3D] = []
var _keyboard_direction: Vector2i = Vector2i.ZERO
var _navigation_cursor_enabled: bool = true
var _owns_navigation_cursor: bool = false
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
	_world = Node3D.new()
	_world.name = "DungeonWorld"
	_viewport.add_child(_world)
	_geometry = MeshInstance3D.new()
	_geometry.name = "DungeonSceneMesh"
	_world.add_child(_geometry)
	_camera = Camera3D.new()
	_camera.name = "DungeonCamera"
	_camera.fov = 70.0
	_camera.near = 0.04
	_camera.far = 12.0
	_camera.position = Vector3(0.0, 0.72, 0.0)
	_world.add_child(_camera)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.fog_enabled = true
	environment.fog_light_color = Color.BLACK
	environment.fog_density = 0.072
	environment_node.environment = environment
	_world.add_child(environment_node)
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


func _exit_tree() -> void:
	_clear_navigation_cursor()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_update_visibility()


func set_speed_percent(percent: int) -> void:
	_speed_percent = clampi(snappedi(percent, 25), 25, 400)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled and _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
		_snap_camera_to_projection()


func set_navigation_cursor_enabled(enabled: bool) -> void:
	if _navigation_cursor_enabled == enabled:
		return
	_navigation_cursor_enabled = enabled
	if not enabled:
		_clear_navigation_cursor()
		return
	if is_visible_in_tree():
		_set_navigation_cursor(_action_at_position(get_local_mouse_position()))


func present(game_view: GameView) -> void:
	_previous_projection = _projection
	_projection = null
	if game_view != null and game_view.session_started:
		var source_key := _projection_source_key(game_view.map_view)
		_projection = DungeonGeometryProjection.from_map_view(game_view.map_view, _projection_geometry_cache.get(source_key) as DungeonGeometryProjection)
		if _projection != null:
			_store_projection_geometry(source_key, _projection)
	_rebuild_geometry(game_view.map_view if game_view != null else null)
	_update_visibility()
	_animate_authoritative_change()


func _projection_source_key(map_view: MapView) -> String:
	if map_view == null:
		return ""
	return "%s:%d" % [map_view.map_id, DungeonGeometryProjection.geometry_source_id_for(map_view)]


func _store_projection_geometry(source_key: String, projection: DungeonGeometryProjection) -> void:
	if source_key.is_empty():
		return
	_projection_geometry_cache[source_key] = projection
	_projection_geometry_cache_order.erase(source_key)
	_projection_geometry_cache_order.append(source_key)
	while _projection_geometry_cache_order.size() > MESH_CACHE_CAPACITY:
		_projection_geometry_cache.erase(_projection_geometry_cache_order.pop_front())


func is_active() -> bool:
	return _enabled and _projection != null


func projection() -> DungeonGeometryProjection:
	return _projection


func _gui_input(event: InputEvent) -> void:
	if not is_active() or not _navigation_cursor_enabled:
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


func _rebuild_geometry(map_view: MapView) -> void:
	if _geometry == null:
		return
	if _projection == null:
		_clear_retained_geometry()
		return
	if map_view != null and not map_view.uses_los:
		_retain_world_geometry(map_view)
		return
	_clear_retained_geometry(false)
	var cache_key := _projection.geometry_cache_key()
	var cached := _mesh_cache.get(cache_key) as ArrayMesh
	if cached != null:
		_geometry_cache_hit_count += 1
		_touch_mesh_cache_key(cache_key)
		_geometry.mesh = cached
		_last_geometry_build_usec = 0
		return
	var started := Time.get_ticks_usec()
	var built := MeshBuilder.build(_projection, _atlas)
	_last_geometry_build_usec = Time.get_ticks_usec() - started
	_geometry_rebuild_count += 1
	_geometry.mesh = built
	_mesh_cache[cache_key] = built
	_mesh_cache_order.append(cache_key)
	while _mesh_cache_order.size() > MESH_CACHE_CAPACITY:
		_mesh_cache.erase(_mesh_cache_order.pop_front())


func _retain_world_geometry(map_view: MapView) -> void:
	var delta := map_view.presentation_delta as MapPresentationDelta
	if _retained_map_id == _projection.map_id and _previous_projection != null and _previous_projection.geometry_source_id == _projection.geometry_source_id:
		_geometry_cache_hit_count += 1
		_last_geometry_build_usec = 0
		return
	var extends_current := _retained_map_id == _projection.map_id and _previous_projection != null and delta != null and not delta.complete_window_rebuild and delta.matches(_previous_projection.map_id, _previous_projection.party_coordinate, _projection.party_coordinate)
	if not extends_current:
		_clear_retained_geometry()
		_retained_map_id = _projection.map_id
		var all_coordinates: Dictionary = {}
		for cell: MapCellView in _projection.source_cells():
			all_coordinates[cell.coordinate] = true
		_add_world_geometry_batch(all_coordinates, true)
		return
	var entering: Dictionary = {}
	for coordinate: Vector2i in delta.entered:
		if not _retained_coordinates.has(coordinate) and _projection.source_cell_at(coordinate) != null:
			entering[coordinate] = true
	if entering.is_empty():
		_geometry_cache_hit_count += 1
		_last_geometry_build_usec = 0
		return
	_add_world_geometry_batch(entering, false)


func _add_world_geometry_batch(coordinates: Dictionary, primary: bool) -> void:
	var started := Time.get_ticks_usec()
	var built := MeshBuilder.build_world_batch(_projection, _atlas, coordinates, _retained_doorways, _retained_pillar_corners)
	_last_geometry_build_usec = Time.get_ticks_usec() - started
	_geometry_rebuild_count += 1
	for coordinate: Vector2i in coordinates:
		_retained_coordinates[coordinate] = true
	if primary:
		_geometry.mesh = built
		return
	var batch := MeshInstance3D.new()
	batch.name = "DungeonScenePatch%d" % _geometry_batches.size()
	batch.mesh = built
	_world.add_child(batch)
	_geometry_batches.append(batch)


func _clear_retained_geometry(clear_primary: bool = true) -> void:
	for batch: MeshInstance3D in _geometry_batches:
		if is_instance_valid(batch):
			if batch.get_parent() != null:
				batch.get_parent().remove_child(batch)
			batch.queue_free()
	_geometry_batches.clear()
	_retained_map_id = ""
	_retained_coordinates.clear()
	_retained_doorways.clear()
	_retained_pillar_corners.clear()
	if clear_primary and _geometry != null:
		_geometry.mesh = null


func _touch_mesh_cache_key(cache_key: String) -> void:
	_mesh_cache_order.erase(cache_key)
	_mesh_cache_order.append(cache_key)


func _animate_authoritative_change() -> void:
	if _projection == null or _camera == null:
		return
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	var target_yaw := heading_yaw(_projection.heading)
	if _reduced_motion:
		_snap_camera_to_projection()
		return
	if _previous_projection != null and _previous_projection.map_id == _projection.map_id:
		var movement := _projection.party_coordinate - _previous_projection.party_coordinate
		if absi(movement.x) + absi(movement.y) == 1 and _previous_projection.heading == _projection.heading:
			_camera.rotation = Vector3(0.0, target_yaw, 0.0)
			_start_camera_tween(&"position", camera_position_for(_projection.party_coordinate), transition_duration(MOVE_TWEEN_SECONDS, _speed_percent))
			return
		if _previous_projection.party_coordinate == _projection.party_coordinate and _previous_projection.heading != _projection.heading:
			_camera.position = camera_position_for(_projection.party_coordinate)
			var current_yaw := heading_yaw(_previous_projection.heading)
			_camera.rotation = Vector3(0.0, current_yaw, 0.0)
			var turn_duration := transition_duration(TURN_TWEEN_SECONDS, _speed_percent)
			if is_zero_approx(turn_duration):
				_camera.rotation = Vector3(0.0, target_yaw, 0.0)
			else:
				_start_camera_tween(&"rotation:y", current_yaw + wrapf(target_yaw - current_yaw, -PI, PI), turn_duration)
			return
	_snap_camera_to_projection()


func _snap_camera_to_projection() -> void:
	if _camera == null or _projection == null:
		return
	_camera.position = camera_position_for(_projection.party_coordinate)
	_camera.rotation = Vector3(0.0, heading_yaw(_projection.heading), 0.0)


func _start_camera_tween(property: StringName, target: Variant, duration: float) -> void:
	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_QUAD)
	_active_tween.set_ease(Tween.EASE_IN_OUT)
	_active_tween.tween_property(_camera, NodePath(property), target, duration)


func geometry_rebuild_count() -> int:
	return _geometry_rebuild_count


func geometry_cache_hit_count() -> int:
	return _geometry_cache_hit_count


func last_geometry_build_usec() -> int:
	return _last_geometry_build_usec


static func transition_duration(base_seconds: float, speed_percent: int) -> float:
	return base_seconds * 100.0 / float(clampi(speed_percent, 25, 400))


static func camera_position_for(coordinate: Vector2i) -> Vector3:
	return Vector3(float(coordinate.x), 0.72, float(coordinate.y))


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
	if not _navigation_cursor_enabled:
		_clear_navigation_cursor()
		return
	match action:
		&"forward": _install_navigation_cursor(_cursor_forward, Vector2(8.0, 0.0))
		&"reverse": _install_navigation_cursor(_cursor_reverse, Vector2(8.0, 15.0))
		&"turn_left": _install_navigation_cursor(_cursor_left, Vector2(0.0, 8.0))
		&"turn_right": _install_navigation_cursor(_cursor_right, Vector2(15.0, 8.0))
		_: _clear_navigation_cursor()


func _install_navigation_cursor(texture: Texture2D, hotspot: Vector2) -> void:
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, hotspot)
	_owns_navigation_cursor = true


func _clear_navigation_cursor() -> void:
	if not _owns_navigation_cursor:
		return
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	_owns_navigation_cursor = false


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
