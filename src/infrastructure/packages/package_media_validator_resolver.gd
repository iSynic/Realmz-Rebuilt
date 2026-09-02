class_name PackageMediaValidatorResolver
extends PackageDecoderBase

func _validate_monster_media(monsters: Array[MonsterDefinition], media_assets: Array[MediaAsset]) -> bool:
	var assets_by_resource: Dictionary = {}
	for asset: MediaAsset in media_assets:
		if not asset.resource_type.is_empty():
			assets_by_resource[JSON.stringify([asset.resource_type, asset.resource_id])] = asset
	for monster: MonsterDefinition in monsters:
		if monster.icon_id <= 0:
			continue
		var asset := assets_by_resource.get(JSON.stringify(["cicn", monster.icon_id])) as MediaAsset
		if asset == null or asset.mime_type != "image/png" or asset.width < 1 or asset.height < 1:
			return _reject("Monster '%s' requires unavailable Classic cicn %d." % [monster.id, monster.icon_id])
	return true

func validate_assets(document: Dictionary, files: Dictionary) -> bool:
	if not document.get("assets") is Array:
		return _reject("Asset index must contain an assets array.")
	var ids: Dictionary = {}
	var resources: Dictionary = {}
	var portrait_resource_ids: Dictionary = {}
	var combat_icon_resource_ids: Dictionary = {}
	var scenario_music_slots: Dictionary = {}
	for asset: Variant in document["assets"]:
		if not asset is Dictionary or not _exact_fields(asset, ["id", "label", "kind", "mimeType", "resourceType", "resourceId", "scenarioMusicSlot", "bytes", "sha256", "path", "width", "height", "durationMs", "sampleRate", "channels", "tileWidth", "tileHeight", "columns", "rows", "landlook", "baseTile"]):
			return _reject("Asset index contains a malformed record.")
		if not asset["id"] is String or asset["id"].is_empty() or ids.has(asset["id"]) or not asset["label"] is String or not asset["kind"] is String:
			return _reject("Asset identities, labels, and kinds must be typed and unique.")
		ids[asset["id"]] = true
		if asset["mimeType"] != null and not asset["mimeType"] is String:
			return _reject("Asset MIME type must be a string or null.")
		if asset["resourceType"] != null and not asset["resourceType"] is String:
			return _reject("Asset resource type must be a string or null.")
		if asset["resourceId"] != null and not _is_integer(asset["resourceId"]):
			return _reject("Asset resource ID must be an integer or null.")
		if asset["scenarioMusicSlot"] != null:
			if not _is_integer(asset["scenarioMusicSlot"]) or _integer(asset["scenarioMusicSlot"]) < 1 or _integer(asset["scenarioMusicSlot"]) > 3 or asset["kind"] != "music" or not String(asset["mimeType"]).begins_with("audio/") or scenario_music_slots.has(_integer(asset["scenarioMusicSlot"])):
				return _reject("Scenario music slots must be unique audio assets numbered one through three.")
			scenario_music_slots[_integer(asset["scenarioMusicSlot"])] = true
		for optional_integer: String in ["width", "height", "durationMs", "sampleRate", "channels", "tileWidth", "tileHeight", "columns", "rows", "landlook", "baseTile"]:
			if asset[optional_integer] != null and (not _is_integer(asset[optional_integer]) or _integer(asset[optional_integer]) < 0):
				return _reject("Asset %s must be a non-negative integer or null." % optional_integer)
		if asset["kind"] in ["tileset", "battle-tileset"]:
			for tileset_field: String in ["width", "height", "tileWidth", "tileHeight", "columns", "rows"]:
				if asset[tileset_field] == null or _integer(asset[tileset_field]) < 1:
					return _reject("Tileset asset '%s' has invalid %s metadata." % [asset["id"], tileset_field])
			if not String(asset["mimeType"]).begins_with("image/") or _integer(asset["width"]) != _integer(asset["tileWidth"]) * _integer(asset["columns"]) or _integer(asset["height"]) != _integer(asset["tileHeight"]) * _integer(asset["rows"]):
				return _reject("Tileset asset '%s' dimensions do not match its atlas grid." % asset["id"])
		if asset["kind"] == "battle-tileset" and (asset["id"] != "classic-battle-tiles-302" or asset["mimeType"] != "image/png" or asset["resourceType"] != null or asset["resourceId"] != null or _integer(asset["width"]) != 640 or _integer(asset["height"]) != 640 or _integer(asset["tileWidth"]) != 32 or _integer(asset["tileHeight"]) != 32 or _integer(asset["columns"]) != 20 or _integer(asset["rows"]) != 20):
			return _reject("Classic battle atlas must be the role-specific 640 by 640 PICT 302 tile grid.")
		if not _is_integer(asset["bytes"]) or _integer(asset["bytes"]) < 0 or not asset["path"] is String or not _is_sha256(asset["sha256"]) or not files.has(asset["path"]):
			return _reject("Asset index contains a malformed or untracked payload.")
		if not asset["path"].begins_with("assets/media/") or files[asset["path"]]["sha256"] != asset["sha256"] or _integer(files[asset["path"]]["bytes"]) != _integer(asset["bytes"]):
			return _reject("Asset payload identity does not match the manifest.")
		if asset["resourceType"] != null and asset["resourceId"] != null:
			var resource_key := JSON.stringify([asset["resourceType"], _integer(asset["resourceId"])])
			if resources.has(resource_key):
				return _reject("Asset resource identities must be unique.")
			resources[resource_key] = true
			if asset["resourceType"] == "cicn" and asset["kind"] == "portrait":
				portrait_resource_ids[_integer(asset["resourceId"])] = true
			if asset["resourceType"] == "cicn" and asset["kind"] == "combat-icon":
				combat_icon_resource_ids[_integer(asset["resourceId"])] = true
		if asset["kind"] in ["portrait", "combat-icon"]:
			if asset["resourceType"] != "cicn" or asset["resourceId"] == null or asset["mimeType"] != "image/png" or asset["width"] == null or _integer(asset["width"]) < 1 or asset["height"] == null or _integer(asset["height"]) < 1:
				return _reject("Character appearance asset '%s' must be a decoded Classic cicn PNG with positive dimensions." % asset["id"])
	for resource_id: int in range(257, 377):
		if not portrait_resource_ids.has(resource_id):
			return _reject("Character portrait catalog is missing Classic cicn %d." % resource_id)
	for resource_id: int in range(9000, 9120):
		if not combat_icon_resource_ids.has(resource_id):
			return _reject("Character combat-icon catalog is missing Classic cicn %d." % resource_id)
	return true

func validate_presentation_capabilities(manifest: Dictionary, assets: Dictionary) -> bool:
	var declares_battle_atlas: bool = manifest["capabilities"].has("realmz.presentation.battle-atlas-v1")
	var battle_atlas_count := 0
	for asset: Dictionary in assets["assets"]:
		if asset["kind"] == "battle-tileset":
			battle_atlas_count += 1
	if declares_battle_atlas != (battle_atlas_count == 1):
		return _reject("Battle-atlas capability and packaged battle artwork do not agree.")
	return true

func validate_render_references(assets: Dictionary, world: Dictionary) -> bool:
	var tileset_ids: Dictionary = {}
	var image_ids: Dictionary = {}
	for asset: Dictionary in assets["assets"]:
		if asset["kind"] == "tileset":
			tileset_ids[asset["id"]] = true
		if asset["mimeType"] is String and asset["mimeType"].begins_with("image/"):
			image_ids[asset["id"]] = true
	if not world.get("maps") is Array:
		return _reject("World maps must be available for tileset validation.")
	for map: Variant in world["maps"]:
		if not map is Dictionary or map.get("topologyFormat") != "realmz2.compact-cell-rows.v2" or not map.get("cells") is Array:
			return _reject("World map is malformed during tileset validation.")
		for cell: Variant in map["cells"]:
			if not cell is Array or cell.size() != 13 or not cell[9] is String:
				return _reject("Topology render facts are malformed during tileset validation.")
			if not tileset_ids.has(cell[9]):
				return _reject("Topology references missing tileset asset '%s'." % cell[9])
			var overlay_asset_id: Variant = cell[10]
			if overlay_asset_id != null and (not overlay_asset_id is String or not image_ids.has(overlay_asset_id)):
				return _reject("Topology references missing image overlay asset '%s'." % overlay_asset_id)
	return true

func construct_assets(document: Dictionary) -> Array[MediaAsset]:
	var assets: Array[MediaAsset] = []
	for record: Dictionary in document["assets"]:
		assets.append(MediaAsset.new(
			record["id"],
			record["label"],
			record["kind"],
			"" if record["mimeType"] == null else record["mimeType"],
			"" if record["resourceType"] == null else record["resourceType"],
			-1 if record["resourceId"] == null else _integer(record["resourceId"]),
			_integer(record["bytes"]),
			record["sha256"],
			record["path"],
			0 if record["width"] == null else _integer(record["width"]),
			0 if record["height"] == null else _integer(record["height"]),
			0 if record["durationMs"] == null else _integer(record["durationMs"]),
			0 if record["sampleRate"] == null else _integer(record["sampleRate"]),
			0 if record["channels"] == null else _integer(record["channels"]),
			0 if record["tileWidth"] == null else _integer(record["tileWidth"]),
			0 if record["tileHeight"] == null else _integer(record["tileHeight"]),
			0 if record["columns"] == null else _integer(record["columns"]),
			0 if record["rows"] == null else _integer(record["rows"]),
			-1 if record["landlook"] == null else _integer(record["landlook"]),
			-1 if record["baseTile"] == null else _integer(record["baseTile"]),
			0 if record["scenarioMusicSlot"] == null else _integer(record["scenarioMusicSlot"]),
		))
	return assets

func _construct_character_appearance_options(assets: Array[MediaAsset], races: Array[RaceDefinition]) -> Array[CharacterAppearanceDefinition]:
	var result: Array[CharacterAppearanceDefinition] = []
	for asset: MediaAsset in assets:
		var kind := CharacterAppearanceDefinition.PORTRAIT if asset.kind == "portrait" else CharacterAppearanceDefinition.COMBAT_ICON if asset.kind == "combat-icon" else &""
		if kind == &"":
			continue
		var recommended_races: Array[String] = []
		for race: RaceDefinition in races:
			var first_resource_id: int
			if kind == CharacterAppearanceDefinition.PORTRAIT:
				first_resource_id = 257 if race.default_icon_set == 0 else 251 + race.default_icon_set * 6
			else:
				first_resource_id = 9000 + (race.classic_id - 1) * 6
			if asset.resource_id >= first_resource_id and asset.resource_id < first_resource_id + 6:
				recommended_races.append(race.id)
		result.append(CharacterAppearanceDefinition.new(asset.id, asset.label, kind, asset.resource_id, recommended_races))
	result.sort_custom(func(left: CharacterAppearanceDefinition, right: CharacterAppearanceDefinition) -> bool: return left.classic_resource_id < right.classic_resource_id)
	return result
