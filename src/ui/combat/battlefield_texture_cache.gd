## Retains decoded battlefield atlases, combatants, and keyed spell-effect textures.

class_name BattlefieldTextureCache
extends RefCounted

var _media: ClassicMediaCatalog
var _atlas_asset: MediaAsset
var _atlas_texture: Texture2D
var _upper_atlas_id := ""
var _upper_atlas_asset: MediaAsset
var _upper_atlas_texture: Texture2D
var _actor_textures: Dictionary = {}


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	_media = media
	_atlas_asset = null
	_atlas_texture = null
	_upper_atlas_id = ""
	_upper_atlas_asset = null
	_upper_atlas_texture = null
	_actor_textures.clear()


func prepare(upper_atlas_id: String) -> void:
	if _media != null and _atlas_texture == null:
		_atlas_asset = _media.battle_tileset()
		_atlas_texture = _load_image_texture(_atlas_asset)
	if upper_atlas_id == _upper_atlas_id:
		return
	_upper_atlas_id = upper_atlas_id
	_upper_atlas_asset = _media.tileset_by_id(_upper_atlas_id) if _media != null and not _upper_atlas_id.is_empty() else null
	_upper_atlas_texture = _load_image_texture(_upper_atlas_asset)


func has_battle_artwork() -> bool:
	if _atlas_asset == null or _atlas_texture == null:
		return false
	return _upper_atlas_id.is_empty() or _upper_atlas_asset != null and _upper_atlas_texture != null


func terrain_asset(tile_id: int) -> MediaAsset:
	return _upper_atlas_asset if tile_id <= 200 and not _upper_atlas_id.is_empty() else _atlas_asset


func terrain_texture(tile_id: int) -> Texture2D:
	return _upper_atlas_texture if tile_id <= 200 and not _upper_atlas_id.is_empty() else _atlas_texture


func battle_atlas_asset() -> MediaAsset:
	return _atlas_asset


func battle_atlas_texture() -> Texture2D:
	return _atlas_texture


static func persistent_field_tile_id(queue_icon: int) -> int:
	return 200 + queue_icon


func actor_texture(asset: MediaAsset) -> Texture2D:
	if asset == null:
		return null
	if _actor_textures.has(asset.id):
		return _actor_textures[asset.id] as Texture2D
	var texture := _load_image_texture(asset)
	_actor_textures[asset.id] = texture
	return texture


func effect_texture(asset: MediaAsset) -> Texture2D:
	if asset == null:
		return null
	var cache_key := "effect:%s" % asset.id
	if _actor_textures.has(cache_key):
		return _actor_textures[cache_key] as Texture2D
	var texture := remove_opaque_white_matte(_load_image_texture(asset))
	_actor_textures[cache_key] = texture
	return texture


func _load_image_texture(asset: MediaAsset) -> Texture2D:
	return _media.image_texture(asset) if _media != null else null


static func remove_opaque_white_matte(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var seeds: Array[Vector2i] = [Vector2i.ZERO, Vector2i(width - 1, 0), Vector2i(0, height - 1), Vector2i(width - 1, height - 1)]
	if not seeds.any(func(point: Vector2i) -> bool: return _is_opaque_white(image.get_pixelv(point))):
		return texture
	var visited := PackedByteArray()
	visited.resize(width * height)
	var pending: Array[Vector2i] = seeds
	while not pending.is_empty():
		var point: Vector2i = pending.pop_back()
		var index := point.y * width + point.x
		if visited[index] != 0:
			continue
		visited[index] = 1
		var color := image.get_pixelv(point)
		if not _is_opaque_white(color):
			continue
		image.set_pixelv(point, Color(color.r, color.g, color.b, 0.0))
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor := point + direction
			if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < width and neighbor.y < height:
				pending.append(neighbor)
	return ImageTexture.create_from_image(image)


static func _is_opaque_white(color: Color) -> bool:
	return color.a > 0.98 and color.r > 0.92 and color.g > 0.92 and color.b > 0.92
