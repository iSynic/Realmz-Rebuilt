## Validates and loads package load result data at the immutable package boundary.

class_name PackageLoadResult
extends RefCounted

var schema_hash: String = ""
var content: RealmzContent
var media: PackageMediaCatalog
var error_code: StringName = &""
var error_message: String = ""


func is_ok() -> bool:
	return content != null and error_code == &""


static func succeeded(loaded_content: RealmzContent, loaded_media: PackageMediaCatalog, loaded_schema_hash: String = "") -> PackageLoadResult:
	var result := PackageLoadResult.new()
	result.schema_hash = loaded_schema_hash
	result.content = loaded_content
	result.media = loaded_media
	return result


static func failed(code: StringName, message: String) -> PackageLoadResult:
	var result := PackageLoadResult.new()
	result.error_code = code
	result.error_message = message
	return result
