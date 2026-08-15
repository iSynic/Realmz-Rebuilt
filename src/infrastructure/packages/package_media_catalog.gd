class_name PackageMediaCatalog
extends MediaSource

var package_path: String
var package_hash: String
var _assets: Array[MediaAsset]
var _assets_by_id: Dictionary = {}
var _assets_by_resource: Dictionary = {}
var _ambiguous_resource_keys: Dictionary = {}


func _init(source_path: String, content_hash: String, indexed_assets: Array[MediaAsset]) -> void:
	package_path = source_path
	package_hash = content_hash
	_assets = indexed_assets.duplicate()
	for asset: MediaAsset in _assets:
		_assets_by_id[asset.id] = asset
		if asset.resource_type.is_empty():
			continue
		var key := _resource_key(asset.resource_type, asset.resource_id)
		if _ambiguous_resource_keys.has(key):
			continue
		if _assets_by_resource.has(key):
			_assets_by_resource.erase(key)
			_ambiguous_resource_keys[key] = true
			continue
		_assets_by_resource[key] = asset


func assets() -> Array[MediaAsset]:
	return _assets.duplicate()


func assets_of_kind(kind: String) -> Array[MediaAsset]:
	var result: Array[MediaAsset] = []
	for asset: MediaAsset in _assets:
		if asset.kind == kind:
			result.append(asset)
	result.sort_custom(func(left: MediaAsset, right: MediaAsset) -> bool: return left.resource_id < right.resource_id)
	return result


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


func tileset_by_id(tileset_id: String) -> MediaAsset:
	var asset := asset_by_id(tileset_id)
	return asset if asset != null and asset.is_tileset() else null


func battle_tileset() -> MediaAsset:
	var asset := asset_by_id("classic-battle-tiles-302")
	return asset if asset != null and asset.is_battle_tileset() else null


func resolution_diagnostic(resource_type: String, resource_id: int, presentation_role: String, decode_result: String = "not-attempted") -> Dictionary:
	var key := _resource_key(resource_type, resource_id)
	var diagnostic := {
		"authoredResourceType": resource_type,
		"authoredResourceId": resource_id,
		"presentationRole": presentation_role,
		"decodeResult": decode_result,
		"status": "missing",
		"packageAssetId": "",
		"sha256": "",
	}
	if _ambiguous_resource_keys.has(key):
		diagnostic["status"] = "ambiguous"
		return diagnostic
	var asset := asset_by_resource(resource_type, resource_id)
	if asset == null:
		return diagnostic
	diagnostic["status"] = "resolved"
	diagnostic["packageAssetId"] = asset.id
	diagnostic["sha256"] = asset.sha256
	return diagnostic


func read_bytes(asset: MediaAsset) -> PackedByteArray:
	if asset == null or not _assets.has(asset):
		return PackedByteArray()
	var archive := ZIPReader.new()
	if archive.open(package_path) != OK:
		return PackedByteArray()
	var bytes := archive.read_file(asset.path)
	archive.close()
	if bytes.size() != asset.byte_count:
		return PackedByteArray()
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(bytes) != OK:
		return PackedByteArray()
	if hashing.finish().hex_encode() != asset.sha256:
		return PackedByteArray()
	return bytes


func read_bytes_batch(requested_assets: Array[MediaAsset]) -> Dictionary:
	var result: Dictionary = {}
	if requested_assets.is_empty():
		return result
	var archive := ZIPReader.new()
	if archive.open(package_path) != OK:
		return result
	for asset: MediaAsset in requested_assets:
		if asset == null or not _assets.has(asset):
			continue
		var bytes := archive.read_file(asset.path)
		if bytes.size() != asset.byte_count:
			continue
		var hashing := HashingContext.new()
		if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(bytes) != OK:
			continue
		if hashing.finish().hex_encode() == asset.sha256:
			result[asset.id] = bytes
	archive.close()
	return result


static func _resource_key(resource_type: String, resource_id: int) -> String:
	return JSON.stringify([resource_type, resource_id])
