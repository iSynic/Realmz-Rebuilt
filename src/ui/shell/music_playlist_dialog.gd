## Owns the scene-authored music library, playlist, and assignment workspace.
class_name MusicPlaylistDialog
extends Control

signal opened
signal closed
signal music_enabled_changed(enabled: bool)
signal music_volume_changed(value: float)
signal playlist_mode_changed(playlist_id: int, mode: int)
signal import_requested(paths: PackedStringArray)
signal import_cancelled
signal preview_requested(track_id: String)
signal preview_stopped
signal remove_requested(track_id: String)
signal repair_requested(track_id: String)
signal apply_requested(draft: MusicLibraryView)

var _settings: PresentationSettings
var _committed := MusicLibraryView.new()
var _draft := MusicLibraryView.new()
var _campaign: String = ""
var _campaign_title: String = ""
var _dirty: bool = false
var _close_after_apply: bool = false
var _importing: bool = false
var _focus_before_open: WeakRef
var _messages: Array[String] = []


func _ready() -> void:
	%MusicEnabled.toggled.connect(func(value: bool) -> void: music_enabled_changed.emit(value))
	%MusicVolume.value_changed.connect(func(value: float) -> void: music_volume_changed.emit(value))
	%MusicDone.pressed.connect(_done)
	%MusicApply.pressed.connect(_apply)
	%MusicCancel.pressed.connect(close)
	%ImportMusic.pressed.connect(_open_import)
	%CancelImport.pressed.connect(func() -> void: import_cancelled.emit())
	%MusicFiles.files_selected.connect(func(paths: PackedStringArray) -> void: import_requested.emit(paths))
	%LibraryTracks.item_selected.connect(func(_index: int) -> void: _show_track())
	%LibraryTracks.item_activated.connect(func(_index: int) -> void: _preview())
	%PreviewTrack.pressed.connect(_preview)
	%StopPreview.pressed.connect(func() -> void: preview_stopped.emit())
	%RemoveLibraryTrack.pressed.connect(func() -> void: remove_requested.emit(_selected_track()))
	%RepairTrack.pressed.connect(func() -> void: repair_requested.emit(_selected_track()))
	%Playlists.changed.connect(_changed)
	%Assignments.changed.connect(_changed)
	%Assignments.mode_changed.connect(func(context: int, mode: int) -> void: playlist_mode_changed.emit(context, mode))
	(%MusicTabs as TabContainer).get_tab_bar().focus_mode = Control.FOCUS_ALL
	resized.connect(_apply_layout)
	visibility_changed.connect(_apply_layout)
	(%MusicPlaylistWindow as PanelContainer).minimum_size_changed.connect(_apply_layout, CONNECT_DEFERRED)
	_apply_layout()
	hide()


func open(settings: PresentationSettings, context: int, title: String, playing: bool) -> void:
	var opening := not visible
	if opening:
		var previous := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		_focus_before_open = weakref(previous) if previous != null else null
		_draft = _committed.copy()
		_dirty = false
	_settings = settings
	if opening:
		opened.emit()
	(%MusicEnabled as CheckButton).set_pressed_no_signal(settings != null and settings.music_enabled)
	(%MusicVolume as HSlider).set_value_no_signal(settings.music_volume if settings != null else 0.8)
	_bind_editors()
	set_playback_state(context, title, playing)
	show()
	if opening:
		(%MusicTabs as TabContainer).current_tab = 0
		(%ImportMusic as Button).grab_focus()


func present_library(library: MusicLibraryView, campaign: String, title: String) -> void:
	_committed = library
	_draft = library.copy()
	_campaign = campaign
	_campaign_title = title
	_dirty = false
	_bind_editors()
	_refresh_library()


func merge_imports(library: MusicLibraryView) -> void:
	_committed = library
	_draft.tracks = library.tracks.duplicate()
	for playlist: MusicLibraryView.Playlist in _draft.playlists.values():
		var retained: Array[String] = []
		for id: String in playlist.tracks:
			if library.tracks.has(id):
				retained.append(id)
		playlist.tracks = retained
	_bind_editors()
	_refresh_library()


func apply_result(success: bool, message: String = "") -> void:
	if not success:
		report(message)
		_close_after_apply = false
		return
	_committed = _draft.copy()
	_dirty = false
	(%MusicApply as Button).disabled = true
	report("Music playlists and assignments saved.")
	if _close_after_apply:
		_close_after_apply = false
		close()


func set_import_status(running: bool, message: String) -> void:
	_importing = running
	(%CancelImport as Button).visible = running
	(%ImportMusic as Button).disabled = running
	(%ImportStatus as Label).text = message
	(%ImportStatus as Label).tooltip_text = message
	_show_track()


func report(message: String) -> void:
	if message.is_empty():
		return
	_messages.append(message)
	if _messages.size() > 20:
		_messages.pop_front()
	(%MusicMessages as Label).text = "\n".join(_messages)
	(%ImportStatus as Label).text = message
	(%ImportStatus as Label).tooltip_text = message


func controller_focus_root() -> Node:
	return %MusicFiles if (%MusicFiles as FileDialog).visible else self


func controller_cycle_tab(delta: int) -> void:
	if (%MusicFiles as FileDialog).visible:
		return
	var tabs := %MusicTabs as TabContainer
	tabs.current_tab = wrapi(tabs.current_tab + delta, 0, tabs.get_tab_count())
	tabs.get_tab_bar().grab_focus()


func close() -> void:
	var browser := %MusicFiles as FileDialog
	if browser.visible:
		browser.hide()
		(%ImportMusic as Button).grab_focus()
		return
	if not visible:
		return
	preview_stopped.emit()
	var previous := _focus_before_open.get_ref() as Control if _focus_before_open != null else null
	_focus_before_open = null
	_draft = _committed.copy()
	_dirty = false
	hide()
	closed.emit()
	if previous != null and previous.is_inside_tree() and previous.is_visible_in_tree():
		previous.grab_focus()


func set_playback_state(context: int, title: String, playing: bool) -> void:
	if not is_node_ready():
		return
	(%NowPlayingTitle as Label).text = "Now Playing  •  %s" % title if playing else "No music is playing"
	(%NowPlayingTitle as Label).tooltip_text = title + (" — " + ClassicMusicContext.context_name(context) if context > 0 else "")


func _bind_editors() -> void:
	if not is_node_ready():
		return
	(%Playlists as MusicPlaylistEditor).present(_draft)
	(%Assignments as MusicAssignmentsEditor).present(_draft, _settings, _campaign, _campaign_title)
	(%MusicApply as Button).disabled = not _dirty


func _refresh_library() -> void:
	var list := %LibraryTracks as ItemList
	var selected := _selected_track()
	list.clear()
	for id: String in _draft.tracks:
		list.add_item(_draft.tracks[id].title)
		list.set_item_metadata(list.item_count - 1, id)
		if id == selected:
			list.select(list.item_count - 1)
	(%LibraryEmpty as Label).visible = list.item_count == 0
	_show_track()


func _selected_track() -> String:
	var list := %LibraryTracks as ItemList
	var selected := list.get_selected_items()
	return String(list.get_item_metadata(selected[0])) if not selected.is_empty() else ""


func _show_track() -> void:
	var track := _draft.tracks.get(_selected_track()) as MusicLibraryView.Track
	(%TrackDetails as Label).text = "%s\n%s  •  %d:%02d\nOriginal: %s" % [track.title, track.format.to_upper(), int(track.duration) / 60, int(track.duration) % 60, track.source_name] if track != null else "Select a track to preview, repair, or remove it."
	(%PreviewTrack as Button).disabled = track == null
	(%RemoveLibraryTrack as Button).disabled = track == null or _importing
	(%RepairTrack as Button).disabled = track == null or _importing


func _preview() -> void:
	var id := _selected_track()
	if not id.is_empty():
		preview_requested.emit(id)


func _open_import() -> void:
	var browser := %MusicFiles as FileDialog
	browser.popup_centered_ratio(0.88)
	browser.get_line_edit().grab_focus()


func _changed() -> void:
	_dirty = true
	(%MusicApply as Button).disabled = false
	(%Assignments as MusicAssignmentsEditor).refresh_playlists()


func _apply() -> void:
	for playlist: MusicLibraryView.Playlist in _draft.playlists.values():
		if playlist.name.strip_edges().is_empty():
			report("Give every playlist a name before applying.")
			_close_after_apply = false
			return
	apply_requested.emit(_draft.copy())


func _done() -> void:
	if _dirty:
		_close_after_apply = true
		_apply()
	else:
		close()


func _apply_layout() -> void:
	if not is_node_ready():
		return
	var profile := UiSizing.profile_for(self)
	var scale := profile.ui_scale if profile != null else 1.0
	var panel := %MusicPlaylistWindow as PanelContainer
	var available := size - Vector2(32, 32) * scale
	var desired := Vector2(1120, 640) * scale
	panel.position = (size - desired.min(available)) * 0.5
	panel.size = desired.min(available)
