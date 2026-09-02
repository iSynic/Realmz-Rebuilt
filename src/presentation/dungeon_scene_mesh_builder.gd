class_name DungeonSceneMeshBuilder
extends RefCounted

const ATLAS_SIZE := Vector2(512.0, 512.0)
const WALL_UV := Rect2(1024.0, 0.0, 512.0, 512.0)
const DOOR_UV := Rect2(86.0, 0.0, 84.0, 144.0)
const STAIR_UV := Rect2(192.0, 0.0, 128.0, 128.0)
const ARCH_JAMB_UV := Rect2(1024.0, 0.0, 256.0, 512.0)
const ARCH_LINTEL_UV := Rect2(1024.0, 0.0, 512.0, 128.0)
const FLOOR_TEXTURE_ORIGIN := Vector2(1536.0, 0.0)
const FLOOR_SOURCE_TILE_SIZE := 128.0
const FLOOR_SOURCE_COLUMNS := 4
const PILLAR_UV := Rect2(1664.0, 0.0, 128.0, 512.0)
const ROOM_HEIGHT := 1.5
const ARCHWAY_OPENING_WIDTH := 0.64
const ARCHWAY_HEADER_HEIGHT := 0.24
const ARCHWAY_FRAME_DEPTH := 0.12
const WALL_TEXTURE_PATH := "res://src/presentation/assets/classic-dungeon/wall-sand-bricks.jpg"
const FLOOR_TEXTURE_PATH := "res://src/presentation/assets/classic-dungeon/floor-sand.jpg"

static var _shared_material: ShaderMaterial
static var _shared_atlas_id := 0


class MeshBuffers:
	extends RefCounted

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()


static func build(projection: DungeonGeometryProjection, atlas: Texture2D) -> ArrayMesh:
	return _build(projection, atlas, {}, false, {}, {})


static func build_world_batch(projection: DungeonGeometryProjection, atlas: Texture2D, coordinates: Dictionary, built_doorways: Dictionary, built_pillar_corners: Dictionary) -> ArrayMesh:
	return _build(projection, atlas, coordinates, true, built_doorways, built_pillar_corners)


static func _build(projection: DungeonGeometryProjection, atlas: Texture2D, coordinates: Dictionary, world_space: bool, built_doorways: Dictionary, pillar_corners: Dictionary) -> ArrayMesh:
	if projection == null or atlas == null:
		return null
	var surface := MeshBuffers.new()
	var material := _material_for_atlas(atlas)
	material.set_shader_parameter("scene_brightness", 0.70 if projection.dark else 1.0)
	var cells := projection.source_cells()
	for cell: MapCellView in cells:
		if not cell.passable:
			continue
		var includes_cell := coordinates.is_empty() or coordinates.has(cell.coordinate)
		var completes_entering_boundary := false
		if world_space and not includes_cell:
			for direction: StringName in DungeonGeometryProjection.DIRECTIONS:
				if coordinates.has(cell.coordinate + DungeonGeometryProjection.direction_vector(direction)) and projection.edge_kind_at(cell.coordinate, direction) == &"open":
					completes_entering_boundary = true
					break
		if not includes_cell and not completes_entering_boundary:
			continue
		var offset := cell.coordinate - projection.party_coordinate
		var center := Vector3(float(cell.coordinate.x), 0.0, float(cell.coordinate.y)) if world_space else Vector3(float(offset.x), 0.0, float(offset.y))
		var color := Color.WHITE
		var features := cell.features()
		if includes_cell:
			if features.has(&"stairs"):
				_add_recessed_stair(surface, center, cell.coordinate, color)
			else:
				_add_floor_and_ceiling(surface, center, cell.coordinate, color)
			if features.has(&"door") and offset != Vector2i.ZERO:
				var vertical_door := cell.feature_orientation(&"door") == &"vertical"
				_add_doorway(surface, cell_door_center(offset, vertical_door), vertical_door, false, color, false)
		for direction: StringName in DungeonGeometryProjection.DIRECTIONS:
			var direction_vector := DungeonGeometryProjection.direction_vector(direction)
			if not includes_cell and (not coordinates.has(cell.coordinate + direction_vector) or projection.edge_kind_at(cell.coordinate, direction) != &"open"):
				continue
			var edge_kind := projection.edge_kind_at(cell.coordinate, direction)
			var neighbor := projection.source_cell_at(cell.coordinate + direction_vector)
			if world_space and neighbor == null and edge_kind == &"open":
				continue
			var entry_edge_kind := projection.edge_kind_at(neighbor.coordinate, direction) if neighbor != null else &""
			var movement_allowed := boundary_allows_movement(projection, cell.coordinate, direction)
			var edge_key := DungeonGeometryProjection.canonical_edge_key(cell.coordinate, direction)
			var boundary_kind := entry_edge_kind if entry_edge_kind == &"archway" else edge_kind
			if boundary_kind == &"archway":
				if not built_doorways.has(edge_key):
					built_doorways[edge_key] = true
					_add_doorway(surface, center + _edge_offset(direction), direction in [&"east", &"west"], true, boundary_color(offset, direction_vector), true)
				continue
			if not movement_allowed:
				_add_wall_boundary(surface, center, direction_vector, boundary_color(offset, direction_vector))
	for cell: MapCellView in cells:
		if not cell.passable or not cell.features().has(&"column") or not coordinates.is_empty() and not coordinates.has(cell.coordinate):
			continue
		var offset := cell.coordinate - projection.party_coordinate
		var center := Vector3(float(cell.coordinate.x), 0.0, float(cell.coordinate.y)) if world_space else Vector3(float(offset.x), 0.0, float(offset.y))
		for corner: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i.ONE, Vector2i(-1, 1)]:
			var corner_key := cell.coordinate * 2 + corner
			if pillar_corners.has(corner_key):
				continue
			pillar_corners[corner_key] = true
			_add_corner_pillar(surface, center + Vector3(float(corner.x), 0.0, float(corner.y)) * 0.44, Color.WHITE)
	var mesh := ArrayMesh.new()
	if surface.vertices.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = surface.vertices
	arrays[Mesh.ARRAY_NORMAL] = surface.normals
	arrays[Mesh.ARRAY_COLOR] = surface.colors
	arrays[Mesh.ARRAY_TEX_UV] = surface.uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


static func boundary_allows_movement(projection: DungeonGeometryProjection, source: Vector2i, direction: StringName) -> bool:
	var target := projection.source_cell_at(source + DungeonGeometryProjection.direction_vector(direction))
	return target != null and target.passable and projection.edge_passable_at(target.coordinate, direction)


static func cell_door_center(offset: Vector2i, vertical: bool) -> Vector3:
	var center := Vector3(float(offset.x), 0.0, float(offset.y))
	if vertical and offset.x != 0:
		center.x -= float(signi(offset.x)) * 0.5
	elif not vertical and offset.y != 0:
		center.z -= float(signi(offset.y)) * 0.5
	return center


static func boundary_color(offset: Vector2i, direction: Vector2i) -> Color:
	var midpoint := Vector2(offset) + Vector2(direction) * 0.5
	var distance := ceili(maxf(absf(midpoint.x), absf(midpoint.y)))
	return _distance_color(Vector2i(distance, 0))


static func _create_material(atlas: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque, unshaded;
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D wall_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D floor_texture : source_color, filter_nearest, repeat_disable;
uniform float scene_brightness = 1.0;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float distance_fade(float distance) {
	if (distance < 0.75) return 1.0;
	if (distance < 1.75) return 0.92;
	if (distance < 2.75) return 0.78;
	if (distance < 3.75) return 0.62;
	if (distance < 4.75) return 0.47;
	if (distance < 5.75) return 0.37;
	return 0.30;
}
void fragment() {
	vec3 sampled;
	bool sand_surface = false;
	if (UV.x >= 3.0) {
		sampled = texture(floor_texture, vec2(UV.x - 3.0, UV.y)).rgb;
		sand_surface = true;
	} else if (UV.x >= 2.0) {
		sampled = texture(wall_texture, vec2(UV.x - 2.0, UV.y)).rgb;
		sand_surface = true;
	} else {
		sampled = texture(atlas, UV).rgb;
	}
	if (sand_surface) {
		sampled *= vec3(0.94, 1.06, 0.92);
	}
	vec3 mac_color = floor(sampled * 15.0 + 0.5) / 15.0;
	vec3 camera_delta = abs(world_position - CAMERA_POSITION_WORLD);
	float shade = floor(distance_fade(max(camera_delta.x, camera_delta.z)) * scene_brightness * 15.0 + 0.5) / 15.0;
	ALBEDO = mac_color * shade;
	ROUGHNESS = 1.0;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("atlas", atlas)
	material.set_shader_parameter("wall_texture", load(WALL_TEXTURE_PATH) as Texture2D)
	material.set_shader_parameter("floor_texture", load(FLOOR_TEXTURE_PATH) as Texture2D)
	return material


static func _material_for_atlas(atlas: Texture2D) -> ShaderMaterial:
	var atlas_id := atlas.get_instance_id()
	if _shared_material == null or _shared_atlas_id != atlas_id:
		_shared_material = _create_material(atlas)
		_shared_atlas_id = atlas_id
	return _shared_material


static func _add_floor_and_ceiling(surface: MeshBuffers, center: Vector3, coordinate: Vector2i, color: Color) -> void:
	var uv := floor_tile_uv(coordinate)
	_add_inward_quad(surface, center + Vector3(-0.5, 0.0, -0.5), center + Vector3(-0.5, 0.0, 0.5), center + Vector3(0.5, 0.0, 0.5), center + Vector3(0.5, 0.0, -0.5), uv, color)
	_add_inward_quad(surface, center + Vector3(-0.5, ROOM_HEIGHT, 0.5), center + Vector3(-0.5, ROOM_HEIGHT, -0.5), center + Vector3(0.5, ROOM_HEIGHT, -0.5), center + Vector3(0.5, ROOM_HEIGHT, 0.5), uv, color)


static func _add_wall_boundary(surface: MeshBuffers, center: Vector3, direction: Vector2i, color: Color) -> void:
	if direction == Vector2i.UP:
		_add_inward_quad(surface, center + Vector3(-0.5, 0.0, -0.5), center + Vector3(0.5, 0.0, -0.5), center + Vector3(0.5, ROOM_HEIGHT, -0.5), center + Vector3(-0.5, ROOM_HEIGHT, -0.5), WALL_UV, color)
	elif direction == Vector2i.DOWN:
		_add_inward_quad(surface, center + Vector3(0.5, 0.0, 0.5), center + Vector3(-0.5, 0.0, 0.5), center + Vector3(-0.5, ROOM_HEIGHT, 0.5), center + Vector3(0.5, ROOM_HEIGHT, 0.5), WALL_UV, color)
	elif direction == Vector2i.LEFT:
		_add_inward_quad(surface, center + Vector3(-0.5, 0.0, 0.5), center + Vector3(-0.5, 0.0, -0.5), center + Vector3(-0.5, ROOM_HEIGHT, -0.5), center + Vector3(-0.5, ROOM_HEIGHT, 0.5), WALL_UV, color)
	else:
		_add_inward_quad(surface, center + Vector3(0.5, 0.0, -0.5), center + Vector3(0.5, 0.0, 0.5), center + Vector3(0.5, ROOM_HEIGHT, 0.5), center + Vector3(0.5, ROOM_HEIGHT, -0.5), WALL_UV, color)


static func _add_corner_pillar(surface: MeshBuffers, corner_position: Vector3, color: Color) -> void:
	_add_box(surface, corner_position + Vector3(0.0, ROOM_HEIGHT * 0.5, 0.0), Vector3(0.10, ROOM_HEIGHT, 0.10), PILLAR_UV, color)
	for height: float in [0.035, ROOM_HEIGHT - 0.035]:
		_add_box(surface, corner_position + Vector3(0.0, height, 0.0), Vector3(0.14, 0.07, 0.14), PILLAR_UV, color)


static func _add_doorway(surface: MeshBuffers, center: Vector3, east_west: bool, door_open: bool, color: Color, archway: bool) -> void:
	if archway:
		_add_archway(surface, center, east_west, color)
		return
	var wing_size := Vector3(0.14, ROOM_HEIGHT, 0.16)
	var wing_a := center + Vector3(-0.43, ROOM_HEIGHT * 0.5, 0.0)
	var wing_b := center + Vector3(0.43, ROOM_HEIGHT * 0.5, 0.0)
	var header_size := Vector3(0.72, ROOM_HEIGHT - 1.23, 0.16)
	if east_west:
		wing_size = Vector3(0.16, ROOM_HEIGHT, 0.14)
		wing_a = center + Vector3(0.0, ROOM_HEIGHT * 0.5, -0.43)
		wing_b = center + Vector3(0.0, ROOM_HEIGHT * 0.5, 0.43)
		header_size = Vector3(0.16, ROOM_HEIGHT - 1.23, 0.72)
	_add_box(surface, wing_a, wing_size, WALL_UV, color)
	_add_box(surface, wing_b, wing_size, WALL_UV, color)
	_add_box(surface, center + Vector3(0.0, (ROOM_HEIGHT + 1.23) * 0.5, 0.0), header_size, WALL_UV, color)
	if not door_open:
		_add_door(surface, center, east_west, color)


static func _add_archway(surface: MeshBuffers, center: Vector3, east_west: bool, color: Color) -> void:
	var jamb_width := (1.0 - ARCHWAY_OPENING_WIDTH) * 0.5
	var jamb_offset := (ARCHWAY_OPENING_WIDTH + jamb_width) * 0.5
	var jamb_size := Vector3(jamb_width, ROOM_HEIGHT, ARCHWAY_FRAME_DEPTH)
	var jamb_a := center + Vector3(-jamb_offset, ROOM_HEIGHT * 0.5, 0.0)
	var jamb_b := center + Vector3(jamb_offset, ROOM_HEIGHT * 0.5, 0.0)
	var lintel_size := Vector3(ARCHWAY_OPENING_WIDTH + jamb_width, ARCHWAY_HEADER_HEIGHT, ARCHWAY_FRAME_DEPTH)
	if east_west:
		jamb_size = Vector3(ARCHWAY_FRAME_DEPTH, ROOM_HEIGHT, jamb_width)
		jamb_a = center + Vector3(0.0, ROOM_HEIGHT * 0.5, -jamb_offset)
		jamb_b = center + Vector3(0.0, ROOM_HEIGHT * 0.5, jamb_offset)
		lintel_size = Vector3(ARCHWAY_FRAME_DEPTH, ARCHWAY_HEADER_HEIGHT, ARCHWAY_OPENING_WIDTH + jamb_width)
	_add_box(surface, jamb_a, jamb_size, ARCH_JAMB_UV, color)
	_add_box(surface, jamb_b, jamb_size, ARCH_JAMB_UV, color)
	_add_box(surface, center + Vector3(0.0, ROOM_HEIGHT - ARCHWAY_HEADER_HEIGHT * 0.5, 0.0), lintel_size, ARCH_LINTEL_UV, color)


static func _add_door(surface: MeshBuffers, center: Vector3, east_west: bool, color: Color) -> void:
	if east_west:
		_add_two_sided_quad(surface, center + Vector3(0.0, 0.0, -0.36), center + Vector3(0.0, 0.0, 0.36), center + Vector3(0.0, 1.23, 0.36), center + Vector3(0.0, 1.23, -0.36), DOOR_UV, color)
	else:
		_add_two_sided_quad(surface, center + Vector3(-0.36, 0.0, 0.0), center + Vector3(0.36, 0.0, 0.0), center + Vector3(0.36, 1.23, 0.0), center + Vector3(-0.36, 1.23, 0.0), DOOR_UV, color)


static func _add_recessed_stair(surface: MeshBuffers, center: Vector3, coordinate: Vector2i, color: Color) -> void:
	_add_inward_quad(surface, center + Vector3(-0.5, -0.28, -0.5), center + Vector3(-0.5, -0.28, 0.5), center + Vector3(0.5, -0.28, 0.5), center + Vector3(0.5, -0.28, -0.5), STAIR_UV, color)
	_add_inward_quad(surface, center + Vector3(-0.5, ROOM_HEIGHT, 0.5), center + Vector3(-0.5, ROOM_HEIGHT, -0.5), center + Vector3(0.5, ROOM_HEIGHT, -0.5), center + Vector3(0.5, ROOM_HEIGHT, 0.5), floor_tile_uv(coordinate), color)
	for direction: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var tangent := Vector3(1.0, 0.0, 0.0) if direction.x == 0.0 else Vector3(0.0, 0.0, 1.0)
		var wall_center := center + Vector3(direction.x, 0.0, direction.y) * 0.5
		_add_two_sided_quad(surface, wall_center - tangent * 0.5 + Vector3(0.0, -0.28, 0.0), wall_center + tangent * 0.5 + Vector3(0.0, -0.28, 0.0), wall_center + tangent * 0.5, wall_center - tangent * 0.5, STAIR_UV, color)


static func _add_box(surface: MeshBuffers, center: Vector3, size: Vector3, uv_rect: Rect2, color: Color) -> void:
	var half := size * 0.5
	var x0 := center.x - half.x
	var x1 := center.x + half.x
	var y0 := center.y - half.y
	var y1 := center.y + half.y
	var z0 := center.z - half.z
	var z1 := center.z + half.z
	_add_quad(surface, Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), uv_rect, color)
	_add_quad(surface, Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x1, y1, z1), uv_rect, color)
	_add_quad(surface, Vector3(x0, y0, z1), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1), uv_rect, color)
	_add_quad(surface, Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), uv_rect, color)
	_add_quad(surface, Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), uv_rect, color)
	_add_quad(surface, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x0, y0, z0), uv_rect, color)


static func _add_quad(surface: MeshBuffers, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_rect: Rect2, color: Color) -> void:
	var u0 := uv_rect.position.x / ATLAS_SIZE.x
	var v0 := uv_rect.position.y / ATLAS_SIZE.y
	var u1 := uv_rect.end.x / ATLAS_SIZE.x
	var v1 := uv_rect.end.y / ATLAS_SIZE.y
	var normal := (b - a).cross(c - a).normalized()
	_append_vertex(surface, a, Vector2(u0, v1), normal, color)
	_append_vertex(surface, b, Vector2(u1, v1), normal, color)
	_append_vertex(surface, c, Vector2(u1, v0), normal, color)
	_append_vertex(surface, a, Vector2(u0, v1), normal, color)
	_append_vertex(surface, c, Vector2(u1, v0), normal, color)
	_append_vertex(surface, d, Vector2(u0, v0), normal, color)


static func _add_inward_quad(surface: MeshBuffers, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_rect: Rect2, color: Color) -> void:
	var u0 := uv_rect.position.x / ATLAS_SIZE.x
	var v0 := uv_rect.position.y / ATLAS_SIZE.y
	var u1 := uv_rect.end.x / ATLAS_SIZE.x
	var v1 := uv_rect.end.y / ATLAS_SIZE.y
	var normal := (d - a).cross(c - a).normalized()
	_append_vertex(surface, a, Vector2(u0, v1), normal, color)
	_append_vertex(surface, d, Vector2(u0, v0), normal, color)
	_append_vertex(surface, c, Vector2(u1, v0), normal, color)
	_append_vertex(surface, a, Vector2(u0, v1), normal, color)
	_append_vertex(surface, c, Vector2(u1, v0), normal, color)
	_append_vertex(surface, b, Vector2(u1, v1), normal, color)


static func _add_two_sided_quad(surface: MeshBuffers, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_rect: Rect2, color: Color) -> void:
	_add_quad(surface, a, b, c, d, uv_rect, color)
	_add_inward_quad(surface, a, b, c, d, uv_rect, color)


static func _append_vertex(surface: MeshBuffers, vertex: Vector3, uv: Vector2, normal: Vector3, color: Color) -> void:
	surface.vertices.append(vertex)
	surface.uvs.append(uv)
	surface.normals.append(normal)
	surface.colors.append(color)


static func _distance_color(offset: Vector2i) -> Color:
	var distance := maxi(absi(offset.x), absi(offset.y))
	var fade := 1.0
	match distance:
		1: fade = 0.92
		2: fade = 0.78
		3: fade = 0.62
		4: fade = 0.47
		5: fade = 0.37
		_: fade = 1.0 if distance == 0 else 0.30
	return Color(fade, fade, fade, 1.0)


static func floor_tile_uv(coordinate: Vector2i) -> Rect2:
	var source_cell := Vector2(posmod(coordinate.x, FLOOR_SOURCE_COLUMNS), posmod(coordinate.y, FLOOR_SOURCE_COLUMNS))
	return Rect2(FLOOR_TEXTURE_ORIGIN + source_cell * FLOOR_SOURCE_TILE_SIZE, Vector2.ONE * FLOOR_SOURCE_TILE_SIZE)


static func _edge_offset(direction: StringName) -> Vector3:
	match direction:
		&"north": return Vector3(0.0, 0.0, -0.5)
		&"east": return Vector3(0.5, 0.0, 0.0)
		&"south": return Vector3(0.0, 0.0, 0.5)
		&"west": return Vector3(-0.5, 0.0, 0.0)
	return Vector3.ZERO
