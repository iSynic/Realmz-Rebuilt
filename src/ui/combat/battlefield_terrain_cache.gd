## Retains an exact native-pixel terrain surface between actor animation frames.
class_name BattlefieldTerrainCache
extends RefCounted

var _view: BattlefieldView
var _camera := Vector2i(-1, -1)
var _cells := Vector2i.ZERO
var _tiles: Array[int] = []
var _texture: ImageTexture
var _upper_atlas_id := ""


func texture_for(view: BattlefieldView, textures: BattlefieldTextureCache, camera: Vector2i, cells: Vector2i) -> ImageTexture:
	if view == _view and camera == _camera and cells == _cells: return _texture
	var tiles: Array[int] = []
	for y: int in cells.y:
		for x: int in cells.x:
			tiles.append(view.terrain_at(camera + Vector2i(x, y)))
	var reusable := cells == _cells and tiles == _tiles and view.upper_tileset_id == _upper_atlas_id
	_view = view
	_camera = camera
	_cells = cells
	_tiles = tiles
	_upper_atlas_id = view.upper_tileset_id
	if not reusable: _texture = _compose(textures, tiles, cells)
	return _texture


static func _compose(textures: BattlefieldTextureCache, tiles: Array[int], cells: Vector2i) -> ImageTexture:
	var surface := Image.create(cells.x * 32, cells.y * 32, false, Image.FORMAT_RGBA8)
	var images: Dictionary = {}
	var tile_images: Dictionary = {}
	for index: int in tiles.size():
		var tile_id := tiles[index]
		if not tile_images.has(tile_id):
			var asset := textures.terrain_asset(tile_id)
			var texture := textures.terrain_texture(tile_id)
			var region := Rect2i() if asset == null else asset.region_for(tile_id)
			if texture == null or not region.has_area(): return null
			if not images.has(texture): images[texture] = texture.get_image()
			var source := images[texture] as Image
			if not Rect2i(Vector2i.ZERO, source.get_size()).encloses(region): return null
			var tile := source.get_region(region)
			if tile.get_size() != Vector2i(32, 32): tile.resize(32, 32, Image.INTERPOLATE_NEAREST)
			tile.convert(Image.FORMAT_RGBA8)
			tile_images[tile_id] = tile
		surface.blit_rect(tile_images[tile_id], Rect2i(0, 0, 32, 32), Vector2i(index % cells.x, index / cells.x) * 32)
	return ImageTexture.create_from_image(surface)
