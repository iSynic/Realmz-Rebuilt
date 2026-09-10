## Retains decoded map atlases, overlays, darkness masks, and land markers.

class_name MapTextureCache
extends RefCounted

const SECRET_LAND_MARKER_TILE_ID := 251
const PATH_LAND_MARKER_TILE_ID := 253
const PARTY_MARKER_LEFT_ASSET_ID: StringName = &"map.party.left"
const PARTY_MARKER_RIGHT_ASSET_ID: StringName = &"map.party.right"
const PARTY_MARKER_CAMP_ASSET_ID: StringName = &"map.party.camp"
const DUNGEON_PARTY_ARROWS_ASSET_ID: StringName = &"map.party.dungeon.arrows"
const BOAT_MARKER_LEFT_ASSET_IDS: Dictionary = {0: &"map.party.boat.left.0", 3: &"map.party.boat.left.3", 5: &"map.party.boat.left.5", 6: &"map.party.boat.left.6", 7: &"map.party.boat.left.7"}
const BOAT_MARKER_RIGHT_ASSET_IDS: Dictionary = {0: &"map.party.boat.right.0", 3: &"map.party.boat.right.3", 5: &"map.party.boat.right.5", 6: &"map.party.boat.right.6", 7: &"map.party.boat.right.7"}

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


func atlas_asset(asset_id: String) -> ClassicMapAtlas:
	_ensure_atlas(asset_id)
	return _atlas_assets.get(asset_id) as ClassicMapAtlas


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
	var asset := _media.battle_tileset() if _media != null else null
	var texture := transparent_atlas_tile(asset, _media.image_texture(asset) if asset != null else null, tile_id)
	if texture != null:
		_land_marker_textures[tile_id] = texture
	return texture


static func darkness_mask_asset_id(level: int) -> String:
	return "classic-darkness-mask-%d" % clampi(level, 0, 6)


static func land_marker_tile_ids(cell: MapCellView) -> Array[int]:
	var result: Array[int] = []
	if cell != null and cell.has_feature(&"secret"):
		result.append(SECRET_LAND_MARKER_TILE_ID)
	if cell != null and cell.has_feature(&"discovered_path"):
		result.append(PATH_LAND_MARKER_TILE_ID)
	return result


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


func _ensure_atlas(asset_id: String) -> void:
	if asset_id.is_empty() or _atlas_assets.has(asset_id) or _missing_assets.has(asset_id) or _media == null:
		return
	var atlas := _media.map_atlas(asset_id)
	if atlas == null:
		_missing_assets[asset_id] = true
		return
	_atlas_assets[asset_id] = atlas
	_atlas_textures[asset_id] = atlas.texture


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
