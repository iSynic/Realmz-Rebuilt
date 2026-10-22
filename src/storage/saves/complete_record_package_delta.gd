## Exact archive inventories and semantic maps for individually reviewed v7 transitions.
class_name CompleteRecordPackageDelta
extends RefCounted

const RECEIPT_PATH := "res://src/storage/packages/bundled_campaigns/complete-records.json.zlib"
const RECEIPT_SHA256 := "e56e8a94ed6cb29d0f6e8f7d2f893b073fd769aed2736b26bbe6df22a0faeae2"
const COMPRESSED_SHA256 := "b1d31ee0783df27ed6c1f02936734443a3cc3328a075ef7d3e385e7fedff06bd"
const RECEIPT_BYTES := 6953757
static var _receipt: Dictionary = {}


static func correction(campaign_id: String, package_hash: String) -> Dictionary:
	if _receipt.is_empty():
		if FileAccess.get_sha256(RECEIPT_PATH) != COMPRESSED_SHA256: return {}
		var bytes := FileAccess.get_file_as_bytes(RECEIPT_PATH).decompress(RECEIPT_BYTES, FileAccess.COMPRESSION_DEFLATE)
		if bytes.size() != RECEIPT_BYTES or PackageArchiveReader.new().sha256(bytes) != RECEIPT_SHA256: return {}
		var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if not value is Dictionary or value.get("kind") != "realmz-rebuilt.complete-records" or value.get("formatVersion") != 1 or value.get("applicationPackageHash") != ApplicationLibraryIdentity.PACKAGE_HASH or value.get("campaigns", []).size() != 13: return {}
		_receipt = value
	for row: Dictionary in _receipt.campaigns:
		if row.get("campaignId") == campaign_id and row.get("packageHash") == package_hash: return row.duplicate(true)
	return {}


static func previous(row: Dictionary, old_hash: String) -> Dictionary:
	for value: Dictionary in row.get("previousRevisions", []):
		if value.get("packageHash") == old_hash: return value.duplicate(true)
	return {}


static func validate_files(path: String, expected: Dictionary) -> Dictionary:
	var archive := ZIPReader.new()
	if archive.open(path) != OK: return {}
	var result: Dictionary = {}
	var reader := PackageArchiveReader.new()
	for name: String in archive.get_files():
		if result.has(name) or not expected.has(name):
			archive.close()
			return {}
		var bytes := archive.read_file(name)
		if bytes.size() != expected[name].bytes or reader.sha256(bytes) != expected[name].sha256:
			archive.close()
			return {}
		result[name] = bytes
	archive.close()
	return result if result.size() == expected.size() else {}
