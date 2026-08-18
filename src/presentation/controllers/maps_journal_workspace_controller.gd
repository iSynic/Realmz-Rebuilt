class_name MapsJournalWorkspaceController
extends RefCounted

signal intent_submitted(intent: PlayerIntent)

const GOLD := Color("d5b45d")
const CYAN := Color("8fcfd1")
const MUTED := Color("9aa0a8")

var _selected_player_map_id: String = ""
var _selected_journal_message_id: int = 0
var _selected_campaign_id: String = ""
var _selected_tab: int = 0
var _text_scale: float = 1.0
var _journal_detail: VBoxContainer


func set_text_scale(text_scale: float) -> void:
	_text_scale = text_scale


func present(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog) -> void:
	_clear(parent)
	if view == null:
		return
	if _selected_campaign_id != view.campaign_id:
		_selected_campaign_id = view.campaign_id
		_selected_player_map_id = ""
		_selected_journal_message_id = 0
		_selected_tab = 0
	_add_header(parent, view)
	var tabs := TabContainer.new()
	tabs.name = "MapsNotesTabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.tab_changed.connect(func(index: int) -> void: _selected_tab = index)
	parent.add_child(tabs)
	_build_places_tab(_tab(tabs, "Places"), view)
	_build_maps_tab(_tab(tabs, "Maps"), view, media)
	_build_journal_tab(_tab(tabs, "Journal"), view)
	tabs.current_tab = mini(_selected_tab, tabs.get_tab_count() - 1)


func _add_header(parent: VBoxContainer, view: GameView) -> void:
	var row := HBoxContainer.new()
	row.name = "MapsNotesHeader"
	parent.add_child(row)
	var title := _label("Maps / Notes", GOLD, 20)
	title.theme_type_variation = &"ClassicHeading"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var maps := view.party_summary.acquired_map_ids.size() if view.party_summary != null else 0
	var facts := _label("%d places  •  %d maps  •  %d journal entries" % [view.location_notes.size(), maps, view.journal_entries.size()], CYAN, 13)
	facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(facts)


func _build_places_tab(parent: VBoxContainer, view: GameView) -> void:
	var columns := _columns(parent, "LocationNotesWorkspace")
	var saved := _pane(columns, "SavedLocationNotes", "Saved Places", 0.8)
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
		for note: LocationNoteView in view.location_notes:
			_add_card(rows, note.map_name, "%s  •  %d,%d%s" % [String(note.level_type).capitalize(), note.coordinate.x, note.coordinate.y, "  •  current" if note.current else ""], note.text)
	var current := _pane(columns, "CurrentLocationNotePane", "Current Location", 1.25)
	_render_location_note_editor(current, view)


func _build_maps_tab(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog) -> void:
	var columns := _columns(parent, "AcquiredMapsWorkspace")
	var browser := _pane(columns, "PlayerMapBrowser", "Acquired Maps", 0.68)
	var display := _pane(columns, "PlayerMapDisplay", "Selected Map", 1.5)
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
		button.custom_minimum_size.y = 38.0
		if not button.disabled:
			button.pressed.connect(_select_player_map.bind(route_body, view, media, player_map.id))
		chooser.add_child(button)
	if selected == null:
		_add_empty_state(display, "No acquired maps", "Maps remain unavailable until the session records their acquisition.")
	else:
		var presenter := PlayerMapPresenter.new()
		presenter.name = "AcquiredPlayerMap"
		presenter.present(selected, media)
		display.add_child(presenter)


func _select_player_map(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, player_map_id: String) -> void:
	_selected_player_map_id = player_map_id
	present(parent, view, media)


func _build_journal_tab(parent: VBoxContainer, view: GameView) -> void:
	var columns := _columns(parent, "JournalWorkspace")
	var browser := _pane(columns, "JournalEntryBrowser", "Journal Entries", 0.85)
	var detail := _pane(columns, "JournalEntryDetail", "Selected Entry", 1.35)
	_journal_detail = VBoxContainer.new()
	_journal_detail.name = "JournalEntryDetailBody"
	_journal_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal_detail.add_theme_constant_override("separation", 5)
	detail.add_child(_journal_detail)
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
		panel.theme_type_variation = &"ClassicInset"
		rows.add_child(panel)
		var record := VBoxContainer.new()
		panel.add_child(record)
		var open := Button.new()
		open.text = "Journal entry %d" % entry.message_id
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open.toggle_mode = true
		open.button_pressed = entry.message_id == _selected_journal_message_id
		open.pressed.connect(_select_journal_entry.bind(view, entry.message_id))
		record.add_child(open)
		record.add_child(_label(entry.text.left(180), MUTED, 13))
	_refresh_journal_detail(view)


func _select_journal_entry(view: GameView, message_id: int) -> void:
	_selected_journal_message_id = message_id
	_refresh_journal_detail(view)


func _refresh_journal_detail(view: GameView) -> void:
	if _journal_detail == null:
		return
	_clear(_journal_detail)
	for entry: JournalEntryView in view.journal_entries:
		if entry.message_id == _selected_journal_message_id:
			_journal_detail.add_child(_label("Journal entry %d" % entry.message_id, GOLD, 18))
			_journal_detail.add_child(HSeparator.new())
			var text := _label(entry.text, Color("e0e2e5"), 15)
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
	panel.theme_type_variation = &"ClassicTextWell"
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


func _scroll(node_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return scroll


func _add_empty_state(parent: Container, title: String, detail: String) -> void:
	_add_card(parent, title, "Unavailable", detail)


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
