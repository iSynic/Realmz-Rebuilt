## Binds detached Character Files revisions to the scene-authored library: tabs, search, list, selection, notices and prompts.
class_name VaultScreenBinder
extends RefCounted

signal back_requested
signal inspect_requested(revision_hash: String)
signal import_requested(character_id: String, revision_hash: String)
signal character_requested(operation: StringName, character_id: String, revision_hash: String)

const ACTIVE := &"active"
const ARCHIVED := &"archived"
const STATUS_SECONDS := 6.0
const LIBRARY_RESTORE_STARTERS := 0
const LIBRARY_REPAIR := 1

var _revisions: Array[CharacterVaultRevisionView] = []
var _notice := ""
var _tab: StringName = ACTIVE
var _query := ""
## The selected character per tab, so switching tabs returns to the same record.
var _selected := {ACTIVE: "", ARCHIVED: ""}
var _selected_index := 0
## Rows of the current tab in list order, keyed by character ID.
var _rows: Dictionary = {}
var _entries: Array[VaultEntry] = []
var _screen: VaultScreen
var _view: GameView
var _textures: Dictionary = {}
var _compact := false
var _status_serial := 0
var _prompt_family := ""
var _prompt_preferences: ControllerPreferences
var _detail := VaultDetailBinder.new()
var _initial_focus_pending := true
var media_catalog: ClassicMediaCatalog


func _init() -> void:
	# Signal-to-signal method callables avoid a reference cycle between the binders.
	_detail.inspect_requested.connect(inspect_requested.emit)
	_detail.character_requested.connect(character_requested.emit)


func set_revisions(revisions: Array[CharacterVaultRevisionView], notice: String) -> void:
	_revisions = revisions.duplicate()
	_notice = notice


func present(screen: VaultScreen, view: GameView, textures: Dictionary, back_label: String, compact: bool) -> void:
	if _screen != screen:
		_screen = screen
		_rows.clear()
		_connect_static_controls(screen)
	if not screen.library.is_visible_in_tree():
		# Opening the library (or returning from inspection) starts on the selected record.
		_initial_focus_pending = true
	_view = view
	_textures = textures
	_compact = compact
	screen.prepare_list_layout()
	screen.list_back_button.text = "‹  %s" % back_label
	screen.apply_profile(compact)
	_bind_prompts(screen)
	_entries = VaultEntry.group(_revisions)
	if screen.archive_confirmation.visible and not screen.archive_confirmation.still_applies(_entries):
		screen.archive_confirmation.hide()
	var empty := _entries.is_empty()
	screen.toolbar.visible = not empty
	screen.vault_body.visible = not empty
	screen.empty_state.visible = empty
	screen.notice_banner.visible = not empty and not _notice.is_empty()
	screen.notice_text.text = _notice
	if empty:
		_clear_rows()
		_bind_empty_library(screen)
	else:
		_bind_tabs(screen)
		_build_rows()
	_restore_focus.call_deferred()


## Switches between Active and Archived; returns true when the shell's section input was consumed.
func cycle_tab(_delta: int) -> bool:
	if not _library_visible() or _entries.is_empty():
		return false
	if not _dialog_open():
		_switch_tab(ARCHIVED if _tab == ACTIVE else ACTIVE)
	return true


func present_status(text: String, is_error: bool) -> void:
	if not is_instance_valid(_screen) or not _screen.is_inside_tree():
		return
	_status_serial += 1
	var label := _screen.status_notice
	label.text = text
	label.theme_type_variation = &"VaultStatusBad" if is_error else &"VaultStatusMuted"
	label.get_tree().create_timer(STATUS_SECONDS).timeout.connect(_expire_status.bind(_status_serial))


func _expire_status(serial: int) -> void:
	if serial == _status_serial and is_instance_valid(_screen):
		_screen.status_notice.text = ""


func set_controller_prompts(family: String, preferences: ControllerPreferences) -> void:
	_prompt_family = family
	_prompt_preferences = preferences
	if is_instance_valid(_screen):
		_bind_prompts(_screen)


## Returns true when Back was consumed: dismissing the confirmation, or returning focus
## from the detail pane to the selected row.
func handle_back() -> bool:
	if not _library_visible():
		return false
	if _screen.archive_confirmation.visible:
		# Cancel runs the dialog's own cancel path, so its pending change clears.
		_screen.archive_confirmation.get_cancel_button().pressed.emit()
		return true
	var owner := _screen.get_viewport().gui_get_focus_owner()
	if owner == null or not _screen.detail_panel.is_ancestor_of(owner):
		return false
	var row := _selected_row()
	if row == null:
		return false
	row.grab_focus()
	return true


func _connect_static_controls(screen: VaultScreen) -> void:
	screen.list_back_button.pressed.connect(back_requested.emit)
	screen.active_tab.pressed.connect(_switch_tab.bind(ACTIVE))
	screen.archived_tab.pressed.connect(_switch_tab.bind(ARCHIVED))
	screen.search_field.text_changed.connect(_search)
	screen.clear_search_button.pressed.connect(_clear_search)
	screen.library_tools.get_popup().id_pressed.connect(_library_tool)
	screen.empty_restore_starters_button.pressed.connect(_begin_starter_restore.bind(screen.empty_restore_starters_button))
	screen.add_to_party_button.pressed.connect(_request_selected.bind(&"add"))
	screen.full_sheet_button.pressed.connect(_request_selected.bind(&"inspect"))
	screen.edit_button.pressed.connect(_request_selected.bind(&"edit"))
	screen.restore_archived_button.pressed.connect(_request_selected.bind(&"restore"))
	screen.archive_button.pressed.connect(_confirm.bind(&"archive", screen.archive_button))
	screen.delete_button.pressed.connect(_confirm.bind(&"delete", screen.delete_button))
	screen.archive_confirmation.change_confirmed.connect(_change_confirmed)


func _library_tool(id: int) -> void:
	if id == LIBRARY_RESTORE_STARTERS: _begin_starter_restore(_screen.library_tools)
	elif id == LIBRARY_REPAIR: _screen.repair_dialog.begin_review(_screen.library_tools)


func _begin_starter_restore(opener: Control) -> void:
	_screen.repair_dialog.begin_starter_restore(opener)


func _request_selected(action: StringName) -> void:
	var entry := _selected_entry()
	if entry == null:
		return
	match action:
		&"add": import_requested.emit(entry.character_id, entry.display.revision_hash)
		&"inspect": inspect_requested.emit(entry.display.revision_hash)
		&"restore": character_requested.emit(&"restore", entry.character_id, entry.display.revision_hash)
		&"edit": character_requested.emit(&"edit", entry.character_id, entry.display.revision_hash)


func _confirm(operation: StringName, opener: Button) -> void:
	var entry := _selected_entry()
	if entry != null:
		_screen.archive_confirmation.present(operation, entry.character_id, entry.display.name, entry.revisions.size(), opener)


func _change_confirmed(operation: StringName, character_id: String) -> void:
	# The next row in the same place receives focus once the refreshed list is presented.
	_initial_focus_pending = true
	character_requested.emit(operation, character_id, "")


func _bind_empty_library(screen: VaultScreen) -> void:
	var unreadable := not _notice.is_empty()
	screen.context_label.text = "Characters you create or bring home from an adventure are kept here."
	screen.empty_title.text = "Character Files can't be read" if unreadable else "No Character Files yet"
	screen.empty_detail.text = _notice if unreadable else "Characters you create or bring home from an adventure appear here. You can also restore the six starter characters."


func _bind_tabs(screen: VaultScreen) -> void:
	var archived := _entries.filter(func(entry: VaultEntry) -> bool: return entry.archived).size()
	screen.active_tab.text = "Active  %d" % (_entries.size() - archived)
	screen.archived_tab.text = "Archived  %d" % archived
	screen.active_tab.set_pressed_no_signal(_tab == ACTIVE)
	screen.archived_tab.set_pressed_no_signal(_tab == ARCHIVED)
	var context := ""
	if _tab == ARCHIVED:
		context = "Archived characters are hidden from party setup. Restore one to use it again."
	elif VaultDetailBinder.has_scenario(_view):
		context = "Showing who can join %s." % _view.campaign_summary.title
	else:
		context = "Choose a scenario in party setup to see who can join."
	screen.context_label.text = context


## Rebuilds the current tab's rows from fresh data; search and selection then update them in place.
func _build_rows() -> void:
	_clear_rows()
	var list := _screen.character_file_list
	for entry: VaultEntry in _entries:
		if entry.archived != (_tab == ARCHIVED):
			continue
		var row := _screen.character_row_scene.instantiate() as VaultCharacterRow
		list.add_child(row)
		var status := VaultDetailBinder.status_for(entry, _view)
		var textures := _ensure_textures(entry)
		var revision := entry.display
		var portrait: Texture2D = textures.get(revision.portrait_id)
		var icon: Texture2D = textures.get(revision.character.combat_icon_id) if revision.character != null else null
		var variation: StringName = status["variation"]
		row.bind(entry, portrait, icon, RowFields.text(status, "text"), variation, _compact)
		row.pressed.connect(_select_character.bind(entry.character_id, true))
		row.focus_entered.connect(_select_character.bind(entry.character_id, false))
		_rows[entry.character_id] = row
	_apply_filter()


func _clear_rows() -> void:
	_rows.clear()
	if not is_instance_valid(_screen):
		return
	var list := _screen.character_file_list
	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()


## Shows rows matching the search, keeps the selection (or the next row in its place) and binds its detail.
func _apply_filter() -> void:
	var visible: Array[VaultEntry] = []
	for entry: VaultEntry in _tab_entries():
		var row := _row(entry.character_id)
		row.visible = entry.matches(_query)
		if row.visible: visible.append(entry)
	var screen := _screen
	screen.list_scroll.visible = not visible.is_empty()
	screen.list_empty.visible = visible.is_empty()
	screen.detail_panel.visible = not visible.is_empty()
	# Without a record to show, the list's empty state takes the whole body.
	screen.list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if visible.is_empty() else Control.SIZE_FILL
	if visible.is_empty():
		_bind_list_empty(screen, _rows.size())
		return
	var selected_id := _selected_id()
	var index := visible.find_custom(func(entry: VaultEntry) -> bool: return entry.character_id == selected_id)
	if index < 0:
		# After archive, restore or delete the next row in the same place is selected.
		index = clampi(_selected_index, 0, visible.size() - 1)
	_select_character(visible[index].character_id, false)


func _bind_list_empty(screen: VaultScreen, tab_count: int) -> void:
	var tab_name := "archived" if _tab == ARCHIVED else "active"
	screen.clear_search_button.visible = tab_count > 0
	if tab_count > 0:
		screen.list_empty_title.text = "No matches"
		screen.list_empty_detail.text = "No %s characters match “%s”." % [tab_name, _query]
	elif _tab == ARCHIVED:
		screen.list_empty_title.text = "Nothing archived"
		screen.list_empty_detail.text = "Archived characters appear here. Every revision is kept until you delete it."
	else:
		screen.list_empty_title.text = "No active characters"
		screen.list_empty_detail.text = "Restore one from Archived, or create a character in party setup."


func _search(text: String) -> void:
	_query = text.strip_edges()
	if _library_visible() and not _entries.is_empty():
		_apply_filter()


func _clear_search() -> void:
	_screen.search_field.clear()
	_search("")
	_restore_focus_to(_selected_row())


func _switch_tab(tab: StringName) -> void:
	if _tab == tab or not _library_visible():
		# Keep the tab group showing the current tab.
		_tab_button().set_pressed_no_signal(true)
		return
	_tab = tab
	_selected_index = 0
	_bind_tabs(_screen)
	_build_rows()
	# The selected record keeps focus so D-pad and LB/RB never strand it on a tab button.
	_restore_focus_to(_selected_row() if _selected_row() != null else _tab_button())


## Selects one row in place: no rows are rebuilt, only the selection marks and the detail pane.
func _select_character(character_id: String, take_focus: bool) -> void:
	var entry := _entry(character_id)
	if entry == null:
		return
	var previous := _row(_selected_id())
	if previous != null: previous.set_selected(false)
	_selected[_tab] = character_id
	var row := _row(character_id)
	row.set_selected(true)
	_selected_index = _tab_entries().filter(func(candidate: VaultEntry) -> bool: return _row(candidate.character_id).visible).find(entry)
	_detail.bind(_screen, entry, _view, _ensure_textures(entry))
	if take_focus: _restore_focus_to(row)


## Called after the route's generic focus restoration; opening the route, returning from
## inspection or a confirmed change focuses the selected record instead of a stored control.
func restore_focus(opened: bool) -> void:
	if opened:
		_initial_focus_pending = true
	_restore_focus()
	if _library_visible():
		_initial_focus_pending = false


func _restore_focus() -> void:
	if not _library_visible():
		return
	if _screen.empty_state.visible:
		_screen.empty_restore_starters_button.grab_focus()
		return
	var owner := _screen.get_viewport().gui_get_focus_owner()
	var keep := owner != null and owner.is_visible_in_tree() and _screen.is_ancestor_of(owner) and not _initial_focus_pending
	if not keep:
		# An empty tab returns focus to Active so the player can always leave it.
		_restore_focus_to(_selected_row() if _selected_row() != null else _screen.active_tab)


func _restore_focus_to(target: Control) -> void:
	if target != null and target.is_visible_in_tree() and not target.has_focus():
		target.grab_focus()


func _bind_prompts(screen: VaultScreen) -> void:
	var prompts := screen.prompts
	prompts.visible = not _prompt_family.is_empty()
	if not prompts.visible:
		return
	var family := _prompt_family
	var prefs := _prompt_preferences
	screen.prompt_glyph("PromptSelect").text = ControllerBindingLabels.action(prefs, &"realmz_controller_confirm", family, ControllerBindingLabels.face(&"south", family))
	screen.prompt_glyph("PromptBack").text = ControllerBindingLabels.action(prefs, &"realmz_controller_back", family, ControllerBindingLabels.face(&"east", family))
	var previous := ControllerBindingLabels.action(prefs, &"realmz_controller_section_previous", family, "LB")
	var next := ControllerBindingLabels.action(prefs, &"realmz_controller_section_next", family, "RB")
	screen.prompt_glyph("PromptTabs").text = "%s / %s" % [previous, next]
	# Narrow layouts drop the tab prompt first so the status notice keeps its room.
	(prompts.get_node("PromptTabs") as Control).visible = not _compact and not _revisions.is_empty()


func _ensure_textures(entry: VaultEntry) -> Dictionary:
	var media := media_catalog
	if media == null:
		return _textures
	var revision := entry.display
	for asset_id: String in [revision.portrait_id, revision.character.combat_icon_id if revision.character != null else ""]:
		if asset_id.is_empty() or _textures.get(asset_id) != null:
			continue
		var asset := media.asset_by_id(asset_id)
		var texture := media.image_texture(asset) if asset != null else null
		if texture != null:
			_textures[asset_id] = texture
	return _textures


func _tab_entries() -> Array[VaultEntry]:
	var result: Array[VaultEntry] = []
	for entry: VaultEntry in _entries:
		if entry.archived == (_tab == ARCHIVED): result.append(entry)
	return result


func _entry(character_id: String) -> VaultEntry:
	for entry: VaultEntry in _entries:
		if entry.character_id == character_id:
			return entry
	return null


func _tab_button() -> Button:
	return _screen.archived_tab if _tab == ARCHIVED else _screen.active_tab


func _dialog_open() -> bool:
	return _screen.archive_confirmation.visible or _screen.repair_dialog.visible


func _library_visible() -> bool:
	return is_instance_valid(_screen) and _screen.library.is_visible_in_tree()


func _selected_entry() -> VaultEntry:
	return _entry(_selected_id())


func _selected_row() -> VaultCharacterRow:
	var row := _row(_selected_id())
	return row if row != null and is_instance_valid(row) and row.visible else null


func _row(character_id: String) -> VaultCharacterRow:
	var row: VaultCharacterRow = _rows.get(character_id)
	return row


func _selected_id() -> String:
	var character_id: String = _selected[_tab]
	return character_id
