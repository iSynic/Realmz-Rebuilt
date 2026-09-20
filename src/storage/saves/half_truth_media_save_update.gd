## Admits the one verified Half Truth media-only package revision change.
class_name HalfTruthMediaSaveUpdate
extends RefCounted

const CAMPAIGN_ID := "scenario-half-truth"
const OLD_PACKAGE_HASH := "952b9705460e117b7b914e143134c895e04405d686de39e7d58bf2790d52b870"
const NEW_PACKAGE_HASH := "a96fbff24e4204ce49bb60556c27cab6091d0f8f8a26d6b6b0c4c543ecc06562"
const OLD_ARCHIVE_SHA256 := "a197fe8977e583f71f97d4d25cfaab36ec2515a622bbad50894263cc2e752e78"
const NEW_ARCHIVE_SHA256 := "f9884317800f5a897a4a5f007898b6d8e81207572a5bb0994353559ea47b5001"
const APPLICATION_HASH := "82b8718f183bb07135ca0438d833c534754e16361314759b83e5192ccb55cbad"
const DOCUMENTS: Array[String] = ["content.json", "world.json", "scenario.json"]

var old_archive_path: String
var new_archive_path: String
var last_error := ""


func _init(installed_old_path: String = "user://packages/scenario-half-truth/%s.realmz2" % OLD_PACKAGE_HASH, bundled_new_path: String = "res://src/storage/packages/bundled_campaigns/scenario-half-truth.realmz2") -> void:
	old_archive_path = installed_old_path
	new_archive_path = bundled_new_path


func eligible(campaign_id: String, old_hash: String, current_hash: String) -> bool:
	return campaign_id == CAMPAIGN_ID and old_hash == OLD_PACKAGE_HASH and current_hash == NEW_PACKAGE_HASH


func validate_archives(content: RealmzContent) -> bool:
	last_error = ""
	if content == null or not eligible(content.campaign_id, OLD_PACKAGE_HASH, content.package_hash) or ApplicationLibraryIdentity.PACKAGE_HASH != APPLICATION_HASH:
		return _fail("This save update is unavailable for the selected campaign and application library.")
	if FileAccess.get_sha256(old_archive_path) != OLD_ARCHIVE_SHA256 or FileAccess.get_sha256(new_archive_path) != NEW_ARCHIVE_SHA256:
		return _fail("The original or corrected Half Truth archive does not match its pinned bytes.")
	var receipt_path := old_archive_path + ".receipt.json"
	var receipt: Variant = _read_json(receipt_path)
	if not receipt is Dictionary or receipt.get("kind") != "realmz2.install-receipt" or receipt.get("campaignId") != CAMPAIGN_ID or receipt.get("packageHash") != OLD_PACKAGE_HASH or receipt.get("applicationPackageHash") != APPLICATION_HASH or receipt.get("archiveSha256") != OLD_ARCHIVE_SHA256:
		return _fail("The original Half Truth installation receipt does not match its pinned library.")
	var old_archive := ZIPReader.new()
	var new_archive := ZIPReader.new()
	if old_archive.open(old_archive_path) != OK:
		return _fail("The original Half Truth archive cannot be opened.")
	if new_archive.open(new_archive_path) != OK:
		old_archive.close()
		return _fail("The corrected Half Truth archive cannot be opened.")
	var equal := true
	for document: String in DOCUMENTS:
		var old_bytes := old_archive.read_file(document)
		var new_bytes := new_archive.read_file(document)
		if old_bytes.is_empty() or old_bytes != new_bytes:
			equal = false
			break
	old_archive.close()
	new_archive.close()
	return equal or _fail("Half Truth gameplay documents differ; this media-only update is unsafe.")


func updated_slot_id(source_slot_id: String, backup: bool) -> String:
	var suffix := "-backup-art-a96fbff2" if backup else "-art-a96fbff2"
	return source_slot_id.left(128 - suffix.length()) + suffix


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return null
	return parser.data


func _fail(message: String) -> bool:
	last_error = message
	return false
