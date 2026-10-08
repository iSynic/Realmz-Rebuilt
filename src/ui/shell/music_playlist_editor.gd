## Edits reusable playlist drafts without touching persistence or playback.
class_name MusicPlaylistEditor
extends VBoxContainer

signal changed

var _library: MusicLibraryView
var _id: String = ""


func _ready() -> void:
	%PlaylistChoice.item_selected.connect(_select_playlist)
	%PlaylistName.text_changed.connect(_rename)
	%NewPlaylist.pressed.connect(_new_playlist)
	%DeletePlaylist.pressed.connect(_delete_playlist)
	%AddTrack.pressed.connect(_add_track)
	%RemoveTrack.pressed.connect(_remove_track)
	%TrackUp.pressed.connect(_move_track.bind(-1))
	%TrackDown.pressed.connect(_move_track.bind(1))
	%Shuffle.toggled.connect(_shuffle_changed)
	%RepeatMode.item_selected.connect(_repeat_changed)
	%AvailableTracks.item_activated.connect(func(_index: int) -> void: _add_track())
	%PlaylistTracks.item_selected.connect(func(_index: int) -> void: _refresh_actions())
	%AvailableTracks.item_selected.connect(func(_index: int) -> void: _refresh_actions())


func present(library: MusicLibraryView) -> void:
	_library = library
	var selector := %PlaylistChoice as OptionButton
	selector.clear()
	for id: String in library.playlists:
		selector.add_item(library.playlists[id].name)
		selector.set_item_metadata(selector.item_count - 1, id)
		if id == _id:
			selector.select(selector.item_count - 1)
	if not library.playlists.has(_id):
		_id = String(selector.get_item_metadata(0)) if selector.item_count > 0 else ""
	_refresh_tracks()


func _select_playlist(index: int) -> void:
	_id = String((%PlaylistChoice as OptionButton).get_item_metadata(index))
	_refresh_tracks()


func _refresh_tracks() -> void:
	var playlist := _library.playlists.get(_id) as MusicLibraryView.Playlist
	(%PlaylistName as LineEdit).text = playlist.name if playlist != null else ""
	(%PlaylistName as LineEdit).editable = playlist != null
	(%Shuffle as CheckButton).set_pressed_no_signal(playlist.shuffle if playlist != null else false)
	(%Shuffle as CheckButton).disabled = playlist == null
	(%RepeatMode as OptionButton).select(["all", "one", "none"].find(playlist.repeat) if playlist != null else 0)
	(%RepeatMode as OptionButton).disabled = playlist == null
	(%DeletePlaylist as Button).disabled = playlist == null
	var selected := %PlaylistTracks as ItemList
	var available := %AvailableTracks as ItemList
	selected.clear()
	available.clear()
	if playlist != null:
		for id: String in playlist.tracks:
			selected.add_item(_library.tracks[id].title)
	for id: String in _library.tracks:
		available.add_item(_library.tracks[id].title)
		available.set_item_metadata(available.item_count - 1, id)
	_refresh_actions()


func _new_playlist() -> void:
	_id = _library.add_playlist("New playlist").id
	present(_library)
	(%PlaylistName as LineEdit).grab_focus()
	(%PlaylistName as LineEdit).select_all()
	changed.emit()


func _delete_playlist() -> void:
	_library.remove_playlist(_id)
	present(_library)
	changed.emit()


func _rename(value: String) -> void:
	if not _library.playlists.has(_id):
		return
	_library.playlists[_id].name = value
	var selector := %PlaylistChoice as OptionButton
	selector.set_item_text(selector.selected, value)
	changed.emit()


func _add_track() -> void:
	var selected := (%AvailableTracks as ItemList).get_selected_items()
	if not _library.playlists.has(_id) or selected.is_empty():
		return
	_library.playlists[_id].tracks.append(String((%AvailableTracks as ItemList).get_item_metadata(selected[0])))
	_refresh_tracks()
	changed.emit()


func _remove_track() -> void:
	var selected := (%PlaylistTracks as ItemList).get_selected_items()
	if selected.is_empty() or not _library.playlists.has(_id):
		return
	_library.playlists[_id].tracks.remove_at(selected[0])
	_refresh_tracks()
	changed.emit()


func _move_track(delta: int) -> void:
	var selected := (%PlaylistTracks as ItemList).get_selected_items()
	if selected.is_empty() or not _library.playlists.has(_id):
		return
	var tracks := _library.playlists[_id].tracks
	var index := selected[0]
	var next := clampi(index + delta, 0, tracks.size() - 1)
	var id := tracks[index]
	tracks.remove_at(index)
	tracks.insert(next, id)
	_refresh_tracks()
	(%PlaylistTracks as ItemList).select(next)
	(%PlaylistTracks as ItemList).ensure_current_is_visible()
	_refresh_actions()
	changed.emit()


func _shuffle_changed(value: bool) -> void:
	if _library.playlists.has(_id):
		_library.playlists[_id].shuffle = value
		changed.emit()


func _repeat_changed(index: int) -> void:
	if _library.playlists.has(_id):
		_library.playlists[_id].repeat = ["all", "one", "none"][index]
		changed.emit()


func _refresh_actions() -> void:
	var selected := (%PlaylistTracks as ItemList).get_selected_items()
	var playlist := _library.playlists.get(_id) as MusicLibraryView.Playlist
	(%AddTrack as Button).disabled = playlist == null or (%AvailableTracks as ItemList).get_selected_items().is_empty()
	(%RemoveTrack as Button).disabled = selected.is_empty()
	(%TrackUp as Button).disabled = selected.is_empty() or selected[0] == 0
	(%TrackDown as Button).disabled = selected.is_empty() or selected[0] == (%PlaylistTracks as ItemList).item_count - 1
