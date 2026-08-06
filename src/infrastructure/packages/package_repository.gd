class_name PackageRepository
extends RefCounted

const EXPECTED_SCHEMA_HASH: String = "215e3e53c25d2f48417cbf084e74e41ceaf5b759a402d37d6c9d45a4911238c5"
const REQUIRED_DOCUMENTS: Array[String] = ["assets/index.json", "content.json", "scenario.json", "world.json"]
const SUPPORTED_CAPABILITIES: Array[String] = [
	"realmz.core.classic-rules-v1",
	"realmz.presentation.content-addressed-media-v1",
	"realmz.scenario.classic-vm-v1",
	"realmz.world.topology-v1",
]

var _last_error: String = ""


func load_package(path: String) -> PackageLoadResult:
	_last_error = ""
	var archive := ZIPReader.new()
	var open_error := archive.open(path)
	if open_error != OK:
		return PackageLoadResult.failed("package_open_failed", "Could not open package '%s' (error %d)." % [path, open_error])
	var result := _load_open_archive(archive)
	archive.close()
	return result


func _load_open_archive(archive: ZIPReader) -> PackageLoadResult:
	var archive_entries_value: Variant = _zip_entries(archive)
	var archive_entries: Array[String] = []
	if archive_entries_value != null:
		archive_entries = archive_entries_value
	if archive_entries_value == null:
		return _validation_failure()
	var manifest_value: Variant = _read_document(archive, "manifest.json")
	if manifest_value == null:
		return _validation_failure()
	var manifest: Dictionary = manifest_value
	if not _validate_manifest(manifest, archive, archive_entries):
		return _validation_failure()
	var content_value: Variant = _read_document(archive, "content.json")
	var world_value: Variant = _read_document(archive, "world.json")
	var scenario_value: Variant = _read_document(archive, "scenario.json")
	var asset_value: Variant = _read_document(archive, "assets/index.json")
	if content_value == null or world_value == null or scenario_value == null or asset_value == null:
		return _validation_failure()
	var content_document: Dictionary = content_value
	var world_document: Dictionary = world_value
	var scenario_document: Dictionary = scenario_value
	var asset_document: Dictionary = asset_value
	if not _validate_document_header(content_document, "realmz2.content") or not _validate_document_header(world_document, "realmz2.world") or not _validate_document_header(scenario_document, "realmz2.scenario") or not _validate_document_header(asset_document, "realmz2.assets"):
		return _validation_failure()
	if not _validate_assets(asset_document, manifest["files"]):
		return _validation_failure()
	var runtime_content := _construct_content(manifest, content_document, world_document, scenario_document)
	if runtime_content == null:
		return _validation_failure()
	return PackageLoadResult.succeeded(runtime_content)


func _validate_manifest(manifest: Dictionary, archive: ZIPReader, archive_entries: Array[String]) -> bool:
	var required_fields: Array[String] = ["kind", "format", "formatVersion", "schemaVersion", "schemaHash", "campaignId", "contentId", "engine", "start", "capabilities", "files", "packageHash"]
	if not _has_fields(manifest, required_fields, "manifest"):
		return false
	if manifest["kind"] != "realmz2.manifest" or manifest["format"] != "realmz2" or _integer(manifest["formatVersion"]) != 1 or _integer(manifest["schemaVersion"]) != 1:
		return _reject("Unsupported Realmz 2.0 package or schema version.")
	if manifest["schemaHash"] != EXPECTED_SCHEMA_HASH:
		return _reject("Package schema hash does not match the runtime contract mirror.")
	if not _is_sha256(manifest["packageHash"]) or not _is_sha256(manifest["contentId"]):
		return _reject("Manifest package/content identity is malformed.")
	if not manifest["campaignId"] is String or manifest["campaignId"].is_empty():
		return _reject("Manifest campaign ID is missing.")
	if not manifest["engine"] is Dictionary or manifest["engine"].get("rulesVersion") != "realmz-classic-1":
		return _reject("Package requires an unsupported Realmz rules version.")
	if not manifest["capabilities"] is Array:
		return _reject("Manifest capabilities must be an array.")
	for capability: Variant in manifest["capabilities"]:
		if not capability is String or not SUPPORTED_CAPABILITIES.has(capability):
			return _reject("Package requires unknown capability '%s'." % str(capability))
	if not manifest["files"] is Dictionary:
		return _reject("Manifest file integrity table is missing.")
	var expected_entries: Array[String] = ["manifest.json"]
	for required: String in REQUIRED_DOCUMENTS:
		if not manifest["files"].has(required):
			return _reject("Manifest is missing required file '%s'." % required)
	for file_path: Variant in manifest["files"].keys():
		if not file_path is String or file_path.begins_with("/") or file_path.contains("..") or file_path.contains("\\"):
			return _reject("Manifest contains an unsafe package path.")
		var integrity: Variant = manifest["files"][file_path]
		if not integrity is Dictionary or not integrity.has("bytes") or not integrity.has("sha256") or not _is_sha256(integrity["sha256"]):
			return _reject("File integrity record for '%s' is malformed." % file_path)
		var bytes := archive.read_file(file_path)
		if bytes.size() != _integer(integrity["bytes"]) or _sha256(bytes) != integrity["sha256"]:
			return _reject("Package file '%s' failed size or SHA-256 validation." % file_path)
		expected_entries.append(file_path)
	expected_entries.sort()
	if archive_entries != expected_entries:
		return _reject("ZIP entries do not exactly match the sorted manifest inventory.")
	var unhashed := manifest.duplicate(true)
	unhashed.erase("packageHash")
	if _sha256(CanonicalJson.encode(unhashed).to_utf8_buffer()) != manifest["packageHash"]:
		return _reject("Package hash does not match the canonical unhashed manifest.")
	return true


func _construct_content(manifest: Dictionary, content: Dictionary, world: Dictionary, scenario: Dictionary) -> RealmzContent:
	if not content.has("campaign") or not content["campaign"] is Dictionary or content["campaign"].get("id") != manifest["campaignId"]:
		_reject("Content campaign identity does not match the manifest.")
		return null
	var messages_value: Variant = _construct_messages(content.get("messages"))
	if messages_value == null:
		return null
	var messages: Array[MessageDefinition] = messages_value
	var programs_value: Variant = _construct_programs(scenario.get("classicPrograms"))
	if programs_value == null or not _validate_scenario_actions(scenario.get("scenarioActions"), manifest["campaignId"]):
		return null
	var programs: Dictionary = programs_value
	var triggers_value: Variant = _construct_triggers(world.get("triggers"), programs)
	if triggers_value == null:
		return null
	var triggers: Array[TriggerDefinition] = triggers_value
	var trigger_ids: Dictionary = {}
	for trigger: TriggerDefinition in triggers:
		if trigger_ids.has(trigger.id):
			_reject("Trigger ID '%s' is duplicated." % trigger.id)
			return null
		trigger_ids[trigger.id] = true
	var maps_value: Variant = _construct_maps(world.get("maps"), trigger_ids)
	if maps_value == null:
		return null
	var maps: Array[MapDefinition] = maps_value
	var world_definition := WorldDefinition.new(maps)
	var start: Variant = manifest.get("start")
	if not start is Dictionary or not start.get("mapId") is String or _integer(start.get("x")) < 0 or _integer(start.get("y")) < 0:
		_reject("Manifest start location is malformed.")
		return null
	var start_coordinate := Vector2i(_integer(start["x"]), _integer(start["y"]))
	var start_map := world_definition.map_by_id(start["mapId"])
	if start_map == null or start_map.topology.cell_at(start_coordinate) == null:
		_reject("Manifest start location does not identify a topology cell.")
		return null
	for trigger: TriggerDefinition in triggers:
		if not trigger.map_id.is_empty():
			var map := world_definition.map_by_id(trigger.map_id)
			if map == null or map.topology.cell_at(trigger.coordinate) == null:
				_reject("Trigger '%s' references an unavailable topology coordinate." % trigger.id)
				return null
	return RealmzContent.new(manifest["campaignId"], manifest["packageHash"], manifest["contentId"], manifest["engine"]["rulesVersion"], start["mapId"], start_coordinate, world_definition, messages, triggers)


func _construct_messages(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content messages must be an array.")
		return null
	var messages: Array[MessageDefinition] = []
	var ids: Dictionary = {}
	for record: Variant in value:
		if not record is Dictionary or _integer(record.get("id")) < 0 or not record.get("text") is String:
			_reject("Message record is malformed.")
			return null
		var id := _integer(record["id"])
		if ids.has(id):
			_reject("Message ID %d is duplicated." % id)
			return null
		ids[id] = true
		messages.append(MessageDefinition.new(id, record["text"]))
	return messages


func _construct_programs(value: Variant) -> Variant:
	if not value is Array:
		_reject("Classic programs must be an array.")
		return null
	var programs: Dictionary = {}
	for program: Variant in value:
		if not program is Dictionary or not program.get("triggerId") is String or not program.get("instructions") is Array:
			_reject("Classic program is malformed.")
			return null
		if programs.has(program["triggerId"]):
			_reject("Classic program for '%s' is duplicated." % program["triggerId"])
			return null
		var actions: Array[ClassicActionDefinition] = []
		for instruction: Variant in program["instructions"]:
			if not instruction is Dictionary or instruction.get("kind") != "classicAction":
				_reject("Classic instruction is malformed or unknown.")
				return null
			for field: String in ["slot", "rawOpcode", "opcode", "id"]:
				if not _is_integer(instruction.get(field)):
					_reject("Classic instruction field '%s' is not an integer." % field)
					return null
			if not instruction.get("gosub") is bool:
				_reject("Classic instruction GOSUB identity is malformed.")
				return null
			var extra_code: Array[int] = []
			if instruction.get("extraCode") != null:
				if not instruction["extraCode"] is Array or instruction["extraCode"].size() != 5:
					_reject("Classic E-code must contain five integers.")
					return null
				for extra: Variant in instruction["extraCode"]:
					if not _is_integer(extra):
						_reject("Classic E-code contains a non-integer.")
						return null
					extra_code.append(_integer(extra))
			actions.append(ClassicActionDefinition.new(_integer(instruction["slot"]), _integer(instruction["rawOpcode"]), _integer(instruction["opcode"]), _integer(instruction["id"]), instruction["gosub"], extra_code))
		programs[program["triggerId"]] = actions
	return programs


func _construct_triggers(value: Variant, programs: Dictionary) -> Variant:
	if not value is Array:
		_reject("World triggers must be an array.")
		return null
	var triggers: Array[TriggerDefinition] = []
	for record: Variant in value:
		if not record is Dictionary or not record.get("id") is String or record["id"].is_empty() or not record.get("active") is bool:
			_reject("Trigger record is malformed.")
			return null
		if not programs.has(record["id"]):
			_reject("Trigger '%s' has no Classic program." % record["id"])
			return null
		var map_id: String = ""
		var coordinate := Vector2i(-1, -1)
		if record.get("mapId") != null or record.get("coordinate") != null:
			if not record.get("mapId") is String or not record.get("coordinate") is Dictionary:
				_reject("Placed trigger '%s' has incomplete map coordinates." % record["id"])
				return null
			map_id = record["mapId"]
			coordinate = Vector2i(_integer(record["coordinate"].get("x")), _integer(record["coordinate"].get("y")))
			if coordinate.x < 0 or coordinate.y < 0:
				_reject("Placed trigger '%s' has invalid map coordinates." % record["id"])
				return null
		var chance := _integer(record.get("chancePercent"))
		if chance < -128 or chance > 127:
			_reject("Trigger '%s' chance is outside Classic storage." % record["id"])
			return null
		triggers.append(TriggerDefinition.new(record["id"], map_id, coordinate, record["active"], chance, programs[record["id"]]))
	return triggers


func _construct_maps(value: Variant, trigger_ids: Dictionary) -> Variant:
	if not value is Array or value.is_empty():
		_reject("World maps must be a non-empty array.")
		return null
	var maps: Array[MapDefinition] = []
	var map_ids: Dictionary = {}
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
		if width < 1 or height < 1 or width > 256 or height > 256 or not record.get("cells") is Array or record["cells"].size() != width * height:
			_reject("Map '%s' dimensions do not match its topology cells." % record["id"])
			return null
		var cells: Array[MapCell] = []
		var coordinates: Dictionary = {}
		for cell_record: Variant in record["cells"]:
			var cell := _construct_cell(cell_record, width, height, trigger_ids)
			if cell == null:
				return null
			if coordinates.has(cell.coordinate):
				_reject("Map '%s' contains duplicate topology coordinate %s." % [record["id"], cell.coordinate])
				return null
			coordinates[cell.coordinate] = true
			cells.append(cell)
		var level_index := _integer(record.get("levelIndex"))
		if level_index < 0:
			_reject("Map '%s' has an invalid Classic level index." % record["id"])
			return null
		maps.append(MapDefinition.new(record["id"], record["name"], StringName(record.get("levelType", "")), level_index, MapTopology.new(width, height, cells)))
	return maps


func _construct_cell(record: Variant, width: int, height: int, trigger_ids: Dictionary) -> MapCell:
	if not record is Dictionary or not record.get("id") is String or not record.get("terrainId") is String:
		_reject("Topology cell identity is malformed.")
		return null
	var x := _integer(record.get("x"))
	var y := _integer(record.get("y"))
	if x < 0 or y < 0 or x >= width or y >= height:
		_reject("Topology cell coordinate is outside its map.")
		return null
	var movement: Variant = record.get("movement")
	var visibility: Variant = record.get("visibility")
	var semantics: Variant = record.get("semantics")
	if not movement is Dictionary or not movement.get("passable") is bool or _integer(movement.get("cost")) < 1:
		_reject("Topology movement facts are malformed.")
		return null
	if not visibility is Dictionary or not visibility.get("blocksLos") is bool or not semantics is Dictionary:
		_reject("Topology visibility or semantic facts are malformed.")
		return null
	for flag: String in ["land", "water", "shore", "path", "boatRequired", "flyFloatRequired"]:
		if not semantics.get(flag) is bool:
			_reject("Topology semantic flag '%s' is malformed." % flag)
			return null
	var cell_triggers_value: Variant = _string_array(record.get("triggerIds"), "cell trigger IDs")
	var random_rects_value: Variant = _string_array(record.get("randomRectIds"), "cell random rectangle IDs")
	if cell_triggers_value == null or random_rects_value == null:
		return null
	var cell_triggers: Array[String] = cell_triggers_value
	var random_rects: Array[String] = random_rects_value
	for trigger_id: String in cell_triggers:
		if not trigger_ids.has(trigger_id):
			_reject("Topology cell references unknown trigger '%s'." % trigger_id)
			return null
	return MapCell.new(record["id"], Vector2i(x, y), record["terrainId"], movement["passable"], _integer(movement["cost"]), visibility["blocksLos"], semantics["land"], semantics["water"], semantics["shore"], semantics["path"], semantics["boatRequired"], semantics["flyFloatRequired"], cell_triggers, random_rects)


func _validate_scenario_actions(value: Variant, campaign_id: String) -> bool:
	if not value is Array:
		return _reject("Scenario Actions must be an array.")
	var ids: Dictionary = {}
	for action: Variant in value:
		if not action is Dictionary or not action.get("id") is String or action["id"].is_empty() or action.get("backend") != "safe" or not action.has("program"):
			return _reject("Scenario Action definition is malformed or uses an unavailable backend.")
		var required_prefix := "scenario.%s." % campaign_id
		if action["id"].begins_with("realmz.") or not action["id"].begins_with(required_prefix) or ids.has(action["id"]):
			return _reject("Scenario Action ID '%s' has an invalid or duplicate namespace." % action["id"])
		ids[action["id"]] = true
		var count := [0]
		if not _validate_program_node(action["program"], count):
			return false
	return true


func _validate_program_node(value: Variant, count: Array) -> bool:
	count[0] += 1
	if count[0] > 4096:
		return _reject("Safe Scenario Action exceeds 4,096 program nodes.")
	if value is Array:
		if value.size() > 256:
			return _reject("Safe Scenario Action contains an array larger than 256 entries.")
		for child: Variant in value:
			if not _validate_program_node(child, count):
				return false
	elif value is Dictionary:
		for child: Variant in value.values():
			if not _validate_program_node(child, count):
				return false
	return true


func _validate_assets(document: Dictionary, files: Dictionary) -> bool:
	if not document.get("assets") is Array:
		return _reject("Asset index must contain an assets array.")
	for asset: Variant in document["assets"]:
		if not asset is Dictionary or not asset.get("path") is String or not _is_sha256(asset.get("sha256")) or not files.has(asset["path"]):
			return _reject("Asset index contains a malformed or untracked payload.")
		if not asset["path"].begins_with("assets/media/") or files[asset["path"]]["sha256"] != asset["sha256"]:
			return _reject("Asset payload identity does not match the manifest.")
	return true


func _zip_entries(archive: ZIPReader) -> Variant:
	var entries: Array[String] = []
	for entry: String in archive.get_files():
		if entry.begins_with("/") or entry.contains("..") or entry.contains("\\") or entry.ends_with("/"):
			_reject("ZIP contains an unsafe or directory entry '%s'." % entry)
			return null
		entries.append(entry)
	var sorted := entries.duplicate()
	sorted.sort()
	if entries != sorted:
		_reject("ZIP entries are not in deterministic sorted order.")
		return null
	return entries


func _read_document(archive: ZIPReader, path: String) -> Variant:
	var bytes := archive.read_file(path)
	if bytes.is_empty():
		_reject("Package document '%s' is missing or empty." % path)
		return null
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		_reject("Package document '%s' is not a JSON object: %s" % [path, parser.get_error_message()])
		return null
	return parser.data


func _validate_document_header(document: Dictionary, expected_kind: String) -> bool:
	if document.get("kind") != expected_kind or _integer(document.get("schemaVersion")) != 1:
		return _reject("Package document '%s' has an unsupported header." % expected_kind)
	return true


func _has_fields(value: Dictionary, fields: Array[String], label: String) -> bool:
	for field: String in fields:
		if not value.has(field):
			return _reject("%s is missing required field '%s'." % [label, field])
	return true


func _string_array(value: Variant, label: String) -> Variant:
	if not value is Array:
		_reject("%s must be an array." % label)
		return null
	var strings: Array[String] = []
	for item: Variant in value:
		if not item is String or item.is_empty() or strings.has(item):
			_reject("%s contains an invalid or duplicate ID." % label)
			return null
		strings.append(item)
	return strings


func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1


func _is_integer(value: Variant) -> bool:
	return value is int or value is float and is_equal_approx(value, round(value))


func _is_sha256(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character: String in value:
		if not character in "0123456789abcdef":
			return false
	return true


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _reject(message: String) -> bool:
	_last_error = message
	return false


func _validation_failure() -> PackageLoadResult:
	return PackageLoadResult.failed("package_validation_failed", _last_error if not _last_error.is_empty() else "Package validation failed.")
