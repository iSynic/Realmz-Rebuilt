class_name ClassicMediaCatalog
extends RefCounted

var package_media: PackageMediaCatalog
var application_media: ApplicationMediaCatalog


func _init(package_catalog: PackageMediaCatalog, application_catalog: ApplicationMediaCatalog) -> void:
	package_media = package_catalog
	application_media = application_catalog


func assets() -> Array[PackageMediaAsset]:
	var result: Array[PackageMediaAsset] = []
	var occupied_resource_keys: Dictionary = {}
	if package_media != null:
		for asset: PackageMediaAsset in package_media.assets():
			result.append(asset)
			if not asset.resource_type.is_empty():
				occupied_resource_keys[_resource_key(asset.resource_type, asset.resource_id)] = true
	if application_media != null:
		for asset: PackageMediaAsset in application_media.assets():
			if not occupied_resource_keys.has(_resource_key(asset.resource_type, asset.resource_id)):
				result.append(asset)
	return result


func assets_of_kind(kind: String) -> Array[PackageMediaAsset]:
	var result: Array[PackageMediaAsset] = []
	for asset: PackageMediaAsset in assets():
		if asset.kind == kind:
			result.append(asset)
	result.sort_custom(func(left: PackageMediaAsset, right: PackageMediaAsset) -> bool: return left.resource_id < right.resource_id)
	return result


func asset_by_id(asset_id: String) -> PackageMediaAsset:
	var package_asset := package_media.asset_by_id(asset_id) if package_media != null else null
	if package_asset != null:
		return package_asset
	return application_media.asset_by_id(asset_id) if application_media != null else null


func asset_by_resource(resource_type: String, resource_id: int) -> PackageMediaAsset:
	if package_media != null:
		var package_status := package_media.resource_status(resource_type, resource_id)
		if package_status == &"ambiguous":
			return null
		if package_status == &"resolved":
			return package_media.asset_by_resource(resource_type, resource_id)
	return application_media.asset_by_resource(resource_type, resource_id) if application_media != null else null


func tileset_by_id(tileset_id: String) -> PackageMediaAsset:
	var asset := asset_by_id(tileset_id)
	return asset if asset != null and asset.is_tileset() else null


func battle_tileset() -> PackageMediaAsset:
	var asset := asset_by_id("classic-battle-tiles-302")
	return asset if asset != null and asset.is_battle_tileset() else null


func resolution_diagnostic(resource_type: String, resource_id: int, presentation_role: String, decode_result: String = "not-attempted") -> Dictionary:
	if package_media != null and package_media.resource_status(resource_type, resource_id) != &"missing":
		var package_diagnostic := package_media.resolution_diagnostic(resource_type, resource_id, presentation_role, decode_result)
		package_diagnostic["sourceOwner"] = "scenario-package"
		package_diagnostic["resolvedAssetId"] = package_diagnostic.get("packageAssetId", "")
		return package_diagnostic
	var diagnostic := {
		"authoredResourceType": resource_type,
		"authoredResourceId": resource_id,
		"presentationRole": presentation_role,
		"decodeResult": decode_result,
		"status": "missing",
		"sourceOwner": "",
		"packageAssetId": "",
		"applicationAssetId": "",
		"resolvedAssetId": "",
		"sha256": "",
	}
	if application_media == null:
		return diagnostic
	var application_status := application_media.resource_status(resource_type, resource_id)
	if application_status == &"ambiguous":
		diagnostic["status"] = "ambiguous"
		diagnostic["sourceOwner"] = "classic-application"
		return diagnostic
	var asset := application_media.asset_by_resource(resource_type, resource_id)
	if asset == null:
		return diagnostic
	diagnostic["status"] = "resolved"
	diagnostic["sourceOwner"] = "classic-application"
	diagnostic["applicationAssetId"] = asset.id
	diagnostic["resolvedAssetId"] = asset.id
	diagnostic["sha256"] = asset.sha256
	return diagnostic


func read_bytes(asset: PackageMediaAsset) -> PackedByteArray:
	if package_media != null and package_media.owns_asset(asset):
		return package_media.read_bytes(asset)
	if application_media != null and application_media.owns_asset(asset):
		return application_media.read_bytes(asset)
	return PackedByteArray()


func read_bytes_batch(requested_assets: Array[PackageMediaAsset]) -> Dictionary:
	var result: Dictionary = {}
	var package_assets: Array[PackageMediaAsset] = []
	for asset: PackageMediaAsset in requested_assets:
		if package_media != null and package_media.owns_asset(asset):
			package_assets.append(asset)
		elif application_media != null and application_media.owns_asset(asset):
			var bytes := application_media.read_bytes(asset)
			if not bytes.is_empty():
				result[asset.id] = bytes
	if package_media != null:
		result.merge(package_media.read_bytes_batch(package_assets), true)
	return result


func audio_stream_by_resource(resource_type: String, resource_id: int) -> AudioStream:
	var asset := asset_by_resource(resource_type, resource_id)
	if asset == null:
		return null
	if application_media != null and application_media.owns_asset(asset):
		return application_media.audio_stream(asset)
	return _decode_stream(asset, package_media.read_bytes(asset)) if package_media != null else null


static func _decode_stream(asset: PackageMediaAsset, bytes: PackedByteArray) -> AudioStream:
	if bytes.is_empty():
		return null
	var mime := asset.mime_type.to_lower()
	var extension := asset.path.get_extension().to_lower()
	if mime == "audio/wav" or mime == "audio/x-wav" or extension == "wav":
		return AudioStreamWAV.load_from_buffer(bytes)
	if mime in ["audio/mpeg", "audio/mp3"] or extension == "mp3":
		return AudioStreamMP3.load_from_buffer(bytes)
	if mime in ["audio/ogg", "audio/vorbis"] or extension == "ogg":
		return AudioStreamOggVorbis.load_from_buffer(bytes)
	return null


static func _resource_key(resource_type: String, resource_id: int) -> String:
	return JSON.stringify([resource_type, resource_id])
