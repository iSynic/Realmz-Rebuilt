class_name DungeonMap3DPresenter
extends SubViewportContainer

@export var cell_span: float = 2.5
@export var wall_height: float = 2.2
@export var wall_thickness: float = 0.14

var _enabled: bool = false
var _projection: DungeonGeometryProjection
var _viewport: SubViewport
var _geometry_root: Node3D
var _camera: Camera3D
var _floor_material: StandardMaterial3D
var _wall_material: StandardMaterial3D
var _door_material: StandardMaterial3D
var _secret_material: StandardMaterial3D
var _feature_material: StandardMaterial3D
var _party_material: StandardMaterial3D


func _ready() -> void:
	position = Vector2(205.0, 58.0)
	size = Vector2(530.0, 452.0)
	z_index = 6
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	visible = false
	_floor_material = _material(Color(0.27, 0.25, 0.20))
	_wall_material = _material(Color(0.53, 0.55, 0.58))
	_door_material = _material(Color(0.64, 0.42, 0.20))
	_secret_material = _material(Color(0.45, 0.25, 0.54))
	_feature_material = _material(Color(0.62, 0.62, 0.57))
	_party_material = _material(Color(0.92, 0.70, 0.20))
	_viewport = SubViewport.new()
	_viewport.name = "DungeonViewport"
	_viewport.size = Vector2i(530, 452)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	_geometry_root = Node3D.new()
	_geometry_root.name = "TopologyGeometry"
	_viewport.add_child(_geometry_root)
	_camera = Camera3D.new()
	_camera.name = "DungeonCamera"
	_camera.fov = 58.0
	_viewport.add_child(_camera)
	var light := DirectionalLight3D.new()
	light.name = "DungeonLight"
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.light_energy = 1.4
	_viewport.add_child(light)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.027, 0.032)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.46, 0.48, 0.54)
	environment.ambient_light_energy = 0.55
	environment_node.environment = environment
	_viewport.add_child(environment_node)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_update_visibility()


func present(game_view: GameView) -> void:
	_projection = null
	if game_view != null and game_view.session_started:
		_projection = DungeonGeometryProjection.from_map_view(game_view.map_view)
	_rebuild_geometry()
	_update_visibility()


func is_active() -> bool:
	return _enabled and _projection != null


func projection() -> DungeonGeometryProjection:
	return _projection


func _update_visibility() -> void:
	visible = is_active()


func _rebuild_geometry() -> void:
	if _geometry_root == null:
		return
	for child: Node in _geometry_root.get_children():
		_geometry_root.remove_child(child)
		child.queue_free()
	if _projection == null:
		return
	for cell: DungeonGeometryProjection.CellProjection in _projection.cells():
		if cell.passable:
			_add_box("Floor_%d_%d" % [cell.coordinate.x, cell.coordinate.y], Vector3(cell_span * 0.94, 0.10, cell_span * 0.94), _cell_center(cell.coordinate) + Vector3(0.0, -0.08, 0.0), _floor_material)
		if cell.features.has(&"column"):
			_add_column(cell.coordinate)
		if cell.features.has(&"stairs"):
			_add_stairs(cell.coordinate)
	var built_edges: Dictionary = {}
	for edge: DungeonGeometryProjection.EdgeProjection in _projection.edges():
		if edge.kind == &"open" or built_edges.has(edge.canonical_key):
			continue
		built_edges[edge.canonical_key] = true
		if edge.kind in [&"door", &"archway"]:
			_add_door_frame(edge)
		else:
			_add_wall(edge, _secret_material if edge.kind == &"secret" else _wall_material)
	_add_party_marker()
	var target := _cell_center(_projection.party_coordinate) + Vector3(0.0, 0.65, 0.0)
	_camera.position = target + Vector3(5.6, 7.5, 7.8)
	_camera.look_at(target, Vector3.UP)


func _add_wall(edge: DungeonGeometryProjection.EdgeProjection, surface_material: Material) -> void:
	var horizontal := edge.direction in [&"north", &"south"]
	var box_dimensions := Vector3(cell_span, wall_height, wall_thickness) if horizontal else Vector3(wall_thickness, wall_height, cell_span)
	_add_box("Edge_%s" % edge.canonical_key, box_dimensions, _edge_center(edge.coordinate, edge.direction) + Vector3(0.0, wall_height * 0.5, 0.0), surface_material)


func _add_door_frame(edge: DungeonGeometryProjection.EdgeProjection) -> void:
	var horizontal := edge.direction in [&"north", &"south"]
	var center := _edge_center(edge.coordinate, edge.direction)
	var post_offset := cell_span * 0.37
	var post_size := Vector3(wall_thickness * 1.35, wall_height * 0.82, wall_thickness * 1.35)
	var left_offset := Vector3(post_offset, 0.0, 0.0) if horizontal else Vector3(0.0, 0.0, post_offset)
	_add_box("DoorPostA_%s" % edge.canonical_key, post_size, center - left_offset + Vector3(0.0, post_size.y * 0.5, 0.0), _door_material)
	_add_box("DoorPostB_%s" % edge.canonical_key, post_size, center + left_offset + Vector3(0.0, post_size.y * 0.5, 0.0), _door_material)
	var lintel_size := Vector3(cell_span, wall_thickness * 1.5, wall_thickness * 1.5) if horizontal else Vector3(wall_thickness * 1.5, wall_thickness * 1.5, cell_span)
	_add_box("DoorLintel_%s" % edge.canonical_key, lintel_size, center + Vector3(0.0, wall_height * 0.84, 0.0), _door_material)
	if edge.kind == &"door" and not edge.passable:
		var panel_size := Vector3(cell_span * 0.62, wall_height * 0.70, wall_thickness * 0.65) if horizontal else Vector3(wall_thickness * 0.65, wall_height * 0.70, cell_span * 0.62)
		_add_box("DoorPanel_%s" % edge.canonical_key, panel_size, center + Vector3(0.0, panel_size.y * 0.5, 0.0), _door_material)


func _add_column(coordinate: Vector2i) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.26
	mesh.bottom_radius = 0.31
	mesh.height = wall_height * 0.88
	var instance := MeshInstance3D.new()
	instance.name = "Column_%d_%d" % [coordinate.x, coordinate.y]
	instance.mesh = mesh
	instance.material_override = _feature_material
	instance.position = _cell_center(coordinate) + Vector3(0.0, mesh.height * 0.5, 0.0)
	_geometry_root.add_child(instance)


func _add_stairs(coordinate: Vector2i) -> void:
	for index: int in range(3):
		var height := 0.12 * float(index + 1)
		_add_box("Stair_%d_%d_%d" % [coordinate.x, coordinate.y, index], Vector3(cell_span * 0.62, height, cell_span * 0.20), _cell_center(coordinate) + Vector3(0.0, height * 0.5, (float(index) - 1.0) * cell_span * 0.20), _feature_material)


func _add_party_marker() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.24
	mesh.bottom_radius = 0.34
	mesh.height = 0.95
	var marker := MeshInstance3D.new()
	marker.name = "PartyMarker"
	marker.mesh = mesh
	marker.material_override = _party_material
	marker.position = _cell_center(_projection.party_coordinate) + Vector3(0.0, mesh.height * 0.5, 0.0)
	_geometry_root.add_child(marker)


func _add_box(node_name: String, box_size: Vector3, box_position: Vector3, surface_material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.name = node_name.validate_node_name()
	instance.mesh = mesh
	instance.material_override = surface_material
	instance.position = box_position
	_geometry_root.add_child(instance)


func _cell_center(coordinate: Vector2i) -> Vector3:
	return Vector3(float(coordinate.x) * cell_span, 0.0, float(coordinate.y) * cell_span)


func _edge_center(coordinate: Vector2i, direction: StringName) -> Vector3:
	var center := _cell_center(coordinate)
	match direction:
		&"north":
			center.z -= cell_span * 0.5
		&"east":
			center.x += cell_span * 0.5
		&"south":
			center.z += cell_span * 0.5
		&"west":
			center.x -= cell_span * 0.5
	return center


static func _material(color: Color) -> StandardMaterial3D:
	var surface_material := StandardMaterial3D.new()
	surface_material.albedo_color = color
	surface_material.roughness = 0.82
	return surface_material
