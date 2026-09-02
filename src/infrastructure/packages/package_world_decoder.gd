class_name PackageWorldDecoder
extends PackageDecoderBase

const DIRECTIONS: Array[String] = ["north", "east", "south", "west"]
const TRANSITION_DIRECTIONS: Array[String] = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
const EDGE_KINDS: Array[String] = ["open", "wall", "door", "secret", "archway", "map-boundary"]
const FEATURE_KINDS: Array[String] = ["door", "secret", "stairs", "column", "unmapped", "note", "action-point", "archway", "no-wall-in-battle"]

func _construct_triggers(value: Variant, scenario: ScenarioDefinition) -> Variant:
	if not value is Array:
		_reject("World triggers must be an array.")
		return null
	var triggers: Array[TriggerDefinition] = []
	var placed_record_keys: Dictionary = {}
	for record: Variant in value:
		if not record is Dictionary or not _exact_fields(record, ["id", "programId", "classicRecordIndex", "mapId", "coordinate", "active", "chancePercent", "postActionLocation"]) or not record.get("id") is String or record["id"].is_empty() or not record.get("programId") is String or record["programId"].is_empty() or not _is_integer(record.get("classicRecordIndex")) or _integer(record["classicRecordIndex"]) < 0 or not record.get("active") is bool:
			_reject("Trigger record is malformed.")
			return null
		var trigger_program := scenario.program_by_id(record["programId"])
		if trigger_program == null or trigger_program.owner_id != record["id"] or trigger_program.owner_kind not in [&"trigger", &"extra-action-point"]:
			_reject("Trigger '%s' references unavailable scenario program '%s'." % [record["id"], record["programId"]])
			return null
		var map_id: String = ""
		var coordinate := Vector2i(-1, -1)
		if record.get("mapId") != null or record.get("coordinate") != null:
			if not record.get("mapId") is String or not record.get("coordinate") is Dictionary or not _exact_fields(record["coordinate"], ["x", "y"]):
				_reject("Placed trigger '%s' has incomplete map coordinates." % record["id"])
				return null
			map_id = record["mapId"]
			coordinate = Vector2i(_integer(record["coordinate"].get("x")), _integer(record["coordinate"].get("y")))
			if coordinate.x < 0 or coordinate.y < 0:
				_reject("Placed trigger '%s' has invalid map coordinates." % record["id"])
				return null
			var placed_record_key := "%s:%d" % [map_id, _integer(record["classicRecordIndex"])]
			if placed_record_keys.has(placed_record_key):
				_reject("Placed trigger '%s' duplicates Classic record %d on map '%s'." % [record["id"], _integer(record["classicRecordIndex"]), map_id])
				return null
			placed_record_keys[placed_record_key] = true
		var chance := _integer(record.get("chancePercent"))
		if chance < -128 or chance > 127:
			_reject("Trigger '%s' chance is outside Classic storage." % record["id"])
			return null
		var destination_record: Variant = record.get("postActionLocation")
		var destination: TriggerDestinationDefinition = null
		if destination_record != null:
			if not destination_record is Dictionary or not _exact_fields(destination_record, ["mapId", "coordinate"]) or not destination_record.get("mapId") is String or not destination_record.get("coordinate") is Dictionary or not _exact_fields(destination_record["coordinate"], ["x", "y"]):
				_reject("Trigger '%s' post-action location is malformed." % record["id"])
				return null
			var destination_coordinate: Dictionary = destination_record["coordinate"]
			if not _is_integer(destination_coordinate.get("x")) or not _is_integer(destination_coordinate.get("y")):
				_reject("Trigger '%s' post-action coordinate is malformed." % record["id"])
				return null
			destination = TriggerDestinationDefinition.new(destination_record["mapId"], Vector2i(_integer(destination_coordinate["x"]), _integer(destination_coordinate["y"])))
		triggers.append(TriggerDefinition.new(record["id"], record["programId"], map_id, coordinate, record["active"], chance, destination, _integer(record["classicRecordIndex"])))
	return triggers

func _construct_battle_terrain_sets(value: Variant) -> Variant:
	if not value is Array:
		_reject("World battle terrain sets must be an array.")
		return null
	var terrain_sets: Array[BattleTerrainSetDefinition] = []
	var set_ids: Dictionary = {}
	for record: Variant in value:
		if not record is Dictionary or not _exact_fields(record, ["id", "landlook", "baseTile", "tiles"]) or not record["id"] is String or record["id"].is_empty() or set_ids.has(record["id"]) or not record["tiles"] is Array:
			_reject("Battle terrain set is malformed or duplicated.")
			return null
		var dungeon_set := record["landlook"] == null
		if dungeon_set != (record["baseTile"] == null):
			_reject("Battle terrain set '%s' has inconsistent landlook/base-tile identity." % record["id"])
			return null
		if not dungeon_set and (not _is_integer(record["landlook"]) or not _is_integer(record["baseTile"])):
			_reject("Battle terrain set '%s' has non-integer landlook or base-tile identity." % record["id"])
			return null
		var landlook := -1 if dungeon_set else _integer(record["landlook"])
		var base_tile := -1 if dungeon_set else _integer(record["baseTile"])
		if not dungeon_set and (landlook < -128 or landlook > 127 or base_tile < 0 or base_tile > 400):
			_reject("Battle terrain set '%s' has invalid landlook or base-tile identity." % record["id"])
			return null
		var tiles: Array[BattleTerrainTileDefinition] = []
		var tile_ids: Dictionary = {}
		for tile_record: Variant in record["tiles"]:
			var tile_definition := _construct_battle_terrain_tile(tile_record)
			if tile_definition == null or tile_ids.has(tile_definition.tile):
				_reject("Battle terrain set '%s' contains a malformed or duplicate tile." % record["id"])
				return null
			tile_ids[tile_definition.tile] = true
			tiles.append(tile_definition)
		var terrain_set := BattleTerrainSetDefinition.new(record["id"], landlook, base_tile, tiles)
		if dungeon_set and not terrain_set.has_complete_range(200, 400):
			_reject("Dungeon battle terrain set '%s' must contain every Combat Data BD tile 200 through 400." % record["id"])
			return null
		if not dungeon_set and not terrain_set.has_complete_range(0, 400):
			_reject("Land battle terrain set '%s' must contain every effective mapstats tile 0 through 400." % record["id"])
			return null
		set_ids[terrain_set.id] = true
		terrain_sets.append(terrain_set)
	return terrain_sets

func _construct_battle_terrain_tile(value: Variant) -> BattleTerrainTileDefinition:
	var fields: Array[String] = ["tile", "sound", "time", "solid", "shore", "needBoat", "isPath", "los", "flyFloat", "forest", "combatBuild"]
	if not value is Dictionary or not _exact_fields(value, fields):
		return null
	var record: Dictionary = value
	var integers_value: Variant = _validated_integer_fields(record, ["tile", "sound", "time", "solid", "needBoat", "forest"], "Battle terrain tile")
	if integers_value == null:
		return null
	var integers: Dictionary = integers_value
	if integers["tile"] < 0 or integers["tile"] > 400 or not _integers_in_range(integers, ["sound", "time", "solid", "needBoat", "forest"], -32768, 32767):
		return null
	for flag: String in ["shore", "isPath", "los", "flyFloat"]:
		if not record[flag] is bool:
			return null
	if not record["combatBuild"] is Array or record["combatBuild"].size() != 3:
		return null
	var combat_build: Array = []
	for row: Variant in record["combatBuild"]:
		if not row is Array or row.size() != 3:
			return null
		var parsed_row: Array[int] = []
		for entry: Variant in row:
			if not _is_integer(entry):
				return null
			var tile_id := _integer(entry)
			if tile_id < -32768 or tile_id > 32767:
				return null
			parsed_row.append(tile_id)
		combat_build.append(parsed_row)
	return BattleTerrainTileDefinition.new(integers["tile"], integers["sound"], integers["time"], integers["solid"], record["shore"], integers["needBoat"], record["isPath"], record["los"], record["flyFloat"], integers["forest"], combat_build)

func _construct_maps(value: Variant, trigger_ids: Dictionary, battle_terrain_sets: Dictionary = {}, require_battle_terrain: bool = false, validate_compact_rows: bool = true) -> Variant:
	if not value is Array or value.is_empty():
		_reject("World maps must be a non-empty array.")
		return null
	var maps: Array[MapDefinition] = []
	var map_ids: Dictionary = {}
	var land_terrain_sets_by_landlook: Dictionary = {}
	for terrain_set_value: Variant in battle_terrain_sets.values():
		var land_terrain_set := terrain_set_value as BattleTerrainSetDefinition
		if land_terrain_set != null and land_terrain_set.landlook >= 0:
			land_terrain_sets_by_landlook[land_terrain_set.landlook] = land_terrain_set
	for record: Variant in value:
		if not record is Dictionary or not record.get("id") is String or record["id"].is_empty() or not record.get("name") is String:
			_reject("Map definition is malformed.")
			return null
		if map_ids.has(record["id"]):
			_reject("Map ID '%s' is duplicated." % record["id"])
			return null
		map_ids[record["id"]] = true
		var width := _integer(record.get("width"))
		var height := _integer(record.get("height"))
		if width < 1 or height < 1 or width > 256 or height > 256 or record.get("topologyFormat") != "realmz2.compact-cell-rows.v2" or not record.get("cells") is Array or record["cells"].size() != width * height:
			_reject("Map '%s' dimensions do not match its topology cells." % record["id"])
			return null
		var level_index := _integer(record.get("levelIndex"))
		var level_type: Variant = record.get("levelType")
		if level_index < 0 or not level_type is String or level_type not in ["land", "dungeon"]:
			_reject("Map '%s' has an invalid Classic level index." % record["id"])
			return null
		var regions_value: Variant = _construct_random_regions(record.get("randomRectangles"), width, height, record["id"])
		if regions_value == null:
			return null
		var regions: Array[RandomEncounterRegion] = regions_value
		var region_ids: Dictionary = {}
		for region: RandomEncounterRegion in regions:
			region_ids[region.id] = true
		if validate_compact_rows:
			for cell_index: int in record["cells"].size():
				if not _validate_compact_cell(record["cells"][cell_index], record["id"], cell_index, trigger_ids, region_ids, StringName(level_type)):
					return null
		var metadata: Variant = record.get("metadata")
		if not metadata is Dictionary or not _exact_fields(metadata, ["dark", "usesLos", "landlook", "baseScale", "battleTerrainSetId"]) or not metadata.get("dark") is bool or not metadata.get("usesLos") is bool or metadata.get("landlook") != null and not _is_integer(metadata.get("landlook")) or metadata.get("baseScale") != null and not _is_integer(metadata.get("baseScale")):
			_reject("Map '%s' metadata is malformed." % record["id"])
			return null
		var landlook := -1 if metadata["landlook"] == null else _integer(metadata["landlook"])
		var base_scale := -1 if metadata["baseScale"] == null else _integer(metadata["baseScale"])
		if level_type == "dungeon" and metadata["baseScale"] != null:
			_reject("Dungeon map '%s' contains land-only base-scale metadata." % record["id"])
			return null
		if metadata["battleTerrainSetId"] != null and (not metadata["battleTerrainSetId"] is String or metadata["battleTerrainSetId"].is_empty()):
			_reject("Map '%s' battle terrain set identity is malformed." % record["id"])
			return null
		var terrain_set_id: String = "" if metadata["battleTerrainSetId"] == null else metadata["battleTerrainSetId"]
		var terrain_set := battle_terrain_sets.get(terrain_set_id) as BattleTerrainSetDefinition
		if require_battle_terrain and terrain_set == null:
			_reject("Map '%s' does not reference a complete battle terrain set." % record["id"])
			return null
		if not terrain_set_id.is_empty() and terrain_set == null:
			_reject("Map '%s' references unknown battle terrain set '%s'." % [record["id"], terrain_set_id])
			return null
		if terrain_set != null and ((level_type == "land" and terrain_set.landlook != landlook) or (level_type == "dungeon" and terrain_set.landlook != -1)):
			_reject("Map '%s' references a battle terrain set for the wrong level type or landlook." % record["id"])
			return null
		var boat_profiles_value: Variant = _construct_boat_replacement_profiles(record.get("boatReplacementProfiles"), StringName(level_type), record["id"])
		if boat_profiles_value == null:
			return null
		var boat_profiles: Array = boat_profiles_value
		var topology := MapTopology.from_compact_rows(record["id"], width, height, record["cells"], boat_profiles[0] as LandTileProfile, boat_profiles[1] as LandTileProfile, landlook, land_terrain_sets_by_landlook)
		maps.append(MapDefinition.new(record["id"], record["name"], StringName(level_type), level_index, topology, metadata["dark"], metadata["usesLos"], landlook, regions, terrain_set_id, base_scale))
	return maps


func _construct_boat_replacement_profiles(value: Variant, level_type: StringName, map_id: String) -> Variant:
	if level_type == &"dungeon":
		if value != null:
			_reject("Dungeon map '%s' contains land-only boat replacement profiles." % map_id)
			return null
		return [null, null]
	if not value is Dictionary or not _exact_fields(value, ["removed", "placed"]):
		_reject("Land map '%s' is missing exact Classic boat replacement profiles." % map_id)
		return null
	var removed := _construct_land_tile_profile(value["removed"], map_id, "removed")
	var placed := _construct_land_tile_profile(value["placed"], map_id, "placed")
	if removed == null or placed == null:
		return null
	return [removed, placed]


func _construct_land_tile_profile(value: Variant, map_id: String, role: String) -> LandTileProfile:
	if not value is Array or value.size() != 7:
		_reject("Land map '%s' has a malformed %s boat replacement profile." % [map_id, role])
		return null
	var row: Array = value
	var movement_cost := _integer(row[1])
	var flags := _integer(row[2])
	var render_tile := _integer(row[4])
	var boat_requirement := _integer(row[5])
	var blocked_attempts := _integer(row[6])
	if not row[0] is String or row[0].is_empty() or movement_cost < 0 or flags < 0 or flags > 511 or row[3] != null and not _is_integer(row[3]) or render_tile < 1 or boat_requirement < 0 or boat_requirement > 2 or blocked_attempts < 0:
		_reject("Land map '%s' has invalid %s boat replacement facts." % [map_id, role])
		return null
	if not bool(flags & 4) or bool(flags & 8) != (boat_requirement == 2) or bool(flags & 64) != (boat_requirement != 0):
		_reject("Land map '%s' has contradictory %s boat replacement semantics." % [map_id, role])
		return null
	return LandTileProfile.new(row[0], movement_cost, flags, -1 if row[3] == null else _integer(row[3]), render_tile, boat_requirement, blocked_attempts)

func _validate_compact_cell(value: Variant, map_id: String, cell_index: int, trigger_ids: Dictionary, region_ids: Dictionary, level_type: StringName) -> bool:
	if not value is Array or value.size() != 13:
		return _reject("Map '%s' compact topology row %d is malformed." % [map_id, cell_index])
	var row: Array = value
	if not row[0] is String or row[0].is_empty() or not _is_integer(row[1]) or _integer(row[1]) < 0 or not _is_integer(row[2]) or _integer(row[2]) < 0 or _integer(row[2]) > 511:
		return _reject("Map '%s' compact topology row %d has malformed terrain facts." % [map_id, cell_index])
	if row[3] != null and not _is_integer(row[3]):
		return _reject("Map '%s' compact topology row %d has malformed movement sound." % [map_id, cell_index])
	var cell_triggers_value: Variant = _string_array(row[4], "compact cell trigger IDs")
	var random_rects_value: Variant = _string_array(row[5], "compact cell random rectangle IDs")
	if cell_triggers_value == null or random_rects_value == null:
		return false
	for trigger_id: String in cell_triggers_value:
		if not trigger_ids.has(trigger_id):
			return _reject("Topology cell references unknown trigger '%s'." % trigger_id)
	for region_id: String in random_rects_value:
		if not region_ids.has(region_id):
			return _reject("Topology cell references unknown random rectangle '%s'." % region_id)
	if not row[7] is Array:
		return _reject("Map '%s' compact topology row %d has malformed features." % [map_id, cell_index])
	var feature_kinds_by_id: Dictionary = {}
	for feature_value: Variant in row[7]:
		if not feature_value is Array or feature_value.size() != 4:
			return _reject("Map '%s' compact topology row %d contains a malformed feature." % [map_id, cell_index])
		var feature: Array = feature_value
		if not feature[0] is String or feature[0].is_empty() or feature_kinds_by_id.has(feature[0]) or not feature[1] is String or not FEATURE_KINDS.has(feature[1]):
			return _reject("Map '%s' compact topology row %d contains a malformed or duplicate feature." % [map_id, cell_index])
		if feature[2] != null and not feature[2] is String:
			return _reject("Topology feature '%s' state is malformed." % feature[0])
		if feature[3] != null and (not feature[3] is String or not DIRECTIONS.has(feature[3]) and feature[3] not in ["horizontal", "vertical"]):
			return _reject("Topology feature '%s' orientation is malformed." % feature[0])
		feature_kinds_by_id[feature[0]] = feature[1]
	if not row[6] is Array or row[6].size() != 4:
		return _reject("Map '%s' compact topology row %d has malformed edges." % [map_id, cell_index])
	for edge_value: Variant in row[6]:
		if not edge_value is Array or edge_value.size() != 4:
			return _reject("Map '%s' compact topology row %d contains a malformed edge." % [map_id, cell_index])
		var edge: Array = edge_value
		if not edge[0] is String or not EDGE_KINDS.has(edge[0]) or not _is_integer(edge[1]) or _integer(edge[1]) < 0 or _integer(edge[1]) > 7:
			return _reject("Map '%s' compact topology row %d contains invalid edge facts." % [map_id, cell_index])
		for reference_index: int in [2, 3]:
			if edge[reference_index] != null and (not edge[reference_index] is String or edge[reference_index].is_empty()):
				return _reject("Map '%s' compact topology row %d contains an invalid edge reference." % [map_id, cell_index])
		var door_id := "" if edge[2] == null else String(edge[2])
		var secret_id := "" if edge[3] == null else String(edge[3])
		if not door_id.is_empty() and feature_kinds_by_id.get(door_id) != "door":
			return _reject("Topology edge references unknown door '%s'." % door_id)
		if not secret_id.is_empty() and feature_kinds_by_id.get(secret_id) != "secret":
			return _reject("Topology edge references unknown secret '%s'." % secret_id)
	if not _is_integer(row[8]) or not row[9] is String or row[9].is_empty() or row[10] != null and (not row[10] is String or row[10].is_empty()):
		return _reject("Map '%s' compact topology row %d has malformed render facts." % [map_id, cell_index])
	if not _is_integer(row[11]) or _integer(row[11]) < 0 or _integer(row[11]) > 2 or not _is_integer(row[12]) or _integer(row[12]) < 0:
		return _reject("Map '%s' compact topology row %d has malformed Classic movement facts." % [map_id, cell_index])
	var boat_requirement := _integer(row[11])
	var flags := _integer(row[2])
	if bool(flags & 8) != (boat_requirement == 2) or bool(flags & 64) != (boat_requirement != 0):
		return _reject("Map '%s' compact topology row %d has contradictory boat facts." % [map_id, cell_index])
	if level_type == &"dungeon" and (boat_requirement != 0 or _integer(row[12]) != 0):
		return _reject("Dungeon map '%s' compact topology row %d contains land-only movement facts." % [map_id, cell_index])
	return true

func _construct_player_maps(value: Variant, maps: Array[MapDefinition], media_assets: Array[MediaAsset]) -> Variant:
	if not value is Array or value.size() > 20:
		_reject("World player maps must be an array of no more than twenty records.")
		return null
	var maps_by_id: Dictionary = {}
	for map: MapDefinition in maps:
		maps_by_id[map.id] = map
	var assets_by_id: Dictionary = {}
	for asset: MediaAsset in media_assets:
		assets_by_id[asset.id] = asset
	var result: Array[PlayerMapDefinition] = []
	var ids: Dictionary = {}
	var classic_ids: Dictionary = {}
	var fields: Array[String] = ["id", "classicId", "name", "unavailableName", "mode", "mapId", "start", "iconSize", "pictureAssetId", "scrollingTextAssetId", "partyMarkerAssetId", "pictureRect", "markers", "note"]
	var modes: Array[String] = ["scrolling-text", "picture", "land-crop", "dungeon-crop"]
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Player-map definition is not an object.")
			return null
		var record: Dictionary = value_record
		if not _exact_fields(record, fields) or not record["id"] is String or record["id"].is_empty() or ids.has(record["id"]) or not _is_integer(record["classicId"]) or not record["name"] is String or record["name"].is_empty() or not record["unavailableName"] is String or not record["mode"] is String or record["mode"] not in modes or not _is_integer(record["iconSize"]) or _integer(record["iconSize"]) <= 0 or not record["note"] is String:
			_reject("Player-map definition is malformed or duplicated.")
			return null
		var classic_id := _integer(record["classicId"])
		if classic_id < 0 or classic_id > 19 or classic_ids.has(classic_id):
			_reject("Player-map Classic ID must be unique and between 0 and 19.")
			return null
		if not record["start"] is Dictionary or not _exact_fields(record["start"], ["x", "y"]) or not _is_integer(record["start"]["x"]) or not _is_integer(record["start"]["y"]):
			_reject("Player-map start coordinate is malformed.")
			return null
		if not record["pictureRect"] is Dictionary or not _exact_fields(record["pictureRect"], ["top", "left", "bottom", "right"]):
			_reject("Player-map picture rectangle is malformed.")
			return null
		for field: String in ["top", "left", "bottom", "right"]:
			if not _is_integer(record["pictureRect"][field]):
				_reject("Player-map picture rectangle is malformed.")
				return null
		var mode := StringName(record["mode"])
		var map_id := "" if record["mapId"] == null else String(record["mapId"])
		var picture_asset_id := "" if record["pictureAssetId"] == null else String(record["pictureAssetId"])
		var scrolling_text_asset_id := "" if record["scrollingTextAssetId"] == null else String(record["scrollingTextAssetId"])
		var party_marker_asset_id := "" if record["partyMarkerAssetId"] == null else String(record["partyMarkerAssetId"])
		var party_marker_asset := assets_by_id.get(party_marker_asset_id) as MediaAsset
		if record["mapId"] != null and (not record["mapId"] is String or map_id.is_empty()) or record["pictureAssetId"] != null and (not record["pictureAssetId"] is String or picture_asset_id.is_empty()) or record["scrollingTextAssetId"] != null and (not record["scrollingTextAssetId"] is String or scrolling_text_asset_id.is_empty()) or record["partyMarkerAssetId"] != null and (not record["partyMarkerAssetId"] is String or party_marker_asset_id.is_empty()):
			_reject("Player-map content references are malformed.")
			return null
		var crop := mode in [PlayerMapDefinition.LAND_CROP, PlayerMapDefinition.DUNGEON_CROP]
		if crop:
			var source_map := maps_by_id.get(map_id) as MapDefinition
			var expected_type := &"dungeon" if mode == PlayerMapDefinition.DUNGEON_CROP else &"land"
			if source_map == null or source_map.level_type != expected_type or not picture_asset_id.is_empty() or not scrolling_text_asset_id.is_empty():
				_reject("Player-map crop references an unavailable or wrong-kind topology map.")
				return null
		if mode == PlayerMapDefinition.PICTURE:
			var picture_map := maps_by_id.get(map_id) as MapDefinition
			if picture_map == null or not _player_map_asset_matches(assets_by_id.get(picture_asset_id), "PICT") or not _player_map_asset_matches(party_marker_asset, "cicn") or party_marker_asset.resource_id != 138 or not scrolling_text_asset_id.is_empty():
				_reject("Picture-backed player map references unavailable PICT media.")
				return null
		elif mode == PlayerMapDefinition.SCROLLING_TEXT:
			if not map_id.is_empty() or not _player_map_asset_matches(assets_by_id.get(scrolling_text_asset_id), "TEXT") or not picture_asset_id.is_empty() or not party_marker_asset_id.is_empty():
				_reject("Scrolling player map references unavailable TEXT media.")
				return null
		elif not _player_map_asset_matches(party_marker_asset, "cicn") or party_marker_asset.resource_id != 138:
			_reject("Player-map crop references unavailable current-party cicn media.")
			return null
		var markers_value: Variant = record["markers"]
		if not markers_value is Array or markers_value.size() > 10 or not crop and not markers_value.is_empty():
			_reject("Player-map markers are malformed or attached outside a crop map.")
			return null
		var markers: Array[PlayerMapMarkerDefinition] = []
		for marker_value: Variant in markers_value:
			if not marker_value is Dictionary or not _exact_fields(marker_value, ["classicIconId", "iconAssetId", "x", "y"]) or not _is_integer(marker_value["classicIconId"]) or not marker_value["iconAssetId"] is String or marker_value["iconAssetId"].is_empty() or not _is_integer(marker_value["x"]) or not _is_integer(marker_value["y"]):
				_reject("Player-map marker is malformed.")
				return null
			var marker_asset := assets_by_id.get(marker_value["iconAssetId"]) as MediaAsset
			if not _player_map_asset_matches(marker_asset, "cicn") or marker_asset.resource_id != _integer(marker_value["classicIconId"]):
				_reject("Player-map marker does not match its exact cicn resource identity.")
				return null
			markers.append(PlayerMapMarkerDefinition.new(_integer(marker_value["classicIconId"]), marker_value["iconAssetId"], Vector2i(_integer(marker_value["x"]), _integer(marker_value["y"]))))
		ids[record["id"]] = true
		classic_ids[classic_id] = true
		var rect: Dictionary = record["pictureRect"]
		result.append(PlayerMapDefinition.new(record["id"], classic_id, record["name"], record["unavailableName"], mode, map_id, Vector2i(_integer(record["start"]["x"]), _integer(record["start"]["y"])), _integer(record["iconSize"]), picture_asset_id, scrolling_text_asset_id, party_marker_asset_id, Rect2i(_integer(rect["left"]), _integer(rect["top"]), _integer(rect["right"]) - _integer(rect["left"]), _integer(rect["bottom"]) - _integer(rect["top"])), markers, record["note"]))
	result.sort_custom(func(left: PlayerMapDefinition, right: PlayerMapDefinition) -> bool: return left.classic_id < right.classic_id)
	return result

func _player_map_asset_matches(value: Variant, resource_type: String) -> bool:
	return value is MediaAsset and value.resource_type == resource_type

func _construct_random_regions(value: Variant, width: int, height: int, map_id: String) -> Variant:
	if not value is Array:
		_reject("Map '%s' random rectangles must be an array." % map_id)
		return null
	var regions: Array[RandomEncounterRegion] = []
	var ids: Dictionary = {}
	for record: Variant in value:
		if not record is Dictionary or not record.get("id") is String or record["id"].is_empty() or ids.has(record["id"]):
			_reject("Map '%s' contains a malformed or duplicate random rectangle." % map_id)
			return null
		for field: String in ["top", "left", "bottom", "right", "chanceTenThousand", "option", "soundId", "textId"]:
			if not _is_integer(record.get(field)):
				_reject("Random rectangle '%s' field '%s' is malformed." % [record["id"], field])
				return null
		var top := _integer(record["top"])
		var left := _integer(record["left"])
		var bottom := _integer(record["bottom"])
		var right := _integer(record["right"])
		var chance := _integer(record["chanceTenThousand"])
		var classic_scalars := {"chance": chance, "option": _integer(record["option"]), "sound": _integer(record["soundId"]), "text": _integer(record["textId"])}
		if top < 0 or left < 0 or bottom < top or right < left or bottom >= height or right >= width or not _integers_in_range(classic_scalars, ["chance", "option", "sound", "text"], -32768, 32767) or not record.get("only") is bool:
			_reject("Random rectangle '%s' bounds or flags are malformed." % record["id"])
			return null
		var battle_range_value: Variant = _integer_array(record.get("battleRange"), 2, "battle range")
		var doors_value: Variant = _integer_array(record.get("randomDoors"), 3, "random doors")
		var percents_value: Variant = _integer_array(record.get("randomDoorPercent"), 3, "random door percentages")
		if battle_range_value == null or doors_value == null or percents_value == null:
			return null
		var battle_range: Array[int] = battle_range_value
		var doors: Array[int] = doors_value
		var percents: Array[int] = percents_value
		if not _integers_in_range({"battleMinimum": battle_range[0], "battleMaximum": battle_range[1]}, ["battleMinimum", "battleMaximum"], -32768, 32767) or not _integers_in_range({"door0": doors[0], "door1": doors[1], "door2": doors[2]}, ["door0", "door1", "door2"], -32768, 32767) or not _integers_in_range({"chance0": percents[0], "chance1": percents[1], "chance2": percents[2]}, ["chance0", "chance1", "chance2"], -32768, 32767):
			_reject("Random rectangle '%s' has values outside Classic 16-bit storage." % record["id"])
			return null
		ids[record["id"]] = true
		regions.append(RandomEncounterRegion.new(record["id"], Rect2i(left, top, right - left + 1, bottom - top + 1), chance, battle_range[0], battle_range[1], doors, percents, record["only"], _integer(record["option"]), _integer(record["soundId"]), _integer(record["textId"])))
	return regions

func _construct_transitions(value: Variant, maps: Array[MapDefinition]) -> Variant:
	if not value is Array:
		_reject("World transitions must be an array.")
		return null
	var map_ids: Dictionary = {}
	for map: MapDefinition in maps:
		map_ids[map.id] = true
	var transitions: Array[MapTransition] = []
	var ids: Dictionary = {}
	var sources: Dictionary = {}
	for record: Variant in value:
		if not record is Dictionary or not record.get("id") is String or record["id"].is_empty() or ids.has(record["id"]) or not record.get("source") is Dictionary or not record.get("target") is Dictionary:
			_reject("World contains a malformed or duplicate transition.")
			return null
		var source: Dictionary = record["source"]
		var target: Dictionary = record["target"]
		if not source.get("mapId") is String or not target.get("mapId") is String or not map_ids.has(source["mapId"]) or not map_ids.has(target["mapId"]) or not source.get("edge") is String or not TRANSITION_DIRECTIONS.has(source["edge"]) or not target.get("edge") is String or not TRANSITION_DIRECTIONS.has(target["edge"]):
			_reject("Transition '%s' references an invalid map edge." % record["id"])
			return null
		var source_key := "%s:%s" % [source["mapId"], source["edge"]]
		if sources.has(source_key):
			_reject("World transition source '%s' is ambiguous." % source_key)
			return null
		ids[record["id"]] = true
		sources[source_key] = true
		transitions.append(MapTransition.new(record["id"], source["mapId"], StringName(source["edge"]), target["mapId"], StringName(target["edge"])))
	return transitions
