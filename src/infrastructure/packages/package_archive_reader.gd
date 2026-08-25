class_name PackageArchiveReader
extends RefCounted

var last_error: String = ""


func entries(archive: ZIPReader) -> Variant:
	last_error = ""
	var paths := archive.get_files()
	if paths == null:
		last_error = "Could not enumerate ZIP entries."
		return null
	var result: Array[String] = []
	result.assign(paths)
	result.sort()
	return result


func read_document(archive: ZIPReader, path: String) -> Variant:
	last_error = ""
	if not archive.file_exists(path):
		last_error = "Package document '%s' is missing." % path
		return null
	var bytes := archive.read_file(path)
	var text := bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		last_error = "Package document '%s' is not a JSON object." % path
		return null
	return parsed


func read_documents(archive: ZIPReader, paths: Array[String], progress_callback: Callable = Callable()) -> Variant:
	last_error = ""
	var documents: Dictionary = {}
	for index: int in paths.size():
		var parsed: Variant = read_document(archive, paths[index])
		if parsed == null:
			return null
		documents[paths[index]] = parsed
		_report_progress(progress_callback, &"reading-documents", index + 1, paths.size())
	return documents


func validate_files(manifest: Dictionary, archive: ZIPReader, progress_callback: Callable = Callable(), cancel_callback: Callable = Callable()) -> bool:
	last_error = ""
	var file_paths: Array[String] = []
	file_paths.assign(manifest["files"].keys())
	file_paths.sort()
	for file_index: int in file_paths.size():
		if cancel_callback.is_valid() and bool(cancel_callback.call()):
			last_error = "Package operation cancelled."
			return false
		var file_path := file_paths[file_index]
		_report_progress(progress_callback, &"validating-integrity", file_index, file_paths.size())
		var integrity: Dictionary = manifest["files"][file_path]
		var bytes := archive.read_file(file_path)
		if bytes.size() != int(integrity["bytes"]) or sha256(bytes) != integrity["sha256"]:
			last_error = "Package file '%s' failed size or SHA-256 validation." % file_path
			return false
	_report_progress(progress_callback, &"validating-integrity", file_paths.size(), file_paths.size())
	return true


func sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		context.update(file.get_buffer(mini(1024 * 1024, file.get_length() - file.get_position())))
	file.close()
	return context.finish().hex_encode()


func _report_progress(callback: Callable, phase: StringName, completed: int, total: int) -> void:
	if callback.is_valid():
		callback.call(phase, completed, total)
