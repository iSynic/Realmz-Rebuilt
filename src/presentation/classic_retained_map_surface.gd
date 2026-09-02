class_name ClassicRetainedMapSurface
extends Control

const SURROUND_TEXTURE_PATH := "res://src/presentation/assets/ui/classic-exploration-surround-tile.png"
const BATTLE_ATLAS_ID := "classic-battle-tiles-302"
const SECRET_TILE_ID := 251
const PATH_TILE_ID := 253
const DARKNESS_MASK_SIZE := Vector2(320.0, 320.0)
const DARKNESS_MEMORY_OPACITY := 0.8

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera2D
var _base_layer: TileMapLayer
var _marker_layer: TileMapLayer
var _feature_layers: Array[TileMapLayer] = []
var _fog_layer: TileMapLayer
var _background: TextureRect
var _party_sprite: Sprite2D
var _overlay_sprites: Dictionary = {}
var _media: ClassicMediaCatalog
var _tile_set := TileSet.new()
var _fog_tile_set := TileSet.new()
var _source_by_asset_id: Dictionary = {}
var _transparent_marker_source_by_tile_id: Dictionary = {}
var _missing_sources: Dictionary = {}
var _map_id: String = ""
var _map_view: MapView
var _camera_coordinate := Vector2i(-1, -1)
var _classic_rect := Rect2i()
var _map_rect := Rect2()
var _party_rect := Rect2()
var _party_texture: Texture2D
var _cell_size: float = 32.0
var _minimap_size: float = 94.0
var _classic_visibility: bool = true
var _show_minimap: bool = false
var _visited: Dictionary = {}
var _seen: Dictionary = {}
var _land_discovery: Dictionary = {}
var _dungeon_discovery: Dictionary = {}
var _darkness_masks: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	_build_viewport()


func _build_viewport() -> void:
	_viewport_container = SubViewportContainer.new()
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_container.stretch = false
	_viewport_container.show_behind_parent = true
	add_child(_viewport_container)
	_viewport = SubViewport.new()
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.size = Vector2i(maxi(1, roundi(size.x)), maxi(1, roundi(size.y)))
	_viewport_container.add_child(_viewport)
	var background_canvas := CanvasLayer.new()
	background_canvas.layer = -10
	_viewport.add_child(background_canvas)
	_background = TextureRect.new()
	_background.texture = load(SURROUND_TEXTURE_PATH) as Texture2D
	_background.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.modulate = Color(0.34, 0.35, 0.36, 0.72)
	_background.size = Vector2(_viewport.size)
	background_canvas.add_child(_background)
	_tile_set.tile_size = Vector2i(32, 32)
	for index: int in 7:
		var layer := TileMapLayer.new()
		layer.tile_set = _tile_set
		layer.z_index = index
		_viewport.add_child(layer)
		if index == 0: _base_layer = layer
		else: _feature_layers.append(layer)
	_marker_layer = TileMapLayer.new()
	_marker_layer.name = "LandSecretMarkerLayer"
	_marker_layer.tile_set = _tile_set
	_marker_layer.z_index = 5
	_viewport.add_child(_marker_layer)
	_build_fog_tiles()
	_fog_layer = TileMapLayer.new()
	_fog_layer.name = "LineOfSightBlackoutLayer"
	_fog_layer.tile_set = _fog_tile_set
	_fog_layer.z_index = 6
	_viewport.add_child(_fog_layer)
	_party_sprite = Sprite2D.new()
	_party_sprite.centered = true
	_party_sprite.z_index = 20
	_viewport.add_child(_party_sprite)
	_camera = Camera2D.new()
	_camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	_camera.position_smoothing_enabled = false
	_camera.enabled = true
	_viewport.add_child(_camera)
	resized.connect(_resize_viewport)


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	if _media == media:
		return
	_media = media
	_source_by_asset_id.clear()
	_transparent_marker_source_by_tile_id.clear()
	_missing_sources.clear()
	for index: int in range(_tile_set.get_source_count() - 1, -1, -1):
		_tile_set.remove_source(_tile_set.get_source_id(index))
	_clear_layers()
	_map_id = ""


func present(game_view: GameView, party_texture: Texture2D, control_size: Vector2, origin: Vector2, native_cell_size: float, minimap_size: float, classic_visibility: bool, show_minimap: bool, visited: Dictionary, seen: Dictionary, land_discovery: Dictionary, dungeon_discovery: Dictionary) -> void:
	if game_view == null or game_view.map_view == null:
		visible = false
		return
	visible = true
	_map_view = game_view.map_view
	_party_texture = party_texture
	_cell_size = native_cell_size
	_minimap_size = minimap_size
	_classic_visibility = classic_visibility
	_show_minimap = show_minimap
	_visited = visited
	_seen = seen
	_land_discovery = land_discovery
	_dungeon_discovery = dungeon_discovery
	size = control_size
	_resize_viewport()
	var requested := ClassicMapPresenter.viewport_cells_for(control_size, origin.y, native_cell_size)
	var viewport_cells := Vector2i(mini(requested.x, _map_view.width), mini(requested.y, _map_view.height))
	var camera := ClassicMapPresenter.camera_top_left(_map_view.party_coordinate, Vector2i(_map_view.width, _map_view.height), viewport_cells)
	var draw_origin := ClassicMapPresenter.map_draw_origin_for(control_size, origin, native_cell_size, viewport_cells)
	_map_rect = Rect2(draw_origin, Vector2(viewport_cells) * native_cell_size)
	_party_rect = Rect2(draw_origin + Vector2(_map_view.party_coordinate - camera) * native_cell_size, Vector2.ONE * native_cell_size)
	_camera.position = Vector2(camera) * native_cell_size - draw_origin
	_party_sprite.texture = party_texture
	_party_sprite.position = (Vector2(_map_view.party_coordinate) + Vector2.ONE * 0.5) * native_cell_size
	_party_sprite.scale = _texture_scale(party_texture)
	var next_classic_rect := ClassicMapPresenter.classic_visible_rect(_map_view.party_coordinate, Vector2i(_map_view.width, _map_view.height))
	var full_refresh: bool = _map_id != _map_view.map_id or _map_view.presentation_delta == null or bool(_map_view.presentation_delta.complete_window_rebuild)
	if full_refresh:
		_clear_layers()
		for cell: MapCellView in _map_view.cells(): _update_cell(cell, next_classic_rect)
	else:
		var changed: Dictionary = {}
		for coordinate: Vector2i in _map_view.presentation_delta.entered + _map_view.presentation_delta.changed:
			changed[coordinate] = true
		for coordinate: Vector2i in _rect_changed_coordinates(_classic_rect, next_classic_rect):
			changed[coordinate] = true
		for coordinate: Vector2i in changed:
			var cell := _map_view.cell_at(coordinate)
			if cell != null: _update_cell(cell, next_classic_rect)
	_map_id = _map_view.map_id
	_camera_coordinate = camera
	_classic_rect = next_classic_rect
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


func party_rect() -> Rect2:
	return _party_rect


func minimap_rect() -> Rect2:
	if not _show_minimap or _map_view == null:
		return Rect2()
	var scale := minf(_minimap_size / float(_map_view.width), _minimap_size / float(_map_view.height))
	var pixel_size := Vector2(_map_view.width, _map_view.height) * scale
	var origin := Vector2(size.x - pixel_size.x - 8.0, size.y - pixel_size.y - 8.0)
	return Rect2(origin - Vector2.ONE * 4.0, pixel_size + Vector2.ONE * 8.0)


func _update_cell(cell: MapCellView, current_classic_rect: Rect2i) -> void:
	_erase_coordinate(cell.coordinate)
	var los := _map_view.uses_los
	if ClassicMapPresenter.los_cell_requires_blackout(los, cell.visible):
		_set_fog(cell.coordinate)
		return
	var revealed := _dungeon_discovery if _map_view.level_type == &"dungeon" else _land_discovery
	var outside_classic := not los and _classic_visibility and not current_classic_rect.has_point(cell.coordinate)
	if outside_classic and not revealed.has(cell.coordinate):
		return
	if _map_view.level_type == &"dungeon":
		if not cell.has_feature(&"unmapped") or _dungeon_discovery.has(cell.coordinate):
			var tiles := _dungeon_tile_ids(cell)
			_set_atlas_cell(_base_layer, cell.coordinate, cell.tileset_id, tiles[0])
			for index: int in mini(_feature_layers.size(), tiles.size() - 1):
				_set_atlas_cell(_feature_layers[index], cell.coordinate, cell.tileset_id, tiles[index + 1])
	else:
		_set_atlas_cell(_base_layer, cell.coordinate, cell.tileset_id, cell.render_tile)
		if not cell.overlay_asset_id.is_empty(): _set_overlay(cell.coordinate, cell.overlay_asset_id)
		if cell.has_feature(&"secret"): _set_transparent_marker_cell(_marker_layer, cell.coordinate, SECRET_TILE_ID)
		if cell.has_feature(&"discovered_path"): _set_transparent_marker_cell(_feature_layers[0], cell.coordinate, PATH_TILE_ID)


func _erase_coordinate(coordinate: Vector2i) -> void:
	_base_layer.erase_cell(coordinate)
	_marker_layer.erase_cell(coordinate)
	_fog_layer.erase_cell(coordinate)
	for layer: TileMapLayer in _feature_layers: layer.erase_cell(coordinate)
	var overlay := _overlay_sprites.get(coordinate) as Sprite2D
	if overlay != null:
		overlay.visible = false


func _set_atlas_cell(layer: TileMapLayer, coordinate: Vector2i, asset_id: String, tile_id: int) -> void:
	var source := _atlas_source(asset_id)
	if source.is_empty():
		return
	var asset: MediaAsset = source[1]
	var atlas_index := maxi(tile_id - 1, 0)
	var atlas_coordinate := Vector2i(atlas_index % asset.columns, floori(float(atlas_index) / asset.columns))
	layer.set_cell(coordinate, int(source[0]), atlas_coordinate)


func _set_transparent_marker_cell(layer: TileMapLayer, coordinate: Vector2i, tile_id: int) -> void:
	var source_id := _transparent_marker_source(tile_id)
	if source_id >= 0:
		layer.set_cell(coordinate, source_id, Vector2i.ZERO)


func _transparent_marker_source(tile_id: int) -> int:
	if _transparent_marker_source_by_tile_id.has(tile_id):
		return int(_transparent_marker_source_by_tile_id[tile_id])
	if _media == null:
		return -1
	var asset := _media.asset_by_id(BATTLE_ATLAS_ID)
	var texture := _media.image_texture(asset) if asset != null else null
	var marker := transparent_marker_tile(asset, texture, tile_id)
	if marker == null:
		return -1
	var atlas := TileSetAtlasSource.new()
	atlas.texture = marker
	atlas.texture_region_size = marker.get_size()
	atlas.create_tile(Vector2i.ZERO)
	var source_id := _tile_set.add_source(atlas)
	_transparent_marker_source_by_tile_id[tile_id] = source_id
	return source_id


static func transparent_marker_tile(atlas: MediaAsset, texture: Texture2D, tile_id: int) -> ImageTexture:
	return ClassicMapPresenter.transparent_atlas_tile(atlas, texture, tile_id)


func _atlas_source(asset_id: String) -> Array:
	if _source_by_asset_id.has(asset_id):
		return _source_by_asset_id[asset_id]
	if _missing_sources.has(asset_id) or _media == null:
		return []
	var asset := _media.asset_by_id(asset_id)
	var texture := _media.image_texture(asset) if asset != null else null
	if asset == null or texture == null or not asset.is_tileset() and not asset.is_battle_tileset():
		_missing_sources[asset_id] = true
		return []
	var retained_texture := _retained_atlas_texture(asset, texture, _tile_set.tile_size)
	if retained_texture == null:
		_missing_sources[asset_id] = true
		return []
	var atlas := TileSetAtlasSource.new()
	atlas.texture = retained_texture
	atlas.texture_region_size = _tile_set.tile_size
	for y: int in asset.rows:
		for x: int in asset.columns: atlas.create_tile(Vector2i(x, y))
	var source_id := _tile_set.add_source(atlas)
	var result: Array = [source_id, asset]
	_source_by_asset_id[asset_id] = result
	return result


static func _retained_atlas_texture(asset: MediaAsset, texture: Texture2D, cell_size: Vector2i) -> Texture2D:
	var source_tile_size := Vector2i(asset.tile_width, asset.tile_height)
	if source_tile_size == cell_size:
		return texture
	var source := texture.get_image()
	if source == null or source_tile_size.x <= 0 or source_tile_size.y <= 0 or cell_size.x <= 0 or cell_size.y <= 0:
		return null
	var source_extent := source_tile_size * Vector2i(asset.columns, asset.rows)
	if source.get_width() < source_extent.x or source.get_height() < source_extent.y:
		return null
	source.convert(Image.FORMAT_RGBA8)
	var retained := Image.create(cell_size.x * asset.columns, cell_size.y * asset.rows, false, Image.FORMAT_RGBA8)
	retained.fill(Color.TRANSPARENT)
	for y: int in asset.rows:
		for x: int in asset.columns:
			var source_origin := Vector2i(x, y) * source_tile_size
			var tile := source.get_region(Rect2i(source_origin, source_tile_size))
			tile.resize(cell_size.x, cell_size.y, Image.INTERPOLATE_NEAREST)
			retained.blit_rect(tile, Rect2i(Vector2i.ZERO, cell_size), Vector2i(x, y) * cell_size)
	return ImageTexture.create_from_image(retained)


func _set_overlay(coordinate: Vector2i, asset_id: String) -> void:
	if _media == null:
		return
	var asset := _media.asset_by_id(asset_id)
	var texture := _media.image_texture(asset) if asset != null else null
	if texture == null:
		return
	var sprite := _overlay_sprites.get(coordinate) as Sprite2D
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.centered = true
		sprite.z_index = 10
		_viewport.add_child(sprite)
		_overlay_sprites[coordinate] = sprite
	sprite.texture = texture
	sprite.position = (Vector2(coordinate) + Vector2.ONE * 0.5) * _cell_size
	sprite.scale = _texture_scale(texture)
	sprite.visible = true


func _texture_scale(texture: Texture2D) -> Vector2:
	if texture == null or texture.get_size().x <= 0.0 or texture.get_size().y <= 0.0:
		return Vector2.ONE
	return Vector2(_cell_size / texture.get_size().x, _cell_size / texture.get_size().y)


func _build_fog_tiles() -> void:
	_fog_tile_set.tile_size = Vector2i(32, 32)
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(32, 32)
	atlas.create_tile(Vector2i.ZERO)
	_fog_tile_set.add_source(atlas, 0)


func _set_fog(coordinate: Vector2i) -> void:
	_fog_layer.set_cell(coordinate, 0, Vector2i.ZERO)


func _clear_layers() -> void:
	if _base_layer == null: return
	_base_layer.clear(); _marker_layer.clear(); _fog_layer.clear()
	for layer: TileMapLayer in _feature_layers: layer.clear()
	for sprite: Sprite2D in _overlay_sprites.values(): sprite.visible = false


func _resize_viewport() -> void:
	if _viewport == null: return
	_viewport.size = Vector2i(maxi(1, roundi(size.x)), maxi(1, roundi(size.y)))
	_background.size = Vector2(_viewport.size)


func _draw() -> void:
	if _map_view == null: return
	if _map_view.dark:
		_draw_darkness_mask(_map_view.darkness_level)
	if _show_minimap:
		_draw_minimap()


func _draw_darkness_mask(level: int) -> void:
	var surface_rect := Rect2(Vector2.ZERO, size)
	var mask_rect := ClassicMapPresenter.darkness_mask_rect(_party_rect)
	var clipped := _map_rect.intersection(mask_rect)
	for blackout_rect: Rect2 in darkness_blackout_rects(surface_rect, clipped):
		draw_rect(blackout_rect, Color.BLACK)
	_draw_darkness_memory(clipped)
	var texture := _darkness_texture(level)
	if texture == null:
		draw_rect(clipped, Color.BLACK)
		return
	draw_texture_rect_region(texture, clipped, Rect2(clipped.position - mask_rect.position, clipped.size))


func _draw_darkness_memory(lit_rect: Rect2) -> void:
	if _viewport == null or _map_view == null:
		return
	var discovered := _seen if _map_view.uses_los else _dungeon_discovery if _map_view.level_type == &"dungeon" else _land_discovery
	var viewport_cells := Vector2i(roundi(_map_rect.size.x / _cell_size), roundi(_map_rect.size.y / _cell_size))
	var viewport_texture := _viewport.get_texture()
	var memory_color := Color(1.0, 1.0, 1.0, 1.0 - DARKNESS_MEMORY_OPACITY)
	for memory_rect: Rect2 in darkness_memory_rects(_map_rect, _camera_coordinate, viewport_cells, _cell_size, discovered):
		for visible_part: Rect2 in _rect_parts_outside(memory_rect, lit_rect):
			draw_texture_rect_region(viewport_texture, visible_part, visible_part, memory_color)


static func darkness_blackout_rects(surface_rect: Rect2, lit_rect: Rect2) -> Array[Rect2]:
	return _rect_parts_outside(surface_rect, surface_rect.intersection(lit_rect))


static func darkness_memory_rects(map_rect: Rect2, camera: Vector2i, viewport_cells: Vector2i, cell_size: float, discovered: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for local_y: int in viewport_cells.y:
		var run_start := -1
		for local_x: int in range(viewport_cells.x + 1):
			var recalled := local_x < viewport_cells.x and discovered.has(camera + Vector2i(local_x, local_y))
			if recalled and run_start < 0:
				run_start = local_x
			elif not recalled and run_start >= 0:
				result.append(Rect2(map_rect.position + Vector2(run_start, local_y) * cell_size, Vector2(local_x - run_start, 1) * cell_size))
				run_start = -1
	return result


static func darkness_memory_opacity() -> float:
	return DARKNESS_MEMORY_OPACITY


static func _rect_parts_outside(outer: Rect2, inner: Rect2) -> Array[Rect2]:
	if not outer.has_area():
		return []
	var clipped := outer.intersection(inner)
	if not clipped.has_area():
		return [outer]
	var result: Array[Rect2] = []
	if clipped.position.y > outer.position.y:
		result.append(Rect2(outer.position, Vector2(outer.size.x, clipped.position.y - outer.position.y)))
	if clipped.end.y < outer.end.y:
		result.append(Rect2(Vector2(outer.position.x, clipped.end.y), Vector2(outer.size.x, outer.end.y - clipped.end.y)))
	if clipped.position.x > outer.position.x:
		result.append(Rect2(Vector2(outer.position.x, clipped.position.y), Vector2(clipped.position.x - outer.position.x, clipped.size.y)))
	if clipped.end.x < outer.end.x:
		result.append(Rect2(Vector2(clipped.end.x, clipped.position.y), Vector2(outer.end.x - clipped.end.x, clipped.size.y)))
	return result


func _darkness_texture(level: int) -> Texture2D:
	var key := clampi(level, 0, 6)
	if _darkness_masks.has(key): return _darkness_masks[key]
	if _media == null: return null
	var asset := _media.asset_by_id("classic-darkness-mask-%d" % key)
	var texture := _media.image_texture(asset) if asset != null else null
	if texture == null: return null
	var image := texture.get_image(); image.convert(Image.FORMAT_RGBA8)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var alpha := image.get_pixel(x, y).get_luminance()
			image.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))
	var result := ImageTexture.create_from_image(image)
	_darkness_masks[key] = result
	return result


func _draw_minimap() -> void:
	var scale := minf(_minimap_size / float(_map_view.width), _minimap_size / float(_map_view.height))
	var pixel_size := Vector2(_map_view.width, _map_view.height) * scale
	var origin := Vector2(size.x - pixel_size.x - 8.0, size.y - pixel_size.y - 8.0)
	draw_rect(Rect2(origin - Vector2.ONE * 4.0, pixel_size + Vector2.ONE * 8.0), Color(0.035, 0.04, 0.05, 0.9))
	for coordinate: Vector2i in _visited: draw_rect(Rect2(origin + Vector2(coordinate) * scale, Vector2.ONE * maxf(scale, 1.0)), Color(0.28, 0.48, 0.32))
	var center := origin + (Vector2(_map_view.party_coordinate) + Vector2.ONE * 0.5) * scale
	draw_circle(center, maxf(2.0, scale * 1.5), Color(0.94, 0.78, 0.28))


static func _dungeon_tile_ids(cell: MapCellView) -> Array[int]:
	var result: Array[int] = [16]
	if cell.terrain_id == "classic.dungeon.wall": result.append(1)
	if cell.has_feature(&"door"): result.append(3 if cell.feature_orientation(&"door") == &"vertical" else 2)
	for feature_kind: StringName in [&"stairs", &"column", &"note"]:
		if cell.has_feature(feature_kind): result.append({&"stairs": 4, &"column": 5, &"note": 6}[feature_kind])
	if cell.has_feature(&"secret"): result.append({&"north": 9, &"east": 10, &"south": 11, &"west": 12}.get(cell.feature_orientation(&"secret"), 7))
	if cell.has_feature(&"unmapped"): result.append(8)
	result.sort()
	result.erase(16)
	result.push_front(16)
	return result


static func _rect_changed_coordinates(previous: Rect2i, current: Rect2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in range(current.position.y, current.end.y):
		for x: int in range(current.position.x, current.end.x):
			var coordinate := Vector2i(x, y)
			if not previous.has_point(coordinate): result.append(coordinate)
	return result
