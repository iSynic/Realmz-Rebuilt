## Rebuilds stock-only character recovery fingerprints from explicit historical archives.
extends SceneTree

var _error := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("Usage: -- source-descriptors.json output.json")
		quit(1)
		return
	var sources: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var profiles: Array[Dictionary] = []
	for source: Dictionary in sources:
		var document := _verified_document(source.path, source.archiveSha256, source.packageHash)
		if document.is_empty(): break
		var catalog := PackageTransferCatalog.build(document, null)
		var stock := catalog
		if source.has("stockApplicationPath"):
			var baseline := _verified_document(source.stockApplicationPath, source.stockApplicationSha256)
			if baseline.is_empty(): break
			stock = PackageTransferCatalog.build(baseline, null)
		var profile := {"packageHash": source.packageHash, "sourceCampaignIds": source.sourceCampaignIds, "rulesVersion": document["recoveryRulesVersion"], "archiveSha256": source.archiveSha256, "evidence": source.evidence, "races": {}, "castes": {}}
		for family: String in ["races", "castes"]:
			for definition: Dictionary in document[family]:
				var fingerprint := catalog.fingerprint(StringName(family), definition.id)
				if fingerprint != stock.fingerprint(StringName(family), definition.id):
					_error = "Historical profile contains custom rules; stock recovery cannot include it."
					break
				profile[family][definition.id] = fingerprint
		profiles.append(profile)
	if not _error.is_empty() or profiles.size() != sources.size():
		printerr(_error)
		quit(1)
		return
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(CanonicalJson.encode({"version": 1, "profiles": profiles}))
	file.close()
	print("Recovery profiles: %d; SHA256: %s" % [profiles.size(), FileAccess.get_sha256(args[1])])
	quit()


func _verified_document(path: String, expected: String, package_hash: String = "") -> Dictionary:
	if FileAccess.get_sha256(path) != expected:
		_error = "Historical archive SHA256 mismatch."
		return {}
	var archive := ZIPReader.new()
	if archive.open(path) != OK:
		_error = "Historical archive could not open."
		return {}
	var manifest: Dictionary = JSON.parse_string(archive.read_file("manifest.json").get_string_from_utf8())
	var identity: String = manifest.packageHash
	if not package_hash.is_empty() and package_hash != identity:
		_error = "Historical descriptor package identity mismatch."
	manifest.erase("packageHash")
	if CanonicalJson.encode(manifest).sha256_text() != identity:
		_error = "Historical manifest identity mismatch."
	for name: String in manifest.files:
		var bytes := archive.read_file(name)
		if bytes.size() != int(manifest.files[name].bytes) or PackageArchiveReader.new().sha256(bytes) != manifest.files[name].sha256:
			_error = "Historical payload integrity mismatch."
	var document: Dictionary = JSON.parse_string(archive.read_file("content.json").get_string_from_utf8())
	document["recoveryRulesVersion"] = manifest.engine.rulesVersion
	archive.close()
	var decoder := PackageCharacterContentDecoder.new()
	if decoder.decode_races(document.get("races")) == null or decoder.decode_castes(document.get("castes")) == null:
		_error = "Historical rule tables failed strict decoding."
	return document if _error.is_empty() else {}
