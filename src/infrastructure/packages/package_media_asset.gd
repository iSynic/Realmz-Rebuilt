class_name PackageMediaAsset
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


func _init(asset_id: String, asset_label: String, asset_kind: String, asset_mime_type: String, asset_resource_type: String, asset_resource_id: int, asset_byte_count: int, asset_sha256: String, asset_path: String, asset_width: int, asset_height: int, asset_duration_ms: int, asset_sample_rate: int, asset_channels: int) -> void:
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


func is_picture() -> bool:
	return mime_type.begins_with("image/") or kind.to_lower() in ["picture", "icon", "special-land-tile"] or resource_type.strip_edges().to_upper() in ["PICT", "ICON", "CICN"]


func is_sound() -> bool:
	return mime_type.begins_with("audio/") or kind.to_lower() in ["sound", "music"] or resource_type.strip_edges().to_upper() in ["SND", "MOD"]
