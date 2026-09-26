## Persists preferred immutable revisions for imported scenarios.

class_name ImportedScenarioLibrary
extends RefCounted

const INDEX_VERSION: int = 2

var last_error: String = ""
var _index_path: String
var _index: Dictionary = {"formatVersion": INDEX_VERSION, "campaigns": {}}
var _index_load_failed: bool = false
var _index_load_error: String = ""
var _available_revision_hashes: Dictionary = {}


func _init(index_path: String = "user://imported-scenarios.json") -> void:
	_index_path = index_path
	_load_index()


func select_revisions(records: Array[PackageDiscoveryResult]) -> Array[PackageDiscoveryResult]:
	last_error = _index_load_error if _index_load_failed else ""
	var previous_index := _index.duplicate(true)
	_available_revision_hashes.clear()
	var ready_by_campaign: Dictionary = {}
	var ordered: Array[PackageDiscoveryResult] = []
	for record: PackageDiscoveryResult in records:
		if not _valid_record(record):
			continue
		ordered.append(record)
	ordered.sort_custom(_record_path_precedes)
	for record: PackageDiscoveryResult in ordered:
		if bool(_campaign(record.campaign_id).get("removed", false)):
			continue
		_register_discovered_revision(record)
		var candidates: Array = ready_by_campaign.get(record.campaign_id, [])
		candidates.append(record)
		ready_by_campaign[record.campaign_id] = candidates

	var selected: Array[PackageDiscoveryResult] = []
	var campaign_ids: Array[String] = []
	campaign_ids.assign(ready_by_campaign.keys())
	campaign_ids.sort()
	for campaign_id: String in campaign_ids:
		var candidates: Array = ready_by_campaign[campaign_id]
		var campaign := _campaign(campaign_id)
		var preferred_hash := String(campaign.get("preferred_package_hash", ""))
		var chosen: PackageDiscoveryResult
		for candidate_value: Variant in candidates:
			var candidate := candidate_value as PackageDiscoveryResult
			if candidate.package_hash == preferred_hash:
				chosen = candidate
				break
		if chosen == null:
			chosen = candidates[0] as PackageDiscoveryResult
			campaign["preferred_package_hash"] = chosen.package_hash
			_set_campaign(campaign_id, campaign)
		selected.append(chosen)
	if not _index_load_failed and _index != previous_index:
		if not _write_index():
			_index = previous_index
	return selected


func _register_discovered_revision(record: PackageDiscoveryResult) -> void:
	_mark_available(record)
	var revisions := _campaign_revisions(record.campaign_id)
	var known := _find_revision(revisions, record.package_hash)
	if known < 0:
		revisions.append({
			"package_hash": record.package_hash,
			"path": record.path,
			"imported_at": "",
			"origin": "imported",
			"diagnostics": [],
			"version_label": "",
		})
	else:
		var revision: Dictionary = revisions[known]
		revision["path"] = record.path
		revisions[known] = revision
	var campaign := _campaign(record.campaign_id)
	campaign["revisions"] = revisions
	campaign["removed"] = false
	_set_campaign(record.campaign_id, campaign)


func revisions(campaign_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if bool(_campaign(campaign_id).get("removed", false)):
		return result
	var available_hashes: Dictionary = _available_revision_hashes.get(campaign_id, {})
	for value: Variant in _campaign_revisions(campaign_id):
		if value is Dictionary and available_hashes.has(String(value.get("package_hash", ""))):
			result.append((value as Dictionary).duplicate(true))
	return result


func record_install(record: PackageDiscoveryResult, diagnostics: Array[String] = [], version_label: String = "") -> bool:
	last_error = ""
	if _index_load_failed:
		last_error = _index_load_error
		return false
	if not _valid_record(record):
		last_error = "Only ready imported package revisions can be recorded."
		return false
	var previous_index := _index.duplicate(true)
	var campaign := _campaign(record.campaign_id)
	campaign["removed"] = false
	var revisions_value := _campaign_revisions(record.campaign_id)
	var existing_index := _find_revision(revisions_value, record.package_hash)
	if existing_index < 0:
		revisions_value.append({
			"package_hash": record.package_hash,
			"path": record.path,
			"imported_at": Time.get_datetime_string_from_system(true, true),
			"origin": "imported",
			"diagnostics": diagnostics.duplicate(),
			"version_label": version_label,
		})
	else:
		var existing: Dictionary = revisions_value[existing_index]
		existing["path"] = record.path
		existing["origin"] = "imported"
		if not diagnostics.is_empty():
			existing["diagnostics"] = diagnostics.duplicate()
		if not version_label.is_empty():
			existing["version_label"] = version_label
		revisions_value[existing_index] = existing
	campaign["revisions"] = revisions_value
	campaign["preferred_package_hash"] = record.package_hash
	_set_campaign(record.campaign_id, campaign)
	if _index != previous_index and not _write_index():
		_index = previous_index
		return false
	_mark_available(record)
	return true


func prefer(campaign_id: String, package_hash: String) -> bool:
	last_error = ""
	if _index_load_failed:
		last_error = _index_load_error
		return false
	if bool(_campaign(campaign_id).get("removed", false)):
		last_error = "That imported scenario has been removed from the library."
		return false
	var found := false
	var available_hashes: Dictionary = _available_revision_hashes.get(campaign_id, {})
	found = available_hashes.has(package_hash)
	if not found:
		last_error = "That scenario revision is not in the imported revision library."
		return false
	var previous_index := _index.duplicate(true)
	var campaign := _campaign(campaign_id)
	if String(campaign.get("preferred_package_hash", "")) == package_hash:
		return true
	campaign["preferred_package_hash"] = package_hash
	_set_campaign(campaign_id, campaign)
	if not _write_index():
		_index = previous_index
		return false
	return true


func contains_revision(campaign_id: String, package_hash: String) -> bool:
	for value: Variant in _campaign_revisions(campaign_id):
		if value is Dictionary and value.get("origin") == "imported" and String(value.get("package_hash", "")) == package_hash:
			return true
	return false


func remove_campaign(campaign_id: String) -> bool:
	last_error = ""
	if _index_load_failed:
		last_error = _index_load_error
		return false
	var campaigns: Dictionary = _index["campaigns"]
	if not campaigns.has(campaign_id):
		last_error = "That imported scenario is not in the library."
		return false
	var previous_index := _index.duplicate(true)
	var campaign := _campaign(campaign_id)
	if bool(campaign.get("removed", false)):
		return true
	campaign["removed"] = true
	_set_campaign(campaign_id, campaign)
	if not _write_index():
		_index = previous_index
		return false
	return true


func _read_index(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		file.close()
		return null
	var parsed: Variant = parser.data
	file.close()
	return parsed


func _load_index() -> void:
	last_error = ""
	var absolute_path := ProjectSettings.globalize_path(_index_path)
	if not FileAccess.file_exists(absolute_path):
		var backup_path := absolute_path + ".previous"
		if not FileAccess.file_exists(backup_path):
			return
		var backup_value: Variant = _read_index(backup_path)
		if not _is_valid_index(backup_value):
			_fail_index_load("Imported scenario index is missing and its previous copy is invalid.")
			return
		var recovery_error := DirAccess.rename_absolute(backup_path, absolute_path)
		if recovery_error != OK:
			_index = _upgrade_index(backup_value)
			_fail_index_load("Could not restore the previous imported scenario index (error %d)." % recovery_error)
			return
		var restored_value: Variant = _read_index(absolute_path)
		if not _is_valid_index(restored_value) or not _indexes_match(restored_value, backup_value):
			DirAccess.rename_absolute(absolute_path, backup_path)
			_fail_index_load("Restored imported scenario index failed validation.")
			return
		_index = _upgrade_index(restored_value)
		return
	var parsed: Variant = _read_index(absolute_path)
	if not _is_valid_index(parsed):
		_fail_index_load("Could not read imported scenario revision index.")
		return
	_index = _upgrade_index(parsed)


func _upgrade_index(value: Dictionary) -> Dictionary:
	var upgraded := value.duplicate(true)
	upgraded["formatVersion"] = INDEX_VERSION
	var campaigns: Dictionary = upgraded["campaigns"]
	for campaign_id: Variant in campaigns:
		var campaign: Dictionary = campaigns[campaign_id]
		if not campaign.has("removed"):
			campaign["removed"] = false
		campaigns[campaign_id] = campaign
	upgraded["campaigns"] = campaigns
	return upgraded


func _write_index() -> bool:
	var absolute_path := ProjectSettings.globalize_path(_index_path)
	var directory := absolute_path.get_base_dir()
	if DirAccess.dir_exists_absolute(absolute_path):
		last_error = "Imported scenario revision index path is a directory."
		return false
	var make_error := DirAccess.make_dir_recursive_absolute(directory)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		last_error = "Could not create imported scenario index directory (error %d)." % make_error
		return false
	var temp_path := absolute_path + ".tmp"
	var temp := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp == null:
		last_error = "Could not write imported scenario revision index."
		return false
	temp.store_string(JSON.stringify(_index, "\t") + "\n")
	temp.flush()
	temp.close()
	var check := FileAccess.open(temp_path, FileAccess.READ)
	if check == null:
		last_error = "Could not read back imported scenario revision index."
		return false
	var parsed: Variant = JSON.parse_string(check.get_as_text())
	check.close()
	if not _is_valid_index(parsed):
		last_error = "Imported scenario revision index failed readback validation."
		return false
	if not _indexes_match(parsed, _index):
		last_error = "Imported scenario revision index readback differs from the staged data."
		return false
	var backup_path := absolute_path + ".previous"
	var had_old := FileAccess.file_exists(absolute_path)
	if had_old:
		if FileAccess.file_exists(backup_path):
			var remove_backup_error := DirAccess.remove_absolute(backup_path)
			if remove_backup_error != OK:
				last_error = "Could not prepare imported scenario index replacement (error %d)." % remove_backup_error
				return false
		var backup_error := DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			last_error = "Could not preserve the previous imported scenario index (error %d)." % backup_error
			return false
	var rename_error := DirAccess.rename_absolute(temp_path, absolute_path)
	if rename_error != OK:
		if had_old:
			DirAccess.rename_absolute(backup_path, absolute_path)
		last_error = "Could not replace imported scenario revision index (error %d)." % rename_error
		return false
	if had_old:
		DirAccess.remove_absolute(backup_path)
	return true


func _valid_record(record: PackageDiscoveryResult) -> bool:
	return record != null and record.ready and not record.campaign_id.is_empty() and not record.package_hash.is_empty() and not record.path.is_empty() and FileAccess.file_exists(record.path)


func _fail_index_load(message: String) -> void:
	_index_load_failed = true
	_index_load_error = message
	last_error = message


func _mark_available(record: PackageDiscoveryResult) -> void:
	var available_hashes: Dictionary = _available_revision_hashes.get(record.campaign_id, {})
	available_hashes[record.package_hash] = true
	_available_revision_hashes[record.campaign_id] = available_hashes


func _is_valid_index(value: Variant) -> bool:
	if not value is Dictionary or (value.get("formatVersion") != 1 and value.get("formatVersion") != INDEX_VERSION) or not value.get("campaigns") is Dictionary:
		return false
	var index_data: Dictionary = value
	if index_data.size() != 2:
		return false
	var campaigns: Dictionary = index_data["campaigns"]
	for campaign_id: Variant in campaigns:
		var campaign_value: Variant = campaigns[campaign_id]
		if not campaign_id is String or String(campaign_id).is_empty() or not campaign_value is Dictionary:
			return false
		var campaign: Dictionary = campaign_value
		var version: int = int(index_data.get("formatVersion", 0))
		var expected_campaign_size := 2 if version == 1 else 3
		if campaign.size() != expected_campaign_size or not campaign.get("preferred_package_hash") is String or not campaign.get("revisions") is Array or (version == INDEX_VERSION and not campaign.get("removed") is bool):
			return false
		var seen_hashes: Dictionary = {}
		for revision_value: Variant in campaign["revisions"]:
			if not revision_value is Dictionary:
				return false
			var revision: Dictionary = revision_value
			if revision.size() != 6 or not revision.get("package_hash") is String or not revision.get("path") is String or not revision.get("imported_at") is String or revision.get("origin") != "imported" or not revision.get("diagnostics") is Array or not revision.get("version_label") is String or String(revision.get("path", "")).is_empty():
				return false
			for diagnostic: Variant in revision["diagnostics"]:
				if not diagnostic is String:
					return false
			var package_hash := String(revision["package_hash"])
			if not _is_sha256(package_hash) or seen_hashes.has(package_hash):
				return false
			seen_hashes[package_hash] = true
		var preferred_hash := String(campaign["preferred_package_hash"])
		if not preferred_hash.is_empty() and not seen_hashes.has(preferred_hash):
			return false
	return true


func _indexes_match(left_value: Variant, right_value: Variant) -> bool:
	if not left_value is Dictionary or not right_value is Dictionary:
		return false
	var left: Dictionary = left_value
	var right: Dictionary = right_value
	if left.get("formatVersion") != right.get("formatVersion") or left.get("campaigns").size() != right.get("campaigns").size():
		return false
	var left_campaigns: Dictionary = left["campaigns"]
	var right_campaigns: Dictionary = right["campaigns"]
	for campaign_id: Variant in left_campaigns:
		if not right_campaigns.has(campaign_id):
			return false
		var left_campaign: Dictionary = left_campaigns[campaign_id]
		var right_campaign: Dictionary = right_campaigns[campaign_id]
		if left_campaign.get("preferred_package_hash") != right_campaign.get("preferred_package_hash") or bool(left_campaign.get("removed", false)) != bool(right_campaign.get("removed", false)):
			return false
		var left_revisions: Array = left_campaign.get("revisions", [])
		var right_revisions: Array = right_campaign.get("revisions", [])
		if left_revisions.size() != right_revisions.size():
			return false
		for revision_index: int in left_revisions.size():
			var left_revision: Dictionary = left_revisions[revision_index]
			var right_revision: Dictionary = right_revisions[revision_index]
			for field: String in ["package_hash", "path", "imported_at", "origin", "version_label"]:
				if left_revision.get(field) != right_revision.get(field):
					return false
			var left_diagnostics: Array = left_revision.get("diagnostics", [])
			var right_diagnostics: Array = right_revision.get("diagnostics", [])
			if left_diagnostics.size() != right_diagnostics.size():
				return false
			for diagnostic_index: int in left_diagnostics.size():
				if left_diagnostics[diagnostic_index] != right_diagnostics[diagnostic_index]:
					return false
	return true


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if not character in "0123456789abcdef":
			return false
	return true


func _campaign(campaign_id: String) -> Dictionary:
	var campaigns: Dictionary = _index["campaigns"]
	var value: Variant = campaigns.get(campaign_id, {})
	return value.duplicate(true) if value is Dictionary else {}


func _campaign_revisions(campaign_id: String) -> Array:
	var value: Variant = _campaign(campaign_id).get("revisions", [])
	return value.duplicate(true) if value is Array else []


func _set_campaign(campaign_id: String, campaign: Dictionary) -> void:
	var campaigns: Dictionary = _index["campaigns"]
	campaigns[campaign_id] = campaign
	_index["campaigns"] = campaigns


func _find_revision(revision_list: Array, package_hash: String) -> int:
	for index: int in revision_list.size():
		var revision: Variant = revision_list[index]
		if revision is Dictionary and String(revision.get("package_hash", "")) == package_hash:
			return index
	return -1


func _record_path_precedes(left: PackageDiscoveryResult, right: PackageDiscoveryResult) -> bool:
	var comparison := left.path.naturalnocasecmp_to(right.path)
	return comparison < 0 if comparison != 0 else left.path < right.path
