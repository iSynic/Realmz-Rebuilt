## Edits global or stable-campaign assignments while retaining Classic modes.
class_name MusicAssignmentsEditor
extends HBoxContainer

signal changed
signal mode_changed(context: int, mode: int)

var _library: MusicLibraryView
var _settings: PresentationSettings
var _campaign: String = ""
var _context: int = 1


func _ready() -> void:
	for context: int in range(1, 21):
		(%Contexts as ItemList).add_item(ClassicMusicContext.context_name(context))
	(%Contexts as ItemList).select(0)
	%Contexts.item_selected.connect(_context_changed)
	%AssignmentScope.item_selected.connect(func(_index: int) -> void: _refresh())
	%AssignmentKind.item_selected.connect(_assignment_changed)
	%AssignmentPlaylist.item_selected.connect(func(_index: int) -> void: _assignment_changed(2))
	%ModePlay.pressed.connect(_mode_changed.bind(PresentationSettings.MUSIC_PLAY))
	%ModeContinue.pressed.connect(_mode_changed.bind(PresentationSettings.MUSIC_CONTINUE))
	%ModeOff.pressed.connect(_mode_changed.bind(PresentationSettings.MUSIC_OFF))


func present(library: MusicLibraryView, settings: PresentationSettings, campaign: String, title: String) -> void:
	_library = library
	_settings = settings
	_campaign = campaign
	var scope := %AssignmentScope as OptionButton
	var previous := scope.selected
	scope.clear()
	scope.add_item("Global defaults")
	scope.add_item(title if not title.is_empty() else "Current scenario")
	scope.set_item_disabled(1, campaign.is_empty())
	scope.select(previous if previous >= 0 and not campaign.is_empty() else 0)
	_refresh()


func refresh_playlists() -> void:
	if _library != null:
		_refresh()


func _context_changed(index: int) -> void:
	_context = index + 1
	_refresh()


func _refresh() -> void:
	if _library == null:
		return
	var campaign := _campaign if (%AssignmentScope as OptionButton).selected == 1 else ""
	var assignment := _library.assignment(campaign, _context)
	var reserved := _context > 17
	(%AssignmentKind as OptionButton).select(["inherit", "original", "playlist"].find(assignment.kind))
	(%AssignmentKind as OptionButton).disabled = reserved
	var list := %AssignmentPlaylist as OptionButton
	list.clear()
	for id: String in _library.playlists:
		list.add_item(_library.playlists[id].name)
		list.set_item_metadata(list.item_count - 1, id)
		if id == assignment.playlist_id:
			list.select(list.item_count - 1)
	list.disabled = reserved or assignment.kind != "playlist" or list.item_count == 0
	var mode := _settings.music_mode(_context) if _settings != null else PresentationSettings.MUSIC_PLAY
	(%ModePlay as Button).set_pressed_no_signal(mode == PresentationSettings.MUSIC_PLAY)
	(%ModeContinue as Button).set_pressed_no_signal(mode == PresentationSettings.MUSIC_CONTINUE)
	(%ModeOff as Button).set_pressed_no_signal(mode == PresentationSettings.MUSIC_OFF)
	for button: Button in [%ModePlay, %ModeContinue, %ModeOff]:
		button.disabled = reserved
	var inherited := _library.resolve(campaign, _context)
	(%AssignmentSummary as Label).text = "Reserved Classic slot; no playback context." if reserved else "Effective music: " + (inherited.name if inherited != null else "Original music")


func _assignment_changed(index: int) -> void:
	var list := %AssignmentPlaylist as OptionButton
	var kind: String = ["inherit", "original", "playlist"][index]
	if kind == "playlist" and list.item_count == 0:
		(%AssignmentSummary as Label).text = "Create a playlist in the Playlists tab first."
		return
	var campaign := _campaign if (%AssignmentScope as OptionButton).selected == 1 else ""
	var playlist_id := String(list.get_item_metadata(list.selected)) if kind == "playlist" else ""
	_library.set_assignment(campaign, _context, kind, playlist_id)
	_refresh()
	changed.emit()


func _mode_changed(mode: int) -> void:
	if _settings != null:
		_settings.set_music_mode(_context, mode)
	mode_changed.emit(_context, mode)
	_refresh()
