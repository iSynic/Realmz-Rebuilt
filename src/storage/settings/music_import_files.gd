## Stages immutable music bytes and validates native decoder results off the UI thread.
class_name MusicImportFiles
extends RefCounted

const MAX_BYTES: int = 256 * 1024 * 1024
const MAX_RESULT_BYTES: int = 128 * 1024


static func prepare(source: String, job: String, helper: String, cancelled: Callable) -> Dictionary:
	var result := _prepare_helper(job, helper)
	if result.has("error"):
		return result
	var error := copy_bounded(source, job.path_join("source"), cancelled)
	if not error.is_empty():
		return {"error": error}
	result["hash"] = FileAccess.get_sha256(job.path_join("source"))
	return result


static func prepare_packaged(asset: MediaAsset, media: MediaSource, job: String, helper: String, cancelled: Callable) -> Dictionary:
	var result := _prepare_helper(job, helper)
	if result.has("error"):
		return result
	if media == null or asset.byte_count <= 0 or asset.byte_count > MAX_BYTES or cancelled.call():
		return {"error": "Scenario music is unavailable or exceeds the decoder limit."}
	var bytes := media.read_bytes(asset)
	if bytes.size() != asset.byte_count or cancelled.call():
		return {"error": "Scenario music could not be read from its package."}
	var file := FileAccess.open(job.path_join("source"), FileAccess.WRITE)
	if file == null:
		return {"error": "Could not stage scenario music."}
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_sha256(job.path_join("source")) != asset.sha256:
		return {"error": "Scenario music failed its content hash check."}
	result["hash"] = asset.sha256
	return result


static func _prepare_helper(job: String, helper: String) -> Dictionary:
	var manifest_path := helper.path_join("manifest.json")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
	if manifest_file == null or manifest_file.get_length() > MAX_RESULT_BYTES:
		return {"error": "The music importer is missing from this installation."}
	var manifest: Variant = JSON.parse_string(manifest_file.get_as_text())
	var executable_name := "realmz-music-importer" + (".exe" if OS.get_name() == "Windows" else "")
	if not manifest is Dictionary or manifest.get("formatVersion") != 1 or not manifest.get("files") is Dictionary:
		return {"error": "The music importer manifest is invalid."}
	var identity: Variant = manifest.get("converter")
	if not identity is String or not identity.begins_with("realmz-music-1:") or identity.trim_prefix("realmz-music-1:").length() != 64 or not identity.trim_prefix("realmz-music-1:").is_valid_hex_number(false):
		return {"error": "The music importer version is unsupported."}
	var executable := helper.path_join(executable_name)
	if not manifest.files.has(executable_name) or not FileAccess.file_exists(executable) or FileAccess.get_sha256(executable) != manifest.files[executable_name]:
		return {"error": "The music importer executable failed its integrity check."}
	if DirAccess.make_dir_recursive_absolute(job.path_join("audio")) != OK:
		return {"error": "Could not create temporary music import storage."}
	return {"executable": executable, "converter": identity}


static func copy_bounded(source: String, destination: String, cancelled: Callable) -> String:
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null or input.get_length() <= 0 or input.get_length() > MAX_BYTES:
		return "Choose a nonempty music file no larger than 256 MiB."
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		return "Could not copy music into managed storage."
	var remaining := input.get_length()
	while remaining > 0:
		if cancelled.call():
			return "Music import cancelled."
		var bytes := input.get_buffer(mini(1024 * 1024, remaining))
		if bytes.is_empty():
			return "The music file changed or could not be read completely."
		output.store_buffer(bytes)
		if output.get_error() != OK:
			return "Could not copy music; check available disk space."
		remaining -= bytes.size()
	output.flush()
	return "" if output.get_error() == OK else "Could not finish copying music."


static func finalize(job: String, root: String, source_hash: String, source_name: String, converter: String, cancelled: Callable) -> Dictionary:
	var result_file := FileAccess.open(job.path_join("result.json"), FileAccess.READ)
	if result_file == null or result_file.get_length() > MAX_RESULT_BYTES:
		return {"error": "The music importer stopped before completing this file."}
	var result: Variant = JSON.parse_string(result_file.get_as_text())
	if not result is Dictionary or result.get("formatVersion") != 1 or result.get("converter") != converter:
		return {"error": "The music importer returned an unsupported result."}
	if result.get("ok") != true:
		return {"error": String(result.get("error", "The music file could not be decoded.")).left(2048)}
	if not result.get("tracks") is Array or result.tracks.is_empty() or result.tracks.size() > 32:
		return {"error": "The music importer returned an invalid track list."}
	var records: Dictionary = {}
	for value: Variant in result.tracks:
		if cancelled.call():
			return {"error": "Music import cancelled."}
		var record := _track(value, job, source_hash, source_name, converter)
		if record.is_empty():
			return {"error": "The converted music failed playback or metadata validation."}
		var id := "%s:%d" % [source_hash, int(record.subsong)]
		if records.has(id):
			return {"error": "The importer returned duplicate subsongs."}
		records[id] = record
	for record: Dictionary in records.values():
		if cancelled.call():
			return {"error": "Music import cancelled."}
		if not String(record.cacheHash).is_empty():
			var audio_path := job.path_join("audio/track-%d.ogg" % int(record.subsong))
			if not _install_blob(audio_path, root.path_join("audio").path_join(record.cacheHash + ".ogg"), record.cacheHash):
				return {"error": "Could not install converted music; check available disk space."}
	if not _install_blob(job.path_join("source"), root.path_join("originals").path_join(source_hash), source_hash):
		return {"error": "Could not install the original music file."}
	return {"tracks": records}


static func _track(value: Variant, job: String, hash: String, source_name: String, converter: String) -> Dictionary:
	if not value is Dictionary or not value.get("subsong") is float and not value.get("subsong") is int:
		return {}
	var song := int(value.subsong)
	if value.subsong != song or song < 0 or song > 31:
		return {}
	var filename: Variant = value.get("cacheFile")
	if filename != "" and filename != "track-%d.ogg" % song:
		return {}
	var playback_path := job.path_join("source" if filename == "" else "audio/" + String(filename))
	var file := FileAccess.open(playback_path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > MAX_BYTES:
		return {}
	var record := {"sourceHash": hash, "sourceName": source_name.left(1024), "title": value.get("title"), "format": value.get("format"), "playbackFormat": value.get("playbackFormat"), "duration": value.get("duration"), "subsong": song, "converter": converter, "cacheHash": "" if filename == "" else FileAccess.get_sha256(playback_path)}
	if not MusicLibraryDocument.valid_track("%s:%d" % [hash, song], record):
		return {}
	var stream: AudioStream = AudioStreamMP3.load_from_file(playback_path) if record.playbackFormat == "mp3" else AudioStreamOggVorbis.load_from_file(playback_path)
	return record if stream != null and stream.get_length() > 0 else {}


static func _install_blob(source: String, destination: String, expected_hash: String) -> bool:
	if FileAccess.file_exists(destination) and FileAccess.get_sha256(destination) == expected_hash:
		return true
	if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK or FileAccess.get_sha256(source) != expected_hash:
		return false
	return DirAccess.rename_absolute(source, destination) == OK


static func remove_job(job: String) -> void:
	if job.is_empty() or not job.get_file().begins_with("import-"):
		return
	var directory := DirAccess.open(job)
	if directory == null:
		return
	for child: String in directory.get_directories():
		if child != "audio" or directory.is_link(child):
			continue
		for file: String in DirAccess.get_files_at(job.path_join(child)):
			DirAccess.remove_absolute(job.path_join(child).path_join(file))
		DirAccess.remove_absolute(job.path_join(child))
	for file: String in directory.get_files():
		DirAccess.remove_absolute(job.path_join(file))
	DirAccess.remove_absolute(job)
