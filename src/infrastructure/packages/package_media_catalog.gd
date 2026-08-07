class_name PackageMediaCatalog
extends RefCounted

var package_path: String
var package_hash: String
var _assets: Array[PackageMediaAsset]


func _init(source_path: String, content_hash: String, indexed_assets: Array[PackageMediaAsset]) -> void:
	package_path = source_path
	package_hash = content_hash
	_assets = indexed_assets.duplicate()


func assets() -> Array[PackageMediaAsset]:
	return _assets.duplicate()


func asset_by_id(asset_id: String) -> PackageMediaAsset:
	for asset: PackageMediaAsset in _assets:
		if asset.id == asset_id:
			return asset
	return null


func picture_by_resource_id(resource_id: int) -> PackageMediaAsset:
	for asset: PackageMediaAsset in _assets:
		if asset.resource_id == resource_id and asset.is_picture():
			return asset
	return null


func sound_by_resource_id(resource_id: int) -> PackageMediaAsset:
	for asset: PackageMediaAsset in _assets:
		if asset.resource_id == resource_id and asset.is_sound():
			return asset
	return null


func tileset_by_id(tileset_id: String) -> PackageMediaAsset:
	for asset: PackageMediaAsset in _assets:
		if asset.id == tileset_id and asset.is_tileset():
			return asset
	return null


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
