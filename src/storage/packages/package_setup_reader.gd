## Reads only party-building documents while the full package remains independently validated.
class_name PackageSetupReader
extends RefCounted

var _reader := PackageArchiveReader.new()


func read(path: String, cache_root: String, application: RealmzContent, application_media: Array[MediaAsset], cancelled: Callable = Callable()) -> PackageSetupResult:
	var result := PackageSetupResult.new()
	result.source_path = path
	if application == null: return result
	var archive := ZIPReader.new()
	if _reader.open_bounded(archive, path) != OK: return result
	var manifest_value: Variant = _reader.read_document(archive, "manifest.json")
	var entries_value: Variant = _reader.entries(archive)
	if not manifest_value is Dictionary or not entries_value is Array:
		archive.close()
		return result
	var manifest: Dictionary = manifest_value
	var discovery := PackageManifestDiscovery.new(PackageRepository.SCHEMA_HASHES, PackageRepository.SUPPORTED_CAPABILITIES, PackageRepository.DEFERRED_PACKAGE_CAPABILITIES, _reader)
	if not discovery.validate_structure(manifest, entries_value):
		result.error_message = discovery.last_error
		archive.close()
		return result
	var archive_hash := _reader.sha256_file(path)
	var cache_path := cache_root.path_join(String(manifest.packageHash) + ".json")
	var documents := PackageSetupCache.read(path + ".setup.json", archive_hash, manifest, application.package_hash) if path.begins_with("res://") else {}
	if documents.is_empty(): documents = PackageSetupCache.read(cache_path, archive_hash, manifest, application.package_hash)
	# Early character publication requires archive-proven rules, even with a self-consistent cache.
	var verified_documents := _read_documents(archive, manifest)
	if documents != verified_documents:
		documents = verified_documents
		if not documents.is_empty(): PackageSetupCache.write(cache_path, archive_hash, manifest, application.package_hash, documents)
	archive.close()
	if documents.is_empty() or cancelled.is_valid() and bool(cancelled.call()): return result
	var validator := PackageMediaValidatorResolver.new()
	if not validator.validate_package_assets(documents.assets, manifest.files):
		result.error_message = validator.error_message()
		return result
	var assets := validator.construct_assets(documents.assets)
	var assembler := PackageDomainAssembler.new()
	result.catalog = assembler.assemble_setup(manifest, documents.content, assets, application, application_media)
	if result.catalog == null:
		result.error_message = assembler.error_message()
		return result
	result.media = PackageMediaCatalog.new(path, manifest.packageHash, assets)
	return result


func _read_documents(archive: ZIPReader, manifest: Dictionary) -> Dictionary:
	var documents: Dictionary = {}
	for path: String in ["content.json", "assets/index.json"]:
		var bytes := archive.read_file(path)
		var identity: Dictionary = manifest.files.get(path, {})
		if bytes.size() != identity.get("bytes", -1) or _reader.sha256(bytes) != identity.get("sha256", ""): return {}
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if not parsed is Dictionary or parsed.get("schemaVersion") != manifest.schemaVersion: return {}
		if path == "content.json":
			if parsed.get("kind") != "realmz2.content": return {}
			var compact: Dictionary = {}
			for field: String in ["campaign", "races", "castes", "items", "spells"]:
				if not parsed.has(field): return {}
				compact[field] = parsed[field]
			if int(manifest.schemaVersion) >= 7:
				var facts: Variant = parsed.get("classicRecords")
				if not facts is Dictionary or not facts.has_all(["sources", "ruleSelection"]): return {}
				compact["classicRecords"] = {"sources": facts.sources, "ruleSelection": facts.ruleSelection}
			var sets: Variant = parsed.get("monsterSets", [])
			if not sets is Array: return {}
			compact["monsterSets"] = []
			for entry: Variant in sets:
				if not entry is Dictionary or entry.size() != 3 or not entry.has_all(["setId", "name", "monsters"]): return {}
				compact.monsterSets.append({"setId": entry.setId, "name": entry.name, "monsters": []})
			documents["content"] = compact
		else:
			if parsed.get("kind") != "realmz2.assets": return {}
			documents["assets"] = parsed
	return documents
