## Reads only integrity-bound character definitions, without preparing an adventure.
class_name CharacterVaultRuleSources
extends RefCounted

var last_error: String = ""
var _application: RealmzContent
var _packages: Array[PackageDiscoveryResult] = []
var _catalogs: Dictionary = {}


func configure(application: RealmzContent, packages: Array[PackageDiscoveryResult]) -> void:
	_application = application
	_packages = packages.duplicate()
	_catalogs.clear()


func catalog(record: CharacterVaultRecord, destination: RealmzContent) -> ContentTransferCatalog:
	last_error = ""
	if record.source_package_hash == destination.package_hash and record.source_campaign_id == destination.campaign_id:
		return destination.transfer_catalog
	if _application == null:
		last_error = "The application character definitions are unavailable."
		return null
	if record.source_package_hash == _application.package_hash and record.source_campaign_id in ["", _application.campaign_id]:
		return _application.transfer_catalog
	var key := "%s:%s" % [record.source_campaign_id, record.source_package_hash]
	if _catalogs.has(key):
		return _catalogs[key] as ContentTransferCatalog
	for package: PackageDiscoveryResult in _packages:
		if package.ready and package.campaign_id == record.source_campaign_id and package.package_hash == record.source_package_hash:
			var result := _read(package)
			if result != null:
				_catalogs[key] = result
			return result
	last_error = "Install this Character File's exact source scenario revision (%s, %s) to validate its race and class." % [record.source_campaign_id, record.source_package_hash]
	return null


func _read(package: PackageDiscoveryResult) -> ContentTransferCatalog:
	var archive := ZIPReader.new()
	if archive.open(package.path) != OK:
		last_error = "The Character File's source scenario package could not be opened."
		return null
	var reader := PackageArchiveReader.new()
	var manifest: Variant = reader.read_document(archive, "manifest.json")
	var entries: Variant = reader.entries(archive)
	var discovery := PackageManifestDiscovery.new(PackageRepository.SCHEMA_HASHES, PackageRepository.SUPPORTED_CAPABILITIES, PackageRepository.DEFERRED_PACKAGE_CAPABILITIES, reader)
	if manifest == null or entries == null or not discovery.validate_structure(manifest, entries) or manifest["campaignId"] != package.campaign_id or manifest["packageHash"] != package.package_hash:
		archive.close()
		last_error = "The Character File's source scenario manifest failed exact identity validation."
		return null
	var bytes := archive.read_file("content.json")
	var integrity: Dictionary = manifest["files"]["content.json"]
	archive.close()
	if bytes.size() != int(integrity["bytes"]) or reader.sha256(bytes) != integrity["sha256"]:
		last_error = "The Character File's source rule document failed size or SHA-256 validation."
		return null
	var content: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	var decoder := PackageCharacterContentDecoder.new()
	if not content is Dictionary or content.get("kind") != "realmz2.content" or content.get("schemaVersion") != manifest["schemaVersion"] or decoder.decode_races(content.get("races")) == null or decoder.decode_castes(content.get("castes")) == null:
		last_error = "The Character File's source race or class definitions are malformed."
		return null
	# Other documents and media are not consumed here. This proves only the exact
	# source rule identities; ordinary package preparation remains authoritative.
	return PackageTransferCatalog.build({"races": content["races"], "castes": content["castes"]}, _application)
