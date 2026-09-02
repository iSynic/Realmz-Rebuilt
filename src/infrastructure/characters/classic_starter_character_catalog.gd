class_name ClassicStarterCharacterCatalog
extends RefCounted

const FORMAT := "realmz2.classic-starter-characters"
const FORMAT_VERSION := 1
const SOURCE_VERSION := "Realmz 7.1.2"
const CASTLE_SOURCE_REVISION := "491816ad60037394f92c428e99c004494d3c28b3"
const EXPECTED_SOURCE_HASHES := {
	"Kevlar": "6a5124c03e41977002d93fcfbc52d206c84e4b0b1948a84bcaf41052aa5b41a2",
	"Lothlorian": "0cf31e9ec12d6435f266689548bb1bc7201cdf66da414bc3fea88e51ef7e6b54",
	"Silver Leaf": "ee736cec9c32eb6226b239d0d79d3ee9f270cf87f29a0d6b1c48268b78bf70d9",
	"Traskelion": "62a785a49d93f7aebfb4abca4aa3eb8d347e6f6dea1b0526b5483c20d8a1a262",
	"Trevor": "06e65b0ae81a0d0cb220a7f46ab8e2daf28ecf4575396e71d269603b1e3aa15b",
	"Vormale": "440e0b9cb675f7cc68553ab3414b830bb8d1889518e095ba4e16d00805f957f5",
}

var last_error: String = ""


func load_records(path: String, application_package_hash: String) -> Array[CharacterVaultRecord]:
	last_error = ""
	var result: Array[CharacterVaultRecord] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("The built-in starter-character catalog is unavailable.", result)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return _fail("The built-in starter-character catalog is not valid JSON.", result)
	if parsed.get("format") != FORMAT or parsed.get("formatVersion") != FORMAT_VERSION or parsed.get("sourceVersion") != SOURCE_VERSION or parsed.get("castleSourceRevision") != CASTLE_SOURCE_REVISION:
		return _fail("The built-in starter-character catalog identity is invalid.", result)
	if application_package_hash.length() != 64 or parsed.get("applicationCharacterLibraryPackageHash") != application_package_hash:
		return _fail("The starter characters do not match the built-in character library.", result)
	if not _valid_sources(parsed.get("sources")) or not parsed.get("records") is Array or parsed["records"].size() != EXPECTED_SOURCE_HASHES.size():
		return _fail("The built-in starter-character inventory is incomplete.", result)
	var character_ids: Dictionary = {}
	for record_data: Variant in parsed["records"]:
		var record := CharacterVaultRecord.from_data(record_data)
		if record == null or record.source_package_hash != application_package_hash or record.rules_version != "realmz-classic-1" or character_ids.has(record.character_id):
			return _fail("A built-in starter-character record is invalid.", result)
		var expected_hash := record.revision_hash
		var canonical_data := record.to_data()
		canonical_data["revisionHash"] = ""
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(CanonicalJson.encode(canonical_data).to_utf8_buffer())
		if context.finish().hex_encode() != expected_hash:
			return _fail("A built-in starter-character revision hash is invalid.", result)
		character_ids[record.character_id] = true
		result.append(record)
	result.sort_custom(func(left: CharacterVaultRecord, right: CharacterVaultRecord) -> bool: return left.character_id < right.character_id)
	return result


func _valid_sources(value: Variant) -> bool:
	if not value is Array or value.size() != EXPECTED_SOURCE_HASHES.size():
		return false
	var found: Dictionary = {}
	for source: Variant in value:
		if not source is Dictionary or not source.get("name") is String or source.get("bytes") != 872 or source.get("sha256") != EXPECTED_SOURCE_HASHES.get(source.get("name"), ""):
			return false
		found[source["name"]] = true
	return found.size() == EXPECTED_SOURCE_HASHES.size()


func _fail(message: String, empty: Array[CharacterVaultRecord]) -> Array[CharacterVaultRecord]:
	last_error = message
	return empty
