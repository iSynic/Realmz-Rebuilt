## Binds global and scenario music drafts to authored assignment controls.
class_name MusicAssignmentsEditor
extends VBoxContainer

signal changed
signal mode_changed(context: int, mode: int)

const COMPACT_WIDTH := 980.0
const ROW_SCENE_PATH := "res://src/ui/shell/music_assignment_row.tscn"
const SOURCE_PLAYLIST := 2

var _library: MusicLibraryView
var _settings: PresentationSettings
var _campaign := ""
var _title := ""
var _context := 1
var _compact := false
var _rebinding := false
var _table_built := false
var _scope_choice := 0
var _row_scene: PackedScene


func _ready() -> void:
	_row_scene = load(ROW_SCENE_PATH) as PackedScene
	%Scope.item_selected.connect(_scope_changed)
	%GlobalDefaults.pressed.connect(_select_global)
	%Context.item_selected.connect(_context_changed)
	%Mode.item_selected.connect(_compact_mode_changed)
	%Source.item_selected.connect(_compact_source_changed)
	%Playlist.item_selected.connect(_compact_playlist_changed)
	resized.connect(_update_layout)
	_update_layout()


func present(library: MusicLibraryView, settings: PresentationSettings, campaign: String, title: String) -> void:
	_library = library
	_settings = settings
	_campaign = campaign
	_title = title
	_rebuild_scope()
	_refresh()


func refresh_playlists() -> void:
	if _library != null:
		_refresh()


func _update_layout() -> void:
	var use_compact := size.x < COMPACT_WIDTH
	if use_compact == _compact:
		return
	_compact = use_compact
	%Wide.visible = not _compact
	%Compact.visible = _compact
	%GlobalDefaults.visible = not _compact
	_rebuild_context_picker()
	_refresh()


func _rebuild_scope() -> void:
	var scope := %Scope as OptionButton
	var preserve_scenario := _scope_choice == 1 and not _campaign.is_empty()
	scope.clear()
	scope.add_item("Global defaults", 0)
	scope.add_item(_title if not _title.is_empty() else "Current scenario", 1)
	scope.set_item_disabled(1, _campaign.is_empty())
	_scope_choice = 1 if preserve_scenario else 0
	scope.select(_scope_choice)
	%ScenarioUnavailable.visible = _campaign.is_empty()


func _rebuild_context_picker() -> void:
	var picker := %Context as OptionButton
	picker.clear()
	for context in range(1, 21):
		picker.add_item(ClassicMusicContext.context_name(context), context)
		picker.set_item_disabled(picker.item_count - 1, context > 17)
	picker.select(_context - 1)


func _refresh() -> void:
	if _library == null:
		return
	_rebinding = true
	if not _table_built:
		_build_table()
	else:
		var table := %Table as VBoxContainer
		for row: HBoxContainer in table.get_children():
			var context := int(row.get_meta("context"))
			_bind_row(context, row.get_node("Mode"), row.get_node("Source"), row.get_node("Playlist"))
	_update_compact()
	_rebinding = false


func _build_table() -> void:
	var table := %Table as VBoxContainer
	_table_built = true
	for context in range(1, 21):
		var row := _row_scene.instantiate() as HBoxContainer
		row.set_meta("context", context)
		row.get_node("Context").text = ClassicMusicContext.context_name(context)
		var mode := row.get_node("Mode") as OptionButton
		var source := row.get_node("Source") as OptionButton
		var playlist := row.get_node("Playlist") as OptionButton
		mode.item_selected.connect(_row_mode_changed.bind(context))
		source.item_selected.connect(_row_source_changed.bind(context))
		playlist.item_selected.connect(_row_playlist_changed.bind(context))
		table.add_child(row)
		_bind_row(context, mode, source, playlist)


func _bind_row(context: int, mode: OptionButton, source: OptionButton, playlist: OptionButton) -> void:
	var reserved := context > 17
	mode.select([PresentationSettings.MUSIC_PLAY, PresentationSettings.MUSIC_CONTINUE, PresentationSettings.MUSIC_OFF].find(_settings.music_mode(context)) if _settings != null else 0)
	mode.disabled = reserved
	var assignment := _library.assignment(_selected_campaign(), context)
	source.select(["inherit", "original", "playlist"].find(assignment.kind))
	source.set_item_disabled(SOURCE_PLAYLIST, _library.playlists.is_empty())
	source.disabled = reserved
	_bind_playlists(playlist, assignment.playlist_id)
	playlist.disabled = reserved or assignment.kind != "playlist" or playlist.item_count == 0


func _bind_playlists(playlist: OptionButton, selected_id: String) -> void:
	playlist.clear()
	var selected := -1
	for id: String in _library.playlists:
		playlist.add_item(_library.playlists[id].name)
		playlist.set_item_metadata(playlist.item_count - 1, id)
		if id == selected_id:
			selected = playlist.item_count - 1
	if selected >= 0:
		playlist.select(selected)


func _update_compact() -> void:
	if _library == null:
		return
	_rebuild_context_picker()
	var context := _context
	var reserved := context > 17
	%CompactTitle.text = ClassicMusicContext.context_name(context)
	var mode := _settings.music_mode(context) if _settings != null else PresentationSettings.MUSIC_PLAY
	%Mode.select([PresentationSettings.MUSIC_PLAY, PresentationSettings.MUSIC_CONTINUE, PresentationSettings.MUSIC_OFF].find(mode))
	%Mode.disabled = reserved
	var assignment := _library.assignment(_selected_campaign(), context)
	%Source.select(["inherit", "original", "playlist"].find(assignment.kind))
	(%Source as OptionButton).set_item_disabled(SOURCE_PLAYLIST, _library.playlists.is_empty())
	%Source.disabled = reserved
	_bind_playlists(%Playlist, assignment.playlist_id)
	%Playlist.disabled = reserved or assignment.kind != "playlist" or %Playlist.item_count == 0
	%Reserved.visible = reserved
	%CompactFields.visible = not reserved


func _selected_campaign() -> String:
	return _campaign if _scope_choice == 1 and not _campaign.is_empty() else ""


func _scope_changed(index: int) -> void:
	_scope_choice = index
	_refresh()


func _select_global() -> void:
	(%Scope as OptionButton).select(0)
	_scope_choice = 0
	_refresh()


func _context_changed(index: int) -> void:
	_context = index + 1
	_refresh()


func _row_mode_changed(index: int, context: int) -> void:
	_set_mode(context, [PresentationSettings.MUSIC_PLAY, PresentationSettings.MUSIC_CONTINUE, PresentationSettings.MUSIC_OFF][index])


func _compact_mode_changed(index: int) -> void:
	_set_mode(_context, [PresentationSettings.MUSIC_PLAY, PresentationSettings.MUSIC_CONTINUE, PresentationSettings.MUSIC_OFF][index])


func _set_mode(context: int, mode: int) -> void:
	if _rebinding or _settings == null or context > 17:
		return
	_settings.set_music_mode(context, mode)
	mode_changed.emit(context, mode)
	_refresh()


func _row_source_changed(index: int, context: int) -> void:
	_assign(context, index)


func _compact_source_changed(index: int) -> void:
	_assign(_context, index)


func _compact_playlist_changed(index: int) -> void:
	if _rebinding or index < 0:
		return
	_set_assignment(_context, SOURCE_PLAYLIST, String((%Playlist as OptionButton).get_item_metadata(index)))


func _row_playlist_changed(index: int, context: int) -> void:
	if _rebinding or index < 0:
		return
	var table := %Table as VBoxContainer
	var row := table.get_child(context - 1) as HBoxContainer
	_set_assignment(context, SOURCE_PLAYLIST, String((row.get_node("Playlist") as OptionButton).get_item_metadata(index)))


func _assign(context: int, index: int) -> void:
	if _rebinding or context > 17:
		return
	_set_assignment(context, index, "")


func _set_assignment(context: int, index: int, playlist_id: String) -> void:
	if _rebinding or context > 17 or index < 0 or index > SOURCE_PLAYLIST:
		return
	if index == SOURCE_PLAYLIST and _library.playlists.is_empty():
		_refresh()
		return
	var kind: String = ["inherit", "original", "playlist"][index]
	_library.set_assignment(_selected_campaign(), context, kind, playlist_id)
	_refresh()
	changed.emit()
