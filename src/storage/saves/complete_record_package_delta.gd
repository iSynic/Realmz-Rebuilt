## Exact archive inventories and semantic maps for individually reviewed v7 transitions.
class_name CompleteRecordPackageDelta
extends RefCounted

const RECEIPT_PATH := "res://src/storage/packages/bundled_campaigns/complete-records.json.zlib"
const RECEIPT_SHA256 := "962bc680cd671cbfff29c6074c1172973c746d2bfcb30d32879c366a9d89355d"
const COMPRESSED_SHA256 := "d0f703bb945f29cccbe33ff04209aae05be81a88e8059187f4bf6bd894244395"
const RECEIPT_BYTES := 6954921
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
