class_name ClassicApplicationSpellText
extends RefCounted

const CATALOG_PATH := "res://src/infrastructure/packages/classic-application-spell-descriptions.json"
const EXPECTED_DESCRIPTION_COUNT: int = 252
const EXPECTED_SOURCE_COMMIT := "491816ad60037394f92c428e99c004494d3c28b3"
const EXPECTED_SOURCE_PATH := "base/Realmz/Data Files/The Family Jewels.rsrc"
const EXPECTED_SOURCE_SHA256 := "8dbae6c6a418c82250dca93937c5958dacea9874d654c62da4e4dafa184dc85c"

static var _descriptions: Dictionary = {}
static var _loaded: bool = false
static var _error: String = ""


static func description(classic_id: int) -> String:
	_load_once()
	return String(_descriptions.get(classic_id, ""))


static func owns(classic_id: int) -> bool:
	_load_once()
	return _descriptions.has(classic_id)


static func error_message() -> String:
	_load_once()
	return _error


static func _load_once() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary:
		_error = "The bundled Classic spell-description catalog is malformed."
		return
	var document: Dictionary = parsed
	if document.size() != 5 or document.get("schemaVersion") != 1 or document.get("sourceCommit") != EXPECTED_SOURCE_COMMIT or document.get("sourcePath") != EXPECTED_SOURCE_PATH or document.get("sourceFileSha256") != EXPECTED_SOURCE_SHA256 or not document.get("descriptions") is Dictionary:
		_error = "The bundled Classic spell-description catalog has an unsupported contract."
		return
	var encoded: Dictionary = document["descriptions"]
	for key: Variant in encoded:
		if not key is String or not (encoded[key] is String) or not String(key).is_valid_int() or String(encoded[key]).is_empty():
			_error = "The bundled Classic spell-description catalog contains an invalid entry."
			_descriptions.clear()
			return
		var classic_id := String(key).to_int()
		if _descriptions.has(classic_id):
			_error = "The bundled Classic spell-description catalog contains duplicate identities."
			_descriptions.clear()
			return
		_descriptions[classic_id] = encoded[key]
	if _descriptions.size() != EXPECTED_DESCRIPTION_COUNT:
		_error = "The bundled Classic spell-description catalog is incomplete."
		_descriptions.clear()
