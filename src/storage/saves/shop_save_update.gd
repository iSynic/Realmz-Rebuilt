## Admits only the three pinned additive shop restorations; never arbitrary rebinding.
class_name ShopSaveUpdate
extends RefCounted

const CATALOG_PATH := "res://src/storage/packages/bundled_campaigns/shop-restoration.json"
const BUNDLE_ROOT := "res://src/storage/packages/bundled_campaigns"

var last_error := ""
var _installed_root: String
var _bundle_root: String
var _catalog: Dictionary = {}


func _init(installed_root: String = "user://packages", bundle_root: String = BUNDLE_ROOT) -> void:
	_installed_root = installed_root
	_bundle_root = bundle_root
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if parsed is Dictionary and parsed.get("kind") == "realmz-rebuilt.shop-restoration" and parsed.get("formatVersion") == 1:
		_catalog = parsed


func transition(campaign_id: String, current_hash: String) -> Dictionary:
	if _catalog.get("applicationPackageHash") != ApplicationLibraryIdentity.PACKAGE_HASH:
		return {}
	for entry: Dictionary in _catalog.get("transitions", []):
		if entry.get("campaignId") == campaign_id and entry.get("newPackageHash") == current_hash:
			return entry.duplicate(true)
	return {}


func eligible(campaign_id: String, old_hash: String, current_hash: String) -> bool:
	var entry := transition(campaign_id, current_hash)
	return not entry.is_empty() and old_hash == entry.get("oldPackageHash")


func updated_slot_id(source_slot: String, backup: bool, current_hash: String) -> String:
	var suffix := "%s-shops-%s" % ["-backup" if backup else "", current_hash.left(8)]
	return source_slot.left(128 - suffix.length()) + suffix


func validate_archives(content: RealmzContent) -> bool:
	last_error = ""
	var entry := transition(content.campaign_id, content.package_hash) if content != null else {}
	if entry.is_empty():
		return _fail("This campaign revision has no verified shop update.")
	var old_path := _installed_root.path_join(content.campaign_id).path_join("%s.realmz2" % entry.oldPackageHash)
	var new_path := _bundle_root.path_join(entry.file)
	if FileAccess.get_sha256(old_path) != entry.oldArchiveSha256 or FileAccess.get_sha256(new_path) != entry.newArchiveSha256:
		return _fail("The original or corrected campaign archive does not match the verified shop update.")
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(old_path + ".receipt.json"))
	if not receipt is Dictionary or receipt.get("kind") != "realmz2.install-receipt" or receipt.get("campaignId") != content.campaign_id or receipt.get("packageHash") != entry.oldPackageHash or receipt.get("archiveSha256") != entry.oldArchiveSha256 or receipt.get("applicationPackageHash") != ApplicationLibraryIdentity.PACKAGE_HASH:
		return _fail("The original campaign installation must be validated with the current application library before updating its save.")
	var old_files := _read_archive(old_path)
	var new_files := _read_archive(new_path)
	if old_files.is_empty() or old_files.keys() != new_files.keys():
		return _fail("The shop update changed the package inventory.")
	for path: String in old_files:
		if path not in ["manifest.json", "content.json"] and old_files[path] != new_files[path]:
			return _fail("The shop update changed an unrelated package document or asset.")
	var old_content: Variant = JSON.parse_string((old_files["content.json"] as PackedByteArray).get_string_from_utf8())
	var new_content: Variant = JSON.parse_string((new_files["content.json"] as PackedByteArray).get_string_from_utf8())
	if not old_content is Dictionary or not new_content is Dictionary:
		return _fail("The shop update content cannot be decoded.")
	var retained: Array = []
	var added: Array = []
	for shop: Dictionary in new_content.get("shops", []):
		if entry.shopIds.has(shop.get("classicId")):
			added.append(shop.get("classicId"))
		else:
			retained.append(shop)
	new_content["shops"] = retained
	if added != entry.shopIds or old_content != new_content:
		return _fail("The shop update is not limited to the approved missing shop records.")
	return true


func _read_archive(path: String) -> Dictionary:
	var archive := ZIPReader.new()
	if archive.open(path) != OK:
		return {}
	var result: Dictionary = {}
	for file: String in archive.get_files():
		result[file] = archive.read_file(file)
	archive.close()
	return result


func _fail(message: String) -> bool:
	last_error = message
	return false
