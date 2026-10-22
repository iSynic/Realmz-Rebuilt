## Admits exact native-program correction pairs before detached save-copy restoration.
class_name ProgramSaveUpdate
extends RefCounted

const BUNDLE_ROOT := "res://src/storage/packages/bundled_campaigns"
var last_error := ""
var _installed_root: String
var _bundle_root: String


func _init(installed_root: String = "user://packages", bundle_root: String = BUNDLE_ROOT) -> void:
	_installed_root = installed_root
	_bundle_root = bundle_root


func eligible(campaign_id: String, old_hash: String, current_hash: String) -> bool:
	var record := ProgramPackageDelta.correction(campaign_id, current_hash)
	return not record.is_empty() and record.previousPackage.packageHash == old_hash


func updated_slot_id(source_slot: String, backup: bool, current_hash: String) -> String:
	var suffix := "%s-programs-%s" % ["-backup" if backup else "", current_hash.left(8)]
	return source_slot.left(128 - suffix.length()) + suffix


func validate_archives(content: RealmzContent) -> bool:
	last_error = ""
	var record := ProgramPackageDelta.correction(content.campaign_id, content.package_hash) if content != null else {}
	if record.is_empty():
		return _fail("This campaign revision has no verified program update.")
	var previous: Dictionary = record.previousPackage
	var old_path := _installed_root.path_join(content.campaign_id).path_join(previous.packageHash + ".realmz2")
	var new_path := _bundle_root.path_join(record.file)
	if not FileAccess.file_exists(old_path):
		return _fail("The original campaign package is missing. Restore its retained installation before updating this save.")
	if FileAccess.get_sha256(old_path) != previous.archiveSha256 or FileAccess.get_sha256(new_path) != CompressionPackageDelta.archive_hash(content.campaign_id, content.package_hash, record.archiveSha256):
		return _fail("The original or corrected campaign archive differs from the approved program update.")
	var installation_error := SaveUpdateInstallation.validate(old_path, content.campaign_id, previous.packageHash, previous.archiveSha256)
	if not installation_error.is_empty():
		return _fail(installation_error)
	var before := _read_archive(old_path)
	var after := _read_archive(new_path)
	if not CompressionPackageDelta.reverse_manifest(after, content.campaign_id, content.package_hash):
		return _fail("The source-compression revision differs from its approved delta.")
	if not ProgramPackageDelta.reverse_payloads(after, record):
		return _fail("The retained native source payloads differ from the approved program update.")
	if before.is_empty() or before.keys() != after.keys():
		return _fail("The program update changed the package inventory.")
	var old_documents: Dictionary = {}
	var new_documents: Dictionary = {}
	for name: String in before:
		if name in record.recipe.previousDocuments:
			old_documents[name] = JSON.parse_string((before[name] as PackedByteArray).get_string_from_utf8())
			new_documents[name] = JSON.parse_string((after[name] as PackedByteArray).get_string_from_utf8())
		elif name != "manifest.json" and before[name] != after[name]:
			return _fail("The program update changed an unrelated payload.")
	return (ProgramPackageDelta.reverse_documents(new_documents, record) and old_documents == new_documents) or _fail("The campaign differs beyond the approved program correction.")


func _read_archive(path: String) -> Dictionary:
	var archive := ZIPReader.new()
	if archive.open(path) != OK:
		return {}
	var files: Dictionary = {}
	for name: String in archive.get_files():
		files[name] = archive.read_file(name)
	archive.close()
	return files


func _fail(message: String) -> bool:
	last_error = message
	return false
