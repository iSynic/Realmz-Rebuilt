class_name PreparedPackage
extends RefCounted

var installed_path: String
var content: RealmzContent
var media: MediaSource
var error_code: StringName
var error_message: String


func _init(package_path: String = "", package_content: RealmzContent = null, package_media: MediaSource = null, preparation_error: StringName = &"", preparation_message: String = "") -> void:
	installed_path = package_path
	content = package_content
	media = package_media
	error_code = preparation_error
	error_message = preparation_message


func is_ok() -> bool:
	return error_code.is_empty() and content != null and media != null
