## Binds one Classic music context to the reusable three-mode playlist row.

class_name MusicPlaylistRow
extends HBoxContainer

signal mode_selected(playlist_id: int, mode: int)

var _playlist_id: int
var _mode_buttons: Dictionary = {}


func configure(playlist_id: int) -> void:
	_playlist_id = playlist_id
	_mode_buttons.clear()
	name = "Playlist%02d" % playlist_id
	var reserved := playlist_id >= 18
	var label := get_node("ContextLabel") as Label
	label.name = "Playlist%02dLabel" % playlist_id
	label.text = "%02d  %s" % [playlist_id, ClassicMusicContext.context_name(playlist_id)]
	label.add_theme_color_override("font_color", Color("9aa0a8") if reserved else Color("e0e2e5"))
	for definition: Dictionary in [
		{"node": "Play", "label": "Play", "mode": PresentationSettings.MUSIC_PLAY},
		{"node": "Continue", "label": "Continue", "mode": PresentationSettings.MUSIC_CONTINUE},
		{"node": "Off", "label": "Off", "mode": PresentationSettings.MUSIC_OFF},
	]:
		var button := get_node(definition["node"]) as Button
		button.name = "Playlist%02d%s" % [playlist_id, definition["label"]]
		button.disabled = reserved
		button.tooltip_text = "Reserved by Classic; no application context selects this slot." if reserved else "Set %s to %s." % [ClassicMusicContext.context_name(playlist_id), definition["label"]]
		button.pressed.connect(_select_mode.bind(int(definition["mode"])))
		_mode_buttons[int(definition["mode"])] = button


func mode_buttons() -> Dictionary:
	return _mode_buttons.duplicate()


func _select_mode(mode: int) -> void:
	mode_selected.emit(_playlist_id, mode)
