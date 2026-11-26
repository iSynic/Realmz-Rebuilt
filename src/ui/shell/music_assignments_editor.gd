## Binds global and scenario music drafts to authored assignment controls.
class_name MusicAssignmentsEditor
extends VBoxContainer

signal changed
signal mode_changed(context: int, mode: int)
signal preview_requested(track_id: String)
signal preview_stopped

const COMPACT_WIDTH := 980.0
const ROW_SCENE_PATH := "res://src/ui/shell/music_assignment_row.tscn"
const SOURCE_INHERIT := 0
const SOURCE_ORIGINAL := 1
const SOURCE_STOCK := 2
const SOURCE_PLAYLIST := 3
const MUSIC_MODES: Array[int] = [PresentationSettings.MUSIC_PLAY, PresentationSettings.MUSIC_CONTINUE, PresentationSettings.MUSIC_OFF]

const MODE_TOOLTIP := "Play: switch to this context's music.\nContinue: keep whatever was already playing.\nOff: silence music in this context.\nModes apply to every scenario."
const GLOBAL_SOURCE_TOOLTIP := "Original music: play the game's or scenario's default track.\nRealmz track: pick any built-in Realmz song (e.g. swap Indoor and Outdoor).\nPlaylist: play one of your custom playlists."
const OUTDOOR_TERRAIN_SOURCE_TOOLTIP := "Use Outdoor: follow whatever is assigned to Outdoor.\nOriginal music: play After the Rain even if Outdoor is customized.\nRealmz track: pick a built-in Realmz song for this terrain.\nPlaylist: play a custom playlist for this terrain."
const SCENARIO_SOURCE_TOOLTIP := "Use global default: follow your Global defaults setting.\nOriginal music: override Global and play this scenario's default track.\nRealmz track: pick any built-in Realmz song for this scenario.\nPlaylist: play one of your custom playlists for this scenario."
const CHOICE_TOOLTIP := "Choose which built-in Realmz track or custom playlist plays for this context."

var _library: MusicLibraryView
var _settings: PresentationSettings
var _campaign := ""
var _title := ""
var _context := 1
var _active_context := 0
var _compact := false
var _rebinding := false
var _table_built := false
var _scope_choice := 0
var _row_scene: PackedScene


func _ready() -> void:
	_row_scene = load(ROW_SCENE_PATH) as PackedScene
	%Scope.item_selected.connect(_scope_changed)
	%GlobalDefaults.pressed.connect(_select_global)
	%StopAssignmentPreview.pressed.connect(func() -> void: preview_stopped.emit())
	%Context.item_selected.connect(_context_changed)
	%Mode.item_selected.connect(_compact_mode_changed)
	%Source.item_selected.connect(_compact_source_changed)
	%Playlist.item_selected.connect(_compact_playlist_changed)
	%CompactPreview.pressed.connect(func() -> void: _preview_context(_context))
	%CompactStopPreview.pressed.connect(func() -> void: preview_stopped.emit())
	resized.connect(_update_layout)
	_update_layout()


func present(library: MusicLibraryView, settings: PresentationSettings, campaign: String, title: String) -> void:
	_library = library
	_settings = settings
	_campaign = campaign
	_title = title
	_rebuild_scope()
	_refresh()


func set_active_context(context: int) -> void:
	if context == _active_context:
		return
	_active_context = context
	if _library != null:
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
	%StopAssignmentPreview.visible = not _compact
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
		var label := ClassicMusicContext.context_name(context)
		if context == _active_context:
			label += " (active)"
		picker.add_item(label, context)
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
			_bind_row(context, row.get_node("Context") as Label, row.get_node("Mode") as OptionButton, row.get_node("Source") as OptionButton, row.get_node("Playlist") as OptionButton, row.get_node("Preview") as Button)
	_update_compact()
	_rebinding = false


func _build_table() -> void:
	var table := %Table as VBoxContainer
	_table_built = true
	for context in range(1, 21):
		var row := _row_scene.instantiate() as HBoxContainer
		row.set_meta("context", context)
		var context_label := row.get_node("Context") as Label
		var mode := row.get_node("Mode") as OptionButton
		var source := row.get_node("Source") as OptionButton
		var playlist := row.get_node("Playlist") as OptionButton
		var preview := row.get_node("Preview") as Button
		mode.item_selected.connect(_row_mode_changed.bind(context))
		source.item_selected.connect(_row_source_changed.bind(context))
		playlist.item_selected.connect(_row_playlist_changed.bind(context))
		preview.pressed.connect(_preview_context.bind(context))
		table.add_child(row)
		_bind_row(context, context_label, mode, source, playlist, preview)


func _bind_row(context: int, context_label: Label, mode: OptionButton, source: OptionButton, choice: OptionButton, preview: Button) -> void:
	var reserved := context > 17
	var is_scenario := not _selected_campaign().is_empty()
	context_label.text = ClassicMusicContext.context_name(context) + ("  (active)" if context == _active_context else "")
	context_label.tooltip_text = _context_tooltip(context, is_scenario)
	mode.select(MUSIC_MODES.find(_settings.music_mode(context)) if _settings != null else 0)
	mode.disabled = reserved
	mode.tooltip_text = MODE_TOOLTIP
	var assignment := _library.assignment(_selected_campaign(), context)
	_bind_source(source, context, assignment, is_scenario, reserved)
	_bind_choice(choice, context, assignment, is_scenario, reserved)
	preview.disabled = reserved or _preview_track_id(context).is_empty()


func _bind_source(source: OptionButton, context: int, assignment: MusicLibraryView.Assignment, is_scenario: bool, reserved: bool) -> void:
	var outdoor_terrain := MusicLibraryView.inherits_outdoor(context)
	var show_explicit_original := is_scenario or outdoor_terrain
	source.clear()
	if is_scenario:
		source.add_item("Use global default", SOURCE_INHERIT)
		source.add_item("Original music", SOURCE_ORIGINAL)
	elif outdoor_terrain:
		source.add_item("Use Outdoor", SOURCE_INHERIT)
		source.add_item("Original music", SOURCE_ORIGINAL)
	else:
		source.add_item("Original music", SOURCE_INHERIT)
	source.add_item("Realmz track", SOURCE_STOCK)
	source.add_item("Playlist", SOURCE_PLAYLIST)
	source.set_item_disabled(source.get_item_index(SOURCE_PLAYLIST), _library.playlists.is_empty())
	var target_id := SOURCE_INHERIT
	if assignment.kind == "stock":
		target_id = SOURCE_STOCK
	elif assignment.kind == "playlist":
		target_id = SOURCE_PLAYLIST
	elif assignment.kind == "original" and show_explicit_original:
		target_id = SOURCE_ORIGINAL
	source.select(source.get_item_index(target_id))
	source.disabled = reserved
	source.tooltip_text = SCENARIO_SOURCE_TOOLTIP if is_scenario else (OUTDOOR_TERRAIN_SOURCE_TOOLTIP if outdoor_terrain else GLOBAL_SOURCE_TOOLTIP)


func _bind_choice(choice: OptionButton, context: int, assignment: MusicLibraryView.Assignment, is_scenario: bool, reserved: bool) -> void:
	choice.clear()
	choice.tooltip_text = CHOICE_TOOLTIP
	if reserved:
		choice.disabled = true
		return
	if assignment.kind == "stock":
		var selected_stock := 0
		for slot: int in range(1, MusicLibraryView.STOCK_TRACK_TITLES.size() + 1):
			var stock_id := MusicLibraryView.stock_track_id(slot)
			choice.add_item(MusicLibraryView.stock_track_label(stock_id))
			choice.set_item_metadata(choice.item_count - 1, stock_id)
			if stock_id == assignment.track_id:
				selected_stock = choice.item_count - 1
		choice.select(selected_stock)
		choice.disabled = false
		return
	if assignment.kind == "playlist":
		var selected := -1
		for id: String in _library.playlists:
			var item := _library.playlists[id]
			var label := item.name + (" (empty)" if item.tracks.is_empty() else "")
			choice.add_item(label)
			choice.set_item_metadata(choice.item_count - 1, id)
			if id == assignment.playlist_id:
				selected = choice.item_count - 1
		if selected >= 0:
			choice.select(selected)
		choice.disabled = choice.item_count == 0
		return
	choice.add_item(_resolved_default_summary(context, assignment, is_scenario))
	choice.select(0)
	choice.disabled = true


func _resolved_default_summary(context: int, assignment: MusicLibraryView.Assignment, is_scenario: bool) -> String:
	if is_scenario and assignment.kind == "inherit":
		var global_choice := _library.assignment("", context)
		if global_choice.kind == "playlist" and _library.playlists.has(global_choice.playlist_id):
			return "Global: " + _library.playlists[global_choice.playlist_id].name
		if global_choice.kind == "stock" and MusicLibraryView.is_stock_track_id(global_choice.track_id):
			return "Global: " + MusicLibraryView.stock_track_label(global_choice.track_id)
		if global_choice.kind == "inherit" and MusicLibraryView.inherits_outdoor(context):
			return "Outdoor: " + _resolved_outdoor_label(_selected_campaign())
		return "Global: " + _default_track_summary(context)
	if assignment.kind == "inherit" and MusicLibraryView.inherits_outdoor(context):
		return "Outdoor: " + _resolved_outdoor_label("")
	return _default_track_summary(context)


func _resolved_outdoor_label(campaign: String) -> String:
	var outdoor := _library.resolve(campaign, 1)
	if outdoor != null:
		return outdoor.name
	return _default_track_summary(1)


func _default_track_summary(context: int) -> String:
	if context >= 1 and context <= 11:
		return MusicLibraryView.stock_track_label(MusicLibraryView.stock_track_id(context))
	if context >= 12 and context <= 14:
		return MusicLibraryView.stock_track_label("stock:1")
	if context >= 15 and context <= 17:
		return "Scenario track"
	return ""


func _context_tooltip(context: int, is_scenario: bool) -> String:
	var lines: Array[String] = []
	if context == _active_context:
		lines.append("Currently playing context.")
	if MusicLibraryView.inherits_outdoor(context):
		lines.append("Follows Outdoor automatically unless given its own assignment.")
	if not is_scenario and not _campaign.is_empty():
		var override := _library.assignment(_campaign, context)
		if override.kind != "inherit":
			lines.append("Overridden in %s." % (_title if not _title.is_empty() else "the current scenario"))
	return "\n".join(lines)


func _update_compact() -> void:
	if _library == null:
		return
	_rebuild_context_picker()
	var context := _context
	var reserved := context > 17
	var is_scenario := not _selected_campaign().is_empty()
	%CompactTitle.text = ClassicMusicContext.context_name(context)
	var mode := _settings.music_mode(context) if _settings != null else PresentationSettings.MUSIC_PLAY
	var mode_picker := %Mode as OptionButton
	mode_picker.select(MUSIC_MODES.find(mode))
	mode_picker.disabled = reserved
	mode_picker.tooltip_text = MODE_TOOLTIP
	var assignment := _library.assignment(_selected_campaign(), context)
	_bind_source(%Source as OptionButton, context, assignment, is_scenario, reserved)
	_bind_choice(%Playlist as OptionButton, context, assignment, is_scenario, reserved)
	(%CompactPreview as Button).disabled = reserved or _preview_track_id(context).is_empty()
	%Reserved.visible = reserved
	%CompactFields.visible = not reserved


func _preview_track_id(context: int) -> String:
	if _library == null or context < 1 or context > 17:
		return ""
	var resolved := _library.resolve(_selected_campaign(), context)
	if resolved != null:
		return resolved.tracks[0] if not resolved.tracks.is_empty() else ""
	if context <= 11:
		return MusicLibraryView.stock_track_id(context)
	if context <= 14:
		return "stock:1"
	return ""


func _preview_context(context: int) -> void:
	var track_id := _preview_track_id(context)
	if not track_id.is_empty():
		preview_requested.emit(track_id)


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
	_set_mode(context, MUSIC_MODES[index])


func _compact_mode_changed(index: int) -> void:
	_set_mode(_context, MUSIC_MODES[index])


func _set_mode(context: int, mode: int) -> void:
	if _rebinding or _settings == null or context > 17:
		return
	_settings.set_music_mode(context, mode)
	mode_changed.emit(context, mode)
	_refresh()


func _row_source_changed(index: int, context: int) -> void:
	var table := %Table as VBoxContainer
	var row := table.get_child(context - 1) as HBoxContainer
	var source := row.get_node("Source") as OptionButton
	_apply_source(context, source.get_item_id(index))


func _compact_source_changed(index: int) -> void:
	_apply_source(_context, (%Source as OptionButton).get_item_id(index))


func _compact_playlist_changed(index: int) -> void:
	if _rebinding or index < 0:
		return
	_apply_choice(_context, String((%Playlist as OptionButton).get_item_metadata(index)))


func _row_playlist_changed(index: int, context: int) -> void:
	if _rebinding or index < 0:
		return
	var table := %Table as VBoxContainer
	var row := table.get_child(context - 1) as HBoxContainer
	_apply_choice(context, String((row.get_node("Playlist") as OptionButton).get_item_metadata(index)))


func _apply_source(context: int, source_id: int) -> void:
	if _rebinding or context > 17:
		return
	var current := _library.assignment(_selected_campaign(), context)
	if source_id == SOURCE_PLAYLIST:
		var playlist_id := current.playlist_id if _library.playlists.has(current.playlist_id) else _library.first_playlist_id()
		if playlist_id.is_empty():
			_refresh()
			return
		_set_assignment(context, "playlist", playlist_id)
		return
	if source_id == SOURCE_STOCK:
		var track_id := current.track_id if MusicLibraryView.is_stock_track_id(current.track_id) else MusicLibraryView.stock_track_id(context if context <= 11 else 1)
		_set_assignment(context, "stock", track_id)
		return
	_set_assignment(context, "original" if source_id == SOURCE_ORIGINAL else "inherit", "")


func _apply_choice(context: int, target_id: String) -> void:
	if _rebinding or context > 17 or target_id.is_empty():
		return
	var current := _library.assignment(_selected_campaign(), context)
	if current.kind == "stock" and MusicLibraryView.is_stock_track_id(target_id):
		_set_assignment(context, "stock", target_id)
	elif current.kind == "playlist" and _library.playlists.has(target_id):
		_set_assignment(context, "playlist", target_id)


func _set_assignment(context: int, kind: String, target_id: String) -> void:
	if _rebinding or context > 17:
		return
	_library.set_assignment(_selected_campaign(), context, kind, target_id)
	_refresh()
	changed.emit()
