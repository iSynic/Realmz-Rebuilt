class_name PackageInstallResult
extends RefCounted

var installed_path: String
var package: PackageLoadResult
var error_code: StringName = &""
var error_message: String = ""


func is_ok() -> bool:
	return package != null and package.is_ok() and not installed_path.is_empty() and error_code == &""


static func succeeded(path: String, loaded_package: PackageLoadResult) -> PackageInstallResult:
	var result := PackageInstallResult.new()
	result.installed_path = path
	result.package = loaded_package
	return result


static func failed(code: StringName, message: String) -> PackageInstallResult:
	var result := PackageInstallResult.new()
	result.error_code = code
	result.error_message = message
	return result
