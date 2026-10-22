## Offers separately named saves only for pinned, fully inventoried v7 package pairs.
class_name CompleteRecordSaveUpdate
extends RefCounted

const BUNDLE_ROOT := "res://src/storage/packages/bundled_campaigns"
var last_error := ""
var _installed_root: String
var _bundle_root: String


func _init(installed_root: String = "user://packages", bundle_root: String = BUNDLE_ROOT) -> void:
	_installed_root = installed_root
	_bundle_root = bundle_root


func eligible(campaign_id: String, old_hash: String, current_hash: String) -> bool:
	return not CompleteRecordPackageDelta.previous(CompleteRecordPackageDelta.correction(campaign_id, current_hash), old_hash).is_empty()


func validate_archives(content: RealmzContent, old_hash: String) -> Dictionary:
	last_error = ""
	var row := CompleteRecordPackageDelta.correction(content.campaign_id, content.package_hash)
	var pair := CompleteRecordPackageDelta.previous(row, old_hash)
	if pair.is_empty(): return _fail("This campaign revision has no verified complete-record update.")
	var old_path := _installed_root.path_join(content.campaign_id).path_join(old_hash + ".realmz2")
	var new_path := _bundle_root.path_join(row.file)
	if FileAccess.get_sha256(old_path) != pair.archiveSha256 or FileAccess.get_sha256(new_path) != row.archiveSha256:
		return _fail("The original or current campaign archive is missing or differs from the reviewed update.")
	var installation_error := SaveUpdateInstallation.validate(old_path, content.campaign_id, old_hash, pair.archiveSha256)
	if not installation_error.is_empty(): return _fail(installation_error)
	var before := CompleteRecordPackageDelta.validate_files(old_path, pair.files)
	var after := CompleteRecordPackageDelta.validate_files(new_path, row.files)
	if before.is_empty() or after.is_empty(): return _fail("The complete package delta could not be verified.")
	var changed: Array[String] = []
	var paths: Dictionary = before.duplicate()
	paths.merge(after)
	for path: String in paths:
		if before.get(path) != after.get(path): changed.append(path)
	changed.sort()
	if changed != pair.changedPaths: return _fail("The campaign differs beyond its declared complete-record delta.")
	return pair


func updated_slot_id(source_slot: String, backup: bool, package_hash: String) -> String:
	var suffix := "%s-records-%s" % ["-backup" if backup else "", package_hash.left(8)]
	return source_slot.left(128 - suffix.length()) + suffix


func _fail(message: String) -> Dictionary:
	last_error = message
	return {}
