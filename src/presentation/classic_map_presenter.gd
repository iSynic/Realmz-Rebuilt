class_name ClassicMapPresenter
extends Control

signal movement_requested(direction: Vector2i)

const MOUSE_REPEAT_DELAY: float = 0.28
const MOUSE_REPEAT_INTERVAL: float = 0.11
const DETACHED_VIEW_DIAMETER: int = 25

@export var cell_size: float = 32.0
@export var map_origin: Vector2 = Vector2(0.0, 24.0)
@export var minimap_size: float = 94.0
@export var show_debug_facts: bool = false

var _view: GameView
var _media: PackageMediaCatalog
var _atlas_assets: Dictionary = {}
var _atlas_textures: Dictionary = {}
var _overlay_textures: Dictionary = {}
var _party_rect: Rect2
var _minimap_rect: Rect2
var _held_direction: Vector2i = Vector2i.ZERO
var _mouse_repeat_remaining: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func _process(delta: float) -> void:
	if _held_direction == Vector2i.ZERO or not visible:
		return
	_mouse_repeat_remaining -= delta
	if _mouse_repeat_remaining <= 0.0:
		movement_requested.emit(_held_direction)
		_mouse_repeat_remaining = MOUSE_REPEAT_INTERVAL


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_held_direction = _movement_direction_at(event.position)
			if _held_direction != Vector2i.ZERO:
				movement_requested.emit(_held_direction)
				_mouse_repeat_remaining = MOUSE_REPEAT_DELAY
				accept_event()
		else:
			_held_direction = Vector2i.ZERO
			_mouse_repeat_remaining = 0.0
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_held_direction = _movement_direction_at(event.position)


func present(game_view: GameView) -> void:
	_view = game_view
	visible = game_view != null and game_view.session_started and game_view.map_view != null
	if not visible:
		_held_direction = Vector2i.ZERO
	queue_redraw()


func set_media_catalog(media: PackageMediaCatalog) -> void:
	_media = media
	_atlas_assets.clear()
	_atlas_textures.clear()
	_overlay_textures.clear()
	if _media == null:
		queue_redraw()
		return
	for asset: PackageMediaAsset in _media.assets():
		if not asset.is_tileset() and not asset.is_picture():
			continue
		var texture := _load_image_texture(asset)
		if texture == null:
			continue
		if asset.is_tileset():
			_atlas_assets[asset.id] = asset
			_atlas_textures[asset.id] = texture
		else:
			_overlay_textures[asset.id] = texture
	queue_redraw()


func _draw() -> void:
	if _view == null or _view.map_view == null:
		return
	var map_view := _view.map_view
	var font := ThemeDB.fallback_font
	var viewport_cells := viewport_cells_for(size, map_origin.y, cell_size)
	var draw_origin := map_draw_origin_for(size, map_origin, cell_size, viewport_cells)
	var camera := camera_top_left(map_view.party_coordinate, Vector2i(map_view.width, map_view.height), viewport_cells)
	var camera_end := camera + viewport_cells
	for cell: MapCellView in map_view.cells():
		if cell.coordinate.x < camera.x or cell.coordinate.y < camera.y or cell.coordinate.x >= camera_end.x or cell.coordinate.y >= camera_end.y:
			continue
		var rect := Rect2(draw_origin + Vector2(cell.coordinate - camera) * cell_size, Vector2.ONE * cell_size)
		_draw_cell(cell, rect, map_view.level_type, map_view.dark)
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
	draw_circle(_party_rect.get_center(), 10.0, Color(0.92, 0.78, 0.34))
	draw_circle(_party_rect.get_center(), 5.0, Color(0.17, 0.12, 0.06))
	_draw_movement_cues(map_view, _party_rect)
	draw_string(font, Vector2(8.0, 17.0), "%s • %s" % [map_view.map_name, String(map_view.level_type)], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.86, 0.75, 0.42))
	var input_hint := "Click map • numpad / arrows / WASD" if map_view.level_type == &"land" else "Click map • arrows / WASD"
	draw_string(font, Vector2(size.x - 258.0, 17.0), input_hint, HORIZONTAL_ALIGNMENT_RIGHT, 250.0, 12, Color(0.66, 0.69, 0.73))
	_draw_minimap(map_view, font)


static func camera_top_left(party_coordinate: Vector2i, map_size: Vector2i, viewport_cells: Vector2i) -> Vector2i:
	var maximum := Vector2i(maxi(map_size.x - viewport_cells.x, 0), maxi(map_size.y - viewport_cells.y, 0))
	return Vector2i(
		clampi(party_coordinate.x - viewport_cells.x / 2, 0, maximum.x),
		clampi(party_coordinate.y - viewport_cells.y / 2, 0, maximum.y)
	)


static func viewport_cells_for(control_size: Vector2, header_height: float, native_cell_size: float) -> Vector2i:
	return Vector2i(
		mini(DETACHED_VIEW_DIAMETER, maxi(1, floori(control_size.x / native_cell_size))),
		mini(DETACHED_VIEW_DIAMETER, maxi(1, floori((control_size.y - header_height) / native_cell_size)))
	)


static func map_draw_origin_for(control_size: Vector2, minimum_origin: Vector2, native_cell_size: float, viewport_cells: Vector2i) -> Vector2:
	var map_pixel_size := Vector2(viewport_cells) * native_cell_size
	var available_height := maxf(control_size.y - minimum_origin.y, 0.0)
	return Vector2(
		maxf(minimum_origin.x, floorf((control_size.x - map_pixel_size.x) * 0.5)),
		minimum_origin.y + maxf(0.0, floorf((available_height - map_pixel_size.y) * 0.5))
	)


func _draw_cell(cell: MapCellView, rect: Rect2, level_type: StringName, dark: bool) -> void:
	if not cell.visible:
		draw_rect(rect, _cell_color(cell, level_type, dark), true)
		return
	var atlas_asset: PackageMediaAsset = _atlas_assets.get(cell.tileset_id) as PackageMediaAsset
	var atlas_texture: Texture2D = _atlas_textures.get(cell.tileset_id) as Texture2D
	if level_type == &"dungeon" and atlas_asset != null and atlas_texture != null and atlas_asset.id == "dungeon-top-down-302":
		_draw_dungeon_atlas_cell(cell, rect, atlas_asset, atlas_texture)
		if dark:
			draw_rect(rect, Color(0.0, 0.0, 0.0, 0.45), true)
		return
	var region := Rect2i() if atlas_asset == null else atlas_asset.region_for(cell.render_tile)
	if atlas_texture == null or not region.has_area():
		draw_rect(rect, _cell_color(cell, level_type, false), true)
	else:
		draw_texture_rect_region(atlas_texture, rect, Rect2(region))
	var overlay_texture: Texture2D = _overlay_textures.get(cell.overlay_asset_id) as Texture2D
	if overlay_texture != null:
		draw_texture_rect(overlay_texture, rect, false)
	if dark:
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.45), true)


func _draw_dungeon_atlas_cell(cell: MapCellView, rect: Rect2, atlas_asset: PackageMediaAsset, atlas_texture: Texture2D) -> void:
	_draw_atlas_region(rect, atlas_asset, atlas_texture, 16)
	if cell.terrain_id == "classic.dungeon.wall":
		_draw_atlas_region(rect, atlas_asset, atlas_texture, 1)
	if cell.has_feature(&"door"):
		_draw_atlas_region(rect, atlas_asset, atlas_texture, 3 if cell.feature_orientation(&"door") == &"vertical" else 2)
	var feature_tiles: Dictionary = {
		&"stairs": 4,
		&"column": 5,
		&"note": 6,
		&"secret": 7,
	}
	for feature_kind: StringName in feature_tiles:
		if cell.has_feature(feature_kind):
			_draw_atlas_region(rect, atlas_asset, atlas_texture, int(feature_tiles[feature_kind]))


func _draw_atlas_region(rect: Rect2, atlas_asset: PackageMediaAsset, atlas_texture: Texture2D, tile_id: int) -> void:
	var region := atlas_asset.region_for(tile_id)
	if region.has_area():
		draw_texture_rect_region(atlas_texture, rect, Rect2(region))


func _load_image_texture(asset: PackageMediaAsset) -> Texture2D:
	var bytes := _media.read_bytes(asset)
	if bytes.is_empty():
		return null
	var image := Image.new()
	var load_error := ERR_FILE_UNRECOGNIZED
	match asset.mime_type:
		"image/png":
			load_error = image.load_png_from_buffer(bytes)
		"image/jpeg":
			load_error = image.load_jpg_from_buffer(bytes)
		"image/webp":
			load_error = image.load_webp_from_buffer(bytes)
	if load_error != OK:
		return null
	if asset.width > 0 and asset.height > 0 and (image.get_width() != asset.width or image.get_height() != asset.height):
		return null
	return ImageTexture.create_from_image(image)


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
		draw_string(ThemeDB.fallback_font, center + Vector2(-5, 6), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.71, 0.46, 0.82))
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
	for coordinate: Vector2i in map_view.visited_coordinates():
		var rect := Rect2(origin + Vector2(coordinate) * scale, Vector2.ONE * maxf(scale, 1.0))
		draw_rect(rect, Color(0.28, 0.48, 0.32), true)
	var party_center := origin + (Vector2(map_view.party_coordinate) + Vector2.ONE * 0.5) * scale
	draw_circle(party_center, maxf(2.0, scale * 1.5), Color(0.94, 0.78, 0.28))


func _draw_movement_cues(map_view: MapView, party_rect: Rect2) -> void:
	var center := party_rect.get_center()
	var cue_points := {
		Vector2i.UP: PackedVector2Array([center + Vector2(-4, -11), center + Vector2(4, -11), center + Vector2(0, -15)]),
		Vector2i.RIGHT: PackedVector2Array([center + Vector2(11, -4), center + Vector2(11, 4), center + Vector2(15, 0)]),
		Vector2i.DOWN: PackedVector2Array([center + Vector2(-4, 11), center + Vector2(4, 11), center + Vector2(0, 15)]),
		Vector2i.LEFT: PackedVector2Array([center + Vector2(-11, -4), center + Vector2(-11, 4), center + Vector2(-15, 0)]),
	}
	for direction: Vector2i in cue_points:
		var color := Color(0.95, 0.76, 0.25, 0.95) if map_view.can_move(direction) else Color(0.42, 0.16, 0.15, 0.90)
		draw_colored_polygon(cue_points[direction], color)


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


static func land_direction_at(position: Vector2, party_rect: Rect2) -> Vector2i:
	var horizontal := -1 if position.x < party_rect.position.x else 1 if position.x > party_rect.end.x else 0
	var vertical := -1 if position.y < party_rect.position.y else 1 if position.y > party_rect.end.y else 0
	return Vector2i(horizontal, vertical)
