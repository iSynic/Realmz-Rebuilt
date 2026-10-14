## Stores disposable compact setup documents bound to exact source and decoder identities.
class_name PackageSetupCache
extends RefCounted

const FORMAT_VERSION := 1
const MAX_BYTES := 32 * 1024 * 1024


static func read(path: String, archive_hash: String, manifest: Dictionary, application_hash: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES: return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	if not value is Dictionary: return {}
	for field: String in ["version", "decoder", "archiveHash", "packageHash", "schemaHash", "applicationHash", "payloadHash", "documents"]:
		if not value.has(field): return {}
	if value.size() != 8 or value.version != FORMAT_VERSION or value.decoder != PackageRepository.DECODER_VERSION or value.archiveHash != archive_hash or value.packageHash != manifest.packageHash or value.schemaHash != manifest.schemaHash or value.applicationHash != application_hash or not value.documents is Dictionary: return {}
	var documents: Dictionary = value.documents
	if documents.size() != 2 or not documents.get("content") is Dictionary or not documents.get("assets") is Dictionary: return {}
	if CanonicalJson.encode(documents).sha256_text() != value.payloadHash: return {}
	return documents


static func write(path: String, archive_hash: String, manifest: Dictionary, application_hash: String, documents: Dictionary) -> bool:
	var value := {"version": FORMAT_VERSION, "decoder": PackageRepository.DECODER_VERSION, "archiveHash": archive_hash, "packageHash": manifest.packageHash, "schemaHash": manifest.schemaHash, "applicationHash": application_hash, "payloadHash": CanonicalJson.encode(documents).sha256_text(), "documents": documents}
	var encoded := JSON.stringify(value)
	if encoded.to_utf8_buffer().size() > MAX_BYTES or DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return false
	var temporary := path + ".writing"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_string(encoded)
	file.flush()
	file.close()
	if read(temporary, archive_hash, manifest, application_hash).is_empty():
		DirAccess.remove_absolute(temporary)
		return false
	return DirAccess.rename_absolute(temporary, path) == OK
