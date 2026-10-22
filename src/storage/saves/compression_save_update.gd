## Admits only pinned source-compression pairs before the existing detached save-copy route.
class_name CompressionSaveUpdate
extends RefCounted

const BUNDLE_ROOT := "res://src/storage/packages/bundled_campaigns"
var last_error := ""
var _installed_root: String
var _bundle_root: String


func _init(installed_root: String = "user://packages", bundle_root: String = BUNDLE_ROOT) -> void:
	_installed_root = installed_root
	_bundle_root = bundle_root


func eligible(campaign_id: String, old_hash: String, current_hash: String) -> bool:
	var row := CompressionPackageDelta.correction(campaign_id, current_hash)
	return not row.is_empty() and old_hash == row.previousPackage.packageHash


func updated_slot_id(source_slot: String, backup: bool, current_hash: String) -> String:
	var suffix := "%s-compressed-%s" % ["-backup" if backup else "", current_hash.left(8)]
	return source_slot.left(128 - suffix.length()) + suffix


func validate_archives(content: RealmzContent) -> bool:
	last_error = ""
	var row := CompressionPackageDelta.correction(content.campaign_id, content.package_hash) if content != null else {}
	if row.is_empty():
		return _fail("This campaign revision has no verified compression update.")
	var previous: Dictionary = row.previousPackage
	var old_path := _installed_root.path_join(content.campaign_id).path_join(previous.packageHash + ".realmz2")
	var new_path := _bundle_root.path_join(row.file)
	if not FileAccess.file_exists(old_path):
		return _fail("The original campaign package is missing. Restore its retained installation before updating this save.")
	if FileAccess.get_sha256(old_path) != previous.archiveSha256 or FileAccess.get_sha256(new_path) != row.archiveSha256:
		return _fail("The original or compressed campaign archive differs from the approved update.")
	var installation_error := SaveUpdateInstallation.validate(old_path, content.campaign_id, previous.packageHash, previous.archiveSha256)
	if not installation_error.is_empty():
		return _fail(installation_error)
	var before := _read_archive(old_path)
	var after := _read_archive(new_path)
	if before.is_empty() or not CompressionPackageDelta.reverse_manifest(after, content.campaign_id, content.package_hash) or before != after:
		return _fail("The compressed campaign changed content beyond its approved compiler identity.")
	return true


func _read_archive(path: String) -> Dictionary:
	var archive := ZIPReader.new()
	if archive.open(path) != OK:
		return {}
	var files: Dictionary = {}
	for name: String in archive.get_files():
		if files.has(name):
			archive.close()
			return {}
		files[name] = archive.read_file(name)
	archive.close()
	return files


func _fail(message: String) -> bool:
	last_error = message
	return false
