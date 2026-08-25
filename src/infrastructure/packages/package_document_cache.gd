class_name PackageDocumentCache
extends RefCounted

const KIND := "realmz2.document-cache"
const FORMAT_VERSION := 1
const MAX_PAYLOAD_BYTES := 512 * 1024 * 1024
const DOCUMENT_PATHS: Array[String] = ["assets/index.json", "content.json", "scenario.json", "world.json"]

var _schema_hash: String
var _decoder_version: int


func _init(schema_hash: String, decoder_version: int) -> void:
	_schema_hash = schema_hash
	_decoder_version = decoder_version


func read(package_path: String, archive_sha256: String) -> Dictionary:
	var cache_path := path_for(package_path)
	if not FileAccess.file_exists(cache_path):
		return {}
	var envelope: Variant = bytes_to_var(FileAccess.get_file_as_bytes(cache_path))
	if not envelope is Dictionary or not _valid_envelope(envelope, archive_sha256):
		return {}
	var payload: PackedByteArray = envelope["payload"]
	if _sha256(payload) != envelope["payloadSha256"]:
		return {}
	var expected_bytes: int = envelope["payloadBytes"]
	var encoded := payload.decompress(expected_bytes, FileAccess.COMPRESSION_ZSTD)
	if encoded.size() != expected_bytes:
		return {}
	var documents: Variant = bytes_to_var(encoded)
	if not documents is Dictionary or documents.size() != DOCUMENT_PATHS.size():
		return {}
	for document_path: String in DOCUMENT_PATHS:
		if not documents.get(document_path) is Dictionary:
			return {}
	return documents


func write(package_path: String, archive_sha256: String, documents: Dictionary) -> bool:
	if documents.size() != DOCUMENT_PATHS.size():
		return false
	for document_path: String in DOCUMENT_PATHS:
		if not documents.get(document_path) is Dictionary:
			return false
	var encoded := var_to_bytes(documents)
	var payload := encoded.compress(FileAccess.COMPRESSION_ZSTD)
	if payload.is_empty():
		return false
	var envelope := {
		"kind": KIND,
		"formatVersion": FORMAT_VERSION,
		"decoderVersion": _decoder_version,
		"schemaHash": _schema_hash,
		"archiveSha256": archive_sha256,
		"payloadSha256": _sha256(payload),
		"payloadBytes": encoded.size(),
		"payload": payload,
	}
	var cache_bytes := var_to_bytes(envelope)
	var cache_path := path_for(package_path)
	var temporary_path := cache_path + ".installing"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(cache_bytes)
	file.flush()
	file.close()
	if _sha256(FileAccess.get_file_as_bytes(temporary_path)) != _sha256(cache_bytes):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return false
	if FileAccess.file_exists(cache_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(cache_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return false
	return true


static func path_for(package_path: String) -> String:
	return package_path + ".documents.cache"


func _valid_envelope(envelope: Dictionary, archive_sha256: String) -> bool:
	var fields := ["kind", "formatVersion", "decoderVersion", "schemaHash", "archiveSha256", "payloadSha256", "payloadBytes", "payload"]
	if envelope.size() != fields.size() or fields.any(func(field: String) -> bool: return not envelope.has(field)):
		return false
	return envelope["kind"] == KIND and int(envelope["formatVersion"]) == FORMAT_VERSION and int(envelope["decoderVersion"]) == _decoder_version and envelope["schemaHash"] == _schema_hash and envelope["archiveSha256"] == archive_sha256 and envelope["payloadSha256"] is String and envelope["payloadBytes"] is int and int(envelope["payloadBytes"]) > 0 and int(envelope["payloadBytes"]) <= MAX_PAYLOAD_BYTES and envelope["payload"] is PackedByteArray


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
