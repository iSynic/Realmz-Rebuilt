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


static func is_stock_track_id(value: Variant) -> bool:
	if not value is String:
		return false
	var text: String = value
	if not text.begins_with("stock:"):
		return false
	var suffix := text.trim_prefix("stock:")
	return suffix == str(int(suffix)) and int(suffix) >= 1 and int(suffix) <= 11


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
		if not id is String or (not tracks.has(id) and not is_stock_track_id(id)):
			return false
	return true


static func _assignments(value: Variant, playlists: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	var map: Dictionary = value
	if map.size() > 17:
		return false
	for key: Variant in map:
		if not key is String:
			return false
		var slot_key: String = key
		if slot_key != str(int(slot_key)) or int(slot_key) < 1 or int(slot_key) > 17:
			return false
		var raw: Variant = map[slot_key]
		if not raw is Dictionary:
			return false
		var assignment: Dictionary = raw
		var kind: Variant = assignment.get("kind")
		if kind == "original":
			if not _keys(assignment, ["kind", "playlistId"]) or assignment.get("playlistId") != "":
				return false
			continue
		if kind == "stock":
			if not _keys(assignment, ["kind", "trackId"]) or not is_stock_track_id(assignment.get("trackId")):
				return false
			continue
		if kind == "playlist":
			var pid: Variant = assignment.get("playlistId")
			if not _keys(assignment, ["kind", "playlistId"]) or not pid is String or not playlists.has(pid):
				return false
			continue
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
