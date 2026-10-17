## Edits reusable playlist drafts without touching persistence or playback.
class_name MusicPlaylistEditor
extends VBoxContainer

signal changed

var _library: MusicLibraryView
var _id: String = ""
var _picker_open := false
var _compact := false


func _ready() -> void:
	%PlaylistChoice.item_selected.connect(_select_playlist)
	%CompactPlaylistChoice.item_selected.connect(_select_compact_playlist)
	%PlaylistName.text_changed.connect(_rename)
	%NewPlaylist.pressed.connect(_new_playlist)
	%DeletePlaylist.pressed.connect(_delete_playlist)
	%CompactNewPlaylist.pressed.connect(_new_playlist)
	%CompactDeletePlaylist.pressed.connect(_delete_playlist)
	%AddTracks.pressed.connect(_open_picker)
	%PickerBack.pressed.connect(_close_picker)
	%AddTrack.pressed.connect(_add_track)
	%RemoveTrack.pressed.connect(_remove_track)
	%TrackUp.pressed.connect(_move_track.bind(-1))
	%TrackDown.pressed.connect(_move_track.bind(1))
	%Shuffle.toggled.connect(_shuffle_changed)
	%RepeatMode.item_selected.connect(_repeat_changed)
	%AvailableTracks.item_selected.connect(func(_index: int) -> void: _refresh_actions())
	%AvailableTracks.item_activated.connect(func(_index: int) -> void: _add_track())
	%PlaylistTracks.item_selected.connect(func(_index: int) -> void: _refresh_actions())
	_show_page()
	resized.connect(_apply_layout)
	visibility_changed.connect(_apply_layout)
	_apply_layout()


func apply_ui_sizing(_profile: UiLayoutProfile) -> void:
	_apply_layout.call_deferred()


func handle_back() -> bool:
	if not _picker_open:
		return false
	_close_picker()
	return true


func present(library: MusicLibraryView) -> void:
	_library = library
	var selector := %PlaylistChoice as ItemList
	selector.clear()
	for id: String in library.playlists:
		selector.add_item(library.playlists[id].name)
		selector.set_item_metadata(selector.item_count - 1, id)
		if id == _id:
			selector.select(selector.item_count - 1)
		var compact_selector := %CompactPlaylistChoice as OptionButton
		compact_selector.add_item(library.playlists[id].name)
		compact_selector.set_item_metadata(compact_selector.item_count - 1, id)
		if id == _id:
			compact_selector.select(compact_selector.item_count - 1)
	if not library.playlists.has(_id):
		_id = String(selector.get_item_metadata(0)) if selector.item_count > 0 else ""
		if selector.item_count > 0:
			selector.select(0)
			(%CompactPlaylistChoice as OptionButton).select(0)
	_refresh_tracks()
	_show_page()


func _select_playlist(index: int) -> void:
	_id = String((%PlaylistChoice as ItemList).get_item_metadata(index))
	(%CompactPlaylistChoice as OptionButton).select(index)
	_refresh_tracks()


func _select_compact_playlist(index: int) -> void:
	_id = String((%CompactPlaylistChoice as OptionButton).get_item_metadata(index))
	(%PlaylistChoice as ItemList).select(index)
	_refresh_tracks()


func _refresh_tracks() -> void:
	if _library == null:
		return
	var playlist := _library.playlists.get(_id) as MusicLibraryView.Playlist
	(%PlaylistName as LineEdit).text = playlist.name if playlist != null else ""
	(%PlaylistName as LineEdit).editable = playlist != null
	(%Shuffle as CheckButton).set_pressed_no_signal(playlist.shuffle if playlist != null else false)
	(%Shuffle as CheckButton).disabled = playlist == null
	(%RepeatMode as OptionButton).select(["all", "one", "none"].find(playlist.repeat) if playlist != null else 0)
	(%RepeatMode as OptionButton).disabled = playlist == null
	(%DeletePlaylist as Button).disabled = playlist == null
	(%CompactDeletePlaylist as Button).disabled = playlist == null
	(%AddTracks as Button).disabled = playlist == null
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
	if _library == null:
		return
	_id = _library.add_playlist("New playlist").id
	present(_library)
	(%PlaylistName as LineEdit).grab_focus()
	(%PlaylistName as LineEdit).select_all()
	changed.emit()


func _delete_playlist() -> void:
	if _library == null or not _library.playlists.has(_id):
		return
	_library.remove_playlist(_id)
	_id = ""
	present(_library)
	changed.emit()


func _rename(value: String) -> void:
	if _library == null or not _library.playlists.has(_id):
		return
	_library.playlists[_id].name = value
	var selector := %PlaylistChoice as ItemList
	var selected := selector.get_selected_items()
	if not selected.is_empty():
		selector.set_item_text(selected[0], value)
	var compact_selector := %CompactPlaylistChoice as OptionButton
	var compact_index := compact_selector.selected
	if compact_index >= 0:
		compact_selector.set_item_text(compact_index, value)
	changed.emit()


func _open_picker() -> void:
	_picker_open = true
	_show_page()
	(%AvailableTracks as ItemList).grab_focus()


func _close_picker() -> void:
	_picker_open = false
	_show_page()
	(%AddTracks as Button).grab_focus()


func _add_track() -> void:
	if _library == null or not _library.playlists.has(_id):
		return
	var selected := (%AvailableTracks as ItemList).get_selected_items()
	if selected.is_empty():
		return
	var track_id := String((%AvailableTracks as ItemList).get_item_metadata(selected[0]))
	_library.playlists[_id].tracks.append(track_id)
	var next_index := selected[0]
	_refresh_tracks()
	if next_index < (%AvailableTracks as ItemList).item_count:
		(%AvailableTracks as ItemList).select(next_index)
	_refresh_actions()
	changed.emit()


func _remove_track() -> void:
	var selected := (%PlaylistTracks as ItemList).get_selected_items()
	if selected.is_empty() or _library == null or not _library.playlists.has(_id):
		return
	_library.playlists[_id].tracks.remove_at(selected[0])
	_refresh_tracks()
	changed.emit()


func _move_track(delta: int) -> void:
	var selected := (%PlaylistTracks as ItemList).get_selected_items()
	if selected.is_empty() or _library == null or not _library.playlists.has(_id):
		return
	var tracks := _library.playlists[_id].tracks
	var index := selected[0]
	var next := clampi(index + delta, 0, tracks.size() - 1)
	var track_id := tracks[index]
	tracks.remove_at(index)
	tracks.insert(next, track_id)
	_refresh_tracks()
	(%PlaylistTracks as ItemList).select(next)
	(%PlaylistTracks as ItemList).ensure_current_is_visible()
	_refresh_actions()
	changed.emit()


func _shuffle_changed(value: bool) -> void:
	if _library != null and _library.playlists.has(_id):
		_library.playlists[_id].shuffle = value
		changed.emit()


func _repeat_changed(index: int) -> void:
	if _library != null and _library.playlists.has(_id):
		_library.playlists[_id].repeat = ["all", "one", "none"][index]
		changed.emit()


func _show_page() -> void:
	%EditorScroll.visible = not _picker_open
	%TrackPickerPage.visible = _picker_open
	%CompactPlaylistBar.visible = _compact and not _picker_open
	%PlaylistPanel.visible = not _compact and not _picker_open


func _refresh_actions() -> void:
	if _library == null:
		return
	var selected := (%PlaylistTracks as ItemList).get_selected_items()
	var playlist := _library.playlists.get(_id) as MusicLibraryView.Playlist
	(%AddTrack as Button).disabled = playlist == null or (%AvailableTracks as ItemList).get_selected_items().is_empty()
	(%RemoveTrack as Button).disabled = selected.is_empty()
	(%TrackUp as Button).disabled = selected.is_empty() or selected[0] == 0
	(%TrackDown as Button).disabled = selected.is_empty() or selected[0] == (%PlaylistTracks as ItemList).item_count - 1


func _apply_layout() -> void:
	if not is_node_ready():
		return
	var profile := UiSizing.profile_for(self)
	var text_scale := profile.font_scale / profile.ui_scale if profile != null and profile.ui_scale > 0.0 else 1.0
	var compact_size := size.x < 820.0
	var large_text := text_scale >= 1.45
	var next_compact := compact_size or large_text or (profile != null and profile.id == UiLayoutProfile.COMPACT)
	if _compact == next_compact:
		return
	_compact = next_compact
	_show_page()
	if _compact:
		var compact_choice := %CompactPlaylistChoice as OptionButton
		var selected := (%PlaylistChoice as ItemList).get_selected_items()
		if compact_choice.item_count > 0:
			compact_choice.select(selected[0] if not selected.is_empty() else 0)
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner != null and not focus_owner.is_visible_in_tree():
			compact_choice.grab_focus()
