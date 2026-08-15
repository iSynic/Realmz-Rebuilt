class_name MapsJournalWorkspaceController
extends RefCounted

signal intent_submitted(intent: PlayerIntent)

const GOLD := Color("d5b45d")
const MUTED := Color("9aa0a8")

var _selected_player_map_id: String = ""
var _selected_campaign_id: String = ""
var _text_scale: float = 1.0


func set_text_scale(text_scale: float) -> void:
	_text_scale = text_scale


func present(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog) -> void:
	_clear(parent)
	if view == null:
		return
	if _selected_campaign_id != view.campaign_id:
		_selected_campaign_id = view.campaign_id
		_selected_player_map_id = ""
	_add_section_heading(parent, "Location notes", "Saved with this adventure")
	_render_location_note_editor(parent, view)
	_add_section_heading(parent, "Acquired maps", "%d available" % view.party_summary.acquired_map_ids.size() if view.party_summary != null else "0 available")
	if view.player_map_menu_entries.is_empty():
		_add_empty_state(parent, "No player-map records", "This campaign supplies no Maps/Notes entries.")
	else:
		var selected: PlayerMapView
		for player_map: PlayerMapView in view.acquired_player_maps:
			if player_map.id == _selected_player_map_id:
				selected = player_map
				break
		if selected == null and not view.acquired_player_maps.is_empty():
			selected = view.acquired_player_maps[0]
			_selected_player_map_id = selected.id
		var chooser := GridContainer.new()
		chooser.name = "AcquiredMapChooser"
		chooser.columns = 2
		chooser.add_theme_constant_override("h_separation", 6)
		chooser.add_theme_constant_override("v_separation", 4)
		for player_map: PlayerMapView in view.player_map_menu_entries:
			var button := Button.new()
			button.text = player_map.name if player_map.acquired else player_map.unavailable_name
			button.toggle_mode = true
			button.disabled = not player_map.acquired
			button.tooltip_text = "Map not acquired." if button.disabled else player_map.name
			button.button_pressed = selected != null and player_map.id == selected.id
			if not button.disabled:
				button.pressed.connect(_select_player_map.bind(parent, view, media, player_map.id))
			chooser.add_child(button)
		parent.add_child(chooser)
		if selected == null:
			_add_empty_state(parent, "No acquired maps", "Maps remain unavailable until the session records their acquisition.")
		else:
			var presenter := PlayerMapPresenter.new()
			presenter.name = "AcquiredPlayerMap"
			presenter.present(selected, media)
			parent.add_child(presenter)
	_add_section_heading(parent, "Journal entries", "%d entries" % view.journal_entries.size())
	if view.journal_entries.is_empty():
		_add_empty_state(parent, "The journal is empty", "No journal records were supplied by the current session.")
	else:
		for entry: JournalEntryView in view.journal_entries:
			_add_card(parent, "Journal entry %d" % entry.message_id, "Authored scenario message", entry.text)


func _select_player_map(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, player_map_id: String) -> void:
	_selected_player_map_id = player_map_id
	present(parent, view, media)


func _render_location_note_editor(parent: VBoxContainer, view: GameView) -> void:
	var current := view.current_location_note
	if current == null:
		_add_empty_state(parent, "No mapped location", "A location note can be edited only while the party occupies a validated map cell.")
		return
	var panel := PanelContainer.new()
	panel.name = "CurrentLocationNote"
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	_add_label(column, "Current location • %s %d,%d" % [current.map_name, current.coordinate.x, current.coordinate.y], Color("e7d078"), 17)
	_add_label(column, "Only the note at the party's current location can be edited. Saved notes below remain readable.", MUTED)
	var editor := TextEdit.new()
	editor.name = "CurrentLocationNoteText"
	editor.custom_minimum_size = Vector2(0, 96)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.placeholder_text = "Write a location note…"
	editor.text = current.text
	column.add_child(editor)
	var count_label := Label.new()
	count_label.name = "LocationNoteByteCount"
	column.add_child(count_label)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var save := Button.new()
	save.name = "SaveLocationNote"
	save.text = "Save note"
	actions.add_child(save)
	var revert := Button.new()
	revert.name = "CancelLocationNoteEdit"
	revert.text = "Revert draft"
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
	parent.add_child(panel)
	_add_section_heading(parent, "Saved %s notes" % String(current.level_type).capitalize(), "%d notes • source order" % view.location_notes.size())
	if view.location_notes.is_empty():
		_add_empty_state(parent, "No location notes", "Write a note at the current location to create the first record.")
		return
	for note: LocationNoteView in view.location_notes:
		_add_card(parent, note.map_name, "Record %d • %s • %d,%d%s" % [note.record_ordinal + 1, String(note.level_type).capitalize(), note.coordinate.x, note.coordinate.y, " • current" if note.current else ""], note.text)


func _add_section_heading(parent: VBoxContainer, title: String, detail: String = "") -> void:
	var row := HBoxContainer.new()
	var heading := _label(title, GOLD, 18)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	if not detail.is_empty():
		var note := _label(detail, MUTED, 13)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(note)
	parent.add_child(row)


func _add_empty_state(parent: VBoxContainer, title: String, detail: String) -> void:
	_add_card(parent, title, detail, "Realmz Rebuilt shows only facts supplied by the detached session view.")


func _add_card(parent: VBoxContainer, title: String, subtitle: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = 280.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	_add_label(box, title, Color("e7d078"), 17)
	_add_label(box, subtitle, Color("e0e2e5"))
	if not detail.is_empty():
		_add_label(box, detail, MUTED)
	parent.add_child(panel)


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * _text_scale)))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _label(text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * _text_scale)))
	return label


func _clear(parent: VBoxContainer) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
