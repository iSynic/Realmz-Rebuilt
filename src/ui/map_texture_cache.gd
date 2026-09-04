## Retains decoded map atlases, overlays, darkness masks, and land markers.

class_name MapTextureCache
extends RefCounted

const CLASSIC_BATTLE_ATLAS_ID := "classic-battle-tiles-302"

var _media: ClassicMediaCatalog
var _atlas_assets: Dictionary = {}
var _atlas_textures: Dictionary = {}
var _image_textures: Dictionary = {}
var _darkness_mask_textures: Dictionary = {}
var _land_marker_textures: Dictionary = {}
var _missing_assets: Dictionary = {}


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	_media = media
	_atlas_assets.clear()
	_atlas_textures.clear()
	_image_textures.clear()
	_darkness_mask_textures.clear()
	_land_marker_textures.clear()
	_missing_assets.clear()


func atlas_asset(asset_id: String) -> MediaAsset:
	_ensure_atlas(asset_id)
	return _atlas_assets.get(asset_id) as MediaAsset


func atlas_texture(asset_id: String) -> Texture2D:
	_ensure_atlas(asset_id)
	return _atlas_textures.get(asset_id) as Texture2D


func image_texture(asset_id: String) -> Texture2D:
	if asset_id.is_empty() or _media == null:
		return null
	if _image_textures.has(asset_id):
		return _image_textures[asset_id] as Texture2D
	if _missing_assets.has(asset_id):
		return null
	var texture := _load_image_texture(_media.asset_by_id(asset_id))
	if texture == null:
		_missing_assets[asset_id] = true
		return null
	_image_textures[asset_id] = texture
	return texture


func darkness_mask_texture(level: int) -> Texture2D:
	var bounded_level := clampi(level, 0, 6)
	if _darkness_mask_textures.has(bounded_level):
		return _darkness_mask_textures[bounded_level] as Texture2D
	var asset_id := "classic-darkness-mask-%d" % bounded_level
	if _missing_assets.has(asset_id) or _media == null:
		return null
	var source := image_texture(asset_id)
	var texture := _darkness_overlay_texture(source) if source != null else null
	if texture == null:
		_missing_assets[asset_id] = true
		return null
	_darkness_mask_textures[bounded_level] = texture
	return texture


func land_marker_texture(tile_id: int) -> Texture2D:
	if _land_marker_textures.has(tile_id):
		return _land_marker_textures[tile_id] as Texture2D
	var texture := transparent_atlas_tile(atlas_asset(CLASSIC_BATTLE_ATLAS_ID), atlas_texture(CLASSIC_BATTLE_ATLAS_ID), tile_id)
	if texture != null:
		_land_marker_textures[tile_id] = texture
	return texture


func _ensure_atlas(asset_id: String) -> void:
	if asset_id.is_empty() or _atlas_assets.has(asset_id) or _missing_assets.has(asset_id) or _media == null:
		return
	var asset := _media.asset_by_id(asset_id)
	if asset == null or not asset.is_tileset() and not asset.is_battle_tileset():
		_missing_assets[asset_id] = true
		return
	var texture := _load_image_texture(asset)
	if texture == null:
		_missing_assets[asset_id] = true
		return
	_atlas_assets[asset_id] = asset
	_atlas_textures[asset_id] = texture


func _load_image_texture(asset: MediaAsset) -> Texture2D:
	return _media.image_texture(asset) if _media != null else null


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
