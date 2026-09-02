class_name MapsJournalWorkspaceController
extends RefCounted

const PlayerMapCartographicStageType := preload("res://src/presentation/screens/player_map_cartographic_stage.gd")
const PlayerMapParchmentMatType := preload("res://src/presentation/screens/player_map_parchment_mat.gd")
const ClassicMapPresenterType := preload("res://src/presentation/classic_map_presenter.gd")

signal intent_submitted(intent: PlayerIntent)

const GOLD := Color("d5b45d")
const CYAN := Color("8fcfd1")
const MUTED := Color("9aa0a8")
const COOL_SURFACE := Color("202729")
const COOL_BORDER := Color("596266")
const BOOK_LEATHER := Color("4b2822")
const BOOK_PAPER := Color("d3bd86")
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
var _journal_detail: VBoxContainer
var _rebuilding: bool = false


func set_text_scale(text_scale: float) -> void:
	_text_scale = text_scale


func present(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog) -> void:
	_rebuilding = true
	_clear(parent)
	if view == null:
		_rebuilding = false
		return
	if _selected_campaign_id != view.campaign_id:
		_selected_campaign_id = view.campaign_id
		_selected_player_map_id = ""
		_selected_location_note_id = ""
		_selected_journal_message_id = 0
		_selected_tab = 0
	_add_header(parent, view)
	var tabs := TabContainer.new()
	tabs.name = "MapsNotesTabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(tabs)
	_build_places_tab(_tab(tabs, "Places"), view, media)
	_build_maps_tab(_tab(tabs, "Maps"), view, media)
	_build_journal_tab(_tab(tabs, "Journal"), view)
	tabs.current_tab = mini(_selected_tab, tabs.get_tab_count() - 1)
	tabs.tab_changed.connect(func(index: int) -> void:
		if not _rebuilding and tabs.get_parent() != null:
			_selected_tab = index
	)
	_rebuilding = false


func _add_header(parent: VBoxContainer, view: GameView) -> void:
	var row := HBoxContainer.new()
	row.name = "MapsNotesHeader"
	parent.add_child(row)
	var maps := view.party_summary.acquired_map_ids.size() if view.party_summary != null else 0
	var facts := _label("%d places  •  %d maps  •  %d journal entries" % [view.location_notes.size(), maps, view.journal_entries.size()], CYAN, 13)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(facts)


func _build_places_tab(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog) -> void:
	var columns := _columns(parent, "LocationNotesWorkspace")
	var saved := _pane(columns, "SavedLocationNotes", "Saved Places", 0.8)
	_style_pane(saved, COOL_SURFACE, COOL_BORDER, 2)
	var scroll := _scroll("SavedLocationNoteScroll")
	saved.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "SavedLocationNoteRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	if view.location_notes.is_empty():
		_add_empty_state(rows, "No saved places", "Write a note at the current location to create the first record.")
	else:
		var selected := _location_note(view, _selected_location_note_id)
		if selected == null:
			selected = view.location_notes.filter(func(note: LocationNoteView) -> bool: return note.current).front() if view.location_notes.any(func(note: LocationNoteView) -> bool: return note.current) else view.location_notes[0]
			_selected_location_note_id = selected.id
		for note: LocationNoteView in view.location_notes:
			var open := Button.new()
			open.name = "LocationNote_%d" % note.record_ordinal
			open.text = "%s  •  %d,%d%s\n%s" % [note.map_name, note.coordinate.x, note.coordinate.y, "  •  current" if note.current else "", note.text]
			open.alignment = HORIZONTAL_ALIGNMENT_LEFT
			open.toggle_mode = true
			open.button_pressed = note.id == _selected_location_note_id
			open.set_meta("location_note_id", note.id)
			open.pressed.connect(_select_location_note.bind(parent, view, media, note.id))
			rows.add_child(open)
	var current := _pane(columns, "CurrentLocationNotePane", "Selected Place & Current Note", 1.25)
	_style_pane(current, Color("222829"), COOL_BORDER, 2)
	var preview := VBoxContainer.new()
	preview.name = "LocationNotePreviewBody"
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	current.add_child(preview)
	_render_location_note_preview(preview, _location_note(view, _selected_location_note_id), media)
	current.add_child(HSeparator.new())
	_render_location_note_editor(current, view)


func _select_location_note(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, note_id: String) -> void:
	_selected_location_note_id = note_id
	var rows := parent.find_child("SavedLocationNoteRows", true, false)
	if rows != null:
		for child: Node in rows.find_children("LocationNote_*", "Button", true, false):
			(child as Button).button_pressed = String(child.get_meta("location_note_id", "")) == note_id
	var preview := parent.find_child("LocationNotePreviewBody", true, false) as VBoxContainer
	if preview != null:
		_clear(preview)
		_render_location_note_preview(preview, _location_note(view, note_id), media)


func _render_location_note_preview(parent: VBoxContainer, note: LocationNoteView, media: ClassicMediaCatalog) -> void:
	if note == null or note.preview_map == null:
		_add_empty_state(parent, "No selected place", "Choose a saved note to recenter its detached map view.")
		return
	_add_label(parent, "%s  •  %s  •  %d,%d" % [note.map_name, String(note.level_type).capitalize(), note.coordinate.x, note.coordinate.y], CYAN, 14)
	_add_label(parent, "Saved darkness mask %d of 6" % clampi(note.darkness_value, 0, 6) if note.darkness_value > 0 else "No saved darkness mask", MUTED, 12)
	var presenter := ClassicMapPresenterType.new()
	presenter.name = "HistoricalLocationMap"
	presenter.custom_minimum_size = Vector2(0, 260)
	presenter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	presenter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	presenter.cell_size = 20.0
	parent.add_child(presenter)
	presenter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	presenter.set_classic_exploration_visibility(false)
	presenter.set_media_catalog(media)
	presenter.present(GameView.new(0, true, null, note.map_id, note.coordinate, 0, 0, 0, note.preview_map))


static func _location_note(view: GameView, note_id: String) -> LocationNoteView:
	for note: LocationNoteView in view.location_notes:
		if note.id == note_id:
			return note
	return null


func _build_maps_tab(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog) -> void:
	var columns := _columns(parent, "AcquiredMapsWorkspace")
	var browser := _pane(columns, "PlayerMapBrowser", "Acquired Maps", 0.5)
	var display := VBoxContainer.new()
	display.name = "PlayerMapDisplay"
	display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	display.size_flags_stretch_ratio = 2.5
	columns.add_child(display)
	_style_pane(browser, COOL_SURFACE, COOL_BORDER, 2)
	if view.player_map_menu_entries.is_empty():
		_add_empty_state(browser, "No player-map records", "This campaign supplies no Maps/Notes entries.")
		_add_empty_state(display, "No selected map", "There is no authored map record to display.")
		return
	var selected: PlayerMapView
	for player_map: PlayerMapView in view.acquired_player_maps:
		if player_map.id == _selected_player_map_id:
			selected = player_map
			break
	if selected == null and not view.acquired_player_maps.is_empty():
		selected = view.acquired_player_maps[0]
		_selected_player_map_id = selected.id
	var chooser := VBoxContainer.new()
	chooser.name = "AcquiredMapChooser"
	chooser.add_theme_constant_override("separation", 4)
	browser.add_child(chooser)
	var route_body := parent.get_parent().get_parent() as VBoxContainer
	for player_map: PlayerMapView in view.player_map_menu_entries:
		var button := Button.new()
		button.text = player_map.name if player_map.acquired else player_map.unavailable_name
		button.toggle_mode = true
		button.disabled = not player_map.acquired
		button.tooltip_text = "Map not acquired." if button.disabled else player_map.name
		button.button_pressed = selected != null and player_map.id == selected.id
		button.set_meta("player_map_id", player_map.id)
		button.custom_minimum_size.y = 38.0
		if not button.disabled:
			button.pressed.connect(_select_player_map.bind(route_body, view, media, player_map.id))
		chooser.add_child(button)
	var display_body := VBoxContainer.new()
	display_body.name = "PlayerMapDisplayBody"
	display_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	display.add_child(display_body)
	_render_selected_player_map(display_body, selected, media)


func _select_player_map(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, player_map_id: String) -> void:
	_selected_player_map_id = player_map_id
	_selected_tab = 1
	var chooser := parent.find_child("AcquiredMapChooser", true, false)
	if chooser != null:
		for child: Node in chooser.find_children("*", "Button", true, false):
			(child as Button).button_pressed = String(child.get_meta("player_map_id", "")) == player_map_id
	var display_body := parent.find_child("PlayerMapDisplayBody", true, false) as VBoxContainer
	var selected: PlayerMapView
	for player_map: PlayerMapView in view.acquired_player_maps:
		if player_map.id == player_map_id:
			selected = player_map
			break
	if display_body != null:
		_clear(display_body)
		_render_selected_player_map(display_body, selected, media)


func _render_selected_player_map(parent: VBoxContainer, selected: PlayerMapView, media: ClassicMediaCatalog) -> void:
	if selected == null:
		_add_empty_state(parent, "No acquired maps", "Maps remain unavailable until the session records their acquisition.")
		return
	var stage := PlayerMapCartographicStageType.new()
	parent.add_child(stage)
	var stage_body := VBoxContainer.new()
	stage_body.name = "PlayerMapStageBody"
	stage_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_body.add_theme_constant_override("separation", 2)
	stage.add_child(stage_body)
	var header_panel := PanelContainer.new()
	header_panel.name = "PlayerMapStageHeader"
	header_panel.theme_type_variation = &"ClassicInset"
	header_panel.custom_minimum_size.y = 30.0
	stage_body.add_child(header_panel)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header_panel.add_child(header)
	var title := _label(selected.name, GOLD, 19)
	title.name = "PlayerMapTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var toolbar := HBoxContainer.new()
	toolbar.name = "PlayerMapZoomToolbar"
	toolbar.alignment = BoxContainer.ALIGNMENT_END
	header.add_child(toolbar)
	var zoom_out := _map_zoom_button("PlayerMapZoomOut", "−", -0.5)
	toolbar.add_child(zoom_out)
	var zoom_label := _label("%d%%" % roundi(_player_map_zoom * 100.0), CYAN, 14)
	zoom_label.name = "PlayerMapZoomLabel"
	toolbar.add_child(zoom_label)
	var fit := _map_zoom_button("PlayerMapZoomFit", "Fit", 0.0)
	toolbar.add_child(fit)
	var zoom_in := _map_zoom_button("PlayerMapZoomIn", "+", 0.5)
	toolbar.add_child(zoom_in)
	if selected.mode == PlayerMapDefinition.SCROLLING_TEXT:
		toolbar.visible = false
		var scrolling_presenter := PlayerMapPresenter.new()
		scrolling_presenter.name = "AcquiredPlayerMap"
		scrolling_presenter.present(selected, media)
		stage_body.add_child(scrolling_presenter)
		return
	if not selected.note.is_empty():
		var note := _label(selected.note, Color("e0e2e5"), 14)
		note.name = "PlayerMapNote"
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stage_body.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.name = "PlayerMapScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_body.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(center)
	var parchment := PlayerMapParchmentMatType.new()
	center.add_child(parchment)
	var presenter := PlayerMapPresenter.new()
	presenter.name = "AcquiredPlayerMap"
	presenter.present(selected, media)
	presenter.set_map_zoom(_player_map_zoom)
	parchment.set_map_zoom(_player_map_zoom)
	parchment.add_child(presenter)
	for button: Button in [zoom_out, fit, zoom_in]:
		button.pressed.connect(_change_player_map_zoom.bind(presenter, parchment, zoom_label, float(button.get_meta("zoom_delta"))))


func _map_zoom_button(node_name: String, text: String, delta: float) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(46, 26)
	button.set_meta("zoom_delta", delta)
	return button


func _change_player_map_zoom(presenter: PlayerMapPresenter, parchment, label: Label, delta: float) -> void:
	_player_map_zoom = 1.0 if is_zero_approx(delta) else clampf(_player_map_zoom + delta, 1.0, 4.0)
	presenter.set_map_zoom(_player_map_zoom)
	parchment.set_map_zoom(_player_map_zoom)
	label.text = "%d%%" % roundi(_player_map_zoom * 100.0)


func _build_journal_tab(parent: VBoxContainer, view: GameView) -> void:
	var columns := _columns(parent, "JournalWorkspace")
	columns.add_theme_constant_override("separation", 4)
	var browser := _pane(columns, "JournalEntryBrowser", "Journal Entries", 1.0)
	var detail := _pane(columns, "JournalEntryDetail", "Selected Entry", 1.0)
	_style_pane(browser, BOOK_PAPER, BOOK_LEATHER, 2)
	_style_pane(detail, BOOK_PAPER, BOOK_LEATHER, 2)
	_style_pane_heading(browser, BOOK_RED)
	_style_pane_heading(detail, BOOK_RED)
	var spine := ColorRect.new()
	spine.name = "JournalBookSpine"
	spine.custom_minimum_size.x = 12.0
	spine.color = BOOK_LEATHER
	spine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(spine)
	columns.move_child(spine, 1)
	var search := LineEdit.new()
	search.name = "JournalSearch"
	search.theme_type_variation = &"ClassicTheldrowLineEdit"
	search.placeholder_text = "Search journal…"
	search.clear_button_enabled = true
	search.text = _journal_query
	search.add_theme_color_override("font_color", BOOK_INK)
	search.add_theme_color_override("font_placeholder_color", BOOK_MUTED_INK)
	search.add_theme_stylebox_override("normal", _flat_style(Color("dfcca0"), Color("89734c"), 1))
	search.add_theme_stylebox_override("focus", _flat_style(Color("e5d4aa"), BOOK_RED, 2))
	browser.add_child(search)
	_journal_detail = VBoxContainer.new()
	_journal_detail.name = "JournalEntryDetailBody"
	_journal_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal_detail.add_theme_constant_override("separation", 5)
	var detail_scroll := _scroll("JournalEntryDetailScroll")
	detail.add_child(detail_scroll)
	detail_scroll.add_child(_journal_detail)
	if view.journal_entries.is_empty():
		_add_empty_state(browser, "The journal is empty", "No journal records were supplied by the current session.")
		_add_empty_state(_journal_detail, "No selected entry", "Authored journal text will appear here.")
		return
	if _selected_journal_message_id == 0:
		_selected_journal_message_id = view.journal_entries[0].message_id
	var scroll := _scroll("JournalEntryScroll")
	browser.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "JournalEntryRows"
	rows.add_theme_constant_override("separation", 4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for entry: JournalEntryView in view.journal_entries:
		var panel := PanelContainer.new()
		var selected := entry.message_id == _selected_journal_message_id
		panel.add_theme_stylebox_override("panel", _flat_style(BOOK_PAPER_SELECTED if selected else Color("d8c38e"), BOOK_RED if selected else Color("9a8358"), 2 if selected else 1))
		panel.set_meta("journal_search_text", ("%d %s" % [entry.message_id, entry.text]).to_lower())
		rows.add_child(panel)
		var record := VBoxContainer.new()
		panel.add_child(record)
		var open := Button.new()
		open.text = "Journal entry %d" % entry.message_id
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open.toggle_mode = true
		open.button_pressed = selected
		_style_journal_button(open, selected)
		open.pressed.connect(_select_journal_entry.bind(view, entry.message_id))
		record.add_child(open)
		var preview_text := entry.text.strip_edges()
		if preview_text.length() > 140:
			preview_text = preview_text.left(137).strip_edges() + "…"
		var preview := _label(preview_text, BOOK_MUTED_INK, 13)
		preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview.max_lines_visible = 2
		preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		record.add_child(preview)
	search.text_changed.connect(_filter_journal_rows.bind(rows))
	_filter_journal_rows(_journal_query, rows)
	_refresh_journal_detail(view)


func _select_journal_entry(view: GameView, message_id: int) -> void:
	_selected_journal_message_id = message_id
	_refresh_journal_detail(view)


func _filter_journal_rows(query: String, rows: VBoxContainer) -> void:
	_journal_query = query.strip_edges()
	var needle := _journal_query.to_lower()
	for child: Node in rows.get_children():
		if child is Control and child.has_meta("journal_search_text"):
			(child as Control).visible = needle.is_empty() or String(child.get_meta("journal_search_text")).contains(needle)


func _refresh_journal_detail(view: GameView) -> void:
	if _journal_detail == null:
		return
	_clear(_journal_detail)
	for entry: JournalEntryView in view.journal_entries:
		if entry.message_id == _selected_journal_message_id:
			_journal_detail.add_child(_label("Journal entry %d" % entry.message_id, BOOK_RED, 20))
			_journal_detail.add_child(HSeparator.new())
			var text := _label(entry.text, BOOK_INK, 17)
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_journal_detail.add_child(text)
			return
	_add_empty_state(_journal_detail, "Entry unavailable", "The selected journal record no longer exists.")


func _render_location_note_editor(parent: VBoxContainer, view: GameView) -> void:
	var current := view.current_location_note
	if current == null:
		_add_empty_state(parent, "No mapped location", "A note can be edited only while the party occupies a validated map cell.")
		return
	_add_label(parent, "%s  •  %d,%d" % [current.map_name, current.coordinate.x, current.coordinate.y], CYAN, 15)
	var editor := TextEdit.new()
	editor.name = "CurrentLocationNoteText"
	editor.custom_minimum_size = Vector2(0, 180)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.placeholder_text = "Write a location note…"
	editor.add_theme_color_override("font_color", BOOK_INK)
	editor.add_theme_color_override("font_placeholder_color", BOOK_MUTED_INK)
	editor.add_theme_stylebox_override("normal", _flat_style(Color("d4c18f"), Color("8b754d"), 2))
	editor.add_theme_stylebox_override("focus", _flat_style(Color("dccb9d"), GOLD, 2))
	editor.text = current.text
	parent.add_child(editor)
	var count_label := Label.new()
	count_label.name = "LocationNoteByteCount"
	parent.add_child(count_label)
	var actions := HBoxContainer.new()
	parent.add_child(actions)
	var save := Button.new()
	save.name = "SaveLocationNote"
	save.text = "Save Note"
	actions.add_child(save)
	var revert := Button.new()
	revert.name = "CancelLocationNoteEdit"
	revert.text = "Revert Draft"
	actions.add_child(revert)
	var availability := view.availability(&"set_location_note")
	var refresh := func() -> void:
		var byte_count := editor.text.to_utf8_buffer().size()
		count_label.text = "%d / %d encoded bytes" % [byte_count, LocationNoteState.MAX_TEXT_BYTES]
		count_label.modulate = Color("d96f6f") if byte_count > LocationNoteState.MAX_TEXT_BYTES else MUTED
		save.disabled = not availability.enabled or editor.text == current.text or byte_count > LocationNoteState.MAX_TEXT_BYTES
		save.tooltip_text = availability.reason if not availability.enabled else "Change the note before saving." if editor.text == current.text else "Classic location notes are limited to 255 encoded bytes." if byte_count > LocationNoteState.MAX_TEXT_BYTES else ""
		revert.disabled = editor.text == current.text
	editor.text_changed.connect(refresh)
	save.pressed.connect(func() -> void: intent_submitted.emit(PlayerIntent.set_location_note(editor.text)))
	revert.pressed.connect(func() -> void:
		editor.text = current.text
		refresh.call()
	)
	refresh.call()


func _tab(tabs: TabContainer, tab_name: String) -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = tab_name
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", 5)
	tabs.add_child(tab)
	return tab


func _columns(parent: VBoxContainer, node_name: String) -> HBoxContainer:
	var columns := HBoxContainer.new()
	columns.name = node_name
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 6)
	parent.add_child(columns)
	return columns


func _pane(parent: HBoxContainer, node_name: String, title: String, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	var heading := _label(title, GOLD, 18)
	heading.theme_type_variation = &"ClassicHeading"
	content.add_child(heading)
	return content


func _style_pane(content: VBoxContainer, background: Color, border: Color, border_width: int) -> void:
	var panel := content.get_parent() as PanelContainer
	if panel != null:
		panel.theme_type_variation = &""
		panel.add_theme_stylebox_override("panel", _flat_style(background, border, border_width))


func _style_pane_heading(content: VBoxContainer, color: Color) -> void:
	if content.get_child_count() > 0 and content.get_child(0) is Label:
		(content.get_child(0) as Label).add_theme_color_override("font_color", color)


func _style_journal_button(button: Button, selected: bool) -> void:
	button.add_theme_color_override("font_color", BOOK_INK)
	button.add_theme_color_override("font_hover_color", BOOK_RED)
	button.add_theme_color_override("font_pressed_color", BOOK_RED)
	button.add_theme_stylebox_override("normal", _flat_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("hover", _flat_style(Color("e0ca96"), Color("9a8358"), 1))
	button.add_theme_stylebox_override("pressed", _flat_style(BOOK_PAPER_SELECTED, BOOK_RED, 1))
	if selected:
		button.add_theme_color_override("font_color", BOOK_RED)


func _flat_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
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


func _scroll(node_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return scroll


func _add_empty_state(parent: Container, title: String, detail: String) -> void:
	_add_card(parent, title, "Empty", detail)


func _add_card(parent: Container, title: String, subtitle: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	_add_label(box, title, GOLD, 16)
	if not subtitle.is_empty():
		_add_label(box, subtitle, CYAN, 13)
	if not detail.is_empty():
		_add_label(box, detail, MUTED, 14)
	parent.add_child(panel)


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := _label(text, color, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _label(text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * _text_scale)))
	return label


func _clear(parent: Container) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
