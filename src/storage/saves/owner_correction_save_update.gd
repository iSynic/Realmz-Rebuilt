## Admits Trouble's pinned owner corrections (terrain, then XAP 1794) from their exact predecessors.
class_name OwnerCorrectionSaveUpdate
extends RefCounted

const BUNDLE_ROOT := "res://src/storage/packages/bundled_campaigns"
## Newest first: each receipt's previous package is the next receipt's corrected package.
const RECEIPTS: Array[Dictionary] = [
	{"path": BUNDLE_ROOT + "/trouble-program-correction.json", "sha256": "bb6d7f70cd0fd887f37882ba032751266f484f1ff653ce601c3e9a3d3a07f201", "kind": "realmz-rebuilt.trouble-program-correction"},
	{"path": BUNDLE_ROOT + "/trouble-terrain-correction.json", "sha256": "21f3e2631fd7586f6efda3547e4d2fb4a10cee9f5472ab41ae918c8a94fb44c4", "kind": "realmz-rebuilt.trouble-terrain-correction"},
]

var last_error := ""
var _installed_root: String
var _bundle_root: String


func _init(installed_root: String = "user://packages", bundle_root: String = BUNDLE_ROOT) -> void:
	_installed_root = installed_root
	_bundle_root = bundle_root


## The verified receipts, newest first; empty when any receipt or link in the chain differs.
static func corrections() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pin: Dictionary in RECEIPTS:
		var path: String = pin.path
		if FileAccess.get_sha256(path) != pin.sha256:
			return []
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			return []
		var record: Dictionary = parsed
		if record.get("kind") != pin.kind or record.get("formatVersion") != 1:
			return []
		if not result.is_empty() and (result[-1].previousPackage.packageHash != record.packageHash or result[-1].campaignId != record.campaignId):
			return []
		result.append(record)
	return result


## The receipts that lead from `old_hash` to `current_hash`, newest first; empty when no exact chain exists.
func chain(campaign_id: String, old_hash: String, current_hash: String) -> Array[Dictionary]:
	var records := corrections()
	if records.is_empty() or campaign_id != records[0].campaignId or current_hash != records[0].packageHash:
		return []
	for index: int in records.size():
		if records[index].previousPackage.packageHash == old_hash:
			return records.slice(0, index + 1)
	return []


func eligible(campaign_id: String, old_hash: String, current_hash: String) -> bool:
	return not chain(campaign_id, old_hash, current_hash).is_empty()


func updated_slot_id(source_slot: String, backup: bool, current_hash: String) -> String:
	var suffix := "%s-corrected-%s" % ["-backup" if backup else "", current_hash.left(8)]
	return source_slot.left(128 - suffix.length()) + suffix


## The current archive must match the reviewed complete-record inventory, and the
## retained predecessor the inventory derived from it by reversing each declared
## owner correction in turn. Gameplay state carries forward unchanged.
func validate_archives(content: RealmzContent, old_hash: String) -> bool:
	last_error = ""
	var records: Array[Dictionary] = []
	if content != null:
		records = chain(content.campaign_id, old_hash, content.package_hash)
	if records.is_empty():
		return _fail("This campaign revision has no verified owner correction update.")
	var row := CompleteRecordPackageDelta.correction(content.campaign_id, content.package_hash)
	var previous: Dictionary = records[-1].previousPackage
	var old_path := _installed_root.path_join(content.campaign_id).path_join(old_hash + ".realmz2")
	var new_path := _bundle_root.path_join(str(records[0].file))
	var current_files: Dictionary = row.get("files", {})
	if row.is_empty() or row.archiveSha256 != records[0].archiveSha256:
		return _fail("The corrected campaign has no reviewed complete inventory.")
	if FileAccess.get_sha256(old_path) != previous.archiveSha256 or FileAccess.get_sha256(new_path) != records[0].archiveSha256:
		return _fail("The original or corrected campaign archive is missing or differs from the approved owner correction.")
	var installation_error := SaveUpdateInstallation.validate(old_path, content.campaign_id, old_hash, str(previous.archiveSha256))
	if not installation_error.is_empty():
		return _fail(installation_error)
	var old_files: Dictionary = current_files.duplicate(true)
	for record: Dictionary in records:
		var later: Dictionary = old_files.duplicate(true)
		for path: String in record.changedFiles:
			var change: Dictionary = record.changedFiles[path]
			if change.before == change.after:
				return _fail("The owner correction declares an unchanged payload.")
			if (change.after == null) == later.has(path) or (change.after != null and change.after != later[path]):
				return _fail("The owner correction differs from the reviewed complete inventory.")
			if change.before == null:
				old_files.erase(path)
			else:
				old_files[path] = change.before
	if CompleteRecordPackageDelta.validate_files(old_path, old_files).is_empty() or CompleteRecordPackageDelta.validate_files(new_path, current_files).is_empty():
		return _fail("The campaign differs beyond its declared owner corrections.")
	return true


func _fail(message: String) -> bool:
	last_error = message
	return false
