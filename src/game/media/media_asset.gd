class_name MediaAsset
extends RefCounted

var id: String
var label: String
var kind: String
var mime_type: String
var resource_type: String
var resource_id: int
var byte_count: int
var sha256: String
var path: String
var width: int
var height: int
var duration_ms: int
var sample_rate: int
var channels: int
var tile_width: int
var tile_height: int
var columns: int
var rows: int
var landlook: int
var base_tile: int
var scenario_music_slot: int


func _init(asset_id: String, asset_label: String, asset_kind: String, asset_mime_type: String, asset_resource_type: String, asset_resource_id: int, asset_byte_count: int, asset_sha256: String, asset_path: String, asset_width: int, asset_height: int, asset_duration_ms: int, asset_sample_rate: int, asset_channels: int, asset_tile_width: int, asset_tile_height: int, asset_columns: int, asset_rows: int, asset_landlook: int, asset_base_tile: int, custom_music_slot: int = 0) -> void:
	id = asset_id
	label = asset_label
	kind = asset_kind
	mime_type = asset_mime_type
	resource_type = asset_resource_type
	resource_id = asset_resource_id
	byte_count = asset_byte_count
	sha256 = asset_sha256
	path = asset_path
	width = asset_width
	height = asset_height
	duration_ms = asset_duration_ms
	sample_rate = asset_sample_rate
	channels = asset_channels
	tile_width = asset_tile_width
	tile_height = asset_tile_height
	columns = asset_columns
	rows = asset_rows
	landlook = asset_landlook
	base_tile = asset_base_tile
	scenario_music_slot = custom_music_slot


func is_picture() -> bool:
	return mime_type.begins_with("image/") or kind.to_lower() in ["picture", "icon", "special-land-tile"] or resource_type.strip_edges().to_upper() in ["PICT", "ICON", "CICN"]


func is_sound() -> bool:
	return mime_type.begins_with("audio/") or kind.to_lower() in ["sound", "music"] or resource_type.strip_edges().to_upper() in ["SND", "MOD"]


func is_tileset() -> bool:
	return kind == "tileset" and mime_type.begins_with("image/") and tile_width > 0 and tile_height > 0 and columns > 0 and rows > 0


func is_battle_tileset() -> bool:
	return kind == "battle-tileset" and mime_type.begins_with("image/") and tile_width == 32 and tile_height == 32 and columns == 20 and rows == 20 and width == 640 and height == 640


func region_for(tile_id: int) -> Rect2i:
	if not is_tileset() and not is_battle_tileset():
		return Rect2i()
	# Castle's tile artwork is one-based. Zero-valued combat-build cells do not
	# alias the first atlas cell; treating them as tile one creates jumbled 3x3
	# patches wherever an authored mapstats record intentionally leaves a build
	# cell empty.
	if tile_id <= 0:
		return Rect2i()
	var atlas_index := tile_id - 1
	if atlas_index >= columns * rows:
		return Rect2i()
	return Rect2i((atlas_index % columns) * tile_width, floori(float(atlas_index) / float(columns)) * tile_height, tile_width, tile_height)
