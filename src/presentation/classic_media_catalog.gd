class_name ClassicMediaCatalog
extends MediaSource

var package_media: MediaSource
var character_media: MediaSource
var application_media: ApplicationMediaCatalog
var _image_textures: Dictionary = {}
var _audio_streams: Dictionary = {}


func _init(package_catalog: MediaSource, application_catalog: ApplicationMediaCatalog, character_catalog: MediaSource = null) -> void:
	package_media = package_catalog
	application_media = application_catalog
	character_media = character_catalog


func assets() -> Array[MediaAsset]:
	var result: Array[MediaAsset] = []
	var occupied_resource_keys: Dictionary = {}
	if package_media != null:
		for asset: MediaAsset in package_media.assets():
			result.append(asset)
			if not asset.resource_type.is_empty():
				occupied_resource_keys[_resource_key(asset.resource_type, asset.resource_id)] = true
	if character_media != null:
		for asset: MediaAsset in character_media.assets():
			if not occupied_resource_keys.has(_resource_key(asset.resource_type, asset.resource_id)):
				result.append(asset)
				occupied_resource_keys[_resource_key(asset.resource_type, asset.resource_id)] = true
	if application_media != null:
		for asset: MediaAsset in application_media.assets():
			if not occupied_resource_keys.has(_resource_key(asset.resource_type, asset.resource_id)):
				result.append(asset)
	return result


func assets_of_kind(kind: String) -> Array[MediaAsset]:
	var result: Array[MediaAsset] = []
	for asset: MediaAsset in assets():
		if asset.kind == kind:
			result.append(asset)
	result.sort_custom(func(left: MediaAsset, right: MediaAsset) -> bool: return left.resource_id < right.resource_id)
	return result


func asset_by_id(asset_id: String) -> MediaAsset:
	var package_asset := package_media.asset_by_id(asset_id) if package_media != null else null
	if package_asset != null:
		return package_asset
	var character_asset := character_media.asset_by_id(asset_id) if character_media != null else null
	if character_asset != null:
		return character_asset
	var land_overlay_resource_id := _land_overlay_resource_id(asset_id)
	if land_overlay_resource_id != 0:
		return asset_by_resource("cicn", land_overlay_resource_id)
	var application_asset := application_media.asset_by_id(asset_id) if application_media != null else null
	if application_asset != null:
		return application_asset
	return null


func asset_by_resource(resource_type: String, resource_id: int) -> MediaAsset:
	if package_media != null:
		var package_status := package_media.resource_status(resource_type, resource_id)
		if package_status == &"ambiguous":
			return null
		if package_status == &"resolved":
			return package_media.asset_by_resource(resource_type, resource_id)
	if character_media != null and character_media.resource_status(resource_type, resource_id) == &"resolved":
		return character_media.asset_by_resource(resource_type, resource_id)
	return application_media.asset_by_resource(resource_type, resource_id) if application_media != null else null


func tileset_by_id(tileset_id: String) -> MediaAsset:
	var asset := asset_by_id(tileset_id)
	return asset if asset != null and asset.is_tileset() else null


static func _land_overlay_resource_id(asset_id: String) -> int:
	const NEGATIVE_PREFIX := "realmz-special-land-neg-"
	const POSITIVE_PREFIX := "realmz-land-cicn-"
	var sign := -1 if asset_id.begins_with(NEGATIVE_PREFIX) else 1
	var prefix := NEGATIVE_PREFIX if sign < 0 else POSITIVE_PREFIX
	if not asset_id.begins_with(prefix):
		return 0
	var magnitude := asset_id.trim_prefix(prefix)
	if magnitude.is_empty() or not magnitude.is_valid_int() or int(magnitude) <= 0:
		return 0
	return sign * int(magnitude)


func battle_tileset() -> MediaAsset:
	var asset := asset_by_id("classic-battle-tiles-302")
	return asset if asset != null and asset.is_battle_tileset() else null


func scenario_music_asset(slot: int) -> MediaAsset:
	if package_media == null or slot < 1 or slot > 3:
		return null
	for asset: MediaAsset in package_media.assets_of_kind("music"):
		if asset.scenario_music_slot == slot:
			return asset
	return null


func resolution_diagnostic(resource_type: String, resource_id: int, presentation_role: String, decode_result: String = "not-attempted") -> Dictionary:
	if package_media != null and package_media.resource_status(resource_type, resource_id) != &"missing":
		var package_diagnostic: Dictionary = package_media.resolution_diagnostic(resource_type, resource_id, presentation_role, decode_result)
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


func read_bytes(asset: MediaAsset) -> PackedByteArray:
	if package_media != null and package_media.owns_asset(asset):
		return package_media.read_bytes(asset)
	if character_media != null and character_media.owns_asset(asset):
		return character_media.read_bytes(asset)
	if application_media != null and application_media.owns_asset(asset):
		return application_media.read_bytes(asset)
	return PackedByteArray()


func read_bytes_batch(requested_assets: Array[MediaAsset]) -> Dictionary:
	var result: Dictionary = {}
	var package_assets: Array[MediaAsset] = []
	for asset: MediaAsset in requested_assets:
		if package_media != null and package_media.owns_asset(asset):
			package_assets.append(asset)
		elif character_media != null and character_media.owns_asset(asset):
			var bytes := character_media.read_bytes(asset)
			if not bytes.is_empty():
				result[asset.id] = bytes
		elif application_media != null and application_media.owns_asset(asset):
			var bytes := application_media.read_bytes(asset)
			if not bytes.is_empty():
				result[asset.id] = bytes
	if package_media != null:
		result.merge(package_media.read_bytes_batch(package_assets), true)
	return result


func image_texture(asset: MediaAsset) -> Texture2D:
	if asset == null:
		return null
	if _image_textures.has(asset.id):
		return _image_textures[asset.id] as Texture2D
	var bytes := read_bytes(asset)
	var texture: Texture2D
	if not bytes.is_empty():
		var image := Image.new()
		var error := ERR_FILE_UNRECOGNIZED
		match asset.mime_type:
			"image/png": error = image.load_png_from_buffer(bytes)
			"image/jpeg": error = image.load_jpg_from_buffer(bytes)
			"image/webp": error = image.load_webp_from_buffer(bytes)
		if error == OK and (asset.width <= 0 or asset.height <= 0 or image.get_width() == asset.width and image.get_height() == asset.height):
			texture = ImageTexture.create_from_image(image)
	_image_textures[asset.id] = texture
	return texture


func audio_stream_by_resource(resource_type: String, resource_id: int) -> AudioStream:
	var asset := asset_by_resource(resource_type, resource_id)
	return audio_stream(asset)


func audio_stream(asset: MediaAsset) -> AudioStream:
	if asset == null:
		return null
	if application_media != null and application_media.owns_asset(asset):
		return application_media.audio_stream(asset)
	if _audio_streams.has(asset.id):
		return _audio_streams[asset.id] as AudioStream
	var stream := _decode_stream(asset, read_bytes(asset))
	_audio_streams[asset.id] = stream
	return stream


static func _decode_stream(asset: MediaAsset, bytes: PackedByteArray) -> AudioStream:
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
