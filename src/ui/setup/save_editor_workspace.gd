## The save editor: Adventure settings, the party roster and each member's character editor
## over one app-owned `SaveEditorSession`. It shows the session's draft and sends commands;
## it never edits game state itself.

class_name SaveEditorWorkspace
extends Control

@export var member_row_scene: PackedScene
@export var page_group: ButtonGroup
@export var prompt_glyph_style: StyleBox

const DIFFICULTIES: Array[int] = [-2, -1, 0, 1, 2]
const MONSTER_SETS: Array[int] = [0, 1, -1]

var _session: SaveEditorSession
var _media: ClassicMediaCatalog
var _textures := {}
var _imported_art: Array[CharacterAppearanceOptionView] = []
var _compact := false
## "" shows Adventure settings; otherwise the selected member's character ID.
var _page_id := ""
var _member_session: CharacterEditorSession
## The draft member `_member_session` edits; a new session, re-add or undo gives a new object.
var _member_for: SaveEditMember
## Picker and dialog flows (adding, dropping, discarding, leaving, reviewing, writing).
var _flows: SaveEditorFlows
var _prompt_family := ""
var _prompt_preferences: ControllerPreferences

@onready var _subtitle: Label = %Subtitle
@onready var _save: Button = %Save
@onready var _discard: Button = %Discard
@onready var _blocking: Label = %Blocking
@onready var _notice: Label = %Notice
@onready var _adventure_row: SaveEditorMemberRow = %AdventureRow
@onready var _members: BoxContainer = %Members
@onready var _party_count: Label = %PartyCount
@onready var _add_files: Button = %AddFromFiles
@onready var _add_reason: Label = %AddReason
@onready var _member_page: Control = %MemberPage
@onready var _difficulty: HBoxContainer = %Difficulty
@onready var _monsters: HBoxContainer = %Monsters
@onready var _ally_list: VBoxContainer = %AllyList
@onready var _change_list: VBoxContainer = %ChangeList
@onready var _member_editor: CharacterEditor = %MemberEditor
@onready var _keep: CheckButton = %KeepInFiles
@onready var _drop: Button = %DropMember
@onready var _picker: SaveEditorPicker = %Picker
@onready var _dialog: EditorDialog = %Dialog


func _ready() -> void:
	_flows = SaveEditorFlows.new(_dialog, _picker)
	_flows.applied.connect(_show_result)
	_flows.page_chosen.connect(func(page_id: String) -> void: _page_id = page_id)
	_flows.review_requested.connect(_request_review)
	_flows.discarded.connect(func() -> void:
		_page_id = ""
		_member_session = null
		_member_for = null
		_show_result(true)
	)
	(%Cancel as Button).pressed.connect(func() -> void: _flows.request_leave(_change_rows(false).size(), not _save.disabled))
	_discard.pressed.connect(_flows.request_discard)
	_save.pressed.connect(_request_review)
	_adventure_row.pressed.connect(_select_page.bind(""))
	_add_files.pressed.connect(func() -> void: _flows.open_character_files())
	(%AddAlly as Button).pressed.connect(func() -> void: _flows.open_allies())
	(%StripDrop as Button).pressed.connect(func() -> void: _drop.pressed.emit())
	(%MemberChanges as Button).pressed.connect(_focus_changes)
	(%StripChanges as Button).pressed.connect(_focus_changes)
	_drop.pressed.connect(func() -> void: _flows.request_drop(_page_id))
	_keep.toggled.connect(func(keep: bool) -> void: _show_result(_session.set_keep_in_files(_page_id, keep)))
	for index: int in DIFFICULTIES.size():
		(_difficulty.get_child(index) as Button).pressed.connect(func() -> void: _show_result(_session.set_difficulty(DIFFICULTIES[index])))
	for index: int in MONSTER_SETS.size():
		(_monsters.get_child(index) as Button).pressed.connect(func() -> void: _show_result(_session.set_monster_set(MONSTER_SETS[index])))
	# Closing the picker returns focus to the button that opened it.
	_picker.visibility_changed.connect(func() -> void:
		if not _picker.visible and visible and not _dialog.visible:
			var opener := (%AddAlly as Control) if _flows.picker_mode() == &"ally" else (%AddFromFiles as Control)
			opener.grab_focus.call_deferred()
	)


## Opens `session` (already open on its slot). `media` supplies portraits and creature icons.
func bind(session: SaveEditorSession, media: ClassicMediaCatalog, compact: bool) -> void:
	if _session != null and _session.changed.is_connected(_refresh):
		_session.changed.disconnect(_refresh)
	_session = session
	_flows.set_session(session)
	_member_session = null
	_member_for = null
	_media = media
	_textures.clear()
	_compact = compact
	_imported_art.clear()
	if media != null:
		_imported_art.append_array(media.imported_appearance_options(CharacterAppearanceDefinition.PORTRAIT))
		_imported_art.append_array(media.imported_appearance_options(CharacterAppearanceDefinition.COMBAT_ICON))
	_session.changed.connect(_refresh)
	_picker.hide()
	_dialog.hide()
	_notice.visible = false
	_page_id = ""
	show()
	_refresh()
	# Focus starts on Adventure settings, never on Cancel, so a first A press can't leave the editor.
	_adventure_row.grab_focus.call_deferred()


## 800x600 narrows the roster and stacks allies over changes; larger sizes scale with Interface Size.
func set_layout_profile(profile: UiLayoutProfile) -> void:
	if profile == null:
		return
	_compact = profile.id == UiLayoutProfile.COMPACT
	UiSizing.apply(self, profile)
	# 800x600 turns the roster into a strip of portraits above the page.
	(%Body as BoxContainer).vertical = _compact
	(%RosterBody as BoxContainer).vertical = not _compact
	_members.vertical = not _compact
	(%PartyHeader as Control).visible = not _compact
	var scroll := %MemberScroll as ScrollContainer
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if _compact else ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if _compact else ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_files.text = "+  Add" if _compact else "+  Add from Character Files…"
	_add_files.size_flags_vertical = Control.SIZE_SHRINK_CENTER if _compact else Control.SIZE_FILL
	UiSizing.minimum_size(%Roster as Control, Vector2(0 if _compact else 300, 0))
	UiSizing.minimum_size(%Changes as Control, Vector2(0 if _compact else 340, 0))
	(%Lower as BoxContainer).vertical = _compact
	var layout := get_node("Layout") as Control
	var margin := 10.0 if _compact else 28.0
	layout.offset_left = margin
	layout.offset_right = -margin
	layout.offset_top = 8.0 if _compact else 20.0
	layout.offset_bottom = -8.0 if _compact else -16.0
	if _member_page.visible:
		_member_editor.apply_compact(_compact)
	set_controller_prompts(_prompt_family, _prompt_preferences)
	if _session != null:
		_refresh()


func session() -> SaveEditorSession:
	return _session


## The open picker, dialog or member overlay, which owns controller focus until it closes.
func overlay_focus_root() -> Control:
	if _picker.visible:
		return _picker
	if _dialog.visible:
		return _dialog
	return _member_editor.overlay_focus_root() if _member_page.visible else null


## Back/Escape: closes the innermost overlay first, then asks to leave.
func handle_back() -> bool:
	if not visible or _session == null:
		return false
	# Once written, the edit is locked: Back on the waiting-file dialog means Later, never more editing.
	if _dialog.visible and _session.waiting != null:
		_flows.dialog_chosen(&"later")
		return true
	if _picker.handle_back() or _dialog.handle_back():
		return true
	if _member_page.visible and _member_editor.handle_back():
		return true
	if not _page_id.is_empty():
		_select_page("")
		_focus_page()
		return true
	_flows.request_leave(_change_rows(false).size(), not _save.disabled)
	return true


## Controller extras beyond D-pad, A, B and LB/RB: X undoes the latest change, Y jumps to
## Changes, Start reviews and saves, LT/RT move between Adventure settings and each member.
## False leaves the action to ordinary workspace navigation.
func handle_controller_shortcut(action: StringName) -> bool:
	if not visible or _session == null or overlay_focus_root() != null:
		return false
	match action:
		&"realmz_controller_action_radial":
			_undo_latest()
		&"realmz_controller_workspace_radial":
			_focus_changes()
		&"realmz_controller_system":
			if _save.disabled:
				_notice.text = _save.tooltip_text
				_notice.visible = true
			_request_review()
		&"realmz_controller_character_previous", &"realmz_controller_character_next":
			cycle_page(-1 if action == &"realmz_controller_character_previous" else 1)
			_focus_page()
		_:
			return false
	return true


## The controller glyph bar; an empty family hides it (mouse and keyboard play).
func set_controller_prompts(family: String, preferences: ControllerPreferences) -> void:
	_prompt_family = family
	_prompt_preferences = preferences
	var bar := %Prompts as HFlowContainer
	for child: Node in bar.get_children():
		bar.remove_child(child)
		child.queue_free()
	bar.visible = not family.is_empty()
	if family.is_empty():
		return
	for item: PackedStringArray in SaveEditorRows.prompt_items(family, preferences, _member_page.visible):
		bar.add_child(SaveEditorRows.prompt(item[0], item[1], prompt_glyph_style))


## X: undoes the newest undoable change on the page in view.
func _undo_latest() -> void:
	if _member_session != null and _member_page.visible:
		var edits := _member_session.changes()
		for index: int in range(edits.size() - 1, -1, -1):
			if RowFields.flag(edits[index], "canUndo", true):
				var undone := _member_session.undo(index)
				_show_result(true)
				if not undone:
					_notice.text = _member_session.last_error
					_notice.visible = true
				return
	var listed := _session.draft.changes()
	for index: int in range(listed.size() - 1, -1, -1):
		if RowFields.flag(listed[index], "canUndo"):
			_show_result(_session.undo(index))
			return
	_notice.text = "Nothing to undo here."
	_notice.visible = true


## Y: shows Adventure settings and focuses the Changes list.
func _focus_changes() -> void:
	_select_page("")
	for row: Node in _change_list.get_children():
		var button := row.get_child(row.get_child_count() - 1) as Button
		if button != null and not button.disabled:
			button.grab_focus()
			return
	_save.grab_focus()


func _focus_page() -> void:
	if _page_id.is_empty():
		(_difficulty.get_child(0) as Button).grab_focus()
		return
	for row: Node in _members.get_children():
		if (row as SaveEditorMemberRow).page_id == _page_id:
			(row as Control).grab_focus()
			return


## LB/RB: a member's editor tabs while a member is open, otherwise Adventure settings and each member.
func cycle_section(delta: int) -> bool:
	if _member_page.visible and _member_editor.visible:
		return _member_editor.cycle_tab(delta)
	return cycle_page(delta)


## Steps through Adventure settings and each member.
func cycle_page(delta: int) -> bool:
	if not visible or overlay_focus_root() != null:
		return false
	var pages: Array[String] = [""]
	for member: SaveEditMember in _session.draft.members():
		pages.append(member.character_id)
	_select_page(pages[posmod(pages.find(_page_id) + delta, pages.size())])
	return true


func _refresh() -> void:
	if _session == null:
		return
	# Rows are rebuilt below; focus on a freed Undo/Dismiss button moves to the row now in its place.
	var ally_focus := SaveEditorRows.focused_index(_ally_list)
	var change_focus := SaveEditorRows.focused_index(_change_list)
	_render()
	# A list hidden by the render (Open moves to a member's page) hands focus to the page now shown.
	if (ally_focus >= 0 or change_focus >= 0) and not _change_list.is_visible_in_tree():
		_focus_page()
	elif ally_focus >= 0 and not SaveEditorRows.focus_row(_ally_list, ally_focus):
		(%AddAlly as Button).grab_focus()
	elif change_focus >= 0 and not SaveEditorRows.focus_row(_change_list, change_focus):
		_adventure_row.grab_focus()


func _render() -> void:
	var draft := _session.draft
	var saved := _session.saved_state()
	_subtitle.text = "%s · Slot %s · saved Day %d" % [SaveEditorFlows.campaign_title(_session), _session.slot_id, saved.clock.day() if saved != null and saved.clock != null else 0]
	var changes := _change_rows(_page_id.is_empty())
	for button: Button in [%MemberChanges as Button, %StripChanges as Button]:
		button.text = "Changes (%d)" % changes.size() if not changes.is_empty() else "Changes"
		button.disabled = changes.is_empty()
	(%StripChanges as Button).visible = _compact
	# At 800x600 the strip's Changes button already sits above the member page.
	(%MemberChanges as Button).visible = not _compact
	_discard.visible = not _compact
	_discard.disabled = not _session.is_dirty()
	_save.disabled = not _session.is_dirty() or not draft.blocking_error.is_empty()
	_save.tooltip_text = draft.blocking_error if not draft.blocking_error.is_empty() else "Review, then write the changes to Slot %s." % _session.slot_id if _session.is_dirty() else "Nothing has changed yet."
	_blocking.text = draft.blocking_error
	_blocking.visible = not draft.blocking_error.is_empty()
	_render_roster()
	_render_adventure(changes)
	_render_member_page()


func _render_roster() -> void:
	var state := _session.draft.state
	var ally_count := state.party.allies().size()
	var monsters := PartySetupView.monster_set_name(state.monster_set)
	# The compact tile names the monster set only when it isn't the usual one ("Hard · Mega set").
	var compact_set := "" if state.monster_set == 0 else " · %s set" % monsters.trim_suffix(" Monsters")
	var summary := PartySetupView.difficulty_name(state.difficulty) + compact_set if _compact else "%s · %s · %d all%s" % [PartySetupView.difficulty_name(state.difficulty), monsters, ally_count, "y" if ally_count == 1 else "ies"]
	_adventure_row.bind("", "Adventure" if _compact else "Adventure settings", summary, null, "", &"", false)
	_adventure_row.set_pressed_no_signal(_page_id.is_empty())
	_adventure_row.set_strip(_compact)
	var members := _session.draft.members()
	while _members.get_child_count() > members.size():
		var extra := _members.get_child(_members.get_child_count() - 1)
		_members.remove_child(extra)
		extra.queue_free()
	for index: int in members.size():
		if index >= _members.get_child_count():
			var row := member_row_scene.instantiate() as SaveEditorMemberRow
			row.button_group = page_group
			row.pressed.connect(func() -> void: _select_page(row.page_id))
			_members.add_child(row)
		var member := members[index]
		var character := member.state()
		var view := CharacterView.new(character, _session.content, null, false, false)
		var tag := ""
		var role: StringName = &"gold"
		if member.dropped:
			tag = "Leaves"
			role = &"bad"
		elif member.origin == SaveEditMember.ADDED:
			tag = "Joins"
			role = &"good"
		elif member.draft.is_dirty():
			tag = "%d edit%s" % [member.draft.changes().size(), "" if member.draft.changes().size() == 1 else "s"]
		var detail := "Leaves · %s" % ("kept in Files" if member.keep_in_files else "not kept") if member.dropped else "Level %d %s %s" % [character.level, view.race_name, view.caste_name]
		var row := _members.get_child(index) as SaveEditorMemberRow
		row.bind(member.character_id, character.name, detail, _texture(character.portrait_id), tag, role, member.dropped)
		row.set_strip(_compact)
		row.set_pressed_no_signal(member.character_id == _page_id)
	var current := state.party.characters().size()
	var maximum := clampi(_session.content.campaign.restrictions.maximum_party_size if _session.content.campaign != null else 6, 1, 6)
	_party_count.text = "%d of %d" % [current, maximum]
	var reason := "The party is full." if current >= maximum else "The scenario is holding this party's equipment, so no one can join until it is returned." if state.party.equipment_storage_active else ""
	_add_files.disabled = not reason.is_empty()
	# The 800x600 strip has no room to spare for an Add that can't be used (the party is full).
	_add_files.visible = not (_compact and _add_files.disabled)
	_add_reason.text = reason
	_add_reason.visible = not reason.is_empty() and not _compact
	_add_files.tooltip_text = reason
	# Strip rows change their own minimum size; the roster re-sorts once they settle.
	(%RosterBody as Container).queue_sort.call_deferred()


func _render_adventure(changes: Array[Dictionary]) -> void:
	(%AdventureScroll as Control).visible = _page_id.is_empty()
	var state := _session.draft.state
	var saved := _session.saved_state()
	for index: int in DIFFICULTIES.size():
		(_difficulty.get_child(index) as Button).set_pressed_no_signal(state.difficulty == DIFFICULTIES[index])
	(%DifficultyWas as Label).text = "was %s" % PartySetupView.difficulty_name(saved.difficulty) if saved.difficulty != state.difficulty else ""
	var available := _session.content.combat.available_monster_sets()
	var offered: Array[String] = []
	for index: int in MONSTER_SETS.size():
		var button := _monsters.get_child(index) as Button
		button.set_pressed_no_signal(state.monster_set == MONSTER_SETS[index])
		button.disabled = not available.has(MONSTER_SETS[index])
		button.tooltip_text = "%s doesn't include %s." % [SaveEditorFlows.campaign_title(_session), button.text] if button.disabled else ""
		if not button.disabled:
			offered.append(button.text)
	(%MonstersWas as Label).text = "was %s" % PartySetupView.monster_set_name(saved.monster_set) if saved.monster_set != state.monster_set else ""
	(%MonstersNote as Label).text = "%s includes %s." % [SaveEditorFlows.campaign_title(_session), " and ".join(offered)] if offered.size() < MONSTER_SETS.size() else "Changes which monster records new battles use."
	var before := _percent(saved.experience_multiplier)
	var after := _percent(state.experience_multiplier)
	(%Rate as Label).text = after
	(%RateWas as Label).text = before
	(%RateWas as Label).visible = before != after
	(%RateArrow as Label).visible = before != after
	_render_allies()
	_render_changes(changes)


func _render_allies() -> void:
	for child: Node in _ally_list.get_children():
		_ally_list.remove_child(child)
		child.queue_free()
	var current := {}
	for ally: MonsterState in _session.draft.state.party.allies():
		current[ally.id] = ally
	var saved_ids := {}
	var stays := 0
	# Saved allies keep their places, leaving ones struck through; new allies follow.
	for ally: MonsterState in _session.saved_state().party.allies():
		saved_ids[ally.id] = true
		if current.has(ally.id):
			stays += 1
			_ally_list.add_child(_ally_row(ally, "Stamina %d/%d · Armor %d" % [ally.current_health, ally.maximum_health, ally.armor], "", "Dismiss"))
		else:
			_ally_list.add_child(_ally_row(ally, "Leaves when you save · can't come back with the same rolls", "Leaves", ""))
	var joining := 0
	for ally_id: String in current:
		if saved_ids.has(ally_id):
			continue
		joining += 1
		var ally: MonsterState = current[ally_id]
		_ally_list.add_child(_ally_row(ally, "Stamina %d/%d · Armor %d · rolled just now" % [ally.current_health, ally.maximum_health, ally.armor], "Joins", "Remove"))
	var leaving := saved_ids.size() - stays
	(%AlliesCount as Label).text = "%d stay · %d join · %d leave" % [stays, joining, leaving] if joining > 0 or leaving > 0 else "%d traveling" % current.size()


func _ally_row(ally: MonsterState, detail: String, tag: String, action: String) -> Control:
	var ally_id := ally.id
	return SaveEditorRows.ally(ally.name, detail, tag, action, _creature_icon(ally.icon_id), func() -> void: _show_result(_session.dismiss_ally(ally_id)))


func _creature_icon(icon_id: int) -> Texture2D:
	var key := "cicn:%d" % icon_id
	if _media == null or icon_id == 0:
		return null
	if not _textures.has(key):
		var asset := _media.asset_by_resource("cicn", icon_id)
		_textures[key] = _media.image_texture(asset) if asset != null else null
	var texture: Texture2D = _textures[key]
	return texture


func _render_changes(changes: Array[Dictionary]) -> void:
	for child: Node in _change_list.get_children():
		_change_list.remove_child(child)
		child.queue_free()
	for change: Dictionary in changes:
		if change.has("memberId"):
			var member_id := RowFields.text(change, "memberId")
			_change_list.add_child(SaveEditorRows.change(change, "Open", "Edit this member's changes.", func() -> void: _select_page(member_id)))
		else:
			var index := RowFields.number(change, "index")
			var tip := RowFields.text(change, "undoReason") if not RowFields.flag(change, "canUndo") else "Undo this change."
			var row := SaveEditorRows.change(change, "Undo", tip, func() -> void: _show_result(_session.undo(index)))
			(row.get_child(1) as Button).disabled = not RowFields.flag(change, "canUndo")
			_change_list.add_child(row)
	(%ChangesEmpty as Label).visible = changes.is_empty()
	(%ChangeCount as Label).text = "%d unsaved" % changes.size() if not changes.is_empty() else ""


## One row per party change, then one per member with character edits ("Lothlorian · 3 changes").
## `with_undo` false is enough for counts and summaries; only the visible Changes list needs undo checks.
func _change_rows(with_undo: bool = true) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var listed := _session.draft.changes(with_undo)
	for index: int in listed.size():
		var row := listed[index].duplicate()
		row["index"] = index
		rows.append(row)
	for member: SaveEditMember in _session.draft.members():
		if member.dropped or not member.draft.is_dirty():
			continue
		var edits := member.draft.changes()
		var labels: Array[String] = []
		for edit: Dictionary in edits.slice(0, 3):
			labels.append(RowFields.text(edit, "label"))
		rows.append({"memberId": member.character_id, "label": "%s · %d change%s" % [member.state().name, edits.size(), "" if edits.size() == 1 else "s"], "detail": ", ".join(labels)})
	return rows


func _render_member_page() -> void:
	var member := _session.draft.member(_page_id) if not _page_id.is_empty() else null
	_member_page.visible = member != null
	var strip_drop := %StripDrop as Button
	strip_drop.visible = _compact and member != null and not member.dropped
	if member == null:
		return
	var character := member.state()
	(%MemberTitle as Label).text = character.name
	# The editor's name field already names a member who stays; the title only names one who leaves.
	(%MemberTitle as Label).visible = member.dropped
	_keep.visible = member.dropped and member.origin == SaveEditMember.SAVED
	_keep.set_pressed_no_signal(member.keep_in_files)
	var only_one := _session.draft.state.party.characters().size() <= 1
	_drop.visible = not member.dropped
	_drop.text = "Remove from party" if member.origin == SaveEditMember.ADDED else "Drop from party…"
	_drop.disabled = only_one and not member.dropped
	_drop.tooltip_text = "The party needs at least one character." if _drop.disabled else ""
	# At 800x600 Drop moves into the strip, so the header row shows only for a member who leaves.
	strip_drop.text = "Remove" if member.origin == SaveEditMember.ADDED else "Drop…"
	strip_drop.disabled = _drop.disabled
	strip_drop.tooltip_text = _drop.tooltip_text
	(%MemberSpacer as Control).visible = not member.dropped
	(get_node("Layout/Body/Right/MemberPage/MemberHeader") as Control).visible = not _compact or member.dropped
	var notice := %MemberNotice as Label
	if member.dropped and member.keep_in_files:
		notice.text = "%s leaves this save when you save and is kept as a new Character File. Undo the drop in Changes to bring them back." % character.name
	elif member.dropped:
		notice.text = "%s leaves this save when you save. Slot %s's backup will be the only copy. Undo the drop in Changes to bring them back." % [character.name, _session.slot_id]
	notice.visible = member.dropped
	_member_editor.visible = not member.dropped
	if member.dropped:
		_member_session = null
		return
	if _member_session == null or _member_for != member:
		_member_session = _session.member_editor(member.character_id)
		_member_for = member
		var character_id := member.character_id
		_member_editor.set_embedded(true, func(text: String) -> String: return _session.name_conflict(character_id, text))
		_member_editor.bind(_member_session, _texture, _imported_art, _compact)


func _select_page(page_id: String) -> void:
	_page_id = page_id
	_notice.visible = false
	_refresh()
	if not _prompt_family.is_empty():
		set_controller_prompts(_prompt_family, _prompt_preferences)


func _show_result(applied: bool) -> void:
	_notice.text = _session.last_error
	_notice.visible = not applied and not _session.last_error.is_empty()
	_refresh()


func _request_review() -> void:
	if not _save.disabled:
		_flows.request_review(_change_rows(false))


func _texture(asset_id: String) -> Texture2D:
	if _media == null or asset_id.is_empty():
		return null
	if not _textures.has(asset_id):
		var asset := _media.asset_by_id(asset_id)
		_textures[asset_id] = _media.image_texture(asset) if asset != null else null
	var texture: Texture2D = _textures[asset_id]
	return texture


## Older saves record no frozen rate (-1); show a dash rather than a negative percentage.
static func _percent(multiplier: float) -> String:
	return "%d%%" % roundi(multiplier * 100.0) if multiplier >= 0.0 else "—"
