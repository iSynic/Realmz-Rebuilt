## Validates and loads package install receipt store data at the immutable package boundary.

class_name PackageInstallReceiptStore
extends RefCounted

const KIND: String = "realmz2.install-receipt"
const FORMAT_VERSION: int = 3
const LEGACY_FORMAT_VERSION: int = 2
const LEGACY_DECODER_VERSION: int = 6

var schema_hash: String
var decoder_version: int
var application_package_hash: String
var last_error: String = ""
var requires_application_revalidation: bool = false


func _init(expected_schema_hash: String, expected_decoder_version: int, expected_application_package_hash: String) -> void:
	schema_hash = expected_schema_hash
	decoder_version = expected_decoder_version
	application_package_hash = expected_application_package_hash


func set_application_package_hash(package_hash: String) -> void:
	application_package_hash = package_hash


func read(package_path: String) -> Dictionary:
	last_error = ""
	requires_application_revalidation = false
	var receipt_path := path_for(package_path)
	if not FileAccess.file_exists(receipt_path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	if not value is Dictionary or not _validate(value, package_path):
		if last_error.is_empty():
			last_error = "Installed package receipt is invalid."
		return {}
	return value


func write(package_path: String, content: RealmzContent, archive_sha256: String) -> bool:
	last_error = ""
	if content == null or not _is_sha256(archive_sha256):
		last_error = "Installed package receipt identity is invalid."
		return false
	var receipt := {
		"kind": KIND,
		"formatVersion": FORMAT_VERSION,
		"decoderVersion": decoder_version,
		"schemaHash": schema_hash,
		"applicationPackageHash": application_package_hash,
		"campaignId": content.campaign_id,
		"packageHash": content.package_hash,
		"archiveSha256": archive_sha256,
		"archiveBytes": FileAccess.get_size(package_path),
		"archiveModifiedTime": FileAccess.get_modified_time(package_path),
	}
	var receipt_path := path_for(package_path)
	var temporary_path := receipt_path + ".installing"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		last_error = "Could not open the temporary package receipt."
		return false
	file.store_string(CanonicalJson.encode(receipt))
	file.flush()
	file.close()
	var readback: Variant = JSON.parse_string(FileAccess.get_file_as_string(temporary_path))
	if not readback is Dictionary or CanonicalJson.encode(readback) != CanonicalJson.encode(receipt):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		last_error = "Package receipt failed typed readback."
		return false
	if FileAccess.file_exists(receipt_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(receipt_path))
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(receipt_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		last_error = "Could not atomically commit the package receipt."
		return false
	return true


func cache_key(package_path: String, receipt: Dictionary) -> String:
	return "%s:%s:%s:%s:%s:%d" % [
		ProjectSettings.globalize_path(package_path).simplify_path().to_lower(),
		receipt.get("packageHash", ""),
		receipt.get("archiveSha256", ""),
		receipt.get("schemaHash", ""),
		receipt.get("applicationPackageHash", ""),
		int(receipt.get("decoderVersion", -1)),
	]


func validate_archive_sha256(receipt: Dictionary, actual_sha256: String) -> bool:
	last_error = ""
	if not _is_sha256(actual_sha256):
		return _fail("Installed package archive could not be hashed.")
	if actual_sha256 != receipt.get("archiveSha256", ""):
		return _fail("Installed package SHA-256 no longer matches its validated receipt.")
	return true


static func path_for(package_path: String) -> String:
	return package_path + ".receipt.json"


func _validate(receipt: Dictionary, package_path: String) -> bool:
	var format_version := _integer(receipt.get("formatVersion", -1))
	var receipt_decoder_version := _integer(receipt.get("decoderVersion", -1))
	var fields: Array[String]
	if format_version == FORMAT_VERSION:
		fields = ["kind", "formatVersion", "decoderVersion", "schemaHash", "applicationPackageHash", "campaignId", "packageHash", "archiveSha256", "archiveBytes", "archiveModifiedTime"]
		if receipt_decoder_version != decoder_version:
			return _fail("Installed package receipt was created by an incompatible package decoder.")
	elif format_version == LEGACY_FORMAT_VERSION:
		fields = ["kind", "formatVersion", "decoderVersion", "schemaHash", "campaignId", "packageHash", "archiveSha256", "archiveBytes", "archiveModifiedTime"]
		if receipt_decoder_version != LEGACY_DECODER_VERSION:
			return _fail("Installed package receipt was created by an incompatible package decoder.")
	else:
		return _fail("Installed package receipt has an unsupported version.")
	if not _exact_fields(receipt, fields):
		return _fail("Installed package receipt has an unsupported shape.")
	if receipt["kind"] != KIND:
		return _fail("Installed package receipt has an unsupported kind.")
	if receipt["schemaHash"] != schema_hash or not _safe_path_component(receipt["campaignId"]):
		return _fail("Installed package receipt does not match the runtime contract.")
	if format_version == FORMAT_VERSION and not _is_sha256(receipt["applicationPackageHash"]):
		return _fail("Installed package receipt does not match the runtime contract.")
	if not _is_sha256(receipt["packageHash"]) or not _is_sha256(receipt["archiveSha256"]):
		return _fail("Installed package receipt contains malformed identities.")
	if not _is_integer(receipt["archiveBytes"]) or _integer(receipt["archiveBytes"]) != FileAccess.get_size(package_path):
		return _fail("Installed package byte count no longer matches its validated receipt.")
	if not _is_integer(receipt["archiveModifiedTime"]) or _integer(receipt["archiveModifiedTime"]) != FileAccess.get_modified_time(package_path):
		return _fail("Installed package modification identity no longer matches its validated receipt.")
	if package_path.get_file().to_lower() != "%s.realmz2" % receipt["packageHash"]:
		return _fail("Installed package filename does not match its validated identity.")
	if package_path.get_base_dir().get_file().to_lower() != String(receipt["campaignId"]).to_lower():
		return _fail("Installed package campaign directory does not match its validated identity.")
	# Format 2 predates application identity binding. It is accepted only as the
	# exact decoder-6 shape above and must take the full application revalidation
	# path before it can be reused or refreshed into a current receipt.
	if format_version == LEGACY_FORMAT_VERSION:
		requires_application_revalidation = true
	else:
		requires_application_revalidation = receipt["applicationPackageHash"] != application_package_hash
	return true


func _fail(message: String) -> bool:
	last_error = message
	return false


static func _exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _integer(value: Variant) -> int:
	return int(value) if _is_integer(value) else -1


static func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and value == floor(value))


static func _is_sha256(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character: String in value:
		if not character in "0123456789abcdef":
			return false
	return true


static func _safe_path_component(value: Variant) -> bool:
	if not value is String or value.is_empty() or value in [".", ".."]:
		return false
	if value.contains("/") or value.contains("\\") or value.contains(":"):
		return false
	return value == value.get_file() and not value.is_absolute_path()
