class_name ClassicMusicCatalog
extends RefCounted

const MANIFEST_PATH := "res://src/presentation/assets/classic-application-music.json"

var last_error: String = ""
var _tracks: Dictionary = {}
var _streams: Dictionary = {}


func _init(manifest_path: String = MANIFEST_PATH) -> void:
	_load_manifest(manifest_path)


func is_valid() -> bool:
	return last_error.is_empty() and _tracks.size() == 11


func has_track(playlist_id: int) -> bool:
	return _tracks.has(_stock_track_id(playlist_id))


func track(playlist_id: int) -> Dictionary:
	return (_tracks.get(_stock_track_id(playlist_id), {}) as Dictionary).duplicate(true)


func title(playlist_id: int) -> String:
	return String((_tracks.get(_stock_track_id(playlist_id), {}) as Dictionary).get("title", ""))


func stream(playlist_id: int) -> AudioStream:
	var stock_track_id := _stock_track_id(playlist_id)
	if _streams.has(stock_track_id):
		return _streams[stock_track_id] as AudioStream
	var record := _tracks.get(stock_track_id, {}) as Dictionary
	if record.is_empty():
		return null
	var path := String(record.get("path", ""))
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() != int(record.get("bytes", 0)) or _sha256(bytes) != String(record.get("sha256", "")):
		last_error = "Classic application music failed integrity validation for playlist %d." % playlist_id
		return null
	var result := load(path) as AudioStream
	if result is AudioStreamOggVorbis:
		(result as AudioStreamOggVorbis).loop = true
	_streams[stock_track_id] = result
	return result


func _stock_track_id(playlist_id: int) -> int:
	if playlist_id >= 12 and playlist_id <= 14:
		return 1
	return playlist_id


func _load_manifest(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		last_error = "Classic application music manifest is unavailable or malformed."
		return
	var manifest := parsed as Dictionary
	if int(manifest.get("schema_version", 0)) != 1 or String(manifest.get("ownership", "")) != "classic-application" or int(manifest.get("slot_count", 0)) != 20 or String(manifest.get("lookup", "")) != "playlist-id":
		last_error = "Classic application music manifest contract is unsupported."
		return
	for value: Variant in manifest.get("tracks", []):
		if not value is Dictionary:
			last_error = "Classic application music contains a malformed track."
			return
		var record := value as Dictionary
		var playlist_id := int(record.get("playlist_id", 0))
		if playlist_id < 1 or playlist_id > 11 or _tracks.has(playlist_id) or String(record.get("path", "")).is_empty() or int(record.get("bytes", 0)) <= 0 or String(record.get("sha256", "")).length() != 64:
			last_error = "Classic application music contains an incomplete or duplicate track."
			return
		_tracks[playlist_id] = record.duplicate(true)
	if _tracks.size() != 11:
		last_error = "Classic application music does not contain the complete stock track bank."


static func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(bytes) != OK:
		return ""
	return hashing.finish().hex_encode()
