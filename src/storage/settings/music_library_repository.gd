## Atomically persists player music independently of scenarios and adventure saves.
class_name MusicLibraryRepository
extends RefCounted

const MAX_INDEX_BYTES: int = 8 * 1024 * 1024

var last_error: String = ""
var root: String
var _data: Dictionary = MusicLibraryDocument.empty()
var _read_only: bool = false


func _init(directory: String = "user://music") -> void:
	root = ProjectSettings.globalize_path(directory)
	var path := root.path_join("index.json")
	if not FileAccess.file_exists(path):
		return
	var loaded := _read(path)
	if loaded.is_empty():
		_read_only = true
		last_error = "The music library index is damaged. Its files have been preserved."
		return
	_data = loaded


func snapshot() -> Dictionary:
	return _data.duplicate(true)


func save_preferences(playlists: Dictionary, assignments: Dictionary) -> bool:
	var candidate := snapshot()
	candidate.playlists = playlists.duplicate(true)
	candidate.assignments = assignments.duplicate(true)
	return _commit(candidate)


func accept_import(records: Dictionary) -> bool:
	var candidate := snapshot()
	for id: Variant in records:
		if not MusicLibraryDocument.valid_track(id, records[id]):
			last_error = "The music importer returned an invalid track."
			return false
		candidate.tracks[id] = records[id].duplicate(true)
	return _commit(candidate)


func remove_track(id: String) -> bool:
	if not _data.tracks.has(id):
		return false
	var candidate := snapshot()
	candidate.tracks.erase(id)
	for playlist: Dictionary in candidate.playlists.values():
		while id in playlist.tracks:
			playlist.tracks.erase(id)
	# Immutable originals remain available to the retained index backup.
	return _commit(candidate)


func playback_path(id: String) -> String:
	var track: Dictionary = _data.tracks.get(id, {})
	if track.is_empty():
		return ""
	if String(track.cacheHash).is_empty():
		return source_path(id)
	return root.path_join("audio").path_join(String(track.cacheHash) + ".ogg")


func source_path(id: String) -> String:
	var track: Dictionary = _data.tracks.get(id, {})
	return root.path_join("originals").path_join(String(track.sourceHash)) if not track.is_empty() else ""


func _commit(candidate: Dictionary) -> bool:
	if _read_only:
		return false
	last_error = ""
	if not MusicLibraryDocument.valid(candidate):
		last_error = "Music preferences contain an invalid track, playlist, or assignment."
		return false
	var text := CanonicalJson.encode(candidate)
	if text.to_utf8_buffer().size() > MAX_INDEX_BYTES:
		last_error = "The music library has reached its index size limit."
		return false
	if DirAccess.make_dir_recursive_absolute(root) != OK:
		last_error = "Could not create music library storage."
		return false
	var path := root.path_join("index.json")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Could not open the temporary music index."
		return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	var readback := _read(temporary)
	if error != OK or readback.is_empty() or CanonicalJson.encode(readback) != text:
		last_error = "The music index failed readback validation."
	elif FileAccess.file_exists(path) and DirAccess.copy_absolute(path, path + ".bak") != OK:
		last_error = "Could not preserve the previous music index."
	elif DirAccess.rename_absolute(temporary, path) != OK:
		last_error = "Could not atomically replace the music index."
	if not last_error.is_empty():
		DirAccess.remove_absolute(temporary)
		return false
	_data = readback
	return true


func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() > MAX_INDEX_BYTES:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	return parser.data if MusicLibraryDocument.valid(parser.data) else {}
