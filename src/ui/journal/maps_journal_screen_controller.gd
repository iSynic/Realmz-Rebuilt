## Binds detached maps, location notes, and journal entries to their authored workspace.
class_name MapsJournalScreenController
extends RefCounted

const WORKSPACE_SCENE_PATH := "res://src/ui/journal/maps_notes_workspace.tscn"

signal intent_submitted(intent: PlayerIntent)

const GOLD := Color("d5b45d")
const CYAN := Color("8fcfd1")
const MUTED := Color("9aa0a8")
const BOOK_PAPER_SELECTED := Color("c3aa70")
const BOOK_INK := Color("30261c")
const BOOK_MUTED_INK := Color("67553a")
const BOOK_RED := Color("963c31")

var _selected_player_map_id: String = ""
var _selected_location_note_id: String = ""
var _selected_journal_message_id: int = 0
var _selected_campaign_id: String = ""
var _selected_tab: int = 0
var _journal_query: String = ""
var _player_map_zoom: float = 1.0
var _text_scale: float = 1.0
var _compact: bool = false
var _rebuilding: bool = false


func set_text_scale(text_scale: float) -> void:
	_text_scale = text_scale


func set_layout_profile(profile_id: StringName) -> void:
	_compact = profile_id == UiLayoutProfile.COMPACT


func present(target: Control, view: GameView, media: ClassicMediaCatalog) -> void:
	if target == null:
		return
	_rebuilding = true
	var screen := target as JournalScreen
	var workspace: MapsNotesWorkspace
	if screen != null:
		screen.prepare_for_render(_compact)
		workspace = screen.workspace()
	else:
		var parent := target as VBoxContainer
		_clear(parent)
		workspace = (load(WORKSPACE_SCENE_PATH) as PackedScene).instantiate() as MapsNotesWorkspace
		parent.add_child(workspace)
		workspace.prepare(_compact)
	if view == null:
		_rebuilding = false
		return
	if _selected_campaign_id != view.campaign_id:
		_selected_campaign_id = view.campaign_id
		_selected_player_map_id = ""
		_selected_location_note_id = ""
		_selected_journal_message_id = 0
		_selected_tab = 0
	_bind_summary(workspace, view)
	_bind_places(workspace, view, media)
	_bind_maps(workspace, view, media)
	_bind_journal(workspace, view)
	var tabs := workspace.tabs()
	tabs.current_tab = mini(_selected_tab, tabs.get_tab_count() - 1)
	if not tabs.tab_changed.is_connected(_on_tab_changed):
		tabs.tab_changed.connect(_on_tab_changed)
	_rebuilding = false


func _on_tab_changed(index: int) -> void:
	if not _rebuilding:
		_selected_tab = index


func _bind_summary(workspace: MapsNotesWorkspace, view: GameView) -> void:
	var maps := view.party_summary.acquired_map_ids.size() if view.party_summary != null else 0
	_bind_label(workspace.summary_label(), "%d places  •  %d maps  •  %d journal entries" % [view.location_notes.size(), maps, view.journal_entries.size()], CYAN, 13)
	workspace.summary_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _bind_places(workspace: MapsNotesWorkspace, view: GameView, media: ClassicMediaCatalog) -> void:
	var rows := workspace.location_note_rows()
	workspace.location_notes_empty().visible = view.location_notes.is_empty()
	var selected := _location_note(view, _selected_location_note_id)
	if selected == null and not view.location_notes.is_empty():
		var current_notes := view.location_notes.filter(func(note: LocationNoteView) -> bool: return note.current)
		selected = current_notes[0] if not current_notes.is_empty() else view.location_notes[0]
		_selected_location_note_id = selected.id
	for note: LocationNoteView in view.location_notes:
		var open := workspace.location_note_row_scene.instantiate() as Button
		open.name = "LocationNote_%d" % note.record_ordinal
		open.text = "%s  •  %d,%d%s\n%s" % [note.map_name, note.coordinate.x, note.coordinate.y, "  •  current" if note.current else "", note.text]
		open.button_pressed = note.id == _selected_location_note_id
		open.set_meta("location_note_id", note.id)
		open.pressed.connect(_select_location_note.bind(workspace, view, media, note.id))
		rows.add_child(open)
	_bind_location_note_preview(workspace, selected, media)
	_bind_location_note_editor(workspace, view)


func _select_location_note(workspace: MapsNotesWorkspace, view: GameView, media: ClassicMediaCatalog, note_id: String) -> void:
	_selected_location_note_id = note_id
	for child: Node in workspace.location_note_rows().get_children():
		if child is Button:
			(child as Button).button_pressed = String(child.get_meta("location_note_id", "")) == note_id
	_bind_location_note_preview(workspace, _location_note(view, note_id), media)


func _bind_location_note_preview(workspace: MapsNotesWorkspace, note: LocationNoteView, media: ClassicMediaCatalog) -> void:
	var facts := workspace.location_preview_facts()
	var empty := workspace.location_preview_empty()
	var presenter := workspace.historical_map()
	var available := note != null and note.preview_map != null
	facts.visible = available
	empty.visible = not available
	presenter.visible = available
	if not available:
		return
	_bind_label(facts.get_node("Location") as Label, "%s  •  %s  •  %d,%d" % [note.map_name, String(note.level_type).capitalize(), note.coordinate.x, note.coordinate.y], CYAN, 14)
	_bind_label(facts.get_node("Darkness") as Label, "Saved darkness mask %d of 6" % clampi(note.darkness_value, 0, 6) if note.darkness_value > 0 else "No saved darkness mask", MUTED, 12)
	presenter.set_classic_exploration_visibility(false)
	presenter.set_media_catalog(media)
	presenter.present(GameView.new(0, true, null, note.map_id, note.coordinate, 0, 0, 0, note.preview_map))


static func _location_note(view: GameView, note_id: String) -> LocationNoteView:
	for note: LocationNoteView in view.location_notes:
		if note.id == note_id:
			return note
	return null


func _bind_location_note_editor(workspace: MapsNotesWorkspace, view: GameView) -> void:
	var current := view.current_location_note
	var editor_area := workspace.location_editor()
	var unavailable := workspace.location_editor_unavailable()
	editor_area.visible = current != null
	unavailable.visible = current == null
	if current == null:
		return
	_bind_label(editor_area.get_node("CurrentLocation") as Label, "%s  •  %d,%d" % [current.map_name, current.coordinate.x, current.coordinate.y], CYAN, 15)
	var editor := editor_area.get_node("CurrentLocationNoteText") as TextEdit
	var count_label := editor_area.get_node("LocationNoteByteCount") as Label
	var save := editor_area.get_node("Actions/SaveLocationNote") as Button
	var revert := editor_area.get_node("Actions/CancelLocationNoteEdit") as Button
	_clear_text_changed_connections(editor)
	_clear_pressed_connections(save)
	_clear_pressed_connections(revert)
	editor.text = current.text
	var availability := view.availability(&"set_location_note")
	var refresh := func() -> void:
		var byte_count := editor.text.to_utf8_buffer().size()
		count_label.text = "%d / %d encoded bytes" % [byte_count, LocationNoteState.MAX_TEXT_BYTES]
		count_label.modulate = Color("d96f6f") if byte_count > LocationNoteState.MAX_TEXT_BYTES else MUTED
		save.disabled = not availability.enabled or editor.text == current.text or byte_count > LocationNoteState.MAX_TEXT_BYTES
		save.tooltip_text = availability.reason if not availability.enabled else "Change the note before saving." if editor.text == current.text else "Classic location notes are limited to 255 encoded bytes." if byte_count > LocationNoteState.MAX_TEXT_BYTES else ""
		revert.disabled = editor.text == current.text
	editor.text_changed.connect(refresh)
	save.pressed.connect(func() -> void: intent_submitted.emit(ExplorationIntents.set_location_note(editor.text)))
	revert.pressed.connect(func() -> void:
		editor.text = current.text
		refresh.call()
	)
	refresh.call()


func _bind_maps(workspace: MapsNotesWorkspace, view: GameView, media: ClassicMediaCatalog) -> void:
	var no_records := view.player_map_menu_entries.is_empty()
	workspace.player_map_browser_empty().visible = no_records
	if no_records:
		workspace.player_map_empty().visible = true
		return
	var selected: PlayerMapView
	for player_map: PlayerMapView in view.acquired_player_maps:
		if player_map.id == _selected_player_map_id:
			selected = player_map
			break
	if selected == null and not view.acquired_player_maps.is_empty():
		selected = view.acquired_player_maps[0]
		_selected_player_map_id = selected.id
	for player_map: PlayerMapView in view.player_map_menu_entries:
		var button := workspace.player_map_row_scene.instantiate() as Button
		button.text = player_map.name if player_map.acquired else player_map.unavailable_name
		button.disabled = not player_map.acquired
		button.tooltip_text = "Map not acquired." if button.disabled else player_map.name
		button.button_pressed = selected != null and player_map.id == selected.id
		button.set_meta("player_map_id", player_map.id)
		if not button.disabled:
			button.pressed.connect(_select_player_map.bind(workspace, view, media, player_map.id))
		workspace.player_map_rows().add_child(button)
	_bind_selected_player_map(workspace, selected, media)


func _select_player_map(workspace: MapsNotesWorkspace, view: GameView, media: ClassicMediaCatalog, player_map_id: String) -> void:
	_selected_player_map_id = player_map_id
	_selected_tab = 1
	for child: Node in workspace.player_map_rows().get_children():
		if child is Button:
			(child as Button).button_pressed = String(child.get_meta("player_map_id", "")) == player_map_id
	var selected: PlayerMapView
	for player_map: PlayerMapView in view.acquired_player_maps:
		if player_map.id == player_map_id:
			selected = player_map
			break
	_bind_selected_player_map(workspace, selected, media)


func _bind_selected_player_map(workspace: MapsNotesWorkspace, selected: PlayerMapView, media: ClassicMediaCatalog) -> void:
	var stage := workspace.player_map_stage()
	var empty := workspace.player_map_empty()
	stage.visible = selected != null
	empty.visible = selected == null
	if selected == null:
		return
	var body := stage.get_node("PlayerMapStageBody") as VBoxContainer
	_bind_label(body.get_node("PlayerMapStageHeader/Header/PlayerMapTitle") as Label, selected.name, GOLD, 19)
	var toolbar := body.get_node("PlayerMapStageHeader/Header/PlayerMapZoomToolbar") as HBoxContainer
	var note := body.get_node("PlayerMapNote") as Label
	var scrolling := body.get_node("AcquiredScrollingPlayerMap") as PlayerMapPresenter
	var scroll := body.get_node("PlayerMapScroll") as ScrollContainer
	var parchment := scroll.get_node("Center/PlayerMapParchmentMat") as PlayerMapParchmentMat
	var presenter := parchment.get_node("AcquiredPlayerMap") as PlayerMapPresenter
	var scrolling_mode := selected.mode == PlayerMapDefinition.SCROLLING_TEXT
	toolbar.visible = not scrolling_mode
	note.visible = not scrolling_mode and not selected.note.is_empty()
	scrolling.visible = scrolling_mode
	scroll.visible = not scrolling_mode
	if scrolling_mode:
		scrolling.present(selected, media)
		return
	_bind_label(note, selected.note, Color("e0e2e5"), 14)
	presenter.present(selected, media)
	presenter.set_map_zoom(_player_map_zoom)
	parchment.set_map_zoom(_player_map_zoom)
	var zoom_label := toolbar.get_node("PlayerMapZoomLabel") as Label
	_bind_label(zoom_label, "%d%%" % roundi(_player_map_zoom * 100.0), CYAN, 14)
	_bind_zoom_button(toolbar.get_node("PlayerMapZoomOut") as Button, presenter, parchment, zoom_label, -0.5)
	_bind_zoom_button(toolbar.get_node("PlayerMapZoomFit") as Button, presenter, parchment, zoom_label, 0.0)
	_bind_zoom_button(toolbar.get_node("PlayerMapZoomIn") as Button, presenter, parchment, zoom_label, 0.5)


func _bind_zoom_button(button: Button, presenter: PlayerMapPresenter, parchment: PlayerMapParchmentMat, label: Label, delta: float) -> void:
	_clear_pressed_connections(button)
	button.pressed.connect(_change_player_map_zoom.bind(presenter, parchment, label, delta))


func _change_player_map_zoom(presenter: PlayerMapPresenter, parchment: PlayerMapParchmentMat, label: Label, delta: float) -> void:
	_player_map_zoom = 1.0 if is_zero_approx(delta) else clampf(_player_map_zoom + delta, 1.0, 4.0)
	presenter.set_map_zoom(_player_map_zoom)
	parchment.set_map_zoom(_player_map_zoom)
	label.text = "%d%%" % roundi(_player_map_zoom * 100.0)


func _bind_journal(workspace: MapsNotesWorkspace, view: GameView) -> void:
	var search := workspace.get_node("MapsNotesTabs/Journal/JournalWorkspace/JournalEntryBrowser/Content/JournalSearch") as LineEdit
	_clear_text_changed_connections(search)
	search.text = _journal_query
	workspace.journal_browser_empty().visible = view.journal_entries.is_empty()
	if view.journal_entries.is_empty():
		_bind_journal_detail(workspace, view)
		return
	if _selected_journal_message_id == 0:
		_selected_journal_message_id = view.journal_entries[0].message_id
	var rows := workspace.journal_entry_rows()
	for entry: JournalEntryView in view.journal_entries:
		var panel := workspace.journal_entry_row_scene.instantiate() as PanelContainer
		var selected := entry.message_id == _selected_journal_message_id
		panel.set_meta("journal_search_text", ("%d %s" % [entry.message_id, entry.text]).to_lower())
		panel.set_meta("journal_message_id", entry.message_id)
		_style_journal_row(panel, selected)
		var open := panel.get_node("Content/Open") as Button
		open.text = "Journal entry %d" % entry.message_id
		open.button_pressed = selected
		_style_journal_button(open, selected)
		open.pressed.connect(_select_journal_entry.bind(workspace, view, entry.message_id))
		var preview_text := entry.text.strip_edges()
		if preview_text.length() > 140:
			preview_text = preview_text.left(137).strip_edges() + "…"
		_bind_label(panel.get_node("Content/Preview") as Label, preview_text, BOOK_MUTED_INK, 13)
		rows.add_child(panel)
	search.text_changed.connect(_filter_journal_rows.bind(rows))
	_filter_journal_rows(_journal_query, rows)
	_bind_journal_detail(workspace, view)


func _select_journal_entry(workspace: MapsNotesWorkspace, view: GameView, message_id: int) -> void:
	_selected_journal_message_id = message_id
	for child: Node in workspace.journal_entry_rows().get_children():
		if child is PanelContainer:
			var selected := int(child.get_meta("journal_message_id", -1)) == message_id
			_style_journal_row(child as PanelContainer, selected)
			var button := child.get_node("Content/Open") as Button
			button.button_pressed = selected
			_style_journal_button(button, selected)
	_bind_journal_detail(workspace, view)


func _filter_journal_rows(query: String, rows: VBoxContainer) -> void:
	_journal_query = query.strip_edges()
	var needle := _journal_query.to_lower()
	for child: Node in rows.get_children():
		if child is Control and child.has_meta("journal_search_text"):
			(child as Control).visible = needle.is_empty() or String(child.get_meta("journal_search_text")).contains(needle)


func _bind_journal_detail(workspace: MapsNotesWorkspace, view: GameView) -> void:
	var record := workspace.journal_detail_record()
	var empty := workspace.journal_detail_empty()
	for entry: JournalEntryView in view.journal_entries:
		if entry.message_id == _selected_journal_message_id:
			record.visible = true
			empty.visible = false
			_bind_label(record.get_node("Title") as Label, "Journal entry %d" % entry.message_id, BOOK_RED, 20)
			_bind_label(record.get_node("JournalEntryText") as Label, entry.text, BOOK_INK, 17)
			return
	record.visible = false
	empty.visible = true
	var message := "No selected entry\nAuthored journal text will appear here." if view.journal_entries.is_empty() else "Entry unavailable\nThe selected journal record no longer exists."
	(empty.get_node("Text") as Label).text = message


func _style_journal_row(panel: PanelContainer, selected: bool) -> void:
	panel.add_theme_stylebox_override("panel", _flat_style(BOOK_PAPER_SELECTED if selected else Color("d8c38e"), BOOK_RED if selected else Color("9a8358"), 2 if selected else 1))


func _style_journal_button(button: Button, selected: bool) -> void:
	button.add_theme_color_override("font_color", BOOK_RED if selected else BOOK_INK)
	button.add_theme_color_override("font_hover_color", BOOK_RED)
	button.add_theme_color_override("font_pressed_color", BOOK_RED)
	button.add_theme_stylebox_override("normal", _flat_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("hover", _flat_style(Color("e0ca96"), Color("9a8358"), 1))
	button.add_theme_stylebox_override("pressed", _flat_style(BOOK_PAPER_SELECTED, BOOK_RED, 1))


static func _flat_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	return style


func _bind_label(label: Label, text: String, color: Color = Color.WHITE, size: int = 15) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * _text_scale)))


static func _clear_pressed_connections(button: Button) -> void:
	for connection: Dictionary in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"] as Callable)


static func _clear_text_changed_connections(control: Control) -> void:
	for connection: Dictionary in control.get_signal_connection_list(&"text_changed"):
		control.disconnect(&"text_changed", connection["callable"] as Callable)


static func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
