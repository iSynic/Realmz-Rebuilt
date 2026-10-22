## Admits only Trouble's pinned additive XAP 330 restoration.
class_name PaymentSaveUpdate
extends RefCounted

const BUNDLE_ROOT := "res://src/storage/packages/bundled_campaigns"
const RECEIPT_PATH := BUNDLE_ROOT + "/trouble-payment-restoration.json"
const RECEIPT_SHA256 := "f0bc470d9f0c6f220b911b9ab74c451fb115bd221d6d851efbe1854d3ef26067"

var last_error := ""
var _installed_root: String
var _bundle_root: String


func _init(installed_root: String = "user://packages", bundle_root: String = BUNDLE_ROOT) -> void:
	_installed_root = installed_root
	_bundle_root = bundle_root


static func restoration() -> Dictionary:
	if FileAccess.get_sha256(RECEIPT_PATH) != RECEIPT_SHA256:
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECEIPT_PATH))
	return parsed if parsed is Dictionary and parsed.get("kind") == "realmz-rebuilt.trouble-payment-restoration" else {}


static func remove_addition(scenario: Dictionary) -> bool:
	var record := restoration()
	if record.is_empty():
		return false
	for addition: Dictionary in record.addedPrograms:
		var matches: Array = scenario.get("programs", []).filter(func(program: Dictionary) -> bool: return program.get("id") == addition.id)
		if matches.size() != 1 or matches[0] != addition:
			return false
		scenario.programs.erase(matches[0])
	return true


func eligible(campaign_id: String, old_hash: String, current_hash: String) -> bool:
	var record := restoration()
	var program := ProgramPackageDelta.correction(campaign_id, current_hash)
	var payment_hash: String = program.previousPackage.packageHash if not program.is_empty() else current_hash
	return not record.is_empty() and campaign_id == record.campaignId and old_hash == record.previousPackage.packageHash and payment_hash == record.packageHash


func previous_hash() -> String:
	return String(restoration().get("previousPackage", {}).get("packageHash", ""))


func updated_slot_id(source_slot: String, backup: bool, current_hash: String) -> String:
	var suffix := "%s-payment-%s" % ["-backup" if backup else "", current_hash.left(8)]
	return source_slot.left(128 - suffix.length()) + suffix


func validate_archives(content: RealmzContent) -> bool:
	last_error = ""
	if content == null or not eligible(content.campaign_id, previous_hash(), content.package_hash):
		return _fail("This campaign revision has no verified payment update.")
	var record := restoration()
	var old_path := _installed_root.path_join(content.campaign_id).path_join(previous_hash() + ".realmz2")
	var new_path := _bundle_root.path_join(record.file)
	var program := ProgramPackageDelta.correction(content.campaign_id, content.package_hash)
	var new_hash: String = program.archiveSha256 if not program.is_empty() else record.archiveSha256
	new_hash = CompressionPackageDelta.archive_hash(content.campaign_id, content.package_hash, new_hash)
	if FileAccess.get_sha256(old_path) != record.previousPackage.archiveSha256 or FileAccess.get_sha256(new_path) != new_hash:
		return _fail("The original or corrected campaign archive does not match the approved payment update.")
	var installation_error := SaveUpdateInstallation.validate(old_path, content.campaign_id, previous_hash(), record.previousPackage.archiveSha256)
	if not installation_error.is_empty():
		return _fail(installation_error)
	var before := _read_archive(old_path)
	var after := _read_archive(new_path)
	if not CompressionPackageDelta.reverse_manifest(after, content.campaign_id, content.package_hash):
		return _fail("The source-compression revision differs from its approved delta.")
	if not program.is_empty() and not ProgramPackageDelta.reverse_payloads(after, program):
		return _fail("The subsequent native source retention differs from its approved delta.")
	if before.is_empty() or before.keys() != after.keys():
		return _fail("The payment update changed the package inventory.")
	var documents: Dictionary = {}
	for name: String in ["content.json", "world.json", "scenario.json"]:
		documents[name] = JSON.parse_string((after[name] as PackedByteArray).get_string_from_utf8())
	if not program.is_empty() and not ProgramPackageDelta.reverse_documents(documents, program):
		return _fail("The subsequent program restoration differs from its approved delta.")
	for path: String in before:
		if path in ["content.json", "world.json"]:
			if JSON.parse_string((before[path] as PackedByteArray).get_string_from_utf8()) != documents[path]:
				return _fail("The payment update changed an unrelated document.")
		elif path not in ["manifest.json", "scenario.json"] and before[path] != after[path]:
			return _fail("The payment update changed an unrelated payload.")
	var old_scenario: Dictionary = JSON.parse_string((before["scenario.json"] as PackedByteArray).get_string_from_utf8())
	var new_scenario: Dictionary = documents["scenario.json"]
	return (remove_addition(new_scenario) and old_scenario == new_scenario) or _fail("The payment update differs beyond the approved native program.")


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
