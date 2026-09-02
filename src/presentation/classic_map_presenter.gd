class_name ClassicMapPresenter
extends Control

signal movement_hold_started(direction: Vector2i)
signal movement_hold_updated(direction: Vector2i)
signal movement_hold_stopped
const CLASSIC_VIEW_CELLS: Vector2i = Vector2i(15, 13)
const RETAINED_PROJECTION_MARGIN_CELLS: Vector2i = Vector2i.ONE
const CLASSIC_BATTLE_ATLAS_ID := "classic-battle-tiles-302"
const SECRET_LAND_MARKER_TILE_ID := 251
const PATH_LAND_MARKER_TILE_ID := 253
const PARTY_MARKER_LEFT_ASSET_ID: StringName = &"map.party.left"
const PARTY_MARKER_RIGHT_ASSET_ID: StringName = &"map.party.right"
const PARTY_MARKER_CAMP_ASSET_ID: StringName = &"map.party.camp"
const DUNGEON_PARTY_ARROWS_ASSET_ID: StringName = &"map.party.dungeon.arrows"
const PARTY_MARKER_ASSET_ID: StringName = PARTY_MARKER_RIGHT_ASSET_ID
const BOAT_MARKER_LEFT_ASSET_IDS: Dictionary = {0: &"map.party.boat.left.0", 3: &"map.party.boat.left.3", 5: &"map.party.boat.left.5", 6: &"map.party.boat.left.6", 7: &"map.party.boat.left.7"}
const BOAT_MARKER_RIGHT_ASSET_IDS: Dictionary = {0: &"map.party.boat.right.0", 3: &"map.party.boat.right.3", 5: &"map.party.boat.right.5", 6: &"map.party.boat.right.6", 7: &"map.party.boat.right.7"}
const SURROUND_TEXTURE_PATH := "res://src/presentation/assets/ui/classic-exploration-surround-tile.png"
const DARKNESS_MASK_SIZE := Vector2(320.0, 320.0)
const RetainedMapSurfaceScript := preload("res://src/presentation/classic_retained_map_surface.gd")

@export var cell_size: float = 32.0
@export var map_origin: Vector2 = Vector2.ZERO
@export var minimap_size: float = 94.0
@export var show_debug_facts: bool = false
@export var show_travel_preview: bool = false
@export var classic_exploration_visibility: bool = true

var _view: GameView
var _media: ClassicMediaCatalog
var _atlas_assets: Dictionary = {}
var _atlas_textures: Dictionary = {}
var _overlay_textures: Dictionary = {}
var _darkness_mask_textures: Dictionary = {}
var _land_marker_textures: Dictionary = {}
var _missing_image_assets: Dictionary = {}
var _party_rect: Rect2
var _minimap_rect: Rect2
var _held_direction: Vector2i = Vector2i.ZERO
var _party_marker_textures: Dictionary = {}
var _dungeon_party_marker_textures: Dictionary = {}
var _party_marker_asset_id: StringName = PARTY_MARKER_RIGHT_ASSET_ID
var _party_facing_asset_id: StringName = PARTY_MARKER_RIGHT_ASSET_ID
var _movement_cursor_asset_id: StringName
var _movement_cursor_enabled: bool = true
var _visibility_cache_map_id: String = ""
var _visibility_cache_map_size: Vector2i = Vector2i.ZERO
var _visibility_cache_level_type: StringName = &""
var _visited_coordinate_cache: Dictionary = {}
var _seen_coordinate_cache: Dictionary = {}
var _land_discovery_cache: Dictionary = {}
var _dungeon_discovery_cache: Dictionary = {}
var _visible_cell_cache: Array[MapCellView] = []
var _visible_cells_by_coordinate: Dictionary = {}
var _visible_cache_map_id: String = ""
var _visible_cache_camera: Vector2i = Vector2i(-1, -1)
var _visible_cache_size: Vector2i = Vector2i.ZERO
var _visible_cache_party_coordinate: Vector2i = Vector2i(-1, -1)
var _surround_texture: Texture2D = load(SURROUND_TEXTURE_PATH) as Texture2D
var _retained_surface: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	mouse_exited.connect(_clear_movement_cursor)
	visibility_changed.connect(_on_visibility_changed)
	_party_marker_textures[PARTY_MARKER_LEFT_ASSET_ID] = ClassicUiAssetCatalog.texture(PARTY_MARKER_LEFT_ASSET_ID)
	_party_marker_textures[PARTY_MARKER_RIGHT_ASSET_ID] = ClassicUiAssetCatalog.texture(PARTY_MARKER_RIGHT_ASSET_ID)
	_party_marker_textures[PARTY_MARKER_CAMP_ASSET_ID] = ClassicUiAssetCatalog.texture(PARTY_MARKER_CAMP_ASSET_ID)
	var dungeon_arrow_strip := ClassicUiAssetCatalog.texture(DUNGEON_PARTY_ARROWS_ASSET_ID)
	if dungeon_arrow_strip != null:
		for heading: int in range(1, 5):
			_dungeon_party_marker_textures[heading] = dungeon_party_marker_texture(dungeon_arrow_strip, heading)
	for asset_id: StringName in BOAT_MARKER_LEFT_ASSET_IDS.values() + BOAT_MARKER_RIGHT_ASSET_IDS.values():
		_party_marker_textures[asset_id] = ClassicUiAssetCatalog.texture(asset_id)
	_retained_surface = RetainedMapSurfaceScript.new()
	_retained_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_retained_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_retained_surface)
	_retained_surface.set_media_catalog(_media)
	resized.connect(_present_retained_surface)


func _gui_input(event: InputEvent) -> void:
	if not _movement_cursor_enabled:
		return
	if event is InputEventMouseMotion:
		_update_movement_cursor((event as InputEventMouseMotion).position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_update_movement_cursor((event as InputEventMouseButton).position)
		if event.pressed:
			_held_direction = _movement_direction_at(event.position)
			if _held_direction != Vector2i.ZERO:
				movement_hold_started.emit(_held_direction)
				accept_event()
		else:
			_held_direction = Vector2i.ZERO
			movement_hold_stopped.emit()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		var next_direction := _movement_direction_at(event.position)
		if next_direction == Vector2i.ZERO and _held_direction != Vector2i.ZERO:
			_held_direction = Vector2i.ZERO
			movement_hold_stopped.emit()
		elif next_direction != Vector2i.ZERO and _held_direction == Vector2i.ZERO:
			_held_direction = next_direction
			movement_hold_started.emit(_held_direction)
		elif next_direction != Vector2i.ZERO and next_direction != _held_direction:
			_held_direction = next_direction
			movement_hold_updated.emit(_held_direction)


func present(game_view: GameView) -> void:
	_view = game_view
	visible = game_view != null and game_view.session_started and game_view.map_view != null
	if visible:
		_update_visibility_cache(game_view.map_view)
		if game_view.map_view.level_type != &"dungeon":
			_party_facing_asset_id = party_marker_asset_id_for_direction(game_view.map_view.last_move_direction, _party_facing_asset_id)
			var summary := game_view.party_summary
			var boat_asset_id := boat_marker_asset_id(game_view.map_view.landlook, _party_facing_asset_id == PARTY_MARKER_RIGHT_ASSET_ID)
			_party_marker_asset_id = boat_asset_id if summary != null and summary.in_boat and not boat_asset_id.is_empty() else PARTY_MARKER_CAMP_ASSET_ID if summary != null and summary.camping else _party_facing_asset_id
	_present_retained_surface()
	if not visible:
		_clear_movement_cursor()
		_held_direction = Vector2i.ZERO
		movement_hold_stopped.emit()
	queue_redraw()


func set_movement_cursor_enabled(enabled: bool) -> void:
	if _movement_cursor_enabled == enabled:
		return
	_movement_cursor_enabled = enabled
	if not enabled:
		_clear_movement_cursor()
		return
	_restore_movement_cursor_at_pointer()


func set_travel_preview_visible(enabled: bool) -> void:
	show_travel_preview = enabled
	if not enabled:
		_minimap_rect = Rect2()
	queue_redraw()
	_present_retained_surface()


func set_classic_exploration_visibility(enabled: bool) -> void:
	classic_exploration_visibility = enabled
	queue_redraw()
	_present_retained_surface()


func _update_visibility_cache(map_view: MapView) -> void:
	var map_size := Vector2i(map_view.width, map_view.height)
	var map_changed := _visibility_cache_map_id != map_view.map_id or _visibility_cache_map_size != map_size or _visibility_cache_level_type != map_view.level_type
	var delta: Variant = map_view.presentation_delta
	var can_append_delta: bool = not map_changed and delta != null and delta.map_id == map_view.map_id
	if not can_append_delta:
		_visibility_cache_map_id = map_view.map_id
		_visibility_cache_map_size = map_size
		_visibility_cache_level_type = map_view.level_type
		_visited_coordinate_cache.clear()
		_seen_coordinate_cache.clear()
		_land_discovery_cache.clear()
		_dungeon_discovery_cache.clear()
	var visited: Array[Vector2i] = []
	var seen: Array[Vector2i] = []
	if can_append_delta:
		visited.assign(delta.newly_visited); seen.assign(delta.newly_seen)
	else:
		visited = map_view.visited_coordinates(); seen = map_view.seen_coordinates()
	for coordinate: Vector2i in visited:
		if _visited_coordinate_cache.has(coordinate):
			continue
		_visited_coordinate_cache[coordinate] = true
		if map_view.level_type == &"dungeon":
			append_dungeon_discovery(_dungeon_discovery_cache, coordinate)
		else:
			append_land_discovery(_land_discovery_cache, coordinate, map_size)
	for coordinate: Vector2i in seen:
		_seen_coordinate_cache[coordinate] = true


func _update_visible_cell_cache(map_view: MapView) -> void:
	var requested := viewport_cells_for(size, map_origin.y, cell_size)
	var viewport_size := Vector2i(mini(requested.x, map_view.width), mini(requested.y, map_view.height))
	var camera := camera_top_left(map_view.party_coordinate, Vector2i(map_view.width, map_view.height), viewport_size)
	var delta: Variant = map_view.presentation_delta
	var can_reuse: bool = _visible_cache_map_id == map_view.map_id and _visible_cache_size == viewport_size and delta != null and delta.matches(map_view.map_id, _visible_cache_party_coordinate, map_view.party_coordinate)
	var changed: Dictionary = {}
	if can_reuse:
		for coordinate: Vector2i in delta.newly_visited + delta.newly_seen + delta.visibility_changed: changed[coordinate] = true
	var previous := _visible_cells_by_coordinate if can_reuse else {}
	var next_by_coordinate: Dictionary = {}
	var next_cells: Array[MapCellView] = []
	for y: int in range(camera.y, camera.y + viewport_size.y):
		for x: int in range(camera.x, camera.x + viewport_size.x):
			var coordinate := Vector2i(x, y)
			var cell := previous.get(coordinate) as MapCellView
			if cell == null or changed.has(coordinate): cell = map_view.cell_at(coordinate)
			if cell != null: next_by_coordinate[coordinate] = cell; next_cells.append(cell)
	_visible_cache_map_id = map_view.map_id; _visible_cache_camera = camera; _visible_cache_size = viewport_size; _visible_cache_party_coordinate = map_view.party_coordinate
	_visible_cells_by_coordinate = next_by_coordinate; _visible_cell_cache = next_cells


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	_media = media
	_atlas_assets.clear()
	_atlas_textures.clear()
	_overlay_textures.clear()
	_darkness_mask_textures.clear()
	_land_marker_textures.clear()
	_missing_image_assets.clear()
	if _retained_surface != null:
		_retained_surface.set_media_catalog(media)
	if _media == null:
		queue_redraw()
		return
	queue_redraw()


func _draw() -> void:
	if _view == null or _view.map_view == null:
		return
	if _retained_surface != null and _retained_surface.visible:
		return
	var map_view := _view.map_view
	var font := get_theme_font(&"font", &"Label")
	var requested_cells := viewport_cells_for(size, map_origin.y, cell_size)
	var viewport_cells := Vector2i(mini(requested_cells.x, map_view.width), mini(requested_cells.y, map_view.height))
	var expected_camera := camera_top_left(map_view.party_coordinate, Vector2i(map_view.width, map_view.height), viewport_cells)
	if _visible_cache_map_id != map_view.map_id or _visible_cache_size != viewport_cells or _visible_cache_camera != expected_camera:
		_update_visible_cell_cache(map_view)
	var draw_origin := map_draw_origin_for(size, map_origin, cell_size, viewport_cells)
	var map_rect := Rect2(draw_origin, Vector2(viewport_cells) * cell_size)
	var los_blackout := map_view.uses_los
	_draw_exploration_stage(map_rect, los_blackout)
	var camera := _visible_cache_camera
	var classic_rect := classic_visible_rect(map_view.party_coordinate, Vector2i(map_view.width, map_view.height))
	var dungeon_discovery := _dungeon_discovery_cache if map_view.level_type == &"dungeon" else {}
	var revealed_coordinates := dungeon_discovery if map_view.level_type == &"dungeon" else _land_discovery_cache
	for cell: MapCellView in _visible_cell_cache:
		var rect := Rect2(draw_origin + Vector2(cell.coordinate - camera) * cell_size, Vector2.ONE * cell_size)
		if los_cell_requires_blackout(los_blackout, cell.visible):
			continue
		var outside_classic_view := not los_blackout and classic_exploration_visibility and not classic_rect.has_point(cell.coordinate)
		if outside_classic_view and not revealed_coordinates.has(cell.coordinate):
			_draw_unvisited_cell(rect)
			continue
		_draw_cell(cell, rect, map_view.level_type, false, not cell.has_feature(&"unmapped") or dungeon_discovery.has(cell.coordinate), not cell.visible or outside_classic_view, map_view.darkness_level)
		if map_view.level_type == &"land":
			_draw_land_markers(cell, rect)
		if show_debug_facts:
			draw_rect(rect, Color(0.22, 0.25, 0.30), false, 1.0)
			_draw_edges(cell, rect)
			_draw_features(cell, rect)
			if cell.has_trigger:
				var center := rect.get_center()
				draw_colored_polygon(PackedVector2Array([center + Vector2(0, -6), center + Vector2(6, 0), center + Vector2(0, 6), center + Vector2(-6, 0)]), Color(0.95, 0.72, 0.26))
			if cell.in_random_region:
				draw_rect(rect.grow(-4.0), Color(0.48, 0.29, 0.58, 0.9), false, 2.0)
			var facts := "%s%s%s" % ["M" if cell.passable else "X", "L" if cell.blocks_los else "", "R" if cell.in_random_region else ""]
			draw_string(font, rect.position + Vector2(7, 17), facts, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.78, 0.82, 0.88))
	_party_rect = Rect2(draw_origin + Vector2(map_view.party_coordinate - camera) * cell_size, Vector2.ONE * cell_size)
	_draw_party_marker(_party_rect)
	if map_view.dark:
		_draw_darkness_mask(map_rect, _party_rect, map_view.darkness_level)
	if show_travel_preview:
		_draw_minimap(map_view, font)
	else:
		_minimap_rect = Rect2()


func _present_retained_surface() -> void:
	if _retained_surface == null:
		return
	if _view == null or _view.map_view == null:
		_retained_surface.visible = false
		return
	if show_debug_facts:
		_retained_surface.visible = false
		_update_visible_cell_cache(_view.map_view)
		return
	var party_texture := _party_marker_texture()
	_retained_surface.present(_view, party_texture, size, map_origin, cell_size, minimap_size, classic_exploration_visibility, show_travel_preview, _visited_coordinate_cache, _seen_coordinate_cache, _land_discovery_cache, _dungeon_discovery_cache)
	_party_rect = _retained_surface.party_rect()
	_minimap_rect = _retained_surface.minimap_rect()


func _draw_exploration_stage(map_rect: Rect2, los_blackout: bool) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.018, 0.022, 0.026), true)
	if _surround_texture != null:
		draw_texture_rect(_surround_texture, Rect2(Vector2.ZERO, size), true, Color(0.34, 0.35, 0.36, 0.72))
	if los_blackout:
		draw_rect(map_rect, Color.BLACK, true)


static func requires_los_blackout(cells: Array[MapCellView]) -> bool:
	return cells.any(func(cell: MapCellView) -> bool: return not cell.visible)


static func los_cell_requires_blackout(uses_los: bool, currently_visible: bool) -> bool:
	return uses_los and not currently_visible


static func darkness_mask_asset_id(level: int) -> String:
	return "classic-darkness-mask-%d" % clampi(level, 0, 6)


static func darkness_mask_rect(party_rect: Rect2) -> Rect2:
	return Rect2(party_rect.position - DARKNESS_MASK_SIZE * 0.5, DARKNESS_MASK_SIZE)


func _draw_darkness_mask(map_rect: Rect2, party_rect: Rect2, level: int) -> void:
	var mask_rect := darkness_mask_rect(party_rect)
	var clipped := map_rect.intersection(mask_rect)
	if clipped.position.y > map_rect.position.y:
		draw_rect(Rect2(map_rect.position, Vector2(map_rect.size.x, clipped.position.y - map_rect.position.y)), Color.BLACK, true)
	if clipped.end.y < map_rect.end.y:
		draw_rect(Rect2(Vector2(map_rect.position.x, clipped.end.y), Vector2(map_rect.size.x, map_rect.end.y - clipped.end.y)), Color.BLACK, true)
	if clipped.position.x > map_rect.position.x:
		draw_rect(Rect2(Vector2(map_rect.position.x, clipped.position.y), Vector2(clipped.position.x - map_rect.position.x, clipped.size.y)), Color.BLACK, true)
	if clipped.end.x < map_rect.end.x:
		draw_rect(Rect2(Vector2(clipped.end.x, clipped.position.y), Vector2(map_rect.end.x - clipped.end.x, clipped.size.y)), Color.BLACK, true)
	var texture := _darkness_mask_texture(level)
	if texture == null:
		draw_rect(clipped, Color.BLACK, true)
		return
	draw_texture_rect_region(texture, clipped, Rect2(clipped.position - mask_rect.position, clipped.size))


static func _darkness_overlay_texture(texture: Texture2D) -> ImageTexture:
	var source := texture.get_image()
	if source == null:
		return null
	source.convert(Image.FORMAT_RGBA8)
	for y: int in source.get_height():
		for x: int in source.get_width():
			var alpha := source.get_pixel(x, y).get_luminance()
			source.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))
	return ImageTexture.create_from_image(source)


static func land_marker_tile_ids(cell: MapCellView) -> Array[int]:
	var result: Array[int] = []
	if cell != null and cell.has_feature(&"secret"):
		result.append(SECRET_LAND_MARKER_TILE_ID)
	if cell != null and cell.has_feature(&"discovered_path"):
		result.append(PATH_LAND_MARKER_TILE_ID)
	return result


func _draw_land_markers(cell: MapCellView, rect: Rect2) -> void:
	for tile_id: int in land_marker_tile_ids(cell):
		var texture := _land_marker_texture(tile_id)
		if texture != null:
			draw_texture_rect(texture, rect, false)


static func transparent_atlas_tile(atlas: MediaAsset, texture: Texture2D, tile_id: int) -> ImageTexture:
	if atlas == null or texture == null:
		return null
	var region := atlas.region_for(tile_id)
	var source := texture.get_image()
	if source == null or not region.has_area() or not Rect2i(Vector2i.ZERO, source.get_size()).encloses(region):
		return null
	var marker := source.get_region(region)
	marker.convert(Image.FORMAT_RGBA8)
	for y: int in marker.get_height():
		for x: int in marker.get_width():
			var pixel := marker.get_pixel(x, y)
			if pixel.r > 0.95 and pixel.g > 0.95 and pixel.b > 0.95:
				marker.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))
	return ImageTexture.create_from_image(marker)


func _draw_party_marker(party_rect: Rect2) -> void:
	var party_marker_texture := _party_marker_texture()
	if party_marker_texture != null:
		draw_texture_rect(party_marker_texture, party_rect, false)
		return
	draw_circle(party_rect.get_center(), 10.0, Color(0.92, 0.78, 0.34))
	draw_circle(party_rect.get_center(), 5.0, Color(0.17, 0.12, 0.06))


func _party_marker_texture() -> Texture2D:
	if _view != null and _view.map_view != null and _view.map_view.level_type == &"dungeon":
		return _dungeon_party_marker_textures.get(clampi(_view.map_view.dungeon_heading, 1, 4)) as Texture2D
	return _party_marker_textures.get(_party_marker_asset_id) as Texture2D


static func dungeon_party_marker_region(heading: int) -> Rect2:
	return Rect2(float(clampi(heading, 1, 4) - 1) * 16.0, 0.0, 16.0, 16.0)


static func dungeon_party_marker_texture(strip: Texture2D, heading: int) -> ImageTexture:
	if strip == null:
		return null
	var source := strip.get_image()
	if source == null:
		return null
	var arrow := source.get_region(Rect2i(dungeon_party_marker_region(heading)))
	arrow.convert(Image.FORMAT_RGBA8)
	for y: int in arrow.get_height():
		for x: int in arrow.get_width():
			var pixel := arrow.get_pixel(x, y)
			if pixel.r == 1.0 and pixel.g == 1.0 and pixel.b == 1.0:
				arrow.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.0))
	return ImageTexture.create_from_image(arrow)


static func party_marker_asset_id_for_direction(direction: Vector2i, current_asset_id: StringName = PARTY_MARKER_RIGHT_ASSET_ID) -> StringName:
	if direction.x < 0:
		return PARTY_MARKER_LEFT_ASSET_ID
	if direction.x > 0:
		return PARTY_MARKER_RIGHT_ASSET_ID
	return current_asset_id


static func boat_marker_asset_id(landlook: int, facing_right: bool) -> StringName:
	return StringName((BOAT_MARKER_RIGHT_ASSET_IDS if facing_right else BOAT_MARKER_LEFT_ASSET_IDS).get(landlook, ""))


static func facing_label(direction: Vector2i) -> String:
	var horizontal := "W" if direction.x < 0 else "E" if direction.x > 0 else ""
	var vertical := "N" if direction.y < 0 else "S" if direction.y > 0 else ""
	return "%s%s" % [vertical, horizontal] if not vertical.is_empty() or not horizontal.is_empty() else "—"


static func movement_cursor_asset_id(direction: Vector2i) -> StringName:
	var normalized := Vector2i(signi(direction.x), signi(direction.y))
	match normalized:
		Vector2i(-1, -1): return &"map.cursor.northwest"
		Vector2i(0, -1): return &"map.cursor.north"
		Vector2i(1, -1): return &"map.cursor.northeast"
		Vector2i(-1, 0): return &"map.cursor.west"
		Vector2i(1, 0): return &"map.cursor.east"
		Vector2i(-1, 1): return &"map.cursor.southwest"
		Vector2i(0, 1): return &"map.cursor.south"
		Vector2i(1, 1): return &"map.cursor.southeast"
		_: return &"map.cursor.center"


static func camera_top_left(party_coordinate: Vector2i, map_size: Vector2i, viewport_cells: Vector2i) -> Vector2i:
	var maximum := Vector2i(maxi(map_size.x - viewport_cells.x, 0), maxi(map_size.y - viewport_cells.y, 0))
	return Vector2i(
		clampi(party_coordinate.x - viewport_cells.x / 2, 0, maximum.x),
		clampi(party_coordinate.y - viewport_cells.y / 2, 0, maximum.y)
	)


static func classic_visible_rect(party_coordinate: Vector2i, map_size: Vector2i) -> Rect2i:
	var view_size := Vector2i(mini(CLASSIC_VIEW_CELLS.x, map_size.x), mini(CLASSIC_VIEW_CELLS.y, map_size.y))
	var maximum := Vector2i(maxi(map_size.x - view_size.x, 0), maxi(map_size.y - view_size.y, 0))
	var origin := Vector2i(clampi(party_coordinate.x - 8, 0, maximum.x), clampi(party_coordinate.y - 6, 0, maximum.y))
	return Rect2i(origin, view_size)


static func land_discovery_coordinates(visited: Array[Vector2i], map_size: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	for coordinate: Vector2i in visited:
		append_land_discovery(result, coordinate, map_size)
	return result


static func append_land_discovery(result: Dictionary, coordinate: Vector2i, map_size: Vector2i) -> void:
	var visible_rect := classic_visible_rect(coordinate, map_size)
	for y: int in range(visible_rect.position.y, visible_rect.end.y):
		for x: int in range(visible_rect.position.x, visible_rect.end.x):
			result[Vector2i(x, y)] = true


static func viewport_cells_for(control_size: Vector2, header_height: float, native_cell_size: float) -> Vector2i:
	return Vector2i(
		maxi(1, floori(control_size.x / native_cell_size)),
		maxi(1, floori((control_size.y - header_height) / native_cell_size))
	)


static func projection_cells_for(control_size: Vector2, header_height: float, native_cell_size: float) -> Vector2i:
	return viewport_cells_for(control_size, header_height, native_cell_size) + RETAINED_PROJECTION_MARGIN_CELLS * 2


static func map_draw_origin_for(control_size: Vector2, minimum_origin: Vector2, native_cell_size: float, viewport_cells: Vector2i) -> Vector2:
	var map_pixel_size := Vector2(viewport_cells) * native_cell_size
	var available_height := maxf(control_size.y - minimum_origin.y, 0.0)
	return Vector2(
		maxf(minimum_origin.x, floorf((control_size.x - map_pixel_size.x) * 0.5)),
		minimum_origin.y + maxf(0.0, floorf((available_height - map_pixel_size.y) * 0.5))
	)


func _draw_unvisited_cell(_rect: Rect2) -> void:
	pass


func _draw_cell(cell: MapCellView, rect: Rect2, level_type: StringName, dark: bool, discovered: bool, recalled: bool = false, saved_darkness_level: int = -1) -> void:
	if level_type == &"dungeon" and not discovered:
		draw_rect(rect, Color(0.025, 0.03, 0.04), true)
		return
	if not cell.visible and not recalled:
		draw_rect(rect, _cell_color(cell, level_type, dark), true)
		return
	_ensure_atlas(cell.tileset_id)
	var atlas_asset: MediaAsset = _atlas_assets.get(cell.tileset_id) as MediaAsset
	var atlas_texture: Texture2D = _atlas_textures.get(cell.tileset_id) as Texture2D
	if level_type == &"dungeon" and atlas_asset != null and atlas_texture != null and atlas_asset.id == "dungeon-top-down-302":
		_draw_dungeon_atlas_cell(cell, rect, atlas_asset, atlas_texture)
		if dark:
			draw_rect(rect, Color(0.0, 0.0, 0.0, darkness_overlay_alpha(saved_darkness_level)), true)
		return
	var region := Rect2i() if atlas_asset == null else atlas_asset.region_for(cell.render_tile)
	if atlas_texture == null or not region.has_area():
		draw_rect(rect, _cell_color(cell, level_type, false), true)
	else:
		draw_texture_rect_region(atlas_texture, rect, Rect2(region))
	var overlay_texture := _image_texture_by_id(cell.overlay_asset_id)
	if overlay_texture != null:
		draw_texture_rect(overlay_texture, rect, false)
	if dark:
		draw_rect(rect, Color(0.0, 0.0, 0.0, darkness_overlay_alpha(saved_darkness_level)), true)


static func dungeon_discovery_coordinates(visited: Array[Vector2i]) -> Dictionary:
	var result: Dictionary = {}
	for coordinate: Vector2i in visited:
		append_dungeon_discovery(result, coordinate)
	return result


static func append_dungeon_discovery(result: Dictionary, coordinate: Vector2i) -> void:
	for y: int in range(coordinate.y - 1, coordinate.y + 2):
		for x: int in range(coordinate.x - 1, coordinate.x + 2):
			result[Vector2i(x, y)] = true


static func darkness_overlay_alpha(saved_darkness_level: int) -> float:
	if saved_darkness_level < 0:
		return 0.45
	return lerpf(0.72, 0.12, float(clampi(saved_darkness_level, 0, 6)) / 6.0)


func _draw_dungeon_atlas_cell(cell: MapCellView, rect: Rect2, atlas_asset: MediaAsset, atlas_texture: Texture2D) -> void:
	for tile_id: int in dungeon_tile_ids(cell):
		_draw_atlas_region(rect, atlas_asset, atlas_texture, tile_id)


static func dungeon_tile_ids(cell: MapCellView) -> Array[int]:
	var result: Array[int] = [16]
	if cell.terrain_id == "classic.dungeon.wall":
		result.append(1)
	if cell.has_feature(&"door"):
		result.append(3 if cell.feature_orientation(&"door") == &"vertical" else 2)
	for feature_kind: StringName in [&"stairs", &"column", &"note"]:
		if cell.has_feature(feature_kind):
			result.append({&"stairs": 4, &"column": 5, &"note": 6}[feature_kind])
	if cell.has_feature(&"secret"):
		result.append({&"north": 9, &"east": 10, &"south": 11, &"west": 12}.get(cell.feature_orientation(&"secret"), 7))
	if cell.has_feature(&"unmapped"):
		result.append(8)
	result.sort()
	result.erase(16)
	result.push_front(16)
	return result


func _draw_atlas_region(rect: Rect2, atlas_asset: MediaAsset, atlas_texture: Texture2D, tile_id: int) -> void:
	var region := atlas_asset.region_for(tile_id)
	if region.has_area():
		draw_texture_rect_region(atlas_texture, rect, Rect2(region))


func _load_image_texture(asset: MediaAsset) -> Texture2D:
	return _media.image_texture(asset) if _media != null else null


func _ensure_atlas(asset_id: String) -> void:
	if asset_id.is_empty() or _atlas_assets.has(asset_id) or _missing_image_assets.has(asset_id) or _media == null:
		return
	var asset := _media.asset_by_id(asset_id)
	if asset == null or not asset.is_tileset() and not asset.is_battle_tileset():
		_missing_image_assets[asset_id] = true
		return
	var texture := _load_image_texture(asset)
	if texture == null:
		_missing_image_assets[asset_id] = true
		return
	_atlas_assets[asset_id] = asset
	_atlas_textures[asset_id] = texture


func _image_texture_by_id(asset_id: String) -> Texture2D:
	if asset_id.is_empty() or _media == null:
		return null
	if _overlay_textures.has(asset_id):
		return _overlay_textures[asset_id] as Texture2D
	if _missing_image_assets.has(asset_id):
		return null
	var asset := _media.asset_by_id(asset_id)
	var texture := _load_image_texture(asset)
	if texture == null:
		_missing_image_assets[asset_id] = true
		return null
	_overlay_textures[asset_id] = texture
	return texture


func _darkness_mask_texture(level: int) -> Texture2D:
	var bounded_level := clampi(level, 0, 6)
	if _darkness_mask_textures.has(bounded_level):
		return _darkness_mask_textures[bounded_level] as Texture2D
	var asset_id := darkness_mask_asset_id(bounded_level)
	if _missing_image_assets.has(asset_id) or _media == null:
		return null
	var source := _image_texture_by_id(asset_id)
	var texture := _darkness_overlay_texture(source) if source != null else null
	if texture == null:
		_missing_image_assets[asset_id] = true
		return null
	_darkness_mask_textures[bounded_level] = texture
	return texture


func _land_marker_texture(tile_id: int) -> Texture2D:
	if _land_marker_textures.has(tile_id):
		return _land_marker_textures[tile_id] as Texture2D
	_ensure_atlas(CLASSIC_BATTLE_ATLAS_ID)
	var texture := transparent_atlas_tile(_atlas_assets.get(CLASSIC_BATTLE_ATLAS_ID) as MediaAsset, _atlas_textures.get(CLASSIC_BATTLE_ATLAS_ID) as Texture2D, tile_id)
	if texture != null:
		_land_marker_textures[tile_id] = texture
	return texture


func _cell_color(cell: MapCellView, level_type: StringName, dark: bool = false) -> Color:
	var color: Color
	if not cell.visible:
		color = Color(0.025, 0.03, 0.04)
	elif not cell.passable:
		color = Color(0.16, 0.17, 0.20)
	elif cell.terrain_id.ends_with(".2"):
		color = Color(0.34, 0.50, 0.31)
	elif level_type == &"dungeon":
		color = Color(0.28, 0.27, 0.24)
	else:
		color = Color(0.20, 0.38, 0.27)
	return color.darkened(0.45) if dark else color


func _draw_edges(cell: MapCellView, rect: Rect2) -> void:
	var edge_points := {
		&"north": [rect.position, rect.position + Vector2(rect.size.x, 0)],
		&"east": [rect.position + Vector2(rect.size.x, 0), rect.end],
		&"south": [rect.position + Vector2(0, rect.size.y), rect.end],
		&"west": [rect.position, rect.position + Vector2(0, rect.size.y)],
	}
	for direction: StringName in edge_points:
		var kind := cell.edge_kind(direction)
		if kind == &"open":
			continue
		var points: Array = edge_points[direction]
		var color := Color(0.84, 0.75, 0.52) if kind == &"door" else Color(0.64, 0.40, 0.72) if kind == &"secret" else Color(0.62, 0.65, 0.70)
		draw_line(points[0], points[1], color, 4.0 if cell.edge_is_passable(direction) else 7.0)


func _draw_features(cell: MapCellView, rect: Rect2) -> void:
	var center := rect.get_center()
	if cell.has_feature(&"door"):
		draw_line(center + Vector2(-13, 0), center + Vector2(13, 0), Color(0.84, 0.63, 0.30), 5.0)
	if cell.has_feature(&"secret"):
		draw_string(get_theme_font(&"font", &"Label"), center + Vector2(-5, 6), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.71, 0.46, 0.82))
	if cell.has_feature(&"stairs"):
		for offset: int in [-8, 0, 8]:
			draw_line(center + Vector2(-12, offset), center + Vector2(12, offset), Color(0.72, 0.72, 0.68), 2.0)
	if cell.has_feature(&"column"):
		draw_circle(center, 10.0, Color(0.64, 0.64, 0.62))


func _draw_minimap(map_view: MapView, font: Font) -> void:
	var scale := minf(minimap_size / float(map_view.width), minimap_size / float(map_view.height))
	var map_pixel_size := Vector2(map_view.width, map_view.height) * scale
	var origin := Vector2(size.x - map_pixel_size.x - 8.0, size.y - map_pixel_size.y - 8.0)
	_minimap_rect = Rect2(origin - Vector2.ONE * 4.0, map_pixel_size + Vector2.ONE * 8.0)
	draw_rect(_minimap_rect, Color(0.035, 0.04, 0.05, 0.9), true)
	draw_string(font, origin - Vector2(0, 7), "Map", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.72, 0.76, 0.82))
	for coordinate: Vector2i in _visited_coordinate_cache:
		var rect := Rect2(origin + Vector2(coordinate) * scale, Vector2.ONE * maxf(scale, 1.0))
		draw_rect(rect, Color(0.28, 0.48, 0.32), true)
	var party_center := origin + (Vector2(map_view.party_coordinate) + Vector2.ONE * 0.5) * scale
	draw_circle(party_center, maxf(2.0, scale * 1.5), Color(0.94, 0.78, 0.28))


func _movement_direction_at(position: Vector2) -> Vector2i:
	if _party_rect.size == Vector2.ZERO or _minimap_rect.has_point(position):
		return Vector2i.ZERO
	if _view != null and _view.map_view != null and _view.map_view.level_type == &"land":
		return land_direction_at(position, _party_rect)
	var offset := position - _party_rect.get_center()
	if absf(offset.x) < cell_size * 0.35 and absf(offset.y) < cell_size * 0.35:
		return Vector2i.ZERO
	if absf(offset.x) > absf(offset.y):
		return Vector2i.RIGHT if offset.x > 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if offset.y > 0.0 else Vector2i.UP


func _update_movement_cursor(position: Vector2) -> void:
	if not _movement_cursor_enabled or not is_visible_in_tree() or _view == null or _view.map_view == null:
		_clear_movement_cursor()
		return
	var asset_id := movement_cursor_asset_id(_movement_direction_at(position))
	var texture := ClassicUiAssetCatalog.texture(asset_id)
	if texture == null:
		_clear_movement_cursor()
		return
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, ClassicUiAssetCatalog.cursor_hotspot(asset_id))
	_movement_cursor_asset_id = asset_id


func _restore_movement_cursor_at_pointer() -> void:
	if not _movement_cursor_enabled or not is_visible_in_tree():
		return
	var local_position := get_local_mouse_position()
	if Rect2(Vector2.ZERO, size).has_point(local_position):
		_update_movement_cursor(local_position)


func _clear_movement_cursor() -> void:
	if _movement_cursor_asset_id.is_empty():
		return
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	_movement_cursor_asset_id = &""


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_clear_movement_cursor()


func _exit_tree() -> void:
	_clear_movement_cursor()


static func land_direction_at(position: Vector2, party_rect: Rect2) -> Vector2i:
	var horizontal := -1 if position.x < party_rect.position.x else 1 if position.x > party_rect.end.x else 0
	var vertical := -1 if position.y < party_rect.position.y else 1 if position.y > party_rect.end.y else 0
	return Vector2i(horizontal, vertical)
