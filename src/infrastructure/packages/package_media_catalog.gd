class_name PackageMediaCatalog
extends RefCounted

var package_path: String
var package_hash: String
var _assets: Array[PackageMediaAsset]
var _assets_by_id: Dictionary = {}
var _assets_by_resource: Dictionary = {}
var _ambiguous_resource_keys: Dictionary = {}


func _init(source_path: String, content_hash: String, indexed_assets: Array[PackageMediaAsset]) -> void:
	package_path = source_path
	package_hash = content_hash
	_assets = indexed_assets.duplicate()
	for asset: PackageMediaAsset in _assets:
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


func assets() -> Array[PackageMediaAsset]:
	return _assets.duplicate()


func asset_by_id(asset_id: String) -> PackageMediaAsset:
	return _assets_by_id.get(asset_id) as PackageMediaAsset


func asset_by_resource(resource_type: String, resource_id: int) -> PackageMediaAsset:
	if resource_type.is_empty():
		return null
	return _assets_by_resource.get(_resource_key(resource_type, resource_id)) as PackageMediaAsset


func tileset_by_id(tileset_id: String) -> PackageMediaAsset:
	var asset := asset_by_id(tileset_id)
	return asset if asset != null and asset.is_tileset() else null


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


func read_bytes(asset: PackageMediaAsset) -> PackedByteArray:
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


static func _resource_key(resource_type: String, resource_id: int) -> String:
	return JSON.stringify([resource_type, resource_id])
