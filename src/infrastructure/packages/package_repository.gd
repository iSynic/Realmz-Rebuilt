class_name PackageRepository
extends RefCounted

const EXPECTED_SCHEMA_HASH: String = "b011d35b0204a31ed3b3d9d17bdb71519d9e2f068105b1326dcaedb323dfd465"
const REQUIRED_DOCUMENTS: Array[String] = ["assets/index.json", "content.json", "scenario.json", "world.json"]
const SUPPORTED_CAPABILITIES: Array[String] = [
	"realmz.core.classic-rules-v1",
	"realmz.presentation.content-addressed-media-v1",
	"realmz.presentation.tileset-atlases-v1",
	"realmz.scenario.classic-vm-v1",
	"realmz.scenario.safe-actions-v1",
	"realmz.world.topology-v1",
]
const DEFERRED_PACKAGE_CAPABILITIES: Array[String] = [
	"realmz.scenario.gdscript-actions-v1",
]
const SUPPORTED_SAFE_CAPABILITIES: Array[String] = RealmzRuntimeApi.SUPPORTED_SAFE_CAPABILITIES
const SUPPORTED_ACTION_CONTEXTS: Array[String] = ["action", "encounter", "spell", "item", "monster-ai", "lifecycle", "rule-modifier"]
const SUPPORTED_VALUE_TYPES: Array[String] = ["void", "bool", "int", "float", "string", "location-snapshot", "time-snapshot", "wealth-snapshot", "character-snapshot", "character-snapshot-array", "combat-snapshot", "action-outcome", "encounter-outcome", "effect-outcome", "spell-validation-outcome", "spell-cast-outcome", "spell-effect-outcome", "spell-tick-outcome", "spell-expiration-outcome", "item-outcome", "monster-decision", "rule-modifier", "bool-array", "int-array", "float-array", "string-array"]
const DIRECTIONS: Array[String] = ["north", "east", "south", "west"]
const TRANSITION_DIRECTIONS: Array[String] = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
const EDGE_KINDS: Array[String] = ["open", "wall", "door", "secret", "archway", "map-boundary"]
const FEATURE_KINDS: Array[String] = ["door", "secret", "stairs", "column", "unmapped", "note", "action-point", "archway", "no-wall-in-battle"]

var _last_error: String = ""
var _loaded_packages: Dictionary = {}


func load_package(path: String) -> PackageLoadResult:
	_last_error = ""
	var cache_key := _package_cache_key(path)
	if _loaded_packages.has(cache_key):
		return _loaded_packages[cache_key] as PackageLoadResult
	var archive := ZIPReader.new()
	var open_error := archive.open(path)
	if open_error != OK:
		return PackageLoadResult.failed("package_open_failed", "Could not open package '%s' (error %d)." % [path, open_error])
	var result := _load_open_archive(archive, path)
	archive.close()
	if result.is_ok():
		_loaded_packages[cache_key] = result
	return result


func install_package(source_path: String, install_root: String = "user://packages") -> PackageInstallResult:
	var source := load_package(source_path)
	if not source.is_ok():
		return PackageInstallResult.failed(source.error_code, source.error_message)
	if not _safe_path_component(source.content.campaign_id):
		return PackageInstallResult.failed("campaign_path_unsafe", "Campaign ID cannot be used as a portable installation path.")
	var campaign_root := install_root.trim_suffix("/").path_join(source.content.campaign_id)
	var create_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(campaign_root))
	if create_error != OK:
		return PackageInstallResult.failed("package_install_directory_failed", "Could not create the package installation directory (error %d)." % create_error)
	var target_path := campaign_root.path_join("%s.realmz2" % source.content.package_hash)
	if FileAccess.file_exists(target_path):
		if _same_package_path(source_path, target_path):
			return PackageInstallResult.succeeded(target_path, source)
		var existing := load_package(target_path)
		if existing.is_ok() and existing.content.package_hash == source.content.package_hash:
			return PackageInstallResult.succeeded(target_path, existing)
		return PackageInstallResult.failed("package_install_collision", "An invalid package already occupies the immutable installation path.")
	var temporary_path := target_path + ".installing"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	if source_bytes.is_empty():
		return PackageInstallResult.failed("package_install_read_failed", "Could not read the source package for installation.")
	var temporary := FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary == null:
		return PackageInstallResult.failed("package_install_write_failed", "Could not open the temporary package installation file.")
	temporary.store_buffer(source_bytes)
	temporary.flush()
	temporary.close()
	var verified := load_package(temporary_path)
	if not verified.is_ok() or verified.content.package_hash != source.content.package_hash:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return PackageInstallResult.failed("package_install_readback_failed", "Temporary package installation failed typed readback validation.")
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(target_path))
	if rename_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return PackageInstallResult.failed("package_install_commit_failed", "Could not atomically install the verified package (error %d)." % rename_error)
	var installed := PackageLoadResult.succeeded(verified.content, PackageMediaCatalog.new(target_path, verified.content.package_hash, verified.media.assets()))
	_loaded_packages[_package_cache_key(target_path)] = installed
	return PackageInstallResult.succeeded(target_path, installed)


func discover_packages(search_roots: Array[String]) -> Array[PackageDiscoveryResult]:
	var paths: Array[String] = []
	for root: String in search_roots:
		_collect_package_paths(root, paths, 0)
	paths.sort()
	var discovered: Array[PackageDiscoveryResult] = []
	for path: String in paths:
		discovered.append(_inspect_package(path))
	return discovered


func discover_campaigns(search_roots: Array[String]) -> Array[PackageDiscoveryResult]:
	var selected_by_campaign: Dictionary = {}
	var visible: Array[PackageDiscoveryResult] = []
	for candidate: PackageDiscoveryResult in discover_packages(search_roots):
		if not candidate.ready:
			visible.append(candidate)
			continue
		var selected := selected_by_campaign.get(candidate.campaign_id) as PackageDiscoveryResult
		if selected == null or _package_revision_is_newer(candidate, selected):
			selected_by_campaign[candidate.campaign_id] = candidate
	var campaign_ids: Array[String] = []
	campaign_ids.assign(selected_by_campaign.keys())
	campaign_ids.sort()
	for campaign_id: String in campaign_ids:
		visible.append(selected_by_campaign[campaign_id] as PackageDiscoveryResult)
	return visible


func _package_revision_is_newer(candidate: PackageDiscoveryResult, selected: PackageDiscoveryResult) -> bool:
	var candidate_modified := FileAccess.get_modified_time(candidate.path)
	var selected_modified := FileAccess.get_modified_time(selected.path)
	if candidate_modified != selected_modified:
		return candidate_modified > selected_modified
	return candidate.path.naturalnocasecmp_to(selected.path) > 0


func _inspect_package(path: String) -> PackageDiscoveryResult:
	_last_error = ""
	var archive := ZIPReader.new()
	var open_error := archive.open(path)
	if open_error != OK:
		return PackageDiscoveryResult.new(path, false, "", "", "", "Could not open package (error %d)." % open_error)
	var entries_value: Variant = _zip_entries(archive)
	var manifest_value: Variant = _read_document(archive, "manifest.json")
	if entries_value == null or manifest_value == null or not manifest_value is Dictionary:
		archive.close()
		return PackageDiscoveryResult.new(path, false, "", "", "", _last_error if not _last_error.is_empty() else "Package manifest is unavailable.")
	var entries: Array[String] = []
	entries.assign(entries_value)
	var manifest: Dictionary = manifest_value
	if not _validate_manifest(manifest, archive, entries):
		archive.close()
		return PackageDiscoveryResult.new(path, false, "", "", "", _last_error if not _last_error.is_empty() else "Package manifest is invalid.")
	archive.close()
	return PackageDiscoveryResult.new(path, true, manifest["campaignId"], manifest["packageHash"], manifest["engine"]["rulesVersion"])


func _collect_package_paths(root: String, paths: Array[String], depth: int) -> void:
	if depth > 4 or not DirAccess.dir_exists_absolute(root):
		return
	for file_name: String in DirAccess.get_files_at(root):
		if file_name.to_lower().ends_with(".realmz2"):
			paths.append(root.path_join(file_name))
	for directory_name: String in DirAccess.get_directories_at(root):
		if directory_name.begins_with("."):
			continue
		_collect_package_paths(root.path_join(directory_name), paths, depth + 1)


func _package_cache_key(path: String) -> String:
	var absolute_path := ProjectSettings.globalize_path(path).simplify_path()
	if not FileAccess.file_exists(path):
		return absolute_path
	return "%s:%d:%d" % [absolute_path, FileAccess.get_modified_time(path), FileAccess.get_size(path)]


func _same_package_path(left: String, right: String) -> bool:
	return ProjectSettings.globalize_path(left).simplify_path().to_lower() == ProjectSettings.globalize_path(right).simplify_path().to_lower()


func _load_open_archive(archive: ZIPReader, source_path: String) -> PackageLoadResult:
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
	if not _validate_render_references(asset_document, world_document):
		return _validation_failure()
	var runtime_content := _construct_content(manifest, content_document, world_document, scenario_document)
	if runtime_content == null:
		return _validation_failure()
	var runtime_assets := _construct_assets(asset_document)
	return PackageLoadResult.succeeded(runtime_content, PackageMediaCatalog.new(source_path, manifest["packageHash"], runtime_assets))


func _validate_manifest(manifest: Dictionary, archive: ZIPReader, archive_entries: Array[String]) -> bool:
	var required_fields: Array[String] = ["kind", "format", "formatVersion", "schemaVersion", "schemaHash", "campaignId", "contentId", "engine", "start", "capabilities", "files", "packageHash"]
	if not _has_fields(manifest, required_fields, "manifest"):
		return false
	if manifest["kind"] != "realmz2.manifest" or manifest["format"] != "realmz2" or _integer(manifest["formatVersion"]) != 1 or _integer(manifest["schemaVersion"]) != 2:
		return _reject("Unsupported Realmz 2.0 package or schema version.")
	if manifest["schemaHash"] != EXPECTED_SCHEMA_HASH:
		return _reject("Package schema hash does not match the runtime contract mirror.")
	if not _is_sha256(manifest["packageHash"]) or not _is_sha256(manifest["contentId"]):
		return _reject("Manifest package/content identity is malformed.")
	if not manifest["campaignId"] is String or not _safe_path_component(manifest["campaignId"]):
		return _reject("Manifest campaign ID is missing.")
	if not manifest["engine"] is Dictionary or manifest["engine"].get("rulesVersion") != "realmz-classic-1":
		return _reject("Package requires an unsupported Realmz rules version.")
	if not manifest["capabilities"] is Array:
		return _reject("Manifest capabilities must be an array.")
	for capability: Variant in manifest["capabilities"]:
		var readiness_error := package_capability_error(capability)
		if not readiness_error.is_empty():
			return _reject(readiness_error)
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


static func package_capability_error(capability: Variant) -> String:
	if capability is String and DEFERRED_PACKAGE_CAPABILITIES.has(capability):
		return "Package requires sandboxed GDScript Scenario Actions, but no secure external host is available on this platform."
	if not capability is String or not SUPPORTED_CAPABILITIES.has(capability):
		return "Package requires unknown capability '%s'." % str(capability)
	return ""


func _construct_content(manifest: Dictionary, content: Dictionary, world: Dictionary, scenario: Dictionary) -> RealmzContent:
	if not content.has("campaign") or not content["campaign"] is Dictionary or content["campaign"].get("id") != manifest["campaignId"]:
		_reject("Content campaign identity does not match the manifest.")
		return null
	var campaign_definition := _construct_campaign_definition(content["campaign"])
	if campaign_definition == null:
		return null
	var messages_value: Variant = _construct_messages(content.get("messages"))
	if messages_value == null:
		return null
	var messages: Array[MessageDefinition] = messages_value
	var option_labels_value: Variant = _construct_option_labels(content.get("optionLabels"))
	if option_labels_value == null:
		return null
	var option_labels: Array[OptionLabelDefinition] = option_labels_value
	var message_ids: Dictionary = {}
	for message: MessageDefinition in messages:
		message_ids[message.id] = true
	var encounters_value: Variant = _construct_simple_encounters(content.get("simpleEncounters"))
	if encounters_value == null:
		return null
	var simple_encounters: Array[SimpleEncounterDefinition] = encounters_value
	var complex_encounters_value: Variant = _construct_complex_encounters(content.get("complexEncounters"))
	var thief_encounters_value: Variant = _construct_thief_encounters(content.get("thiefEncounters"))
	var timed_encounters_value: Variant = _construct_timed_encounters(content.get("timedEncounters"))
	if complex_encounters_value == null or thief_encounters_value == null or timed_encounters_value == null:
		return null
	if CanonicalJson.encode(content.get("timedEncounters")) != CanonicalJson.encode(world.get("timedEncounters")):
		_reject("Content and world timed-encounter inventories do not match.")
		return null
	var complex_encounters: Array[ComplexEncounterDefinition] = complex_encounters_value
	var thief_encounters: Array[ThiefEncounterDefinition] = thief_encounters_value
	var timed_encounters: Array[TimedEncounterDefinition] = timed_encounters_value
	var races_value: Variant = _construct_races(content.get("races"))
	var castes_value: Variant = _construct_castes(content.get("castes"))
	var items_value: Variant = _construct_items(content.get("items"))
	var spells_value: Variant = _construct_spells(content.get("spells"))
	var monsters_value: Variant = _construct_monsters(content.get("monsters"))
	var battles_value: Variant = _construct_battles(content.get("battles"))
	var treasures_value: Variant = _construct_treasures(content.get("treasures"))
	var shops_value: Variant = _construct_shops(content.get("shops"))
	if races_value == null or castes_value == null or items_value == null or spells_value == null or monsters_value == null or battles_value == null or treasures_value == null or shops_value == null:
		return null
	var races: Array[RaceDefinition] = races_value
	var castes: Array[CasteDefinition] = castes_value
	var items: Array[ItemDefinition] = items_value
	var spells: Array[SpellDefinition] = spells_value
	var monsters: Array[MonsterDefinition] = monsters_value
	var battles: Array[BattleDefinition] = battles_value
	var treasures: Array[TreasureDefinition] = treasures_value
	var shops: Array[ShopDefinition] = shops_value
	var scenario_definition := _construct_scenario(scenario, manifest["campaignId"])
	if scenario_definition == null:
		return null
	var triggers_value: Variant = _construct_triggers(world.get("triggers"), scenario_definition)
	if triggers_value == null:
		return null
	var triggers: Array[TriggerDefinition] = triggers_value
	if not _validate_scenario_references(scenario_definition, message_ids, simple_encounters, complex_encounters, thief_encounters):
		return null
	if not _validate_rule_references(races, castes, items, spells, monsters, battles, treasures, shops, message_ids):
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
	if not _validate_random_region_references(maps, scenario_definition, battles):
		return null
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
		if trigger.post_action_location != null:
			var destination_map := world_definition.map_by_id(trigger.post_action_location.map_id)
			if destination_map == null or destination_map.topology.cell_at(trigger.post_action_location.coordinate) == null:
				_reject("Trigger '%s' references an unavailable post-action location." % trigger.id)
				return null
	return RealmzContent.new(manifest["campaignId"], manifest["packageHash"], manifest["contentId"], manifest["engine"]["rulesVersion"], start["mapId"], start_coordinate, world_definition, scenario_definition, messages, triggers, simple_encounters, races, castes, items, spells, monsters, battles, treasures, shops, complex_encounters, thief_encounters, timed_encounters, option_labels, campaign_definition)


func _construct_campaign_definition(value: Variant) -> CampaignDefinition:
	if not value is Dictionary:
		_reject("Content campaign metadata must be an object.")
		return null
	var record: Dictionary = value
	var fields: Array[String] = ["id", "name", "version", "author", "contact", "description", "splashAssetId", "restrictions"]
	if not _exact_fields(record, fields) or not record["id"] is String or record["id"].is_empty() or not record["name"] is String or record["name"].is_empty() or not record["version"] is String or not record["author"] is String or not record["contact"] is Dictionary or not record["description"] is String or not record["splashAssetId"] is String or not record["restrictions"] is Dictionary:
		_reject("Campaign display metadata is malformed.")
		return null
	var contact: Dictionary = record["contact"]
	if not _exact_fields(contact, ["email", "web", "date", "fee"]) or not contact["email"] is String or not contact["web"] is String or not contact["date"] is String or not contact["fee"] is String:
		_reject("Campaign contact metadata is malformed.")
		return null
	var restrictions: Dictionary = record["restrictions"]
	var restriction_fields: Array[String] = ["description", "maxPartySize", "maxLevel", "bannedRaces", "bannedCastes"]
	if not _exact_fields(restrictions, restriction_fields) or not restrictions["description"] is String or _integer(restrictions["maxPartySize"]) < 1 or _integer(restrictions["maxPartySize"]) > 6 or _integer(restrictions["maxLevel"]) < 0 or not restrictions["bannedRaces"] is Array or not restrictions["bannedCastes"] is Array:
		_reject("Campaign restriction metadata is malformed.")
		return null
	var result := CampaignDefinition.new()
	result.id = record["id"]
	result.title = record["name"]
	result.version = record["version"]
	result.author = record["author"]
	result.contact = record["contact"].duplicate(true)
	result.description = record["description"]
	result.splash_asset_id = record["splashAssetId"]
	result.restrictions.description = restrictions["description"]
	result.restrictions.maximum_party_size = _integer(restrictions["maxPartySize"])
	result.restrictions.maximum_level = _integer(restrictions["maxLevel"])
	for race_id: Variant in restrictions["bannedRaces"]:
		if not race_id is String:
			_reject("Campaign banned race IDs must be strings.")
			return null
		result.restrictions.banned_races.append(race_id)
	for caste_id: Variant in restrictions["bannedCastes"]:
		if not caste_id is String:
			_reject("Campaign banned caste IDs must be strings.")
			return null
		result.restrictions.banned_castes.append(caste_id)
	return result


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


func _construct_option_labels(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content option labels must be an array.")
		return null
	var option_labels: Array[OptionLabelDefinition] = []
	var ids: Dictionary = {}
	for record: Variant in value:
		if not record is Dictionary or not _exact_fields(record, ["id", "text"]) or _integer(record.get("id")) < 0 or not record.get("text") is String:
			_reject("Option-label record is malformed.")
			return null
		var id := _integer(record["id"])
		if ids.has(id):
			_reject("Option-label ID %d is duplicated." % id)
			return null
		ids[id] = true
		option_labels.append(OptionLabelDefinition.new(id, record["text"]))
	return option_labels


func _construct_items(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content items must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "name", "unidentifiedName", "description", "iconId", "itemType", "strengthBonus", "blunt", "hands", "luckBonus", "movementBonus", "armorBonus", "magicResistanceBonus", "damageBonus", "spellPointBonus", "soundId", "weight", "cost", "initialCharges", "cursedItemId", "magical", "itemCategoryMaskLow", "itemCategoryMaskHigh", "raceRestrictions", "casteRestrictions", "specificRaceId", "specificCasteId", "raceClassOnly", "casteClassOnly", "versusSmall", "versusLarge", "heat", "cold", "electric", "versusUndead", "versusDemonDevil", "versusEvil", "special", "weightPerCharge", "dropOnEmpty"]
	var integer_fields: Array[String] = ["classicId", "iconId", "itemType", "strengthBonus", "blunt", "hands", "luckBonus", "movementBonus", "armorBonus", "magicResistanceBonus", "damageBonus", "spellPointBonus", "soundId", "weight", "cost", "initialCharges", "itemCategoryMaskLow", "itemCategoryMaskHigh", "raceRestrictions", "casteRestrictions", "raceClassOnly", "casteClassOnly", "versusSmall", "versusLarge", "heat", "cold", "electric", "versusUndead", "versusDemonDevil", "versusEvil", "weightPerCharge"]
	var result: Array[ItemDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Item definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, integer_fields, "Item definition")
		if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Item") or not record["unidentifiedName"] is String or record["unidentifiedName"].is_empty() or not record["description"] is String or not record["cursedItemId"] is String or not record["specificRaceId"] is String or not record["specificCasteId"] is String or not record["magical"] is bool or not record["dropOnEmpty"] is bool:
			_reject("Item definition is malformed or duplicated.")
			return null
		var special_value: Variant = _integer_array(record["special"], 5, "Item special values")
		if special_value == null:
			return null
		var integers: Dictionary = integers_value
		var special: Array[int] = special_value
		var item := ItemDefinition.new(record["id"], integers["classicId"], record["name"], record["unidentifiedName"], record["description"])
		item.icon_id = integers["iconId"]
		item.item_type = integers["itemType"]
		item.strength_bonus = integers["strengthBonus"]
		item.blunt = integers["blunt"]
		item.hands = integers["hands"]
		item.luck_bonus = integers["luckBonus"]
		item.movement_bonus = integers["movementBonus"]
		item.armor_bonus = integers["armorBonus"]
		item.magic_resistance_bonus = integers["magicResistanceBonus"]
		item.damage_bonus = integers["damageBonus"]
		item.spell_point_bonus = integers["spellPointBonus"]
		item.sound_id = integers["soundId"]
		item.weight = integers["weight"]
		item.cost = integers["cost"]
		item.initial_charges = integers["initialCharges"]
		item.cursed_item_id = record["cursedItemId"]
		item.magical = record["magical"]
		item.item_category_mask_low = integers["itemCategoryMaskLow"]
		item.item_category_mask_high = integers["itemCategoryMaskHigh"]
		item.race_restrictions = integers["raceRestrictions"]
		item.caste_restrictions = integers["casteRestrictions"]
		item.specific_race_id = record["specificRaceId"]
		item.specific_caste_id = record["specificCasteId"]
		item.race_class_only = integers["raceClassOnly"]
		item.caste_class_only = integers["casteClassOnly"]
		item.vs_small = integers["versusSmall"]
		item.vs_large = integers["versusLarge"]
		item.heat = integers["heat"]
		item.cold = integers["cold"]
		item.electric = integers["electric"]
		item.vs_undead = integers["versusUndead"]
		item.vs_demon_devil = integers["versusDemonDevil"]
		item.vs_evil = integers["versusEvil"]
		item.special_1 = special[0]
		item.special_2 = special[1]
		item.special_3 = special[2]
		item.special_4 = special[3]
		item.special_5 = special[4]
		item.weight_per_charge = integers["weightPerCharge"]
		item.drop_on_empty = record["dropOnEmpty"]
		result.append(item)
	return result


func _construct_races(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content races must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "name", "description", "eligibleCasteIds", "hitModifiers", "saveBonuses", "attributeBonuses", "attributeLimits", "conditionLevels", "ageRanges", "ageChanges", "maximumAge", "doesNotDie", "baseMovement", "magicResistance", "twoHandBonus", "missileBonus", "baseAttacks", "maximumAttacks", "canRegenerate", "defaultIconSet", "itemCategoryMasks", "descriptorFlags"]
	var integer_fields: Array[String] = ["classicId", "maximumAge", "baseMovement", "magicResistance", "twoHandBonus", "missileBonus", "baseAttacks", "maximumAttacks", "defaultIconSet", "descriptorFlags"]
	var result: Array[RaceDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Race definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, integer_fields, "Race definition")
		if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Race") or not record["name"] is String or not record["description"] is String or not record["eligibleCasteIds"] is Array or not record["doesNotDie"] is bool or not record["canRegenerate"] is bool or not record["ageRanges"] is Array or record["ageRanges"].size() != 5 or not record["ageChanges"] is Array or record["ageChanges"].size() != 5:
			_reject("Race definition is malformed or duplicated.")
			return null
		var hit_value: Variant = _integer_array(record["hitModifiers"], 8, "Race hit modifiers")
		var save_value: Variant = _integer_array(record["saveBonuses"], 8, "Race save bonuses")
		var bonus_value: Variant = _integer_array(record["attributeBonuses"], 6, "Race attribute bonuses")
		var limits_value: Variant = _integer_array(record["attributeLimits"], 12, "Race attribute limits")
		var conditions_value: Variant = _integer_array(record["conditionLevels"], 40, "Race condition levels")
		var masks_value: Variant = _integer_array(record["itemCategoryMasks"], 2, "Race item masks")
		if hit_value == null or save_value == null or bonus_value == null or limits_value == null or conditions_value == null or masks_value == null:
			return null
		var ages: Array[Vector2i] = []
		for row: Variant in record["ageRanges"]:
			var pair_value: Variant = _integer_array(row, 2, "Race age range")
			if pair_value == null:
				return null
			var pair: Array[int] = pair_value
			ages.append(Vector2i(pair[0], pair[1]))
		var age_changes: Array[PackedInt32Array] = []
		for row: Variant in record["ageChanges"]:
			var changes_value: Variant = _integer_array(row, 15, "Race age change")
			if changes_value == null:
				return null
			var changes: Array[int] = changes_value
			age_changes.append(PackedInt32Array(changes))
		var integers: Dictionary = integers_value
		var masks: Array[int] = masks_value
		var eligible_castes: Array[String] = []
		for caste_id: Variant in record["eligibleCasteIds"]:
			if not caste_id is String or caste_id.is_empty():
				_reject("Race eligibility IDs must be non-empty strings.")
				return null
			eligible_castes.append(caste_id)
		result.append(RaceDefinition.new(record["id"], integers["classicId"], record["name"], hit_value, save_value, bonus_value, limits_value, conditions_value, ages, age_changes, integers["maximumAge"], record["doesNotDie"], integers["baseMovement"], integers["magicResistance"], integers["twoHandBonus"], integers["missileBonus"], integers["baseAttacks"], integers["maximumAttacks"], record["canRegenerate"], integers["defaultIconSet"], masks[0], masks[1], integers["descriptorFlags"], record["description"], eligible_castes))
	return result


func _construct_castes(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content castes must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "name", "description", "eligibleRaceIds", "saveBonuses", "attributeBonuses", "attributeLimits", "conditionLevels", "staminaDice", "strengthValues", "dodgeValues", "toHitValues", "missileValues", "handToHandValues", "spellcasterRows", "attackLevels", "startingItemIds", "casteClass", "minimumAgeGroup", "movementBonus", "magicResistanceMultiplier", "twoHandBonus", "maximumStaminaBonus", "bonusAttacks", "maximumAttacks", "startMoney", "canUseMissile", "getsMissileBonus", "defaultIcon", "itemCategoryMasks"]
	var integer_fields: Array[String] = ["classicId", "casteClass", "minimumAgeGroup", "movementBonus", "magicResistanceMultiplier", "twoHandBonus", "maximumStaminaBonus", "bonusAttacks", "maximumAttacks", "startMoney", "defaultIcon"]
	var result: Array[CasteDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Caste definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, integer_fields, "Caste definition")
		if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Caste") or not record["name"] is String or not record["description"] is String or not record["eligibleRaceIds"] is Array or not record["canUseMissile"] is bool or not record["getsMissileBonus"] is bool or not record["spellcasterRows"] is Array or record["spellcasterRows"].size() != 4:
			_reject("Caste definition is malformed or duplicated.")
			return null
		var saves_value: Variant = _integer_array(record["saveBonuses"], 8, "Caste save bonuses")
		var bonuses_value: Variant = _integer_array(record["attributeBonuses"], 6, "Caste attribute bonuses")
		var limits_value: Variant = _integer_array(record["attributeLimits"], 12, "Caste attribute limits")
		var conditions_value: Variant = _integer_array(record["conditionLevels"], 40, "Caste condition levels")
		var stamina_value: Variant = _integer_array(record["staminaDice"], 2, "Caste stamina dice")
		var strength_value: Variant = _integer_array(record["strengthValues"], 2, "Caste strength values")
		var dodge_value: Variant = _integer_array(record["dodgeValues"], 2, "Caste dodge values")
		var to_hit_value: Variant = _integer_array(record["toHitValues"], 2, "Caste to-hit values")
		var missile_value: Variant = _integer_array(record["missileValues"], 2, "Caste missile values")
		var hand_value: Variant = _integer_array(record["handToHandValues"], 2, "Caste hand-to-hand values")
		var attacks_value: Variant = _integer_array(record["attackLevels"], 10, "Caste attack levels")
		var masks_value: Variant = _integer_array(record["itemCategoryMasks"], 2, "Caste item masks")
		var start_items_value: Variant = _string_list(record["startingItemIds"], "Caste starting item IDs")
		if saves_value == null or bonuses_value == null or limits_value == null or conditions_value == null or stamina_value == null or strength_value == null or dodge_value == null or to_hit_value == null or missile_value == null or hand_value == null or attacks_value == null or masks_value == null or start_items_value == null:
			return null
		var spellcasters: Array[Vector3i] = []
		for row: Variant in record["spellcasterRows"]:
			var row_value: Variant = _integer_array(row, 3, "Caste spellcaster row")
			if row_value == null:
				return null
			var values: Array[int] = row_value
			spellcasters.append(Vector3i(values[0], values[1], values[2]))
		var integers: Dictionary = integers_value
		var stamina: Array[int] = stamina_value
		var strength: Array[int] = strength_value
		var dodge: Array[int] = dodge_value
		var to_hit: Array[int] = to_hit_value
		var missile: Array[int] = missile_value
		var hand: Array[int] = hand_value
		var masks: Array[int] = masks_value
		var eligible_races: Array[String] = []
		for race_id: Variant in record["eligibleRaceIds"]:
			if not race_id is String or race_id.is_empty():
				_reject("Caste eligibility IDs must be non-empty strings.")
				return null
			eligible_races.append(race_id)
		result.append(CasteDefinition.new(record["id"], integers["classicId"], record["name"], saves_value, bonuses_value, limits_value, conditions_value, Vector2i(stamina[0], stamina[1]), Vector2i(to_hit[0], to_hit[1]), Vector2i(dodge[0], dodge[1]), Vector2i(missile[0], missile[1]), Vector2i(hand[0], hand[1]), spellcasters, attacks_value, start_items_value, integers["casteClass"], integers["minimumAgeGroup"], integers["movementBonus"], integers["magicResistanceMultiplier"], integers["twoHandBonus"], integers["maximumStaminaBonus"], integers["bonusAttacks"], integers["maximumAttacks"], integers["startMoney"], record["canUseMissile"], record["getsMissileBonus"], integers["defaultIcon"], masks[0], masks[1], Vector2i(strength[0], strength[1]), record["description"], eligible_races))
	return result


func _construct_spells(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content spells must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "name", "description", "rangeMin", "rangeMax", "queueIcon", "toHitBonus", "saveBonus", "fixedTargetCount", "canRotate", "saveAdjust", "cannot", "resistanceAdjust", "cost", "damageMin", "damageMax", "powerDamageMin", "powerDamageMax", "durationMin", "durationMax", "powerDurationMin", "powerDurationMax", "lookStart", "lookEnd", "soundStart", "soundEnd", "targetType", "size", "special", "damageType", "spellClass", "inCombat", "inCamp"]
	var integer_fields := fields.slice(1)
	integer_fields.erase("name")
	integer_fields.erase("description")
	integer_fields.erase("canRotate")
	integer_fields.erase("inCombat")
	integer_fields.erase("inCamp")
	var result: Array[SpellDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Spell definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, integer_fields, "Spell definition")
		if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Spell") or not record["description"] is String or not record["canRotate"] is bool or not record["inCombat"] is bool or not record["inCamp"] is bool:
			_reject("Spell definition is malformed or duplicated.")
			return null
		var integers: Dictionary = integers_value
		var spell := SpellDefinition.new(record["id"], integers["classicId"], record["name"], record["description"])
		spell.range_min = integers["rangeMin"]
		spell.range_max = integers["rangeMax"]
		spell.queue_icon = integers["queueIcon"]
		spell.to_hit_bonus = integers["toHitBonus"]
		spell.save_bonus = integers["saveBonus"]
		spell.fixed_target_count = integers["fixedTargetCount"]
		spell.can_rotate = record["canRotate"]
		spell.save_adjust = integers["saveAdjust"]
		spell.cannot = integers["cannot"]
		spell.resistance_adjust = integers["resistanceAdjust"]
		spell.cost = integers["cost"]
		spell.damage_min = integers["damageMin"]
		spell.damage_max = integers["damageMax"]
		spell.power_damage_min = integers["powerDamageMin"]
		spell.power_damage_max = integers["powerDamageMax"]
		spell.duration_min = integers["durationMin"]
		spell.duration_max = integers["durationMax"]
		spell.power_duration_min = integers["powerDurationMin"]
		spell.power_duration_max = integers["powerDurationMax"]
		spell.look_start = integers["lookStart"]
		spell.look_end = integers["lookEnd"]
		spell.sound_start = integers["soundStart"]
		spell.sound_end = integers["soundEnd"]
		spell.target_type = integers["targetType"]
		spell.size = integers["size"]
		spell.special = integers["special"]
		spell.damage_type = integers["damageType"]
		spell.spell_class = integers["spellClass"]
		spell.in_combat = record["inCombat"]
		spell.in_camp = record["inCamp"]
		result.append(spell)
	return result


func _construct_monsters(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content monsters must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "name", "hitDice", "staminaBonus", "agility", "movementMaximum", "armor", "magicResistance", "requiredWeapon", "magicToHit", "traitor", "size", "typeFlags", "attackCount", "magicAttackCount", "attacks", "damageBonus", "castPercent", "runPercent", "surrenderPercent", "missilePercent", "canSummon", "saves", "spellImmunities", "money", "spellIds", "itemIds", "weaponId", "randomWeaponTable", "iconId", "spellPoints", "experience", "deathMacro"]
	var integer_fields: Array[String] = ["classicId", "hitDice", "staminaBonus", "agility", "movementMaximum", "armor", "magicResistance", "requiredWeapon", "magicToHit", "size", "attackCount", "magicAttackCount", "damageBonus", "castPercent", "runPercent", "surrenderPercent", "missilePercent", "canSummon", "randomWeaponTable", "iconId", "spellPoints", "experience", "deathMacro"]
	var result: Array[MonsterDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Monster definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, integer_fields, "Monster definition")
		if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Monster") or not record["traitor"] is bool or not record["weaponId"] is String or not record["attacks"] is Array or _integer(record["requiredWeapon"]) < -128 or _integer(record["requiredWeapon"]) > 127 or _integer(record["magicToHit"]) < 0 or _integer(record["magicToHit"]) > 127 or _integer(record["randomWeaponTable"]) < 0 or _integer(record["randomWeaponTable"]) > 10:
			_reject("Monster definition is malformed or duplicated.")
			return null
		var type_value: Variant = _integer_array(record["typeFlags"], 8, "Monster type flags")
		var saves_value: Variant = _integer_array(record["saves"], 6, "Monster saves")
		var immunity_value: Variant = _integer_array(record["spellImmunities"], 6, "Monster spell immunities")
		var money_value: Variant = _integer_array(record["money"], 3, "Monster wealth")
		var spell_ids_value: Variant = _string_list(record["spellIds"], "Monster spell IDs")
		var item_ids_value: Variant = _string_list(record["itemIds"], "Monster item IDs")
		if type_value == null or saves_value == null or immunity_value == null or money_value == null or spell_ids_value == null or item_ids_value == null:
			return null
		var attacks: Array[MonsterAttackDefinition] = []
		for attack_value: Variant in record["attacks"]:
			if not attack_value is Dictionary or not _exact_fields(attack_value, ["damageMin", "damageMax", "soundOrType", "special"]):
				_reject("Monster attack definition is malformed.")
				return null
			var attack_integers_value: Variant = _validated_integer_fields(attack_value, ["damageMin", "damageMax", "soundOrType", "special"], "Monster attack")
			if attack_integers_value == null:
				return null
			var attack_integers: Dictionary = attack_integers_value
			attacks.append(MonsterAttackDefinition.new(attack_integers["damageMin"], attack_integers["damageMax"], attack_integers["soundOrType"], attack_integers["special"]))
		var integers: Dictionary = integers_value
		var monster := MonsterDefinition.new(record["id"], integers["classicId"], record["name"], integers["hitDice"], integers["staminaBonus"], integers["agility"], integers["armor"], integers["magicResistance"], type_value, saves_value, immunity_value, money_value, spell_ids_value, item_ids_value, attacks)
		monster.movement_max = integers["movementMaximum"]
		monster.required_weapon = integers["requiredWeapon"]
		monster.magic_to_hit = integers["magicToHit"]
		monster.traitor = record["traitor"]
		monster.size = integers["size"]
		monster.attack_count = integers["attackCount"]
		monster.magic_attack_count = integers["magicAttackCount"]
		monster.damage_bonus = integers["damageBonus"]
		monster.cast_percent = integers["castPercent"]
		monster.run_percent = integers["runPercent"]
		monster.surrender_percent = integers["surrenderPercent"]
		monster.missile_percent = integers["missilePercent"]
		monster.can_summon = integers["canSummon"]
		monster.weapon_id = record["weaponId"]
		monster.random_weapon_table = integers["randomWeaponTable"]
		monster.icon_id = integers["iconId"]
		monster.spell_points = integers["spellPoints"]
		monster.experience = integers["experience"]
		monster.death_macro = integers["deathMacro"]
		result.append(monster)
	return result


func _construct_battles(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content battles must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "monsterSlots", "distance", "messageBeforeId", "messageAfterId", "macroId"]
	var result: Array[BattleDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Battle definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, ["classicId", "distance", "messageBeforeId", "messageAfterId", "macroId"], "Battle definition")
		if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Battle", false) or not record["monsterSlots"] is Array or record["monsterSlots"].size() > 169:
			_reject("Battle definition is malformed or duplicated.")
			return null
		var monster_slots: Array[BattleMonsterSlotDefinition] = []
		var occupied: Dictionary = {}
		for slot_value: Variant in record["monsterSlots"]:
			if not slot_value is Dictionary or not _exact_fields(slot_value, ["x", "y", "monsterId", "invertTraitor"]) or not _is_integer(slot_value["x"]) or not _is_integer(slot_value["y"]) or _integer(slot_value["x"]) < 0 or _integer(slot_value["x"]) > 12 or _integer(slot_value["y"]) < 0 or _integer(slot_value["y"]) > 12 or not slot_value["monsterId"] is String or slot_value["monsterId"].is_empty() or not slot_value["invertTraitor"] is bool:
				_reject("Battle monster slot is malformed.")
				return null
			var coordinate := Vector2i(_integer(slot_value["x"]), _integer(slot_value["y"]))
			if occupied.has(coordinate):
				_reject("Battle monster slot coordinate is duplicated.")
				return null
			occupied[coordinate] = true
			monster_slots.append(BattleMonsterSlotDefinition.new(coordinate, slot_value["monsterId"], slot_value["invertTraitor"]))
		var integers: Dictionary = integers_value
		result.append(BattleDefinition.new(record["id"], integers["classicId"], monster_slots, integers["distance"], integers["messageBeforeId"], integers["messageAfterId"], integers["macroId"]))
	return result


func _construct_treasures(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content treasures must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "itemIds", "experience", "gold", "gems", "jewelry"]
	var result: Array[TreasureDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Treasure definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, ["classicId", "experience", "gold", "gems", "jewelry"], "Treasure definition")
		var item_ids_value: Variant = _string_list(record.get("itemIds"), "Treasure item IDs")
		if not _exact_fields(record, fields) or integers_value == null or item_ids_value == null or not _definition_identity(record, ids, "Treasure", false):
			_reject("Treasure definition is malformed or duplicated.")
			return null
		var integers: Dictionary = integers_value
		result.append(TreasureDefinition.new(record["id"], integers["classicId"], item_ids_value, integers["experience"], integers["gold"], integers["gems"], integers["jewelry"]))
	return result


func _construct_shops(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content shops must be an array.")
		return null
	var fields: Array[String] = ["id", "classicId", "inflationPercent", "stock"]
	var result: Array[ShopDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Shop definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, ["classicId", "inflationPercent"], "Shop definition")
		if not _exact_fields(record, fields) or integers_value == null or not _definition_identity(record, ids, "Shop", false) or not record["stock"] is Array or record["stock"].size() > 1000:
			_reject("Shop definition is malformed or duplicated.")
			return null
		var item_ids: Array[String] = []
		var quantities: Array[int] = []
		for stock_value: Variant in record["stock"]:
			if not stock_value is Dictionary or not _exact_fields(stock_value, ["itemId", "quantity"]) or not stock_value["itemId"] is String or stock_value["itemId"].is_empty() or not _is_integer(stock_value["quantity"]) or _integer(stock_value["quantity"]) < 0:
				_reject("Shop stock record is malformed.")
				return null
			item_ids.append(stock_value["itemId"])
			quantities.append(_integer(stock_value["quantity"]))
		var integers: Dictionary = integers_value
		result.append(ShopDefinition.new(record["id"], integers["classicId"], item_ids, quantities, integers["inflationPercent"]))
	return result


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


func _construct_complex_encounters(value: Variant) -> Variant:
	if not value is Array:
		_reject("Complex Encounters must be an array.")
		return null
	var fields: Array[String] = ["id", "promptMessageId", "actionResult", "wordResult", "groups", "spellIds", "spellResults", "itemIds", "itemResults", "canBackOut", "thief", "maxTimes", "casteSuccess", "thiefSuccess", "thiefFail", "texts"]
	var scalar_fields: Array[String] = ["id", "promptMessageId", "actionResult", "wordResult", "maxTimes", "casteSuccess", "thiefSuccess", "thiefFail"]
	var encounters: Array[ComplexEncounterDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Complex Encounter definition is not an object.")
			return null
		var record: Dictionary = value_record
		var scalars_value: Variant = _validated_integer_fields(record, scalar_fields, "Complex Encounter")
		if not _exact_fields(record, fields) or scalars_value == null or not record["canBackOut"] is bool or not record["thief"] is bool:
			_reject("Complex Encounter definition is malformed.")
			return null
		var scalars: Dictionary = scalars_value
		if scalars["id"] < 0 or ids.has(scalars["id"]) or not _integers_in_range(scalars, ["actionResult", "wordResult", "maxTimes", "casteSuccess", "thiefSuccess", "thiefFail"], -128, 127):
			_reject("Complex Encounter identity or Classic scalar fields are malformed.")
			return null
		var groups_value: Variant = _integer_array(record["groups"], 8, "Complex Encounter groups")
		var spell_ids_value: Variant = _integer_array(record["spellIds"], 10, "Complex Encounter spell IDs")
		var spell_results_value: Variant = _integer_array(record["spellResults"], 10, "Complex Encounter spell results")
		var item_ids_value: Variant = _integer_array(record["itemIds"], 5, "Complex Encounter item IDs")
		var item_results_value: Variant = _integer_array(record["itemResults"], 5, "Complex Encounter item results")
		var texts_value: Variant = _fixed_string_list(record["texts"], 9, 40, "Complex Encounter texts")
		if groups_value == null or spell_ids_value == null or spell_results_value == null or item_ids_value == null or item_results_value == null or texts_value == null:
			return null
		var groups: Array[int] = groups_value
		var spell_ids: Array[int] = spell_ids_value
		var spell_results: Array[int] = spell_results_value
		var item_ids: Array[int] = item_ids_value
		var item_results: Array[int] = item_results_value
		if not _array_values_in_range(groups, -128, 127) or not _array_values_in_range(spell_ids, -32768, 32767) or not _array_values_in_range(spell_results, -128, 127) or not _array_values_in_range(item_ids, -32768, 32767) or not _array_values_in_range(item_results, -128, 127):
			_reject("Complex Encounter arrays exceed Classic storage.")
			return null
		ids[scalars["id"]] = true
		encounters.append(ComplexEncounterDefinition.new(scalars["id"], scalars["promptMessageId"], scalars["actionResult"], scalars["wordResult"], groups, spell_ids, spell_results, item_ids, item_results, record["canBackOut"], record["thief"], scalars["maxTimes"], scalars["casteSuccess"], scalars["thiefSuccess"], scalars["thiefFail"], texts_value))
	return encounters


func _construct_thief_encounters(value: Variant) -> Variant:
	if not value is Array:
		_reject("Thief Encounters must be an array.")
		return null
	var fields: Array[String] = ["id", "typeFlags", "modifiers", "successCodes", "failureCodes", "successText", "failureText", "successSounds", "failureSounds", "spellId", "lowDamage", "highDamage", "tumblers", "prompts", "promptSounds"]
	var scalar_fields: Array[String] = ["id", "spellId", "lowDamage", "highDamage", "tumblers"]
	var encounters: Array[ThiefEncounterDefinition] = []
	var ids: Dictionary = {}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Thief Encounter definition is not an object.")
			return null
		var record: Dictionary = value_record
		var scalars_value: Variant = _validated_integer_fields(record, scalar_fields, "Thief Encounter")
		if not _exact_fields(record, fields) or scalars_value == null:
			_reject("Thief Encounter definition is malformed.")
			return null
		var scalars: Dictionary = scalars_value
		if scalars["id"] < 0 or ids.has(scalars["id"]) or not _integers_in_range(scalars, ["spellId", "lowDamage", "highDamage", "tumblers"], -32768, 32767):
			_reject("Thief Encounter identity or Classic scalar fields are malformed.")
			return null
		var type_flags_value: Variant = _boolean_array(record["typeFlags"], 10, "Thief Encounter type flags")
		var modifiers_value: Variant = _integer_array(record["modifiers"], 8, "Thief Encounter modifiers")
		var success_codes_value: Variant = _integer_array(record["successCodes"], 8, "Thief Encounter success codes")
		var failure_codes_value: Variant = _integer_array(record["failureCodes"], 8, "Thief Encounter failure codes")
		var success_text_value: Variant = _integer_array(record["successText"], 8, "Thief Encounter success text")
		var failure_text_value: Variant = _integer_array(record["failureText"], 8, "Thief Encounter failure text")
		var success_sounds_value: Variant = _integer_array(record["successSounds"], 8, "Thief Encounter success sounds")
		var failure_sounds_value: Variant = _integer_array(record["failureSounds"], 8, "Thief Encounter failure sounds")
		var prompts_value: Variant = _integer_array(record["prompts"], 3, "Thief Encounter prompts")
		var prompt_sounds_value: Variant = _integer_array(record["promptSounds"], 3, "Thief Encounter prompt sounds")
		if type_flags_value == null or modifiers_value == null or success_codes_value == null or failure_codes_value == null or success_text_value == null or failure_text_value == null or success_sounds_value == null or failure_sounds_value == null or prompts_value == null or prompt_sounds_value == null:
			return null
		for signed_bytes: Array[int] in [modifiers_value, success_codes_value, failure_codes_value]:
			if not _array_values_in_range(signed_bytes, -128, 127):
				_reject("Thief Encounter byte arrays exceed Classic storage.")
				return null
		for signed_shorts: Array[int] in [success_text_value, failure_text_value, success_sounds_value, failure_sounds_value, prompts_value, prompt_sounds_value]:
			if not _array_values_in_range(signed_shorts, -32768, 32767):
				_reject("Thief Encounter short arrays exceed Classic storage.")
				return null
		ids[scalars["id"]] = true
		encounters.append(ThiefEncounterDefinition.new(scalars["id"], type_flags_value, modifiers_value, success_codes_value, failure_codes_value, success_text_value, failure_text_value, success_sounds_value, failure_sounds_value, scalars["spellId"], scalars["lowDamage"], scalars["highDamage"], scalars["tumblers"], prompts_value, prompt_sounds_value))
	return encounters


func _construct_timed_encounters(value: Variant) -> Variant:
	if not value is Array:
		_reject("Timed Encounters must be an array.")
		return null
	var fields: Array[String] = ["id", "day", "increment", "chancePercent", "triggerRecordIndex", "requiredLevel", "requiredRandomRectangle", "requiredX", "requiredY", "requiredItemId", "requiredQuestId", "locationKind"]
	var integer_fields: Array[String] = ["id", "day", "increment", "chancePercent", "triggerRecordIndex", "requiredLevel", "requiredRandomRectangle", "requiredX", "requiredY", "requiredItemId", "requiredQuestId"]
	var encounters: Array[TimedEncounterDefinition] = []
	var ids: Dictionary = {}
	var location_kinds: Dictionary = {"any": TimedEncounterDefinition.LocationKind.ANY, "land": TimedEncounterDefinition.LocationKind.LAND, "dungeon": TimedEncounterDefinition.LocationKind.DUNGEON}
	for value_record: Variant in value:
		if not value_record is Dictionary:
			_reject("Timed Encounter definition is not an object.")
			return null
		var record: Dictionary = value_record
		var integers_value: Variant = _validated_integer_fields(record, integer_fields, "Timed Encounter")
		if not _exact_fields(record, fields) or integers_value == null or not record["locationKind"] is String or not location_kinds.has(record["locationKind"]):
			_reject("Timed Encounter definition is malformed.")
			return null
		var integers: Dictionary = integers_value
		if integers["id"] < 0 or ids.has(integers["id"]) or not _integers_in_range(integers, integer_fields.slice(1), -32768, 32767):
			_reject("Timed Encounter identity or Classic fields are malformed.")
			return null
		ids[integers["id"]] = true
		encounters.append(TimedEncounterDefinition.new(integers["id"], integers["day"], integers["increment"], integers["chancePercent"], integers["triggerRecordIndex"], integers["requiredLevel"], integers["requiredRandomRectangle"], integers["requiredX"], integers["requiredY"], integers["requiredItemId"], integers["requiredQuestId"], location_kinds[record["locationKind"]]))
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
	var normalized := ClassicOpcodeCatalog.normalize(raw_opcode)
	if normalized != _integer(instruction["opcode"]) or instruction["gosub"] != (raw_opcode < 0 and raw_opcode not in [-14, -23]):
		_reject("Classic instruction raw/normalized/GOSUB identity is inconsistent.")
		return null
	if not ClassicOpcodeCatalog.is_executable(normalized):
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
	if not render is Dictionary or not _exact_fields(render, ["tile", "tilesetId", "overlayAssetId"]) or not _is_integer(render.get("tile")) or not render.get("tilesetId") is String or render["tilesetId"].is_empty():
		_reject("Topology cell render facts are malformed.")
		return null
	if render["overlayAssetId"] != null and (not render["overlayAssetId"] is String or render["overlayAssetId"].is_empty()):
		_reject("Topology cell overlay render identity is malformed.")
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
	return MapCell.new(record["id"], Vector2i(x, y), record["terrainId"], movement["passable"], _integer(movement["cost"]), visibility["blocksLos"], semantics["land"], semantics["water"], semantics["shore"], semantics["path"], semantics["boatRequired"], semantics["flyFloatRequired"], sound_id, _integer(render["tile"]), render["tilesetId"], cell_triggers, random_rects, edges, features, "" if render["overlayAssetId"] == null else render["overlayAssetId"])


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


func _validate_random_region_references(maps: Array[MapDefinition], scenario: ScenarioDefinition, battles: Array[BattleDefinition]) -> bool:
	var battle_ids: Dictionary = {}
	for battle: BattleDefinition in battles:
		battle_ids[battle.classic_id] = true
	for map: MapDefinition in maps:
		for region: RandomEncounterRegion in map.random_regions():
			var doors := region.random_doors()
			var door_percents := region.random_door_percents()
			for index: int in doors.size():
				if door_percents[index] != 0 and (doors[index] < 0 or scenario.program_by_id("xap:%d" % doors[index]) == null):
					return _reject("Random rectangle '%s' references unavailable XAP %d." % [region.id, doors[index]])
			if region.battle_minimum == 0:
				continue
			if region.battle_minimum < 1 or region.battle_maximum < region.battle_minimum:
				return _reject("Random rectangle '%s' has an invalid battle range." % region.id)
			for battle_id: int in range(region.battle_minimum, region.battle_maximum + 1):
				if not battle_ids.has(battle_id):
					return _reject("Random rectangle '%s' references unavailable battle %d." % [region.id, battle_id])
	return true


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


func _validate_rule_references(races: Array[RaceDefinition], castes: Array[CasteDefinition], items: Array[ItemDefinition], spells: Array[SpellDefinition], monsters: Array[MonsterDefinition], battles: Array[BattleDefinition], treasures: Array[TreasureDefinition], shops: Array[ShopDefinition], message_ids: Dictionary) -> bool:
	var race_ids := _definition_ids(races)
	var caste_ids := _definition_ids(castes)
	var item_ids := _definition_ids(items)
	var spell_ids := _definition_ids(spells)
	var monster_ids := _definition_ids(monsters)
	for item: ItemDefinition in items:
		if not item.cursed_item_id.is_empty() and not item_ids.has(item.cursed_item_id):
			return _reject("Item '%s' references unavailable cursed item '%s'." % [item.id, item.cursed_item_id])
		if not item.specific_race_id.is_empty() and not race_ids.has(item.specific_race_id):
			return _reject("Item '%s' references unavailable race '%s'." % [item.id, item.specific_race_id])
		if not item.specific_caste_id.is_empty() and not caste_ids.has(item.specific_caste_id):
			return _reject("Item '%s' references unavailable caste '%s'." % [item.id, item.specific_caste_id])
	for caste: CasteDefinition in castes:
		for item_id: String in caste.start_items():
			if not item_ids.has(item_id):
				return _reject("Caste '%s' references unavailable starting item '%s'." % [caste.id, item_id])
	for monster: MonsterDefinition in monsters:
		for spell_id: String in monster.spell_ids():
			if not spell_ids.has(spell_id):
				return _reject("Monster '%s' references unavailable spell '%s'." % [monster.id, spell_id])
		for item_id: String in monster.item_ids():
			if not item_ids.has(item_id):
				return _reject("Monster '%s' references unavailable item '%s'." % [monster.id, item_id])
		if not monster.weapon_id.is_empty() and not item_ids.has(monster.weapon_id):
			return _reject("Monster '%s' references unavailable weapon '%s'." % [monster.id, monster.weapon_id])
	for battle: BattleDefinition in battles:
		for slot: BattleMonsterSlotDefinition in battle.monster_slots():
			if not monster_ids.has(slot.monster_id):
				return _reject("Battle '%s' references unavailable monster '%s'." % [battle.id, slot.monster_id])
		for message_id: int in [battle.message_before_id, battle.message_after_id]:
			if message_id != 0 and not message_ids.has(absi(message_id)):
				return _reject("Battle '%s' references unavailable message %d." % [battle.id, message_id])
	for treasure: TreasureDefinition in treasures:
		for item_id: String in treasure.item_ids():
			if not item_ids.has(item_id):
				return _reject("Treasure '%s' references unavailable item '%s'." % [treasure.id, item_id])
	for shop: ShopDefinition in shops:
		for item_id: String in shop.item_ids():
			if not item_ids.has(item_id):
				return _reject("Shop '%s' references unavailable item '%s'." % [shop.id, item_id])
	return true


func _validate_scenario_references(scenario: ScenarioDefinition, message_ids: Dictionary, encounters: Array[SimpleEncounterDefinition], complex_encounters: Array[ComplexEncounterDefinition], thief_encounters: Array[ThiefEncounterDefinition]) -> bool:
	var encounter_ids: Dictionary = {}
	for encounter: SimpleEncounterDefinition in encounters:
		encounter_ids[encounter.id] = true
		if not message_ids.has(absi(encounter.prompt_message_id)):
			return _reject("Simple Encounter %d references unavailable prompt message %d." % [encounter.id, encounter.prompt_message_id])
		for response: SimpleEncounterResponse in encounter.responses():
			if scenario.program_by_id(response.result_program_id) == null:
				return _reject("Simple Encounter %d response '%s' references unavailable result program '%s'." % [encounter.id, response.id, response.result_program_id])
	var complex_ids: Dictionary = {}
	var thief_ids: Dictionary = {}
	for thief_encounter: ThiefEncounterDefinition in thief_encounters:
		thief_ids[thief_encounter.id] = true
	for encounter: ComplexEncounterDefinition in complex_encounters:
		complex_ids[encounter.id] = true
		if not message_ids.has(absi(encounter.prompt_message_id)):
			return _reject("Complex Encounter %d references unavailable prompt message %d." % [encounter.id, encounter.prompt_message_id])
		for outcome: int in range(1, 5):
			if scenario.program_by_id(encounter.result_program_id(outcome)) == null:
				return _reject("Complex Encounter %d references unavailable result program %d." % [encounter.id, outcome])
		if encounter.thief and not thief_ids.has(encounter.thief_success):
			return _reject("Complex Encounter %d references unavailable Thief Encounter %d." % [encounter.id, encounter.thief_success])
	for program_id: String in scenario.program_ids():
		var program := scenario.program_by_id(program_id)
		for index: int in range(program.instruction_count()):
			var instruction: Variant = program.instruction_at(index)
			if not instruction is ClassicActionDefinition:
				continue
			match instruction.opcode:
				1:
					if not message_ids.has(absi(instruction.operand_id)):
						return _reject("Scenario program '%s' references unavailable message %d." % [program.id, instruction.operand_id])
				4:
					if not encounter_ids.has(instruction.operand_id):
						return _reject("Scenario program '%s' references unavailable Simple Encounter %d." % [program.id, instruction.operand_id])
				5:
					if not complex_ids.has(instruction.operand_id):
						return _reject("Scenario program '%s' references unavailable Complex Encounter %d." % [program.id, instruction.operand_id])
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
	var ids: Dictionary = {}
	var resources: Dictionary = {}
	for asset: Variant in document["assets"]:
		if not asset is Dictionary or not _exact_fields(asset, ["id", "label", "kind", "mimeType", "resourceType", "resourceId", "bytes", "sha256", "path", "width", "height", "durationMs", "sampleRate", "channels", "tileWidth", "tileHeight", "columns", "rows", "landlook", "baseTile"]):
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
		for optional_integer: String in ["width", "height", "durationMs", "sampleRate", "channels", "tileWidth", "tileHeight", "columns", "rows", "landlook", "baseTile"]:
			if asset[optional_integer] != null and (not _is_integer(asset[optional_integer]) or _integer(asset[optional_integer]) < 0):
				return _reject("Asset %s must be a non-negative integer or null." % optional_integer)
		if asset["kind"] == "tileset":
			for tileset_field: String in ["width", "height", "tileWidth", "tileHeight", "columns", "rows"]:
				if asset[tileset_field] == null or _integer(asset[tileset_field]) < 1:
					return _reject("Tileset asset '%s' has invalid %s metadata." % [asset["id"], tileset_field])
			if not String(asset["mimeType"]).begins_with("image/") or _integer(asset["width"]) != _integer(asset["tileWidth"]) * _integer(asset["columns"]) or _integer(asset["height"]) != _integer(asset["tileHeight"]) * _integer(asset["rows"]):
				return _reject("Tileset asset '%s' dimensions do not match its atlas grid." % asset["id"])
		if not _is_integer(asset["bytes"]) or _integer(asset["bytes"]) < 0 or not asset["path"] is String or not _is_sha256(asset["sha256"]) or not files.has(asset["path"]):
			return _reject("Asset index contains a malformed or untracked payload.")
		if not asset["path"].begins_with("assets/media/") or files[asset["path"]]["sha256"] != asset["sha256"] or _integer(files[asset["path"]]["bytes"]) != _integer(asset["bytes"]):
			return _reject("Asset payload identity does not match the manifest.")
		if asset["resourceType"] != null and asset["resourceId"] != null:
			var resource_key := JSON.stringify([asset["resourceType"], _integer(asset["resourceId"])])
			if resources.has(resource_key):
				return _reject("Asset resource identities must be unique.")
			resources[resource_key] = true
	return true


func _validate_render_references(assets: Dictionary, world: Dictionary) -> bool:
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
		if not map is Dictionary or not map.get("cells") is Array:
			return _reject("World map is malformed during tileset validation.")
		for cell: Variant in map["cells"]:
			if not cell is Dictionary or not cell.get("render") is Dictionary or not cell["render"].get("tilesetId") is String or not cell["render"].has("overlayAssetId"):
				return _reject("Topology render facts are malformed during tileset validation.")
			if not tileset_ids.has(cell["render"]["tilesetId"]):
				return _reject("Topology references missing tileset asset '%s'." % cell["render"]["tilesetId"])
			var overlay_asset_id: Variant = cell["render"]["overlayAssetId"]
			if overlay_asset_id != null and (not overlay_asset_id is String or not image_ids.has(overlay_asset_id)):
				return _reject("Topology references missing image overlay asset '%s'." % overlay_asset_id)
	return true


func _construct_assets(document: Dictionary) -> Array[PackageMediaAsset]:
	var assets: Array[PackageMediaAsset] = []
	for record: Dictionary in document["assets"]:
		assets.append(PackageMediaAsset.new(
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
		))
	return assets


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
	if document.get("kind") != expected_kind or _integer(document.get("schemaVersion")) != 2:
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


func _string_list(value: Variant, label: String, allow_empty: bool = false) -> Variant:
	if not value is Array or value.size() > 4096:
		_reject("%s must be a bounded array." % label)
		return null
	var strings: Array[String] = []
	for item: Variant in value:
		if not item is String or not allow_empty and item.is_empty():
			_reject("%s contains an invalid ID." % label)
			return null
		strings.append(item)
	return strings


func _fixed_string_list(value: Variant, expected_size: int, maximum_length: int, label: String) -> Variant:
	if not value is Array or value.size() != expected_size:
		_reject("%s must contain %d strings." % [label, expected_size])
		return null
	var strings: Array[String] = []
	for item: Variant in value:
		if not item is String or item.length() > maximum_length:
			_reject("%s contains an invalid string." % label)
			return null
		strings.append(item)
	return strings


func _boolean_array(value: Variant, expected_size: int, label: String) -> Variant:
	if not value is Array or value.size() != expected_size:
		_reject("%s must contain %d booleans." % [label, expected_size])
		return null
	var booleans: Array[bool] = []
	for item: Variant in value:
		if not item is bool:
			_reject("%s contains a non-boolean." % label)
			return null
		booleans.append(item)
	return booleans


func _validated_integer_fields(record: Dictionary, fields: Array[String], label: String) -> Variant:
	var result: Dictionary = {}
	for field: String in fields:
		if not record.has(field) or not _is_integer(record[field]):
			_reject("%s field '%s' must be an integer." % [label, field])
			return null
		result[field] = _integer(record[field])
	return result


func _integers_in_range(values: Dictionary, fields: Array[String], minimum: int, maximum: int) -> bool:
	for field: String in fields:
		var value := int(values[field])
		if value < minimum or value > maximum:
			return false
	return true


func _array_values_in_range(values: Array[int], minimum: int, maximum: int) -> bool:
	for value: int in values:
		if value < minimum or value > maximum:
			return false
	return true


func _definition_identity(record: Dictionary, ids: Dictionary, _label: String, requires_name: bool = true) -> bool:
	if not record.get("id") is String or record["id"].is_empty() or requires_name and (not record.get("name") is String or record["name"].is_empty()) or ids.has(record["id"]):
		return false
	ids[record["id"]] = true
	return true


func _definition_ids(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value: Variant in values:
		result[value.id] = true
	return result


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


func _safe_path_component(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	for index: int in value.length():
		var code := value.unicode_at(index)
		var valid := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 45 or code == 95
		if not valid:
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
