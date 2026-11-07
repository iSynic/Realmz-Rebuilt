## Admits only Trouble's pinned owner terrain correction from its exact predecessor.
class_name TerrainSaveUpdate
extends RefCounted

const BUNDLE_ROOT := "res://src/storage/packages/bundled_campaigns"
const RECEIPT_PATH := BUNDLE_ROOT + "/trouble-terrain-correction.json"
const RECEIPT_SHA256 := "21f3e2631fd7586f6efda3547e4d2fb4a10cee9f5472ab41ae918c8a94fb44c4"

var last_error := ""
var _installed_root: String
var _bundle_root: String


func _init(installed_root: String = "user://packages", bundle_root: String = BUNDLE_ROOT) -> void:
	_installed_root = installed_root
	_bundle_root = bundle_root


static func correction() -> Dictionary:
	if FileAccess.get_sha256(RECEIPT_PATH) != RECEIPT_SHA256:
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECEIPT_PATH))
	if not parsed is Dictionary:
		return {}
	var record: Dictionary = parsed
	return record if record.get("kind") == "realmz-rebuilt.trouble-terrain-correction" and record.get("formatVersion") == 1 else {}


func eligible(campaign_id: String, old_hash: String, current_hash: String) -> bool:
	var record := correction()
	return not record.is_empty() and campaign_id == record.campaignId and old_hash == record.previousPackage.packageHash and current_hash == record.packageHash


func previous_hash() -> String:
	var previous: Dictionary = correction().get("previousPackage", {})
	return str(previous.get("packageHash", ""))


func updated_slot_id(source_slot: String, backup: bool, current_hash: String) -> String:
	var suffix := "%s-terrain-%s" % ["-backup" if backup else "", current_hash.left(8)]
	return source_slot.left(128 - suffix.length()) + suffix


## Both complete archive inventories must match: the current one from the
## reviewed complete-record receipt and the predecessor derived from it through
## the declared terrain delta. Gameplay state carries forward unchanged.
func validate_archives(content: RealmzContent) -> bool:
	last_error = ""
	if content == null or not eligible(content.campaign_id, previous_hash(), content.package_hash):
		return _fail("This campaign revision has no verified terrain update.")
	var record := correction()
	var row := CompleteRecordPackageDelta.correction(content.campaign_id, content.package_hash)
	var old_path := _installed_root.path_join(content.campaign_id).path_join(previous_hash() + ".realmz2")
	var file: String = record.file
	var previous: Dictionary = record.previousPackage
	var old_archive: String = previous.archiveSha256
	var current_files: Dictionary = row.get("files", {})
	var new_path := _bundle_root.path_join(file)
	if row.is_empty() or row.archiveSha256 != record.archiveSha256:
		return _fail("The corrected campaign has no reviewed complete inventory.")
	if FileAccess.get_sha256(old_path) != old_archive or FileAccess.get_sha256(new_path) != record.archiveSha256:
		return _fail("The original or corrected campaign archive is missing or differs from the approved terrain update.")
	var installation_error := SaveUpdateInstallation.validate(old_path, content.campaign_id, previous_hash(), old_archive)
	if not installation_error.is_empty():
		return _fail(installation_error)
	var old_files: Dictionary = current_files.duplicate(true)
	for path: String in record.changedFiles:
		var change: Dictionary = record.changedFiles[path]
		if change.before == change.after:
			return _fail("The terrain update declares an unchanged payload.")
		if change.before == null:
			old_files.erase(path)
		else:
			old_files[path] = change.before
		if (change.after == null) == current_files.has(path) or (change.after != null and change.after != current_files[path]):
			return _fail("The terrain update differs from the reviewed complete inventory.")
	if CompleteRecordPackageDelta.validate_files(old_path, old_files).is_empty() or CompleteRecordPackageDelta.validate_files(new_path, current_files).is_empty():
		return _fail("The campaign differs beyond its declared terrain delta.")
	return true


func _fail(message: String) -> bool:
	last_error = message
	return false
