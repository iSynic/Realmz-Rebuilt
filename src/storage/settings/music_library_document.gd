## Validates the local music index before any paths or preferences are admitted.
class_name MusicLibraryDocument
extends RefCounted

const VERSION: int = 1
const FORMATS := ["mp3", "ogg", "wav", "flac", "aiff", "mod", "xm", "s3m", "it"]


static func empty() -> Dictionary:
	return {"formatVersion": VERSION, "tracks": {}, "playlists": {}, "assignments": {}}


static func valid(data: Variant) -> bool:
	if not data is Dictionary or not _keys(data, ["formatVersion", "tracks", "playlists", "assignments"]):
		return false
	if not _integer(data.formatVersion, VERSION, VERSION):
		return false
	for key: String in ["tracks", "playlists", "assignments"]:
		if not data[key] is Dictionary or data[key].size() > 10000:
			return false
	for id: Variant in data.tracks:
		if not valid_track(id, data.tracks[id]):
			return false
	for id: Variant in data.playlists:
		if not _hex(id, 32) or not _playlist(data.playlists[id], data.tracks):
			return false
	for campaign: Variant in data.assignments:
		if not campaign is String or campaign.length() > 512 or not _assignments(data.assignments[campaign], data.playlists):
			return false
	return true


static func valid_track(id: Variant, record: Variant) -> bool:
	if not id is String or not record is Dictionary:
		return false
	if not _keys(record, ["sourceHash", "sourceName", "title", "format", "playbackFormat", "duration", "subsong", "converter", "cacheHash"]):
		return false
	if not _hex(record.sourceHash, 64) or not _integer(record.subsong, 0, 31):
		return false
	if id != "%s:%d" % [record.sourceHash, int(record.subsong)]:
		return false
	for key: String in ["sourceName", "title", "converter"]:
		if not record[key] is String or record[key].is_empty() or record[key].length() > 1024:
			return false
	if not record.format in FORMATS or not record.playbackFormat in ["mp3", "ogg"]:
		return false
	if not (record.duration is float or record.duration is int) or not is_finite(float(record.duration)) or record.duration <= 0 or record.duration > 7200:
		return false
	return record.cacheHash == "" and record.playbackFormat == record.format if record.format in ["mp3", "ogg"] else _hex(record.cacheHash, 64) and record.playbackFormat == "ogg"


static func _playlist(value: Variant, tracks: Dictionary) -> bool:
	if not value is Dictionary or not _keys(value, ["name", "tracks", "shuffle", "repeat"]):
		return false
	if not value.name is String or value.name.strip_edges().is_empty() or value.name.length() > 120:
		return false
	if not value.shuffle is bool or not value.repeat in ["all", "one", "none"]:
		return false
	if not value.tracks is Array or value.tracks.size() > 10000:
		return false
	for id: Variant in value.tracks:
		if not id is String or not tracks.has(id):
			return false
	return true


static func _assignments(value: Variant, playlists: Dictionary) -> bool:
	if not value is Dictionary or value.size() > 17:
		return false
	for key: Variant in value:
		if not key is String or key != str(int(key)) or int(key) < 1 or int(key) > 17:
			return false
		var assignment: Variant = value[key]
		if not assignment is Dictionary or not _keys(assignment, ["kind", "playlistId"]):
			return false
		if assignment.kind == "original" and assignment.playlistId == "":
			continue
		if assignment.kind != "playlist" or not assignment.playlistId is String or not playlists.has(assignment.playlistId):
			return false
	return true


static func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in value:
		if not key in expected:
			return false
	return true


static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high


static func _hex(value: Variant, length: int) -> bool:
	if not value is String or value.length() != length:
		return false
	for letter: String in value:
		if not letter in "0123456789abcdef":
			return false
	return true
