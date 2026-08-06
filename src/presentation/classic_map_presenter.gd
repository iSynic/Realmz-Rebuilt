class_name ClassicMapPresenter
extends Control

@export var cell_size: float = 48.0
@export var map_origin: Vector2 = Vector2(0.0, 24.0)
@export var minimap_size: float = 94.0
@export var show_debug_facts: bool = true

var _view: GameView
var _media: PackageMediaCatalog
var _atlas_assets: Dictionary = {}
var _atlas_textures: Dictionary = {}


func present(game_view: GameView) -> void:
	_view = game_view
	visible = game_view != null and game_view.session_started and game_view.map_view != null
	queue_redraw()


func set_media_catalog(media: PackageMediaCatalog) -> void:
	_media = media
	_atlas_assets.clear()
	_atlas_textures.clear()
	if _media == null:
		queue_redraw()
		return
	for asset: PackageMediaAsset in _media.assets():
		if not asset.is_tileset():
			continue
		var texture := _load_atlas_texture(asset)
		if texture == null:
			continue
		_atlas_assets[asset.id] = asset
		_atlas_textures[asset.id] = texture
	queue_redraw()


func _draw() -> void:
	if _view == null or _view.map_view == null:
		return
	var map_view := _view.map_view
	var font := ThemeDB.fallback_font
	var viewport_cells := Vector2i(
		maxi(1, floori(size.x / cell_size)),
		maxi(1, floori((size.y - map_origin.y) / cell_size))
	)
	var camera := camera_top_left(map_view.party_coordinate, Vector2i(map_view.width, map_view.height), viewport_cells)
	var camera_end := camera + viewport_cells
	for cell: MapCellView in map_view.cells():
		if cell.coordinate.x < camera.x or cell.coordinate.y < camera.y or cell.coordinate.x >= camera_end.x or cell.coordinate.y >= camera_end.y:
			continue
		var rect := Rect2(map_origin + Vector2(cell.coordinate - camera) * cell_size, Vector2.ONE * cell_size)
		_draw_cell(cell, rect, map_view.level_type, map_view.dark)
		draw_rect(rect, Color(0.22, 0.25, 0.30), false, 1.0)
		_draw_edges(cell, rect)
		_draw_features(cell, rect)
		if cell.has_trigger:
			var center := rect.get_center()
			draw_colored_polygon(PackedVector2Array([center + Vector2(0, -8), center + Vector2(8, 0), center + Vector2(0, 8), center + Vector2(-8, 0)]), Color(0.95, 0.72, 0.26))
		if cell.in_random_region:
			draw_rect(rect.grow(-5.0), Color(0.48, 0.29, 0.58, 0.9), false, 2.0)
		if show_debug_facts:
			var facts := "%s%s%s" % ["M" if cell.passable else "X", "L" if cell.blocks_los else "", "R" if cell.in_random_region else ""]
			draw_string(font, rect.position + Vector2(7, 17), facts, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.78, 0.82, 0.88))
	var party_rect := Rect2(map_origin + Vector2(map_view.party_coordinate - camera) * cell_size, Vector2.ONE * cell_size)
	draw_circle(party_rect.get_center(), 13.0, Color(0.92, 0.78, 0.34))
	draw_circle(party_rect.get_center(), 7.0, Color(0.17, 0.12, 0.06))
	draw_string(font, Vector2(8.0, 17.0), "%s • %s" % [map_view.map_name, String(map_view.level_type)], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.86, 0.75, 0.42))
	_draw_minimap(map_view, font)


static func camera_top_left(party_coordinate: Vector2i, map_size: Vector2i, viewport_cells: Vector2i) -> Vector2i:
	var maximum := Vector2i(maxi(map_size.x - viewport_cells.x, 0), maxi(map_size.y - viewport_cells.y, 0))
	return Vector2i(
		clampi(party_coordinate.x - viewport_cells.x / 2, 0, maximum.x),
		clampi(party_coordinate.y - viewport_cells.y / 2, 0, maximum.y)
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


func _load_atlas_texture(asset: PackageMediaAsset) -> Texture2D:
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
	if load_error != OK or image.get_width() != asset.width or image.get_height() != asset.height:
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
	draw_rect(Rect2(origin - Vector2.ONE * 4.0, map_pixel_size + Vector2.ONE * 8.0), Color(0.035, 0.04, 0.05, 0.9), true)
	draw_string(font, origin - Vector2(0, 7), "Map", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.72, 0.76, 0.82))
	for cell: MapCellView in map_view.cells():
		var rect := Rect2(origin + Vector2(cell.coordinate) * scale, Vector2.ONE * maxf(scale, 1.0))
		var color := Color(0.28, 0.48, 0.32) if cell.visited else Color(0.09, 0.10, 0.12)
		draw_rect(rect, color, true)
	var party_center := origin + (Vector2(map_view.party_coordinate) + Vector2.ONE * 0.5) * scale
	draw_circle(party_center, maxf(2.0, scale * 1.5), Color(0.94, 0.78, 0.28))
