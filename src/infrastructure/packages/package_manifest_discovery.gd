class_name PackageManifestDiscovery
extends RefCounted

const REQUIRED_DOCUMENTS: Array[String] = ["assets/index.json", "content.json", "scenario.json", "world.json"]

var last_error: String = ""
var _expected_schema_hash: String
var _supported_capabilities: Array[String]
var _deferred_capabilities: Array[String]
var _archive_reader: PackageArchiveReader


func _init(expected_schema_hash: String, supported_capabilities: Array[String], deferred_capabilities: Array[String], archive_reader: PackageArchiveReader) -> void:
	_expected_schema_hash = expected_schema_hash
	_supported_capabilities = supported_capabilities.duplicate()
	_deferred_capabilities = deferred_capabilities.duplicate()
	_archive_reader = archive_reader


func discover_packages(search_roots: Array[String]) -> Array[PackageDiscoveryResult]:
	var paths: Array[String] = []
	for root: String in search_roots:
		_collect_paths(root, paths, 0)
	paths.sort()
	var discovered: Array[PackageDiscoveryResult] = []
	for path: String in paths:
		discovered.append(inspect(path))
	return discovered


func discover_campaigns(search_roots: Array[String]) -> Array[PackageDiscoveryResult]:
	var selected_by_campaign: Dictionary = {}
	var rejected_by_key: Dictionary = {}
	var visible: Array[PackageDiscoveryResult] = []
	for candidate: PackageDiscoveryResult in discover_packages(search_roots):
		if not candidate.ready:
			var rejection_key := candidate.campaign_id if not candidate.campaign_id.is_empty() else "error:%s" % candidate.error_message
			var selected_rejection := rejected_by_key.get(rejection_key) as PackageDiscoveryResult
			if selected_rejection == null or _revision_is_newer(candidate, selected_rejection):
				rejected_by_key[rejection_key] = candidate
			continue
		var selected := selected_by_campaign.get(candidate.campaign_id) as PackageDiscoveryResult
		if selected == null or _revision_is_newer(candidate, selected):
			selected_by_campaign[candidate.campaign_id] = candidate
	var campaign_ids: Array[String] = []
	campaign_ids.assign(selected_by_campaign.keys())
	campaign_ids.sort()
	for campaign_id: String in campaign_ids:
		visible.append(selected_by_campaign[campaign_id] as PackageDiscoveryResult)
	var rejection_keys: Array[String] = []
	rejection_keys.assign(rejected_by_key.keys())
	rejection_keys.sort()
	for rejection_key: String in rejection_keys:
		var rejected := rejected_by_key[rejection_key] as PackageDiscoveryResult
		if not rejected.campaign_id.is_empty() and selected_by_campaign.has(rejected.campaign_id):
			continue
		visible.append(rejected)
	return visible


func inspect(path: String) -> PackageDiscoveryResult:
	last_error = ""
	var archive := ZIPReader.new()
	var open_error := archive.open(path)
	if open_error != OK:
		return PackageDiscoveryResult.new(path, false, "", "", "", "Could not open package (error %d)." % open_error)
	var entries_value: Variant = _archive_reader.entries(archive)
	var manifest_value: Variant = _archive_reader.read_document(archive, "manifest.json")
	if entries_value == null or manifest_value == null:
		archive.close()
		return PackageDiscoveryResult.new(path, false, "", "", "", _archive_reader.last_error if not _archive_reader.last_error.is_empty() else "Package manifest is unavailable.")
	var entries: Array[String] = []
	entries.assign(entries_value)
	var manifest: Dictionary = manifest_value
	var campaign_id := String(manifest.get("campaignId", "")) if manifest.get("campaignId") is String else ""
	var package_hash := String(manifest.get("packageHash", "")) if manifest.get("packageHash") is String else ""
	var display_name := String(manifest.get("name", "")) if manifest.get("name") is String else ""
	var engine: Variant = manifest.get("engine")
	var rules_version := String(engine.get("rulesVersion", "")) if engine is Dictionary and engine.get("rulesVersion") is String else ""
	if not validate_structure(manifest, entries):
		archive.close()
		return PackageDiscoveryResult.new(path, false, campaign_id, package_hash, rules_version, last_error, display_name)
	archive.close()
	return PackageDiscoveryResult.new(path, true, campaign_id, package_hash, rules_version, "", display_name)


func validate_structure(manifest: Dictionary, archive_entries: Array[String]) -> bool:
	last_error = ""
	var required_fields: Array[String] = ["kind", "format", "formatVersion", "schemaVersion", "schemaHash", "campaignId", "contentId", "engine", "start", "capabilities", "files", "packageHash"]
	for field: String in required_fields:
		if not manifest.has(field):
			return _reject("manifest is missing required field '%s'." % field)
	if manifest["kind"] != "realmz2.manifest" or manifest["format"] != "realmz2" or not _is_integer(manifest["formatVersion"]) or int(manifest["formatVersion"]) != 2 or not _is_integer(manifest["schemaVersion"]) or int(manifest["schemaVersion"]) != 3:
		return _reject("Unsupported Realmz 2.0 package or schema version.")
	if manifest["schemaHash"] != _expected_schema_hash:
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
		var readiness_error := capability_error(capability)
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
		expected_entries.append(file_path)
	expected_entries.sort()
	if archive_entries != expected_entries:
		return _reject("ZIP entries do not exactly match the sorted manifest inventory.")
	var unhashed := manifest.duplicate(true)
	unhashed.erase("packageHash")
	if _archive_reader.sha256(CanonicalJson.encode(unhashed).to_utf8_buffer()) != manifest["packageHash"]:
		return _reject("Package hash does not match the canonical unhashed manifest.")
	return true


func capability_error(capability: Variant) -> String:
	if capability is String and _deferred_capabilities.has(capability):
		return "Package requires sandboxed GDScript Scenario Actions, but no secure external host is available on this platform."
	if not capability is String or not _supported_capabilities.has(capability):
		return "Package requires unknown capability '%s'." % str(capability)
	return ""


func _collect_paths(root: String, paths: Array[String], depth: int) -> void:
	if depth > 4 or not DirAccess.dir_exists_absolute(root):
		return
	for file_name: String in DirAccess.get_files_at(root):
		if file_name.to_lower().ends_with(".realmz2"):
			paths.append(root.path_join(file_name))
	for directory_name: String in DirAccess.get_directories_at(root):
		if not directory_name.begins_with("."):
			_collect_paths(root.path_join(directory_name), paths, depth + 1)


func _revision_is_newer(candidate: PackageDiscoveryResult, selected: PackageDiscoveryResult) -> bool:
	var candidate_modified := FileAccess.get_modified_time(candidate.path)
	var selected_modified := FileAccess.get_modified_time(selected.path)
	if candidate_modified != selected_modified:
		return candidate_modified > selected_modified
	return candidate.path.naturalnocasecmp_to(selected.path) > 0


func _safe_path_component(value: String) -> bool:
	return not value.is_empty() and value != "." and value != ".." and value.validate_filename() == value and not value.contains("/") and not value.contains("\\") and not value.contains(":")


func _is_sha256(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character: String in value:
		if not character in "0123456789abcdef":
			return false
	return true


func _is_integer(value: Variant) -> bool:
	return value is int or value is float and is_equal_approx(value, roundf(value))


func _reject(message: String) -> bool:
	last_error = message
	return false
