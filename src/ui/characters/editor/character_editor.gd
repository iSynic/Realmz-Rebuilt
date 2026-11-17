## The Character Files editor: identity, changes and six tabbed panels over one
## app-owned `CharacterEditorSession`. Panels emit operations; this script applies them,
## shows refusals and owns the editor's dialogs. It never edits character state itself.

class_name CharacterEditor
extends Control

@export var change_row_scene: PackedScene

var _session: CharacterEditorSession
var _texture_for: Callable
var _imported_art: Array[CharacterAppearanceOptionView] = []
var _pending_age := 0
var _pending_number: Dictionary = {}
## The control that opened the current overlay; focus returns to it when the overlay closes.
var _return_focus: Control
var _compact := false
## Inside the save editor: no header or change list here, and the save editor owns saving.
var _embedded := false
## Extra name rule from the embedding owner, such as party-unique names; returns "" or the reason.
var _name_check: Callable

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _save: Button = %Save
@onready var _discard: Button = %Discard
@onready var _portrait: TextureRect = %Portrait
@onready var _icon: TextureRect = %Icon
@onready var _identity: Label = %Identity
@onready var _experience: Label = %Experience
@onready var _name_edit: LineEdit = %NameEdit
@onready var _name_error: Label = %NameError
@onready var _level: Label = %Level
@onready var _level_up: Button = %LevelUp
@onready var _level_reason: Label = %LevelReason
@onready var _change_count: Label = %ChangeCount
@onready var _change_list: VBoxContainer = %ChangeList
@onready var _changes_empty: Label = %ChangesEmpty
@onready var _hint: Label = %Hint
@onready var _notice: Label = %Notice
@onready var _dialog: EditorDialog = %Dialog
@onready var _number_pad: EditorNumberPad = %NumberPad
@onready var _tabs: Dictionary[Button, Control] = {%BasicsTab: %BasicsPanel, %RecordTab: %RecordPanel, %ItemsTab: %ItemsPanel, %SpellsTab: %SpellsPanel, %ConditionsTab: %ConditionsPanel, %AppearanceTab: %AppearancePanel}


func _ready() -> void:
	(%Cancel as Button).pressed.connect(_request_leave)
	_discard.pressed.connect(_request_discard)
	_save.pressed.connect(_save_revision)
	_level_up.pressed.connect(_run_level_up)
	_name_edit.text_changed.connect(_rename)
	_dialog.chosen.connect(_dialog_chosen)
	_number_pad.submitted.connect(_number_submitted)
	for tab: Button in _tabs:
		tab.pressed.connect(_show_tab.bind(tab))
		var panel: Control = _tabs[tab]
		panel.connect(&"command", _apply)
		if panel.has_signal(&"number_requested"):
			panel.connect(&"number_requested", _request_number)
	(%RecordPanel as EditorRecordPanel).age_requested.connect(_request_age)
	(%ItemsPanel as EditorItemsPanel).add_requested.connect(_add_item)
	_dialog.visibility_changed.connect(_overlay_visibility_changed)
	_number_pad.visibility_changed.connect(_overlay_visibility_changed)
	get_viewport().gui_focus_changed.connect(_keep_focus_in_overlay)


## Opens `session` for editing. `texture_for(asset_id)` returns a native portrait or icon
## texture on demand; `imported_art` lists the player's imported portrait and icon choices.
func bind(session: CharacterEditorSession, texture_for: Callable, imported_art: Array[CharacterAppearanceOptionView], compact: bool) -> void:
	_session = session
	_texture_for = texture_for
	_imported_art = imported_art
	_return_focus = null
	_notice.visible = false
	_dialog.hide()
	_number_pad.hide()
	var name := RowFields.text(session.queries.identity(), "baseName")
	_title.text = "Edit %s" % name
	_name_edit.text = name
	apply_compact(compact)
	(%BasicsTab as Button).button_pressed = true
	_show_tab(%BasicsTab as Button)
	if not _embedded:
		_cancel_button().grab_focus.call_deferred()


## Hosts the editor inside another workspace (the save editor), which supplies its own
## header, change list and Save. `name_check(text)` adds a rule such as party-unique names.
func set_embedded(enabled: bool, name_check: Callable = Callable()) -> void:
	_embedded = enabled
	_name_check = name_check
	(get_node("Layout/Header") as Control).visible = not enabled
	(get_node("Layout/Body/LeftColumn/ChangesCard") as Control).visible = not enabled
	# Beside the save editor's roster the identity column narrows and drops its Level Up help.
	(get_node("Layout/Body/LeftColumn/IdentityCard/Identity/LevelHelp") as Control).visible = not enabled
	apply_compact(_compact)


func session() -> CharacterEditorSession:
	return _session


## Narrows the identity column for the 800x600 composition; reapplied when the layout changes.
func apply_compact(compact: bool) -> void:
	_compact = compact
	_dialog.apply_compact(compact)
	# Inside the save editor the identity card is one header row above the tabs (S2/C2).
	var stacked := _embedded
	(get_node("Layout/Body") as BoxContainer).vertical = stacked
	var identity := get_node("Layout/Body/LeftColumn/IdentityCard/Identity") as BoxContainer
	identity.vertical = not stacked
	(identity.get_node("NameCaption") as Control).visible = not stacked
	# One header row: race and class on one line beside the art, then a name field sized for 20 letters.
	_name_edit.size_flags_horizontal = Control.SIZE_FILL
	UiSizing.minimum_size(_name_edit, Vector2(220 if stacked else 0, 0))
	_name_edit.tooltip_text = "Name" if stacked else ""
	var facts := identity.get_node("ArtRow/Facts") as Control
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(identity.get_node("ArtRow") as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL if stacked else Control.SIZE_FILL
	_identity.autowrap_mode = TextServer.AUTOWRAP_OFF if stacked else TextServer.AUTOWRAP_WORD_SMART
	_identity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if stacked else TextServer.OVERRUN_NO_TRIMMING
	(%Icon as Control).tooltip_text = "Combat icon"
	# Embedded, the host sizes the editor; its standalone minimum would overflow 800x600.
	UiSizing.minimum_size(self, Vector2(0, 0 if _embedded else 520))
	UiSizing.minimum_size(%LeftColumn as Control, Vector2(0 if stacked else 220 if _embedded else 240 if compact else 300, 0))


## LB/RB: moves to the previous or next tab while no overlay is open.
func cycle_tab(delta: int) -> bool:
	if not visible or overlay_focus_root() != null:
		return false
	var tabs: Array[Button] = []
	tabs.assign(_tabs.keys())
	var current := 0
	for index: int in tabs.size():
		if tabs[index].button_pressed:
			current = index
	var next := tabs[posmod(current + delta, tabs.size())]
	next.button_pressed = true
	_show_tab(next)
	next.grab_focus()
	return true


## The open number pad or dialog, which owns controller focus until it closes.
func overlay_focus_root() -> Control:
	if _number_pad.visible:
		return _number_pad
	return _dialog if _dialog.visible else null


## Back/Escape: closes the number pad or dialog first, then asks to leave.
func handle_back() -> bool:
	if not visible or _session == null:
		return false
	if _number_pad.handle_back() or _dialog.handle_back():
		return true
	if _embedded:
		return false
	_request_leave()
	return true


func _refresh() -> void:
	var identity := _session.queries.identity()
	var view := _session.queries.character_view()
	_subtitle.text = "%s · %s · Level %d" % [view.race_name, view.caste_name, RowFields.number(identity, "level")]
	var portrait: Texture2D = _texture_for.call(RowFields.text(identity, "portraitId"))
	var icon: Texture2D = _texture_for.call(RowFields.text(identity, "iconId"))
	_portrait.texture = portrait
	_icon.texture = icon
	_identity.text = "%s %s %s" % [view.gender_name, view.race_name, view.caste_name]
	_experience.text = RowFields.text(identity, "experienceText")
	if not _name_edit.has_focus() and _name_edit.text != RowFields.text(identity, "name"):
		_name_edit.text = RowFields.text(identity, "name")
	# Undo or Discard can restore a valid name while the field still shows the old text.
	var name_error := _name_error_for(_name_edit.text)
	_name_error.text = name_error
	_name_error.visible = not name_error.is_empty()
	_level.text = "Level %d" % RowFields.number(identity, "level")
	var reason := _session.queries.rules_reason()
	_level_up.disabled = not reason.is_empty()
	_level_reason.text = reason
	_level_reason.visible = not reason.is_empty()
	_refresh_changes()
	_refresh_tab_counts()
	for tab: Button in _tabs:
		if tab.button_pressed:
			_bind_panel(_tabs[tab])


## "Items 14/30", "Spells 9", "Conditions 2": how full each tab is before it opens.
func _refresh_tab_counts() -> void:
	var state := _session.queries.character_view()
	var active := _session.queries.conditions().filter(func(row: Dictionary) -> bool: return RowFields.number(row, "value") != 0).size()
	(%ItemsTab as Button).text = "Items %d/%d" % [_session.queries.items().size(), InventoryRules.MAX_ITEMS]
	var spells := _session.queries.spell_summary()
	# A character who can't cast shows a plain Spells tab rather than "Spells 0".
	(%SpellsTab as Button).text = "Spells %d" % RowFields.number(spells, "known", 0) if state != null and (RowFields.flag(spells, "caster", false) or RowFields.number(spells, "known", 0) > 0) else "Spells"
	(%ConditionsTab as Button).text = "Conditions %d" % active if active > 0 else "Conditions"


func _refresh_changes() -> void:
	var changes := _session.changes()
	while _change_list.get_child_count() > changes.size():
		var extra := _change_list.get_child(_change_list.get_child_count() - 1)
		_change_list.remove_child(extra)
		extra.queue_free()
	for index: int in changes.size():
		if index >= _change_list.get_child_count():
			var row := change_row_scene.instantiate() as EditorChangeRow
			row.name = "Change%d" % (index + 1)
			row.undo_requested.connect(_undo)
			_change_list.add_child(row)
		(_change_list.get_child(index) as EditorChangeRow).bind(index, changes[index])
	_changes_empty.visible = changes.is_empty()
	_change_count.text = "%d" % changes.size() if not changes.is_empty() else ""
	var dirty := _session.is_dirty()
	_discard.disabled = not dirty
	_save.disabled = not dirty or _name_error.visible
	_save.tooltip_text = "Save these changes as a new revision." if dirty else "Nothing has changed yet."


func _bind_panel(panel: Control) -> void:
	if panel is EditorAppearancePanel:
		(panel as EditorAppearancePanel).bind(_session, _texture_for, _imported_art)
	else:
		panel.call(&"bind", _session)


func _show_tab(selected: Button) -> void:
	for tab: Button in _tabs:
		_tabs[tab].visible = tab == selected
	# The 800x600 composition has no room for the stepping hint beside the tabs.
	_hint.visible = selected in [%BasicsTab, %RecordTab, %ConditionsTab] and not _compact and not _embedded
	_notice.visible = false
	_refresh()


func _apply(operation: Dictionary) -> void:
	_show_result(_session.apply(operation))


func _undo(index: int) -> void:
	_show_result(_session.undo(index))


func _add_item(definition_id: String) -> void:
	_show_result(_session.add_item(definition_id))


func _show_result(applied: bool) -> void:
	_notice.text = _session.last_error
	_notice.visible = not applied and not _session.last_error.is_empty()
	_refresh()


func _name_error_for(text: String) -> String:
	var error := CharacterEditLimits.name_error(text)
	if error.is_empty() and _name_check.is_valid():
		var refusal: String = _name_check.call(text)
		error = refusal
	return error


func _rename(text: String) -> void:
	var error := _name_error_for(text)
	_name_error.text = error
	_name_error.visible = not error.is_empty()
	if error.is_empty():
		_apply({"kind": &"name", "value": text})
	else:
		_refresh_changes()


func _request_number(spec: Dictionary) -> void:
	_pending_number = spec.operation
	var limits: Vector2i = spec.range
	_number_pad.open(RowFields.text(spec, "title"), RowFields.number(spec, "value"), limits)


func _number_submitted(value: int) -> void:
	if _pending_number.kind == &"age":
		_request_age(value)
		return
	var operation := _pending_number.duplicate()
	operation["value"] = value
	_apply(operation)


## Ages crossing an age group show Classic aging's changes before they apply.
func _request_age(years: int) -> void:
	var preview := _session.queries.age_preview(years)
	if not RowFields.flag(preview, "crosses"):
		_apply({"kind": &"age", "value": years})
		return
	_pending_age = years
	var rows: Array[Dictionary] = []
	var preview_rows: Array = preview.rows
	rows.assign(preview_rows)
	var message := "%s moves from %s to %s. Classic aging changes these values, as it does in play:" % [_session.queries.identity().name, preview.fromGroup, preview.group]
	var error := RowFields.text(preview, "error")
	_dialog.open("Change age group?", message, rows, {
		&"secondary": {"id": &"cancel", "text": "Keep current age"},
		&"primary": {"id": &"apply_age", "text": "Apply aging", "disabled": not error.is_empty()},
	}, error)


func _run_level_up() -> void:
	var before := RowFields.number(_session.queries.identity(), "level")
	if not _session.level_up():
		_show_result(false)
		return
	_show_result(true)
	_present_level_result(before)


func _present_level_result(before: int) -> void:
	var result := _session.queries.level_result()
	var rows: Array[Dictionary] = [{"label": "Level", "before": before, "after": RowFields.number(_session.queries.identity(), "level")}]
	for key: String in ["stamina", "spellPoints", "toHit", "magicResistance"]:
		var label: String = {"stamina": "Stamina", "spellPoints": "Spell points", "toHit": "To-hit", "magicResistance": "Magic resistance"}[key]
		rows.append({"label": label, "text": "%+d" % RowFields.number(result, key)})
	var buttons := {&"secondary": {"id": &"done", "text": "Done"}, &"tertiary": {"id": &"undo_level", "text": "Undo Level Up"}}
	# Casters below their first casting level have no spells to choose yet.
	var spell_levels: Array = _session.queries.spell_summary().levels
	if not spell_levels.is_empty():
		buttons[&"primary"] = {"id": &"choose_spells", "text": "Choose spells…"}
	_dialog.open("Level %d" % RowFields.number(_session.queries.identity(), "level"), "Fresh dice were rolled. Undo Level Up and run it again to reroll; experience now counts toward the next level.", rows, buttons)


func _present_spell_choice() -> void:
	var summary := _session.queries.spell_summary()
	var spells: Array[Dictionary] = []
	for level: int in summary.levels:
		for spell: Dictionary in _session.queries.spells(level):
			spell["level"] = level
			spells.append(spell)
	_dialog.open_spell_choice("Choose spells", "Pick any spells this caster can learn. The editor charges no spell points.", spells)


func _request_discard() -> void:
	_dialog.open("Discard all changes?", "Every change in this draft is undone. The saved character stays as it was.", [], {
		&"secondary": {"id": &"cancel", "text": "Keep editing"},
		&"tertiary": {"id": &"discard", "text": "Discard changes"},
	})


func _request_leave() -> void:
	if _session == null:
		return
	if not _session.is_dirty():
		_session.close()
		return
	_dialog.open("Leave without saving?", "This draft has %d unsaved changes." % _session.changes().size(), [], {
		&"secondary": {"id": &"cancel", "text": "Keep editing"},
		&"tertiary": {"id": &"leave", "text": "Discard and leave"},
		&"primary": {"id": &"save", "text": "Save and leave", "disabled": _save.disabled},
	})


func _save_revision() -> void:
	var name := RowFields.text(_session.queries.identity(), "name")
	match _session.save():
		&"saved":
			_session.close("Saved a new revision of %s." % name)
		&"conflict":
			_dialog.open("A newer revision exists", "%s\nThis draft can't be saved over it. Leave, then edit the newer revision." % _session.last_error, [], {
				&"secondary": {"id": &"cancel", "text": "Keep editing"},
				&"tertiary": {"id": &"leave", "text": "Discard and leave"},
			})
		_:
			_notice.text = "The revision wasn't saved • %s" % _session.last_error
			_notice.visible = true


func _dialog_chosen(action: StringName) -> void:
	match action:
		&"apply_age": _apply({"kind": &"age", "value": _pending_age})
		&"undo_level": _show_result(_session.undo_level_up())
		&"choose_spells": _present_spell_choice()
		&"confirm_spells": _apply({"kind": &"level_spells", "spell_ids": _dialog.selected_spells()})
		&"discard":
			_session.discard()
			_name_edit.text = RowFields.text(_session.queries.identity(), "name")
			_show_result(true)
		&"leave": _session.close()
		&"save": _save_revision()


func _overlay_visibility_changed() -> void:
	if _dialog.visible or _number_pad.visible:
		if _return_focus == null:
			_return_focus = get_viewport().gui_get_focus_owner()
	else:
		_restore_focus.call_deferred()


## Returns focus to the control that opened the closed overlay, or to Cancel when that
## control is gone or disabled. A chained overlay (pad, then age preview) waits.
func _restore_focus() -> void:
	if _dialog.visible or _number_pad.visible or not is_visible_in_tree():
		return
	var target := _return_focus
	_return_focus = null
	if target == null or not is_instance_valid(target) or not is_ancestor_of(target) or not target.is_visible_in_tree() or (target is BaseButton and (target as BaseButton).disabled):
		target = _cancel_button()
	target.grab_focus()


## Keyboard Tab and controller moves can't leave an open overlay for the editor controls
## behind it. Focus taken by shell modals above the editor (the controller keyboard,
## pause) is left alone.
func _keep_focus_in_overlay(focused: Control) -> void:
	var overlay := overlay_focus_root()
	if overlay == null or focused == null or not is_visible_in_tree() or not is_ancestor_of(focused) or overlay.is_ancestor_of(focused):
		return
	var first := overlay.find_next_valid_focus()
	if first != null and overlay.is_ancestor_of(first):
		first.grab_focus.call_deferred()


func _cancel_button() -> Button:
	return %BasicsTab as Button if _embedded else %Cancel as Button
