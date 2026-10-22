## Revalidates a pinned save predecessor through ordinary package installation.
class_name SaveUpdateInstallation
extends RefCounted


static func validate(path: String, campaign_id: String, package_hash: String, archive_hash: String) -> String:
	if FileAccess.get_sha256(path) != archive_hash:
		return "The retained campaign archive differs from the approved save update."
	var schema_hash := _schema_hash(path, campaign_id, package_hash)
	if schema_hash.is_empty():
		return "The retained campaign manifest does not match the approved save update."
	var schemas: Array[String] = [schema_hash]
	var store := PackageInstallReceiptStore.new(schemas, PackageRepository.DECODER_VERSION, ApplicationLibraryIdentity.PACKAGE_HASH)
	var receipt := store.read(path)
	if receipt.is_empty():
		receipt = _older_receipt(path, schemas)
		if receipt.is_empty():
			return "The retained campaign installation receipt is missing or invalid."
	elif not store.requires_application_revalidation:
		return "" if _matches(receipt, campaign_id, package_hash, archive_hash) else "The retained campaign receipt does not match the approved save update."
	if not _matches(receipt, campaign_id, package_hash, archive_hash):
		return "The retained campaign receipt does not match the approved save update."
	var repository := PackageRepository.new()
	var app := repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	if not app.is_ok():
		repository.close()
		return "Could not validate the application library: " + app.error_message
	repository.set_application_content(app.content, app.media.assets())
	var installed := repository.install_package(path, path.get_base_dir().get_base_dir())
	repository.close()
	if not installed.is_ok():
		return "Could not revalidate the retained campaign: " + installed.error_message
	receipt = store.read(path)
	if store.requires_application_revalidation or not _matches(receipt, campaign_id, package_hash, archive_hash):
		return "The retained campaign receipt failed revalidation readback."
	return ""


static func _older_receipt(path: String, schemas: Array[String]) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PackageInstallReceiptStore.path_for(path)))
	if not value is Dictionary or value.get("formatVersion") != PackageInstallReceiptStore.FORMAT_VERSION:
		return {}
	var decoder: Variant = value.get("decoderVersion")
	if not (decoder is int or (decoder is float and decoder == floor(decoder))) or decoder < 1 or decoder >= PackageRepository.DECODER_VERSION:
		return {}
	# Validate the complete historical receipt shape and file identity before
	# allowing the ordinary installer to replace its disposable metadata.
	return PackageInstallReceiptStore.new(schemas, int(decoder), ApplicationLibraryIdentity.PACKAGE_HASH).read(path)


static func _schema_hash(path: String, campaign_id: String, package_hash: String) -> String:
	var archive := ZIPReader.new()
	if archive.open(path) != OK:
		return ""
	var manifest: Variant = PackageArchiveReader.new().read_document(archive, "manifest.json")
	archive.close()
	if not manifest is Dictionary or manifest.get("campaignId") != campaign_id or manifest.get("packageHash") != package_hash:
		return ""
	return manifest.schemaHash if PackageRepository.SCHEMA_HASHES.get(int(manifest.get("schemaVersion", 0))) == manifest.get("schemaHash") else ""


static func _matches(receipt: Dictionary, campaign_id: String, package_hash: String, archive_hash: String) -> bool:
	return not receipt.is_empty() and receipt.get("campaignId") == campaign_id and receipt.get("packageHash") == package_hash and receipt.get("archiveSha256") == archive_hash
