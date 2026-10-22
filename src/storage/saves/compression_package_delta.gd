## Verifies the thirteen exact encoding-only successors without relaxing package identity.
class_name CompressionPackageDelta
extends RefCounted

const RECEIPT_PATH := "res://src/storage/packages/bundled_campaigns/source-compression.json"
const RECEIPT_SHA256 := "164fbc5944fc1e7b1b0b14930df78b34a968f7745e3920ee9b48b1edee2b48aa"
static var _receipt: Dictionary = {}


static func correction(campaign_id: String, package_hash: String) -> Dictionary:
	if _receipt.is_empty():
		if FileAccess.get_sha256(RECEIPT_PATH) != RECEIPT_SHA256:
			return {}
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECEIPT_PATH))
		if not parsed is Dictionary or parsed.get("kind") != "realmz-rebuilt.source-compression" or parsed.get("formatVersion") != 1 or parsed.get("applicationPackageHash") != ApplicationLibraryIdentity.PACKAGE_HASH or parsed.get("campaigns", []).size() != 13:
			return {}
		_receipt = parsed
	for row: Dictionary in _receipt.campaigns:
		if row.campaignId == campaign_id and row.packageHash == package_hash:
			return row.duplicate(true)
	return {}


static func previous_hash(campaign_id: String, package_hash: String) -> String:
	var row := correction(campaign_id, package_hash)
	return row.previousPackage.packageHash if not row.is_empty() else package_hash


static func archive_hash(campaign_id: String, package_hash: String, legacy_hash: String) -> String:
	var row := correction(campaign_id, package_hash)
	return row.archiveSha256 if not row.is_empty() else legacy_hash


static func reverse_manifest(files: Dictionary, campaign_id: String, package_hash: String) -> bool:
	var row := correction(campaign_id, package_hash)
	if row.is_empty():
		return true
	if not files.has("manifest.json"):
		return false
	var reader := PackageArchiveReader.new()
	var bytes: PackedByteArray = files["manifest.json"]
	if reader.sha256(bytes) != row.manifestSha256:
		return false
	var manifest: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	if manifest.get("campaignId") != campaign_id or manifest.get("packageHash") != package_hash or manifest.get("contentId") != row.contentId or files.size() != manifest.files.size() + 1:
		return false
	for path: String in manifest.files:
		if not files.has(path):
			return false
		var payload: PackedByteArray = files[path]
		if payload.size() != manifest.files[path].bytes or reader.sha256(payload) != manifest.files[path].sha256:
			return false
	manifest["compiler"] = row.previousCompiler.duplicate(true)
	manifest["packageHash"] = row.previousPackage.packageHash
	var previous := CanonicalJson.encode(manifest).to_utf8_buffer()
	if reader.sha256(previous) != row.previousManifestSha256:
		return false
	files["manifest.json"] = previous
	return true
