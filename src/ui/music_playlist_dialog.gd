class_name MusicPlaylistDialog
extends Control

signal closed
signal music_enabled_changed(enabled: bool)
signal music_volume_changed(value: float)
signal playlist_mode_changed(playlist_id: int, mode: int)

const GOLD := Color("d5b45d")
const CYAN := Color("8fcfd1")
const MUTED := Color("9aa0a8")

var _panel: PanelContainer
var _now_playing: Label
var _enabled: CheckButton
var _volume: HSlider
var _done: Button
var _mode_buttons: Dictionary = {}
var _settings: PresentationSettings


func _ready() -> void:
	name = "MusicPlaylistDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 120
	_build()
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


func _build() -> void:
	var veil := ColorRect.new()
	veil.name = "MusicModalVeil"
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.0, 0.0, 0.0, 0.68)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)
	var center := CenterContainer.new()
	center.name = "MusicModalCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 28.0
	add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "MusicPlaylistWindow"
	_panel.theme_type_variation = &"ClassicTextWell"
	center.add_child(_panel)
	var content := VBoxContainer.new()
	content.name = "MusicPlaylistContent"
	content.add_theme_constant_override("separation", 6)
	_panel.add_child(content)
	var header := HBoxContainer.new()
	header.name = "MusicPlaylistHeader"
	content.add_child(header)
	var title := _label("Music Playlist", GOLD, 22)
	title.theme_type_variation = &"ClassicHeading"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_enabled = CheckButton.new()
	_enabled.name = "MusicEnabled"
	_enabled.text = "Music enabled"
	_enabled.toggled.connect(func(value: bool) -> void: music_enabled_changed.emit(value))
	header.add_child(_enabled)
	var now_row := HBoxContainer.new()
	now_row.name = "NowPlayingRow"
	now_row.add_theme_constant_override("separation", 8)
	content.add_child(now_row)
	_now_playing = _label("No music is playing", CYAN, 15)
	_now_playing.name = "NowPlayingTitle"
	_now_playing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	now_row.add_child(_now_playing)
	now_row.add_child(_label("Music volume", Color("e0e2e5"), 14))
	_volume = HSlider.new()
	_volume.name = "MusicVolume"
	_volume.custom_minimum_size.x = 150.0
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.value_changed.connect(func(value: float) -> void: music_volume_changed.emit(value))
	now_row.add_child(_volume)
	content.add_child(HSeparator.new())
	var columns := HBoxContainer.new()
	columns.name = "PlaylistColumns"
	columns.add_theme_constant_override("separation", 8)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	for column_index: int in 2:
		var column := VBoxContainer.new()
		column.name = "PlaylistColumn%d" % (column_index + 1)
		column.add_theme_constant_override("separation", 2)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(column)
		for row_index: int in 10:
			_add_playlist_row(column, column_index * 10 + row_index + 1)
	var legend := _label("Play switches to this context • Continue keeps the current title • Off stops music on entry", MUTED, 13)
	legend.name = "MusicModeLegend"
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(legend)
	var footer := HBoxContainer.new()
	footer.name = "MusicPlaylistFooter"
	content.add_child(footer)
	var note := _label("Saved with Rebuilt preferences, not the adventure save.", MUTED, 12)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(note)
	_done = Button.new()
	_done.name = "MusicDone"
	_done.text = "Done"
	_done.custom_minimum_size = Vector2(110.0, 36.0)
	_done.pressed.connect(close)
	footer.add_child(_done)


func _add_playlist_row(parent: VBoxContainer, playlist_id: int) -> void:
	var row := HBoxContainer.new()
	row.name = "Playlist%02d" % playlist_id
	row.custom_minimum_size.y = 28.0
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	var name_label := _label("%02d  %s" % [playlist_id, ClassicMusicContext.context_name(playlist_id)], MUTED if playlist_id >= 18 else Color("e0e2e5"), 13)
	name_label.name = "Playlist%02dLabel" % playlist_id
	name_label.custom_minimum_size.x = 116.0
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var group := ButtonGroup.new()
	var buttons: Dictionary = {}
	for definition: Dictionary in [
		{"label": "Play", "mode": PresentationSettings.MUSIC_PLAY, "width": 45.0},
		{"label": "Continue", "mode": PresentationSettings.MUSIC_CONTINUE, "width": 68.0},
		{"label": "Off", "mode": PresentationSettings.MUSIC_OFF, "width": 38.0},
	]:
		var button := Button.new()
		button.name = "Playlist%02d%s" % [playlist_id, definition["label"]]
		button.text = definition["label"]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(definition["width"], 26.0)
		button.disabled = playlist_id >= 18
		button.tooltip_text = "Reserved by Classic; no application context selects this slot." if button.disabled else "Set %s to %s." % [ClassicMusicContext.context_name(playlist_id), definition["label"]]
		button.pressed.connect(_on_mode_pressed.bind(playlist_id, int(definition["mode"])))
		row.add_child(button)
		buttons[int(definition["mode"])] = button
	_mode_buttons[playlist_id] = buttons


func _on_mode_pressed(playlist_id: int, mode: int) -> void:
	if _settings != null:
		_settings.set_music_mode(playlist_id, mode)
	playlist_mode_changed.emit(playlist_id, mode)


func _apply_layout() -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = Vector2(minf(900.0, maxf(700.0, size.x - 48.0)), minf(560.0, maxf(480.0, size.y - 64.0)))


static func _label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	return label
