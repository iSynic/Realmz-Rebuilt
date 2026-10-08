## Detached presentation-only library and editable preference draft.
class_name MusicLibraryView
extends RefCounted

class Track extends RefCounted:
	var id: String
	var title: String
	var source_name: String
	var format: String
	var duration: float
	var record: Dictionary

class Playlist extends RefCounted:
	var id: String
	var name: String
	var tracks: Array[String] = []
	var shuffle: bool = false
	var repeat: String = "all"

	func to_data() -> Dictionary:
		return {"name": name, "tracks": tracks.duplicate(), "shuffle": shuffle, "repeat": repeat}

class Assignment extends RefCounted:
	var kind: String = "inherit"
	var playlist_id: String = ""

var tracks: Dictionary[String, Track] = {}
var playlists: Dictionary[String, Playlist] = {}
var _assignments: Dictionary = {}


static func from_data(data: Dictionary) -> MusicLibraryView:
	var view := MusicLibraryView.new()
	for id: String in data.get("tracks", {}):
		var record: Dictionary = data.tracks[id]
		var track := Track.new()
		track.id = id
		track.title = record.title
		track.source_name = record.sourceName
		track.format = record.format
		track.duration = record.duration
		track.record = record.duplicate(true)
		view.tracks[id] = track
	for id: String in data.get("playlists", {}):
		var record: Dictionary = data.playlists[id]
		var playlist := Playlist.new()
		playlist.id = id
		playlist.name = record.name
		playlist.tracks.assign(record.tracks)
		playlist.shuffle = record.shuffle
		playlist.repeat = record.repeat
		view.playlists[id] = playlist
	view._assignments = data.get("assignments", {}).duplicate(true)
	return view


func copy() -> MusicLibraryView:
	var result := from_data({"playlists": playlist_data(), "assignments": assignment_data()})
	result.tracks = tracks.duplicate()
	return result


func playlist_data() -> Dictionary:
	var result := {}
	for id: String in playlists:
		result[id] = playlists[id].to_data()
	return result


func assignment_data() -> Dictionary:
	return _assignments.duplicate(true)


func assignment(campaign: String, context: int) -> Assignment:
	var result := Assignment.new()
	var record: Dictionary = _assignments.get(campaign, {}).get(str(context), {})
	result.kind = record.get("kind", "inherit")
	result.playlist_id = record.get("playlistId", "")
	return result


func resolve(campaign: String, context: int) -> Playlist:
	var selected := assignment(campaign, context)
	if selected.kind == "inherit" and not campaign.is_empty():
		selected = assignment("", context)
	return playlists.get(selected.playlist_id) if selected.kind == "playlist" else null


func set_assignment(campaign: String, context: int, kind: String, playlist_id: String = "") -> void:
	if not _assignments.has(campaign):
		_assignments[campaign] = {}
	if kind == "inherit":
		_assignments[campaign].erase(str(context))
	else:
		_assignments[campaign][str(context)] = {"kind": kind, "playlistId": playlist_id if kind == "playlist" else ""}
	if _assignments[campaign].is_empty():
		_assignments.erase(campaign)


func add_playlist(title: String) -> Playlist:
	var playlist := Playlist.new()
	playlist.id = Crypto.new().generate_random_bytes(16).hex_encode()
	playlist.name = title
	playlists[playlist.id] = playlist
	return playlist


func remove_playlist(id: String) -> void:
	playlists.erase(id)
	for campaign: String in _assignments.keys():
		for context: String in _assignments[campaign].keys():
			if _assignments[campaign][context].get("playlistId", "") == id:
				set_assignment(campaign, int(context), "inherit")
