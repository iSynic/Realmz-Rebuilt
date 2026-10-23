## Reconstructs the converter's exact support inputs from its archive and the bundled stock library.

class_name ClassicImporterSupport
extends RefCounted

var directory: String = ""
var _cancelled: Callable


func prepare(root: String, destination: String, application_path: String, executable: String, cancelled: Callable = Callable()) -> String:
	_cancelled = cancelled
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(root.path_join("build-manifest.json"))) != OK:
		return "The scenario importer build manifest is missing or invalid. Reinstall Rebuilt."
	var value: Variant = parser.data
	if not value is Dictionary:
		return "The scenario importer build manifest is missing or invalid. Reinstall Rebuilt."
	var manifest: Dictionary = value
	if (manifest.get("formatVersion") != 1 and manifest.get("formatVersion") != 2) or not manifest.get("executable") is Dictionary or not manifest.get("supportFiles") is Array:
		return "The scenario importer build manifest is missing or invalid. Reinstall Rebuilt."
	var binary: Dictionary = manifest.executable
	if str(binary.get("path", "")) != executable.get_file() or FileAccess.get_sha256(executable) != str(binary.get("sha256", "")):
		return "The scenario importer executable failed its integrity check. Reinstall Rebuilt."
	if manifest.formatVersion == 1:
		directory = root.path_join("support")
		var records: Array = manifest.supportFiles
		return _verify_loose(root, records)
	directory = destination
	return _prepare_archive(root, destination, application_path, manifest)


func _verify_loose(root: String, records: Array) -> String:
	for value: Variant in records:
		if _is_cancelled():
			return "Scenario import cancelled."
		if not value is Dictionary:
			return "The scenario importer support manifest is invalid."
		var record: Dictionary = value
		if not _safe_path(str(record.get("path", ""))):
			return "The scenario importer support manifest contains an unsafe path."
		var path := root.path_join("support").path_join(str(record.path))
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != str(record.get("sha256", "")):
			return "Scenario importer support failed its integrity check: %s" % str(record.path)
	return ""


func _prepare_archive(root: String, destination: String, application_path: String, manifest: Dictionary) -> String:
	if manifest.get("kind") != "realmz-rebuilt.scenario-importer-build" or not manifest.get("supportArchive") is Dictionary or not manifest.get("supportApplication") is Dictionary:
		return "The scenario importer support archive manifest is invalid."
	var source: Dictionary = manifest.supportApplication
	if source.get("campaignId") != ApplicationLibraryIdentity.CAMPAIGN_ID or source.get("packageHash") != ApplicationLibraryIdentity.PACKAGE_HASH or source.get("sha256") != FileAccess.get_sha256(application_path):
		return "The scenario importer requires a different stock application library. Reinstall Rebuilt."
	var descriptor: Dictionary = manifest.supportArchive
	var path := root.path_join("support.zip")
	if descriptor.get("path") != "support.zip" or not _matches_file(path, descriptor):
		return "The scenario importer support archive failed its integrity check. Reinstall Rebuilt."
	var support := ZIPReader.new()
	var application := ZIPReader.new()
	if PackageArchiveReader.new().open_bounded(support, path) != OK:
		return "The scenario importer support archive is invalid."
	if application.open(application_path) != OK:
		support.close()
		return "Could not open the stock application library for import."
	var records: Array = manifest.supportFiles
	var error := _write_entries(destination, records, support, application)
	support.close()
	application.close()
	return error


func _write_entries(destination: String, records: Array, support: ZIPReader, application: ZIPReader) -> String:
	var expected: Dictionary = {}
	var destinations: Dictionary = {}
	var directories: Dictionary = {}
	for value: Variant in records:
		if _is_cancelled():
			return "Scenario import cancelled."
		if not value is Dictionary:
			return "The scenario importer support manifest is invalid."
		var record: Dictionary = value
		var relative := str(record.get("path", ""))
		if not _safe_path(relative) or destinations.has(relative.to_lower()):
			return "The scenario importer support manifest contains an unsafe or duplicate path."
		destinations[relative.to_lower()] = true
		var application_entry := str(record.get("applicationPath", ""))
		var archive := application if record.has("applicationPath") else support
		var entry := application_entry if record.has("applicationPath") else relative
		if not _safe_path(entry) or not archive.file_exists(entry):
			return "Scenario importer support is missing: %s" % relative
		if archive == support:
			expected[entry] = true
		var bytes := archive.read_file(entry)
		if not _matches_bytes(bytes, record):
			return "Scenario importer support failed its integrity check: %s" % relative
		var error := _write_file(destination.path_join(relative), bytes, directories)
		if not error.is_empty():
			return error
	var entries := support.get_files()
	if entries.size() != expected.size():
		return "The scenario importer support archive contains unexpected or duplicate files."
	for entry: String in entries:
		if not expected.has(entry):
			return "The scenario importer support archive contains an unexpected file."
	return ""


func _matches_file(path: String, descriptor: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var length := file.get_length()
	file.close()
	return descriptor.get("bytes") == length and descriptor.get("sha256") == FileAccess.get_sha256(path)


func _matches_bytes(bytes: PackedByteArray, descriptor: Dictionary) -> bool:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return descriptor.get("bytes") == bytes.size() and descriptor.get("sha256") == hash.finish().hex_encode()


func _write_file(path: String, bytes: PackedByteArray, directories: Dictionary) -> String:
	var parent := path.get_base_dir()
	if not directories.has(parent):
		if DirAccess.make_dir_recursive_absolute(parent) != OK:
			return "Could not prepare scenario importer support storage."
		directories[parent] = true
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not write scenario importer support."
	file.store_buffer(bytes)
	var error := file.get_error()
	file.close()
	return "" if error == OK else "Could not write scenario importer support (error %d)." % error


func _safe_path(path: String) -> bool:
	if path.is_empty() or path.is_absolute_path() or path.contains("\\") or path.contains(":"):
		return false
	for part: String in path.split("/"):
		if part in ["", ".", ".."] or part.ends_with(".") or part.ends_with(" "):
			return false
	return true


func _is_cancelled() -> bool:
	return _cancelled.is_valid() and _cancelled.call() == true
