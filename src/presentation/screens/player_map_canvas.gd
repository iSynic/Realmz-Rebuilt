class_name PlayerMapCanvas
extends Control

const MAP_SIZE: int = 320

var _view: PlayerMapView
var _media: ClassicMediaCatalog
var _textures: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func present(view: PlayerMapView, media: ClassicMediaCatalog) -> void:
	_view = view
	_media = media
	_textures.clear()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE)), Color.BLACK, true)
	if _view == null or _media == null:
		return
	if _view.mode == PlayerMapDefinition.PICTURE:
		_draw_picture()
	elif _view.mode in [PlayerMapDefinition.LAND_CROP, PlayerMapDefinition.DUNGEON_CROP]:
		_draw_crop()
	else:
		return
	_draw_party_marker()


func _draw_picture() -> void:
	var texture := _texture_for(_view.picture_asset_id)
	if texture == null:
		return
	var destination := Rect2(_view.picture_rect)
	if destination.size.x <= 0.0 or destination.size.y <= 0.0:
		destination = Rect2(Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE))
	draw_texture_rect(texture, destination, false)


func _draw_crop() -> void:
	var cell_size := float(_view.icon_size)
	for cell: MapCellView in _view.cells:
		var destination := Rect2(Vector2(cell.coordinate - _view.start) * cell_size, Vector2.ONE * cell_size)
		_draw_cell(cell, destination)
	for marker: PlayerMapMarkerDefinition in _view.markers:
		var texture := _texture_for(marker.icon_asset_id)
		if texture == null:
			continue
		var marker_size := 32.0 if marker.classic_icon_id in [137, 139] else cell_size
		var center := Vector2(marker.coordinate) * cell_size + Vector2.ONE * cell_size * 0.5
		draw_texture_rect(texture, Rect2(center - Vector2.ONE * marker_size * 0.5, Vector2.ONE * marker_size), false)


func _draw_cell(cell: MapCellView, destination: Rect2) -> void:
	var atlas := _media.asset_by_id(cell.tileset_id)
	var texture := _texture_for(cell.tileset_id)
	if _view.mode == PlayerMapDefinition.DUNGEON_CROP and atlas != null and texture != null and atlas.id == "dungeon-top-down-302":
		_draw_atlas_region(destination, atlas, texture, 16)
		if cell.terrain_id == "classic.dungeon.wall":
			_draw_atlas_region(destination, atlas, texture, 1)
		if cell.has_feature(&"door"):
			_draw_atlas_region(destination, atlas, texture, 3 if cell.feature_orientation(&"door") == &"vertical" else 2)
		var feature_tiles: Dictionary = {&"stairs": 4, &"column": 5, &"note": 6, &"secret": 7}
		for feature_kind: StringName in feature_tiles:
			if cell.has_feature(feature_kind):
				_draw_atlas_region(destination, atlas, texture, int(feature_tiles[feature_kind]))
	else:
		var region := Rect2i() if atlas == null else atlas.region_for(cell.render_tile)
		if texture != null and region.has_area():
			draw_texture_rect_region(texture, destination, Rect2(region))
	var overlay := _texture_for(cell.overlay_asset_id)
	if overlay != null:
		draw_texture_rect(overlay, destination, false)


func _draw_atlas_region(destination: Rect2, atlas: PackageMediaAsset, texture: Texture2D, tile_id: int) -> void:
	var region := atlas.region_for(tile_id)
	if region.has_area():
		draw_texture_rect_region(texture, destination, Rect2(region))


func _draw_party_marker() -> void:
	if not _view.party_marker_visible:
		return
	var texture := _texture_for(_view.party_marker_asset_id)
	if texture == null:
		return
	var origin := Vector2(_view.party_coordinate - _view.start) * float(_view.icon_size)
	draw_texture_rect(texture, Rect2(origin - Vector2(20.0, 24.0), Vector2(64.0, 64.0)), false)


func _texture_for(asset_id: String) -> Texture2D:
	if asset_id.is_empty() or _media == null:
		return null
	if _textures.has(asset_id):
		return _textures[asset_id] as Texture2D
	var asset := _media.asset_by_id(asset_id)
	if asset == null or not asset.is_picture():
		return null
	var bytes := _media.read_bytes(asset)
	if bytes.is_empty():
		return null
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	match asset.mime_type:
		"image/png":
			error = image.load_png_from_buffer(bytes)
		"image/jpeg":
			error = image.load_jpg_from_buffer(bytes)
		"image/webp":
			error = image.load_webp_from_buffer(bytes)
	if error != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_textures[asset_id] = texture
	return texture
