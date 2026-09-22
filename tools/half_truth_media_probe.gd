## Checks a pinned Half Truth candidate through the runtime's exact-key media boundary.
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2 or not arguments[0].begins_with("--package-path=") or not arguments[1].begins_with("--package-hash="):
		printerr("USAGE: --script res://tools/half_truth_media_probe.gd -- --package-path=<archive> --package-hash=<sha256>")
		quit(2)
		return
	var package_path := arguments[0].trim_prefix("--package-path=")
	var expected_hash := arguments[1].trim_prefix("--package-hash=")
	if package_path.is_empty() or expected_hash.length() != 64:
		printerr("INVALID_PACKAGE_IDENTITY")
		quit(2)
		return
	var repository := PackageRepository.new()
	var application := repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	if not application.is_ok():
		printerr("APPLICATION_ERROR ", application.error_code)
		quit(1)
		return
	repository.set_application_content(application.content, application.media.assets())
	var package := repository.load_package(package_path)
	if not package.is_ok():
		printerr("PACKAGE_ERROR ", package.error_code)
		quit(1)
		return
	var content: RealmzContent = package.content
	if content.campaign_id != "scenario-half-truth" or content.package_hash != expected_hash:
		printerr("PACKAGE_IDENTITY_CHANGED ", content.campaign_id, " ", content.package_hash)
		quit(1)
		return
	var media := ClassicMediaCatalog.new(package.media, ApplicationMediaCatalog.new(), application.media)
	var exact_keys := 0
	var decoded_images := 0
	var text_resources := 0
	for asset: MediaAsset in package.media.assets():
		if asset.resource_type.is_empty() or media.asset_by_resource(asset.resource_type, asset.resource_id) != asset:
			printerr("EXACT_RESOURCE_UNAVAILABLE ", asset.id)
			quit(1)
			return
		exact_keys += 1
		if asset.mime_type == "image/png":
			if media.image_texture(asset) == null:
				printerr("IMAGE_UNAVAILABLE ", asset.resource_type, " ", asset.resource_id)
				quit(1)
				return
			decoded_images += 1
		elif asset.resource_type == "TEXT":
			if package.media.read_bytes(asset).is_empty():
				printerr("TEXT_UNAVAILABLE ", asset.resource_id)
				quit(1)
				return
			text_resources += 1
	var overlay_ids: Dictionary = {}
	for map_id: String in content.world.map_ids():
		var map := content.world.map_by_id(map_id)
		for cell: MapCell in map.topology.cells():
			if not cell.overlay_asset_id.is_empty():
				overlay_ids[cell.overlay_asset_id] = true
	for overlay_id: String in overlay_ids:
		var overlay := media.asset_by_id(overlay_id)
		if overlay == null or media.image_texture(overlay) == null:
			printerr("OVERLAY_UNAVAILABLE ", overlay_id)
			quit(1)
			return
	for resource_id: int in [306, 307, 308]:
		var atlas := media.asset_by_resource("PICT", resource_id)
		if atlas == null or media.map_atlas(atlas.id) == null:
			printerr("LANDLOOK_UNAVAILABLE ", resource_id)
			quit(1)
			return
	if exact_keys != 464 or decoded_images != 404 or text_resources != 4:
		printerr("MEDIA_INVENTORY_CHANGED ", exact_keys, " ", decoded_images, " ", text_resources)
		quit(1)
		return
	print("HALF_TRUTH_MEDIA_PROBE_PASS ", JSON.stringify({"packageHash": content.package_hash, "exactKeys": exact_keys, "decodedImages": decoded_images, "textResources": text_resources, "overlayIds": overlay_ids.size(), "landlookAtlases": 3}))
	quit(0)
