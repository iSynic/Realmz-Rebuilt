class_name ClassicUiAssetCatalog
extends RefCounted

const MANIFEST_PATH := "res://src/presentation/assets/classic-ui-assets.json"

static var _definitions: Dictionary = {}


static func definition(asset_id: StringName) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(String(asset_id), {})


static func texture(asset_id: StringName) -> Texture2D:
	var record := ClassicUiAssetCatalog.definition(asset_id)
	if record.is_empty():
		return null
	return load(String(record.get("path", ""))) as Texture2D


static func native_size(asset_id: StringName) -> Vector2i:
	var record := ClassicUiAssetCatalog.definition(asset_id)
	return Vector2i(int(record.get("native_width", 0)), int(record.get("native_height", 0)))


static func cursor_hotspot(asset_id: StringName) -> Vector2:
	var record := ClassicUiAssetCatalog.definition(asset_id)
	var hotspot: Variant = record.get("cursor_hotspot", [])
	if hotspot is Array and (hotspot as Array).size() == 2:
		return Vector2(float(hotspot[0]), float(hotspot[1]))
	return Vector2.ZERO


static func all_definitions() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for value: Variant in _definitions.values():
		result.append(value as Dictionary)
	return result


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary:
		push_error("Classic UI asset manifest is unavailable or malformed.")
		return
	for value: Variant in (parsed as Dictionary).get("assets", []):
		if value is Dictionary:
			var record := value as Dictionary
			_definitions[String(record.get("id", ""))] = record
