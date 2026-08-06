class_name PackageRepository
extends RefCounted

const EXPECTED_SCHEMA_HASH: String = "31fbbaac9f6ef8fbedc20e628be9f4a05bdf1ebffda97709dcd84319beedadc6"
const REQUIRED_DOCUMENTS: Array[String] = ["assets/index.json", "content.json", "scenario.json", "world.json"]
const SUPPORTED_CAPABILITIES: Array[String] = [
	"realmz.core.classic-rules-v1",
	"realmz.presentation.content-addressed-media-v1",
	"realmz.scenario.classic-vm-v1",
	"realmz.scenario.safe-actions-v1",
	"realmz.world.topology-v1",
]
const SUPPORTED_CLASSIC_OPCODES: Array[int] = [1, 4, 39, 111, 112]
const SUPPORTED_SAFE_CAPABILITIES: Array[String] = ["core.presentation.choice", "core.presentation.text", "core.state.read", "core.state.write"]
const SUPPORTED_ACTION_CONTEXTS: Array[String] = ["action", "encounter", "spell", "item", "monster-ai", "lifecycle", "rule-modifier"]
const SUPPORTED_VALUE_TYPES: Array[String] = ["void", "bool", "int", "float", "string", "location-snapshot", "time-snapshot", "wealth-snapshot", "character-snapshot", "character-snapshot-array", "combat-snapshot", "action-outcome", "encounter-outcome", "effect-outcome", "spell-validation-outcome", "spell-cast-outcome", "spell-effect-outcome", "spell-tick-outcome", "spell-expiration-outcome", "item-outcome", "monster-decision", "rule-modifier", "bool-array", "int-array", "float-array", "string-array"]
const DIRECTIONS: Array[String] = ["north", "east", "south", "west"]
const EDGE_KINDS: Array[String] = ["open", "wall", "door", "secret", "archway", "map-boundary"]
const FEATURE_KINDS: Array[String] = ["door", "secret", "stairs", "column", "unmapped", "note", "action-point", "archway", "no-wall-in-battle"]

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
	var message_ids: Dictionary = {}
	for message: MessageDefinition in messages:
		message_ids[message.id] = true
	var encounters_value: Variant = _construct_simple_encounters(content.get("simpleEncounters"))
	if encounters_value == null:
		return null
	var simple_encounters: Array[SimpleEncounterDefinition] = encounters_value
	var scenario_definition := _construct_scenario(scenario, manifest["campaignId"])
	if scenario_definition == null:
		return null
	var triggers_value: Variant = _construct_triggers(world.get("triggers"), scenario_definition)
	if triggers_value == null:
		return null
	var triggers: Array[TriggerDefinition] = triggers_value
	if not _validate_scenario_references(scenario_definition, message_ids, simple_encounters):
		return null
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
	var transitions_value: Variant = _construct_transitions(world.get("transitions"), maps)
	if transitions_value == null:
		return null
	var transitions: Array[MapTransition] = transitions_value
	var world_definition := WorldDefinition.new(maps, transitions)
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
	return RealmzContent.new(manifest["campaignId"], manifest["packageHash"], manifest["contentId"], manifest["engine"]["rulesVersion"], start["mapId"], start_coordinate, world_definition, scenario_definition, messages, triggers, simple_encounters)


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


func _construct_simple_encounters(value: Variant) -> Variant:
	if not value is Array:
		_reject("Simple Encounters must be an array.")
		return null
	var encounters: Array[SimpleEncounterDefinition] = []
	var ids: Dictionary = {}
	for record: Variant in value:
		if not record is Dictionary or not _exact_fields(record, ["id", "promptMessageId", "responses", "canBackOut", "maxTimes", "casteSuccess"]):
			_reject("Simple Encounter definition is malformed.")
			return null
		var encounter_id := _integer(record["id"])
		if encounter_id < 0 or ids.has(encounter_id) or not _is_integer(record["promptMessageId"]) or not record["responses"] is Array or record["responses"].is_empty() or record["responses"].size() > 4 or not record["canBackOut"] is bool or not _is_integer(record["maxTimes"]) or not _is_integer(record["casteSuccess"]):
			_reject("Simple Encounter identity, choices, or Classic fields are malformed.")
			return null
		var responses: Array[SimpleEncounterResponse] = []
		var response_ids: Dictionary = {}
		for response: Variant in record["responses"]:
			if not response is Dictionary or not _exact_fields(response, ["id", "label", "resultProgramId"]) or not response["id"] is String or response["id"].is_empty() or response_ids.has(response["id"]) or not response["label"] is String or response["label"].is_empty() or not response["resultProgramId"] is String or response["resultProgramId"].is_empty():
				_reject("Simple Encounter %d contains a malformed or duplicate response." % encounter_id)
				return null
			response_ids[response["id"]] = true
			responses.append(SimpleEncounterResponse.new(response["id"], response["label"], response["resultProgramId"]))
		ids[encounter_id] = true
		encounters.append(SimpleEncounterDefinition.new(encounter_id, _integer(record["promptMessageId"]), responses, record["canBackOut"], _integer(record["maxTimes"]), _integer(record["casteSuccess"])))
	return encounters


func _construct_scenario(document: Dictionary, campaign_id: String) -> ScenarioDefinition:
	if not _has_fields(document, ["programs", "scenarioActions", "stateDefinitions", "migrations"], "scenario document"):
		return null
	if not document["stateDefinitions"] is Array or document["stateDefinitions"].size() > 4096 or not document["migrations"] is Array or document["migrations"].size() > 4096 or not _json_safe(document["stateDefinitions"], 0) or not _json_safe(document["migrations"], 0):
		_reject("Scenario state definitions or migrations are malformed.")
		return null
	var programs_value: Variant = _construct_programs(document["programs"])
	var actions_value: Variant = _construct_scenario_actions(document["scenarioActions"], campaign_id)
	if programs_value == null or actions_value == null:
		return null
	var programs: Array[ScenarioProgramDefinition] = programs_value
	var actions: Array[ScenarioActionDefinition] = actions_value
	var definition := ScenarioDefinition.new(programs, actions)
	for program: ScenarioProgramDefinition in programs:
		for index: int in range(program.instruction_count()):
			var instruction: Variant = program.instruction_at(index)
			if instruction is CallScenarioActionInstruction:
				var called_action := definition.action_by_id(instruction.action_id)
				var calling_context := _program_context(program.owner_kind)
				if called_action == null or called_action.visibility != &"public" or calling_context == &"" or not called_action.allows_context(calling_context) or not _call_arguments_match(instruction.argument_names(), instruction.result_target, called_action):
					_reject("Scenario program '%s' has an invalid public Scenario Action call to '%s'." % [program.id, instruction.action_id])
					return null
	for action: ScenarioActionDefinition in actions:
		for index: int in range(action.program.instruction_count()):
			var instruction := action.program.instruction_at(index)
			if instruction.kind == SafeInstructionDefinition.Kind.CALL_ACTION:
				var called_action := definition.action_by_id(instruction.action_id)
				if called_action == null or not _call_arguments_match(instruction.argument_names(), instruction.result_target, called_action) or not _contexts_are_compatible(action, called_action):
					_reject("Scenario Action '%s' has an invalid call to '%s'." % [action.id, instruction.action_id])
					return null
	return definition


func _construct_programs(value: Variant) -> Variant:
	if not value is Array:
		_reject("Scenario programs must be an array.")
		return null
	var programs: Array[ScenarioProgramDefinition] = []
	var ids: Dictionary = {}
	for program: Variant in value:
		if not program is Dictionary or not _exact_fields(program, ["id", "ownerKind", "ownerId", "instructions"]) or not program["id"] is String or program["id"].is_empty() or not program["ownerKind"] is String or program["ownerKind"] not in ["trigger", "extra-action-point", "simple-encounter-result", "complex-encounter-result"] or not program["ownerId"] is String or program["ownerId"].is_empty() or not program["instructions"] is Array or program["instructions"].size() > 4096:
			_reject("Scenario program is malformed.")
			return null
		if ids.has(program["id"]):
			_reject("Scenario program '%s' is duplicated." % program["id"])
			return null
		var instructions: Array[Variant] = []
		for instruction: Variant in program["instructions"]:
			var constructed: Variant = _construct_program_instruction(instruction)
			if constructed == null:
				return null
			instructions.append(constructed)
		ids[program["id"]] = true
		programs.append(ScenarioProgramDefinition.new(program["id"], StringName(program["ownerKind"]), program["ownerId"], instructions))
	return programs


func _construct_program_instruction(instruction: Variant) -> Variant:
	if not instruction is Dictionary or not instruction.get("kind") is String:
		_reject("Scenario instruction is malformed.")
		return null
	if instruction["kind"] == "callScenarioAction":
		return _construct_call_instruction(instruction)
	if instruction["kind"] != "classicAction" or not _exact_fields(instruction, ["kind", "slot", "rawOpcode", "opcode", "id", "gosub", "extraCode"]):
		_reject("Scenario program contains an unknown instruction kind.")
		return null
	for field: String in ["slot", "rawOpcode", "opcode", "id"]:
		if not _is_integer(instruction[field]):
			_reject("Classic instruction field '%s' is not an integer." % field)
			return null
	if _integer(instruction["slot"]) < 0 or not instruction["gosub"] is bool:
		_reject("Classic instruction slot or GOSUB identity is malformed.")
		return null
	var raw_opcode := _integer(instruction["rawOpcode"])
	var normalized := raw_opcode * -1 if raw_opcode < 0 and raw_opcode not in [-14, -23] else raw_opcode
	if normalized != _integer(instruction["opcode"]) or instruction["gosub"] != (raw_opcode < 0 and raw_opcode not in [-14, -23]):
		_reject("Classic instruction raw/normalized/GOSUB identity is inconsistent.")
		return null
	if not SUPPORTED_CLASSIC_OPCODES.has(normalized):
		_reject("Scenario program requires unsupported Classic opcode %d." % normalized)
		return null
	var extra_code: Array[int] = []
	if instruction["extraCode"] != null:
		if not instruction["extraCode"] is Array or instruction["extraCode"].size() != 5:
			_reject("Classic E-code must contain five integers.")
			return null
		for extra: Variant in instruction["extraCode"]:
			if not _is_integer(extra):
				_reject("Classic E-code contains a non-integer.")
				return null
			extra_code.append(_integer(extra))
	return ClassicActionDefinition.new(_integer(instruction["slot"]), raw_opcode, normalized, _integer(instruction["id"]), instruction["gosub"], extra_code)


func _construct_call_instruction(record: Dictionary) -> CallScenarioActionInstruction:
	if not _exact_fields(record, ["kind", "actionId", "arguments", "result"]) or not record["actionId"] is String or record["actionId"].is_empty() or not record["arguments"] is Dictionary or record["result"] != null and not record["result"] is String:
		_reject("Scenario Action call instruction is malformed.")
		return null
	var arguments: Dictionary = {}
	var count := [0]
	for name: Variant in record["arguments"].keys():
		if not name is String or name.is_empty():
			_reject("Scenario Action call contains an invalid argument name.")
			return null
		var expression := _construct_safe_expression(record["arguments"][name], count, 0)
		if expression == null:
			return null
		arguments[name] = expression
	return CallScenarioActionInstruction.new(record["actionId"], arguments, "" if record["result"] == null else record["result"])


func _construct_triggers(value: Variant, scenario: ScenarioDefinition) -> Variant:
	if not value is Array:
		_reject("World triggers must be an array.")
		return null
	var triggers: Array[TriggerDefinition] = []
	for record: Variant in value:
		if not record is Dictionary or not record.get("id") is String or record["id"].is_empty() or not record.get("programId") is String or record["programId"].is_empty() or not record.get("active") is bool:
			_reject("Trigger record is malformed.")
			return null
		var trigger_program := scenario.program_by_id(record["programId"])
		if trigger_program == null or trigger_program.owner_id != record["id"] or trigger_program.owner_kind not in [&"trigger", &"extra-action-point"]:
			_reject("Trigger '%s' references unavailable scenario program '%s'." % [record["id"], record["programId"]])
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
		var replacement_record: Variant = record.get("replacement")
		if not replacement_record is Dictionary:
			_reject("Trigger '%s' replacement is malformed." % record["id"])
			return null
		for replacement_field: String in ["doorId", "terrainId", "targetX", "targetY"]:
			if not _is_integer(replacement_record.get(replacement_field)):
				_reject("Trigger '%s' replacement field '%s' is malformed." % [record["id"], replacement_field])
				return null
		var replacement := TriggerReplacementDefinition.new(_integer(replacement_record["doorId"]), _integer(replacement_record["terrainId"]), Vector2i(_integer(replacement_record["targetX"]), _integer(replacement_record["targetY"])))
		triggers.append(TriggerDefinition.new(record["id"], record["programId"], map_id, coordinate, record["active"], chance, replacement))
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
		var regions_value: Variant = _construct_random_regions(record.get("randomRectangles"), width, height, record["id"])
		if regions_value == null:
			return null
		var regions: Array[RandomEncounterRegion] = regions_value
		var region_ids: Dictionary = {}
		for region: RandomEncounterRegion in regions:
			region_ids[region.id] = true
		var cells: Array[MapCell] = []
		var coordinates: Dictionary = {}
		for cell_record: Variant in record["cells"]:
			var cell := _construct_cell(cell_record, width, height, trigger_ids, region_ids)
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
		var metadata: Variant = record.get("metadata")
		if not metadata is Dictionary or not metadata.get("dark") is bool or not metadata.get("usesLos") is bool or metadata.get("landlook") != null and not _is_integer(metadata.get("landlook")):
			_reject("Map '%s' metadata is malformed." % record["id"])
			return null
		var landlook := -1 if metadata["landlook"] == null else _integer(metadata["landlook"])
		maps.append(MapDefinition.new(record["id"], record["name"], StringName(record.get("levelType", "")), level_index, MapTopology.new(width, height, cells), metadata["dark"], metadata["usesLos"], landlook, regions))
	return maps


func _construct_cell(record: Variant, width: int, height: int, trigger_ids: Dictionary, region_ids: Dictionary) -> MapCell:
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
	var metadata: Variant = record.get("metadata")
	var render: Variant = record.get("render")
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
	for region_id: String in random_rects:
		if not region_ids.has(region_id):
			_reject("Topology cell references unknown random rectangle '%s'." % region_id)
			return null
	if not metadata is Dictionary or metadata.get("movementSoundId") != null and not _is_integer(metadata.get("movementSoundId")):
		_reject("Topology cell movement metadata is malformed.")
		return null
	if not render is Dictionary or not _is_integer(render.get("tile")) or not render.get("tilesetId") is String or render["tilesetId"].is_empty():
		_reject("Topology cell render facts are malformed.")
		return null
	var features_value: Variant = _construct_features(record.get("features"), record["id"])
	if features_value == null:
		return null
	var features: Array[MapFeature] = features_value
	var edges_value: Variant = _construct_edges(record.get("edges"), features, record["id"])
	if edges_value == null:
		return null
	var edges: Dictionary = edges_value
	var sound_id := -1 if metadata["movementSoundId"] == null else _integer(metadata["movementSoundId"])
	return MapCell.new(record["id"], Vector2i(x, y), record["terrainId"], movement["passable"], _integer(movement["cost"]), visibility["blocksLos"], semantics["land"], semantics["water"], semantics["shore"], semantics["path"], semantics["boatRequired"], semantics["flyFloatRequired"], sound_id, _integer(render["tile"]), render["tilesetId"], cell_triggers, random_rects, edges, features)


func _construct_features(value: Variant, cell_id: String) -> Variant:
	if not value is Array:
		_reject("Topology cell '%s' features must be an array." % cell_id)
		return null
	var features: Array[MapFeature] = []
	var ids: Dictionary = {}
	for record: Variant in value:
		if not record is Dictionary or not record.get("id") is String or record["id"].is_empty() or not record.get("kind") is String or not FEATURE_KINDS.has(record["kind"]):
			_reject("Topology cell '%s' contains a malformed feature." % cell_id)
			return null
		if ids.has(record["id"]):
			_reject("Topology feature '%s' is duplicated." % record["id"])
			return null
		ids[record["id"]] = true
		if record.get("state") != null and not record.get("state") is String:
			_reject("Topology feature '%s' state is malformed." % record["id"])
			return null
		if record.get("orientation") != null and (not record.get("orientation") is String or not DIRECTIONS.has(record["orientation"]) and record["orientation"] not in ["horizontal", "vertical"]):
			_reject("Topology feature '%s' orientation is malformed." % record["id"])
			return null
		features.append(MapFeature.new(record["id"], StringName(record["kind"]), StringName(record.get("state", "") if record.get("state") != null else ""), StringName(record.get("orientation", "") if record.get("orientation") != null else "")))
	return features


func _construct_edges(value: Variant, features: Array[MapFeature], cell_id: String) -> Variant:
	if not value is Dictionary:
		_reject("Topology cell '%s' edges must be an object." % cell_id)
		return null
	var feature_by_id: Dictionary = {}
	for feature: MapFeature in features:
		feature_by_id[feature.id] = feature
	var edges: Dictionary = {}
	for direction: String in DIRECTIONS:
		var record: Variant = value.get(direction)
		if not record is Dictionary or not record.get("kind") is String or not EDGE_KINDS.has(record["kind"]) or not record.get("passable") is bool or not record.get("blocksLos") is bool or not record.get("initiallyDiscovered") is bool:
			_reject("Topology cell '%s' edge '%s' is malformed." % [cell_id, direction])
			return null
		var door_id := "" if record.get("doorId") == null else str(record.get("doorId"))
		var secret_id := "" if record.get("secretId") == null else str(record.get("secretId"))
		if not door_id.is_empty() and (not feature_by_id.has(door_id) or (feature_by_id[door_id] as MapFeature).kind != &"door"):
			_reject("Topology edge references unknown door '%s'." % door_id)
			return null
		if not secret_id.is_empty() and (not feature_by_id.has(secret_id) or (feature_by_id[secret_id] as MapFeature).kind != &"secret"):
			_reject("Topology edge references unknown secret '%s'." % secret_id)
			return null
		edges[StringName(direction)] = MapEdge.new(StringName(record["kind"]), record["passable"], record["blocksLos"], door_id, secret_id, record["initiallyDiscovered"])
	return edges


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
		for field: String in ["top", "left", "bottom", "right", "chancePercent", "option", "soundId", "textId"]:
			if not _is_integer(record.get(field)):
				_reject("Random rectangle '%s' field '%s' is malformed." % [record["id"], field])
				return null
		var top := _integer(record["top"])
		var left := _integer(record["left"])
		var bottom := _integer(record["bottom"])
		var right := _integer(record["right"])
		if top < 0 or left < 0 or bottom < top or right < left or bottom >= height or right >= width or not record.get("only") is bool:
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
		ids[record["id"]] = true
		regions.append(RandomEncounterRegion.new(record["id"], Rect2i(left, top, right - left + 1, bottom - top + 1), _integer(record["chancePercent"]), battle_range[0], battle_range[1], doors, percents, record["only"], _integer(record["option"]), _integer(record["soundId"]), _integer(record["textId"])))
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
		if not source.get("mapId") is String or not target.get("mapId") is String or not map_ids.has(source["mapId"]) or not map_ids.has(target["mapId"]) or not source.get("edge") is String or not DIRECTIONS.has(source["edge"]) or not target.get("edge") is String or not DIRECTIONS.has(target["edge"]):
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


func _construct_scenario_actions(value: Variant, campaign_id: String) -> Variant:
	if not value is Array:
		_reject("Scenario Actions must be an array.")
		return null
	var actions: Array[ScenarioActionDefinition] = []
	var ids: Dictionary = {}
	var required_prefix := "scenario.%s." % campaign_id
	for record: Variant in value:
		var fields: Array[String] = ["id", "name", "description", "visibility", "category", "abiVersion", "implementationVersion", "stateSchemaVersion", "parameters", "returnType", "allowedContexts", "requiredCapabilities", "persistentState", "backend", "program"]
		if not record is Dictionary or not _exact_fields(record, fields) or not record["id"] is String or record["id"].is_empty() or not record["name"] is String or record["name"].is_empty() or not record["description"] is String or record["visibility"] not in ["public", "private"] or not record["category"] is String or record["category"].is_empty() or not record["returnType"] is String or not SUPPORTED_VALUE_TYPES.has(record["returnType"]) or record["backend"] != "safe" or not record["persistentState"] is Dictionary or not _json_safe(record["persistentState"], 0):
			_reject("Scenario Action definition is malformed or uses an unavailable backend.")
			return null
		if record["id"].begins_with("realmz.") or not record["id"].begins_with(required_prefix) or ids.has(record["id"]):
			_reject("Scenario Action ID '%s' has an invalid or duplicate namespace." % record["id"])
			return null
		for version_field: String in ["abiVersion", "implementationVersion", "stateSchemaVersion"]:
			if _integer(record[version_field]) < 1:
				_reject("Scenario Action '%s' has invalid version field '%s'." % [record["id"], version_field])
				return null
		if not record["parameters"] is Array or record["parameters"].size() > 256:
			_reject("Scenario Action '%s' parameters are malformed." % record["id"])
			return null
		var parameters: Array[ScenarioActionParameter] = []
		var parameter_names: Dictionary = {}
		for parameter: Variant in record["parameters"]:
			if not parameter is Dictionary or not _exact_fields(parameter, ["name", "valueType", "maxLength"]) or not parameter["name"] is String or not _safe_identifier(parameter["name"]) or parameter_names.has(parameter["name"]) or not parameter["valueType"] is String or not SUPPORTED_VALUE_TYPES.has(parameter["valueType"]) or parameter["valueType"] == "void" or (parameter["maxLength"] != null and (_integer(parameter["maxLength"]) < 1 or _integer(parameter["maxLength"]) > 256)):
				_reject("Scenario Action '%s' contains a malformed or duplicate parameter." % record["id"])
				return null
			parameter_names[parameter["name"]] = true
			parameters.append(ScenarioActionParameter.new(parameter["name"], StringName(parameter["valueType"]), -1 if parameter["maxLength"] == null else _integer(parameter["maxLength"])))
		var contexts_value: Variant = _string_array(record["allowedContexts"], "Scenario Action allowed contexts")
		var capabilities_value: Variant = _string_array(record["requiredCapabilities"], "Scenario Action required capabilities")
		if contexts_value == null or capabilities_value == null:
			return null
		var context_strings: Array[String] = contexts_value
		if context_strings.is_empty():
			_reject("Scenario Action '%s' has no allowed calling context." % record["id"])
			return null
		var contexts: Array[StringName] = []
		for context: String in context_strings:
			if not SUPPORTED_ACTION_CONTEXTS.has(context) or contexts.has(StringName(context)):
				_reject("Scenario Action '%s' has an unknown or duplicate calling context '%s'." % [record["id"], context])
				return null
			contexts.append(StringName(context))
		var capabilities: Array[String] = capabilities_value
		for capability: String in capabilities:
			if not SUPPORTED_SAFE_CAPABILITIES.has(capability) or capabilities.count(capability) > 1:
				_reject("Scenario Action '%s' requires unknown capability '%s'." % [record["id"], capability])
				return null
		var program := _construct_safe_program(record["program"], capabilities)
		if program == null:
			return null
		ids[record["id"]] = true
		actions.append(ScenarioActionDefinition.new(record["id"], record["name"], record["description"], StringName(record["visibility"]), StringName(record["category"]), _integer(record["abiVersion"]), _integer(record["implementationVersion"]), _integer(record["stateSchemaVersion"]), parameters, StringName(record["returnType"]), contexts, capabilities, &"safe", program))
	return actions


func _construct_safe_program(value: Variant, declared_capabilities: Array[String]) -> SafeProgramDefinition:
	if not value is Dictionary or not _exact_fields(value, ["format", "instructions"]) or value["format"] != "realmz.safe-bytecode.v1" or not value["instructions"] is Array or value["instructions"].size() > 4096:
		_reject("Safe Scenario Action bytecode is malformed or exceeds 4,096 instructions.")
		return null
	var instructions: Array[SafeInstructionDefinition] = []
	var node_count := [value["instructions"].size()]
	for record: Variant in value["instructions"]:
		var instruction := _construct_safe_instruction(record, node_count)
		if instruction == null:
			return null
		if instruction.kind == SafeInstructionDefinition.Kind.OPERATION and not declared_capabilities.has(instruction.capability):
			_reject("Safe program uses undeclared capability '%s'." % instruction.capability)
			return null
		instructions.append(instruction)
	for index: int in range(instructions.size()):
		var instruction := instructions[index]
		if instruction.kind in [SafeInstructionDefinition.Kind.JUMP, SafeInstructionDefinition.Kind.JUMP_IF_FALSE, SafeInstructionDefinition.Kind.BEGIN_FOR_EACH] and instruction.target > instructions.size():
			_reject("Safe instruction %d jumps outside its program." % index)
			return null
		if instruction.kind == SafeInstructionDefinition.Kind.NEXT_FOR_EACH and (instruction.target < 0 or instruction.target >= instructions.size() or instructions[instruction.target].kind != SafeInstructionDefinition.Kind.BEGIN_FOR_EACH):
			_reject("Safe for-each continuation at %d has an invalid begin target." % index)
			return null
		if instruction.kind == SafeInstructionDefinition.Kind.BEGIN_FOR_EACH and (instruction.target <= index + 1 or instructions[instruction.target - 1].kind != SafeInstructionDefinition.Kind.NEXT_FOR_EACH or instructions[instruction.target - 1].target != index):
			_reject("Safe for-each beginning at %d has an invalid bounded loop target." % index)
			return null
	return SafeProgramDefinition.new(instructions)


func _construct_safe_instruction(value: Variant, node_count: Array) -> SafeInstructionDefinition:
	if not value is Dictionary or not value.get("kind") is String:
		_reject("Safe instruction is malformed.")
		return null
	match value["kind"]:
		"operation":
			if not _exact_fields(value, ["kind", "capability", "arguments", "result"]) or not value["capability"] is String or not SUPPORTED_SAFE_CAPABILITIES.has(value["capability"]) or not value["arguments"] is Dictionary or value["result"] != null and not value["result"] is String:
				_reject("Safe operation instruction is malformed or unavailable.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.OPERATION)
			instruction.capability = value["capability"]
			instruction.result_target = "" if value["result"] == null else value["result"]
			var arguments: Variant = _construct_safe_arguments(value["arguments"], node_count)
			if arguments == null:
				return null
			instruction.set_arguments(arguments)
			return instruction
		"callScenarioAction":
			if not _exact_fields(value, ["kind", "actionId", "arguments", "result"]) or not value["actionId"] is String or value["actionId"].is_empty() or not value["arguments"] is Dictionary or value["result"] != null and not value["result"] is String:
				_reject("Safe Scenario Action call is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.CALL_ACTION)
			instruction.action_id = value["actionId"]
			instruction.result_target = "" if value["result"] == null else value["result"]
			var arguments: Variant = _construct_safe_arguments(value["arguments"], node_count)
			if arguments == null:
				return null
			instruction.set_arguments(arguments)
			return instruction
		"setValue":
			if not _exact_fields(value, ["kind", "scope", "stateScope", "ownerId", "name", "value"]) or value["scope"] not in ["local", "persistent"] or value["stateScope"] != null and not value["stateScope"] is String or value["ownerId"] != null and not value["ownerId"] is String or not value["name"] is String or value["name"].is_empty():
				_reject("Safe value assignment is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.SET_VALUE)
			instruction.scope = StringName(value["scope"])
			instruction.state_scope = "" if value["stateScope"] == null else value["stateScope"]
			instruction.owner_id = "" if value["ownerId"] == null else value["ownerId"]
			instruction.name = value["name"]
			instruction.value = _construct_safe_expression(value["value"], node_count, 0)
			return instruction if instruction.value != null else null
		"jumpIfFalse":
			if not _exact_fields(value, ["kind", "condition", "target"]) or _integer(value["target"]) < 0:
				_reject("Safe conditional jump is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.JUMP_IF_FALSE)
			instruction.condition = _construct_safe_expression(value["condition"], node_count, 0)
			instruction.target = _integer(value["target"])
			return instruction if instruction.condition != null else null
		"jump":
			if not _exact_fields(value, ["kind", "target"]) or _integer(value["target"]) < 0:
				_reject("Safe jump is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.JUMP)
			instruction.target = _integer(value["target"])
			return instruction
		"beginForEach":
			if not _exact_fields(value, ["kind", "itemName", "collection", "endTarget"]) or not value["itemName"] is String or value["itemName"].is_empty() or _integer(value["endTarget"]) < 0:
				_reject("Safe for-each beginning is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.BEGIN_FOR_EACH)
			instruction.item_name = value["itemName"]
			instruction.collection = _construct_safe_expression(value["collection"], node_count, 0)
			instruction.target = _integer(value["endTarget"])
			return instruction if instruction.collection != null else null
		"nextForEach":
			if not _exact_fields(value, ["kind", "beginTarget"]) or _integer(value["beginTarget"]) < 0:
				_reject("Safe for-each continuation is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.NEXT_FOR_EACH)
			instruction.target = _integer(value["beginTarget"])
			return instruction
		"return":
			if not _exact_fields(value, ["kind", "value"]):
				_reject("Safe return instruction is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.RETURN)
			if value["value"] != null:
				instruction.value = _construct_safe_expression(value["value"], node_count, 0)
				if instruction.value == null:
					return null
			return instruction
		"halt":
			if not _exact_fields(value, ["kind", "outcome"]):
				_reject("Safe halt instruction is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.HALT)
			instruction.outcome = value["outcome"]
			return instruction
	_reject("Safe program contains unknown instruction kind '%s'." % value["kind"])
	return null


func _construct_safe_arguments(value: Dictionary, node_count: Array) -> Variant:
	var result: Dictionary = {}
	for name: Variant in value.keys():
		if not name is String or name.is_empty():
			_reject("Safe instruction contains an invalid argument name.")
			return null
		var expression := _construct_safe_expression(value[name], node_count, 0)
		if expression == null:
			return null
		result[name] = expression
	return result


func _construct_safe_expression(value: Variant, node_count: Array, depth: int) -> SafeExpressionDefinition:
	node_count[0] += 1
	if node_count[0] > 4096 or depth > 64 or not value is Dictionary or not value.get("kind") is String:
		_reject("Safe expression is malformed or exceeds its complexity limit.")
		return null
	match value["kind"]:
		"literal":
			if not _exact_fields(value, ["kind", "value"]) or not _json_safe(value["value"], depth + 1):
				_reject("Safe literal expression is malformed.")
				return null
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.LITERAL)
			expression.value = value["value"]
			return expression
		"variable":
			if not _exact_fields(value, ["kind", "scope", "stateScope", "ownerId", "name"]) or value["scope"] not in ["parameter", "local", "persistent", "context"] or value["stateScope"] != null and not value["stateScope"] is String or value["ownerId"] != null and not value["ownerId"] is String or not value["name"] is String or value["name"].is_empty():
				_reject("Safe variable expression is malformed.")
				return null
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.VARIABLE)
			expression.scope = StringName(value["scope"])
			expression.state_scope = "" if value["stateScope"] == null else value["stateScope"]
			expression.owner_id = "" if value["ownerId"] == null else value["ownerId"]
			expression.name = value["name"]
			return expression
		"array":
			if not _exact_fields(value, ["kind", "values"]) or not value["values"] is Array or value["values"].size() > 256:
				_reject("Safe array expression is malformed or exceeds 256 entries.")
				return null
			var entries: Array[SafeExpressionDefinition] = []
			for child: Variant in value["values"]:
				var entry := _construct_safe_expression(child, node_count, depth + 1)
				if entry == null:
					return null
				entries.append(entry)
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.ARRAY)
			expression.set_values(entries)
			return expression
		"record":
			if not _exact_fields(value, ["kind", "fields"]) or not value["fields"] is Dictionary or value["fields"].size() > 256:
				_reject("Safe record expression is malformed or oversized.")
				return null
			var fields: Dictionary = {}
			for field_name: Variant in value["fields"].keys():
				if not field_name is String:
					_reject("Safe record field name is malformed.")
					return null
				var field := _construct_safe_expression(value["fields"][field_name], node_count, depth + 1)
				if field == null:
					return null
				fields[field_name] = field
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.RECORD)
			expression.set_fields(fields)
			return expression
		"unary":
			if not _exact_fields(value, ["kind", "operator", "operand"]) or value["operator"] not in ["not", "-"]:
				_reject("Safe unary expression is malformed.")
				return null
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.UNARY)
			expression.operator = StringName(value["operator"])
			expression.operand = _construct_safe_expression(value["operand"], node_count, depth + 1)
			return expression if expression.operand != null else null
		"binary":
			if not _exact_fields(value, ["kind", "operator", "left", "right"]) or value["operator"] not in ["==", "!=", "<", "<=", ">", ">=", "+", "-", "*", "/", "and", "or"]:
				_reject("Safe binary expression is malformed.")
				return null
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.BINARY)
			expression.operator = StringName(value["operator"])
			expression.left = _construct_safe_expression(value["left"], node_count, depth + 1)
			expression.right = _construct_safe_expression(value["right"], node_count, depth + 1)
			return expression if expression.left != null and expression.right != null else null
		"member":
			if not _exact_fields(value, ["kind", "object", "member"]) or not value["member"] is String or value["member"].is_empty():
				_reject("Safe member expression is malformed.")
				return null
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.MEMBER)
			expression.object = _construct_safe_expression(value["object"], node_count, depth + 1)
			expression.member = value["member"]
			return expression if expression.object != null else null
		"collection":
			if not _exact_fields(value, ["kind", "operation", "collection", "itemName", "predicate"]) or value["operation"] not in ["count", "any", "all", "first"] or value["itemName"] != null and not value["itemName"] is String:
				_reject("Safe collection expression is malformed.")
				return null
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.COLLECTION)
			expression.operator = StringName(value["operation"])
			expression.collection = _construct_safe_expression(value["collection"], node_count, depth + 1)
			expression.item_name = "" if value["itemName"] == null else value["itemName"]
			if value["operation"] == "count" and (value["itemName"] != null or value["predicate"] != null) or value["operation"] in ["any", "all"] and (expression.item_name.is_empty() or value["predicate"] == null) or value["operation"] == "first" and ((value["predicate"] == null) != expression.item_name.is_empty()):
				_reject("Safe collection expression has an inconsistent predicate contract.")
				return null
			if value["predicate"] != null:
				expression.predicate = _construct_safe_expression(value["predicate"], node_count, depth + 1)
			return expression if expression.collection != null and (value["predicate"] == null or expression.predicate != null) else null
	_reject("Safe program contains unknown expression kind '%s'." % value["kind"])
	return null


func _validate_scenario_references(scenario: ScenarioDefinition, message_ids: Dictionary, encounters: Array[SimpleEncounterDefinition]) -> bool:
	var encounter_ids: Dictionary = {}
	for encounter: SimpleEncounterDefinition in encounters:
		encounter_ids[encounter.id] = true
		if not message_ids.has(encounter.prompt_message_id):
			return _reject("Simple Encounter %d references unavailable prompt message %d." % [encounter.id, encounter.prompt_message_id])
		for response: SimpleEncounterResponse in encounter.responses():
			if scenario.program_by_id(response.result_program_id) == null:
				return _reject("Simple Encounter %d response '%s' references unavailable result program '%s'." % [encounter.id, response.id, response.result_program_id])
	for program_id: String in scenario.program_ids():
		var program := scenario.program_by_id(program_id)
		for index: int in range(program.instruction_count()):
			var instruction: Variant = program.instruction_at(index)
			if not instruction is ClassicActionDefinition:
				continue
			match instruction.opcode:
				1:
					if not message_ids.has(instruction.operand_id):
						return _reject("Scenario program '%s' references unavailable message %d." % [program.id, instruction.operand_id])
				4:
					if not encounter_ids.has(instruction.operand_id):
						return _reject("Scenario program '%s' references unavailable Simple Encounter %d." % [program.id, instruction.operand_id])
				39:
					if scenario.program_by_id("xap:%d" % instruction.operand_id) == null:
						return _reject("Scenario program '%s' references unavailable XAP %d." % [program.id, instruction.operand_id])
	return true


func _program_context(owner_kind: StringName) -> StringName:
	match owner_kind:
		&"simple-encounter-result", &"complex-encounter-result":
			return &"encounter"
		&"trigger", &"extra-action-point":
			return &"action"
	return &""


func _call_arguments_match(argument_names: Array[String], result_target: String, action: ScenarioActionDefinition) -> bool:
	if argument_names != action.parameter_names():
		return false
	if result_target.is_empty():
		return true
	return action.return_type != &"void" and _safe_identifier(result_target)


func _contexts_are_compatible(caller: ScenarioActionDefinition, called: ScenarioActionDefinition) -> bool:
	for context: StringName in caller.allowed_contexts():
		if not called.allows_context(context):
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


func _exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
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


func _integer_array(value: Variant, expected_size: int, label: String) -> Variant:
	if not value is Array or value.size() != expected_size:
		_reject("%s must contain %d integers." % [label, expected_size])
		return null
	var integers: Array[int] = []
	for item: Variant in value:
		if not _is_integer(item):
			_reject("%s contains a non-integer." % label)
			return null
		integers.append(_integer(item))
	return integers


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


func _safe_identifier(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in value.length():
		var code := value.unicode_at(index)
		var lower := code >= 97 and code <= 122
		var digit := code >= 48 and code <= 57
		if not lower and not (digit and index > 0) and not (code == 95 and index > 0):
			return false
	return true


func _json_safe(value: Variant, depth: int) -> bool:
	if depth > 64:
		return false
	if value == null or value is bool or value is int or value is float or value is String:
		return true
	if value is Array:
		if value.size() > 4096:
			return false
		for child: Variant in value:
			if not _json_safe(child, depth + 1):
				return false
		return true
	if value is Dictionary:
		if value.size() > 4096:
			return false
		for key: Variant in value.keys():
			if not key is String or not _json_safe(value[key], depth + 1):
				return false
		return true
	return false


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
