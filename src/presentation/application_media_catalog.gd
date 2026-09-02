class_name ApplicationMediaCatalog
extends MediaSource

const MANIFEST_PATH := "res://src/presentation/assets/classic-application-media.json"
const CASTLE_SOURCE_COMMIT := "491816ad60037394f92c428e99c004494d3c28b3"

var source_commit: String = ""
var last_error: String = ""
var _assets: Array[MediaAsset] = []
var _assets_by_id: Dictionary = {}
var _assets_by_resource: Dictionary = {}
var _ambiguous_resource_keys: Dictionary = {}


func _init(manifest_path: String = MANIFEST_PATH) -> void:
	_load_manifest(manifest_path)


func is_valid() -> bool:
	return last_error.is_empty() and not _assets.is_empty()


func assets() -> Array[MediaAsset]:
	return _assets.duplicate()


func asset_by_id(asset_id: String) -> MediaAsset:
	return _assets_by_id.get(asset_id) as MediaAsset


func asset_by_resource(resource_type: String, resource_id: int) -> MediaAsset:
	if resource_type.is_empty():
		return null
	return _assets_by_resource.get(_resource_key(resource_type, resource_id)) as MediaAsset


func resource_status(resource_type: String, resource_id: int) -> StringName:
	if resource_type.is_empty():
		return &"missing"
	var key := _resource_key(resource_type, resource_id)
	if _ambiguous_resource_keys.has(key):
		return &"ambiguous"
	return &"resolved" if _assets_by_resource.has(key) else &"missing"


func owns_asset(asset: MediaAsset) -> bool:
	return asset != null and _assets.has(asset)


func read_bytes(asset: MediaAsset) -> PackedByteArray:
	if not owns_asset(asset):
		return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(asset.path)
	if bytes.size() != asset.byte_count or _sha256(bytes) != asset.sha256:
		return PackedByteArray()
	return bytes


func audio_stream(asset: MediaAsset) -> AudioStream:
	if not owns_asset(asset) or not asset.is_sound():
		return null
	return load(asset.path) as AudioStream


func _load_manifest(manifest_path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		last_error = "Classic application media manifest is unavailable or malformed."
		return
	var manifest := parsed as Dictionary
	if int(manifest.get("schema_version", 0)) != 1 or String(manifest.get("lookup", "")) != "scenario-first-application-fallback":
		last_error = "Classic application media manifest contract is unsupported."
		return
	source_commit = String(manifest.get("source_commit", ""))
	if source_commit != CASTLE_SOURCE_COMMIT:
		last_error = "Classic application media source revision is unsupported."
		return
	for value: Variant in manifest.get("assets", []):
		if not value is Dictionary:
			last_error = "Classic application media contains a malformed asset."
			return
		var record := value as Dictionary
		var asset := MediaAsset.new(
			String(record.get("id", "")),
			String(record.get("label", "")),
			String(record.get("kind", "")),
			String(record.get("mime_type", "")),
			String(record.get("resource_type", "")),
			int(record.get("resource_id", 0)),
			int(record.get("bytes", 0)),
			String(record.get("sha256", "")),
			String(record.get("path", "")),
			int(record.get("width", 0)),
			int(record.get("height", 0)),
			int(record.get("duration_ms", 0)),
			int(record.get("sample_rate", 0)),
			int(record.get("channels", 0)),
			int(record.get("tile_width", 0)),
			int(record.get("tile_height", 0)),
			int(record.get("columns", 0)),
			int(record.get("rows", 0)),
			int(record.get("landlook", -1)),
			int(record.get("base_tile", -1))
		)
		if asset.id.is_empty() or asset.resource_type.is_empty() or asset.path.is_empty() or asset.byte_count <= 0 or asset.sha256.length() != 64:
			last_error = "Classic application media contains an incomplete asset."
			return
		if _assets_by_id.has(asset.id):
			last_error = "Classic application media contains duplicate asset IDs."
			return
		_assets.append(asset)
		_assets_by_id[asset.id] = asset
		var key := _resource_key(asset.resource_type, asset.resource_id)
		if _ambiguous_resource_keys.has(key):
			continue
		if _assets_by_resource.has(key):
			_assets_by_resource.erase(key)
			_ambiguous_resource_keys[key] = true
			last_error = "Classic application media contains duplicate resource keys."
			continue
		_assets_by_resource[key] = asset


static func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(bytes) != OK:
		return ""
	return hashing.finish().hex_encode()


static func _resource_key(resource_type: String, resource_id: int) -> String:
	return JSON.stringify([resource_type, resource_id])
