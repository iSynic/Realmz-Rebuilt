## Presents music playlist dialog through the Godot interface.

class_name MusicPlaylistDialog
extends Control

signal closed
signal music_enabled_changed(enabled: bool)
signal music_volume_changed(value: float)
signal playlist_mode_changed(playlist_id: int, mode: int)

const PLAYLIST_ROW_SCENE_PATH := "res://src/ui/shell/music_playlist_row.tscn"

var _panel: PanelContainer
var _now_playing: Label
var _enabled: CheckButton
var _volume: HSlider
var _done: Button
var _mode_buttons: Dictionary = {}
var _settings: PresentationSettings


func _ready() -> void:
	_panel = %MusicPlaylistWindow
	_now_playing = %NowPlayingTitle
	_enabled = %MusicEnabled
	_volume = %MusicVolume
	_done = %MusicDone
	_enabled.toggled.connect(func(value: bool) -> void: music_enabled_changed.emit(value))
	_volume.value_changed.connect(func(value: float) -> void: music_volume_changed.emit(value))
	_done.pressed.connect(close)
	_populate_playlist_rows()
	resized.connect(_apply_layout)
	_apply_layout()
	hide()


func open(settings: PresentationSettings, playlist_id: int, title: String, playing: bool) -> void:
	_settings = settings
	_enabled.set_pressed_no_signal(settings != null and settings.music_enabled)
	_volume.set_value_no_signal(settings.music_volume if settings != null else 0.8)
	for id_value: Variant in _mode_buttons:
		var id := int(id_value)
		var buttons := _mode_buttons[id] as Dictionary
		var mode := settings.music_mode(id) if settings != null else PresentationSettings.MUSIC_PLAY
		for mode_value: Variant in buttons:
			(buttons[mode_value] as Button).set_pressed_no_signal(int(mode_value) == mode)
	set_playback_state(playlist_id, title, playing)
	show()
	if _done != null and _done.is_inside_tree():
		_done.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func set_playback_state(playlist_id: int, title: String, playing: bool) -> void:
	if _now_playing == null:
		return
	_now_playing.text = "Now Playing  •  %s" % title if playing else "No music is playing"
	_now_playing.tooltip_text = ClassicMusicContext.context_name(playlist_id) if playlist_id > 0 else "Music is stopped."


func _populate_playlist_rows() -> void:
	_mode_buttons.clear()
	for column_index: int in 2:
		var column := get_node("MusicModalCenter/MusicPlaylistWindow/MusicPlaylistContent/PlaylistColumns/PlaylistColumn%d" % (column_index + 1)) as VBoxContainer
		for row_index: int in 10:
			var playlist_id := column_index * 10 + row_index + 1
			var row := (load(PLAYLIST_ROW_SCENE_PATH) as PackedScene).instantiate() as MusicPlaylistRow
			column.add_child(row)
			row.configure(playlist_id)
			row.mode_selected.connect(_on_mode_pressed)
			_mode_buttons[playlist_id] = row.mode_buttons()


func _on_mode_pressed(playlist_id: int, mode: int) -> void:
	if _settings != null:
		_settings.set_music_mode(playlist_id, mode)
	playlist_mode_changed.emit(playlist_id, mode)


func _apply_layout() -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = Vector2(minf(900.0, maxf(700.0, size.x - 48.0)), minf(560.0, maxf(480.0, size.y - 64.0)))
