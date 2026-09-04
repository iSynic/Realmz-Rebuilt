## Binds detached character records and party-order actions to the Character screen.
class_name CharacterScreenController
extends RefCounted

signal intent_submitted(intent: PlayerIntent)
signal refresh_requested
signal vault_back_requested
signal vault_archive_requested(character_id: String)
signal vault_restore_requested(character_id: String, revision_hash: String)

const GOLD := Color("d5b45d")
const MUTED := Color("9aa0a8")

var _selected_character_id: String = ""
var _selected_tab: StringName = &"overview"
var _party_order_open: bool = false
var _source_order_ids: Array[String] = []
var _draft_order_ids: Array[String] = []
var _vault_revisions: Array[CharacterVaultRevisionView] = []
var _vault_inspection_revision_hash: String = ""
var _vault_target: Control
var _vault_screen: VaultScreen
var _vault_parent: VBoxContainer
var _vault_view: GameView
var _vault_appearance_textures: Dictionary = {}
var _vault_text_scale: float = 1.0
var _vault_back_label: String = "Back"
var _vault_media: ClassicMediaCatalog
var _vault_show_history: bool = false
var _layout_profile: StringName = UiLayoutProfile.WIDE


func set_layout_profile(profile_id: StringName) -> void:
	_layout_profile = profile_id


func reset() -> void:
	_selected_character_id = ""
	_selected_tab = &"overview"
	_party_order_open = false
	_source_order_ids.clear()
	_draft_order_ids.clear()
	_vault_inspection_revision_hash = ""
	_vault_show_history = false
	_vault_target = null
	_vault_parent = null
	_vault_view = null
	_vault_media = null


func select_character(character_id: String, view: GameView) -> bool:
	if view == null:
		return false
	for character: CharacterView in view.party_members:
		if character.id == character_id:
			_selected_character_id = character_id
			return true
	return false


func set_vault_revisions(revisions: Array[CharacterVaultRevisionView]) -> void:
	_vault_revisions = revisions.duplicate()


func clear_vault_inspection() -> void:
	_vault_inspection_revision_hash = ""


func handle_vault_back() -> bool:
	if _vault_inspection_revision_hash.is_empty():
		return false
	_vault_inspection_revision_hash = ""
	_refresh_vault()
	return true


func present_vault(target: Control, view: GameView, appearance_textures: Dictionary, text_scale: float, back_label: String = "Back", media: ClassicMediaCatalog = null) -> void:
	var screen := target as VaultScreen
	if screen == null:
		return
	_vault_target = target
	_vault_screen = screen
	_vault_parent = screen.body_control()
	_vault_view = view
	_vault_appearance_textures = appearance_textures
	_vault_text_scale = text_scale
	_vault_back_label = back_label
	_vault_media = media
	if not _vault_inspection_revision_hash.is_empty():
		screen.prepare_inspection_layout()
		_render_vault_inspection()
		return
	screen.prepare_list_layout(_layout_profile == UiLayoutProfile.COMPACT)
	var back := screen.list_back_button()
	back.text = back_label
	_clear_pressed_connections(back)
	back.pressed.connect(func() -> void: vault_back_requested.emit())
	var current_revisions := _current_vault_revisions()
	_bind_label(screen.available_count(), "%d available" % current_revisions.size(), MUTED, 13)
	var history_count := _vault_revisions.size() - current_revisions.size()
	var history_button := screen.history_toggle()
	history_button.text = ("Hide revision history" if _vault_show_history else "Revision history and archives") + " (%d)" % history_count
	history_button.disabled = history_count == 0
	_clear_pressed_connections(history_button)
	if not history_button.disabled:
		history_button.pressed.connect(func() -> void:
			_vault_show_history = not _vault_show_history
			_refresh_vault()
		)
	if _vault_revisions.is_empty():
		screen.empty_state().visible = true
		screen.current_title().visible = false
		return
	_bind_label(screen.current_title(), "Current Character Files", GOLD, 15)
	if view != null and view.campaign_summary != null:
		var context := screen.eligibility_context()
		context.visible = true
		_bind_label(context, "Eligibility shown for %s" % view.campaign_summary.title, MUTED, 11)
	for revision: CharacterVaultRevisionView in current_revisions:
		_render_vault_current_row(screen.character_file_list(), revision, view)
	if _vault_show_history:
		screen.history_title().visible = true
		_render_vault_history(screen.history_rows(), current_revisions)


func _current_vault_revisions() -> Array[CharacterVaultRevisionView]:
	var result: Array[CharacterVaultRevisionView] = []
	var selected_by_character: Dictionary = {}
	for revision: CharacterVaultRevisionView in _vault_revisions:
		if revision.archived:
			continue
		if not selected_by_character.has(revision.character_id) or revision.is_current:
			selected_by_character[revision.character_id] = revision
	for revision: CharacterVaultRevisionView in selected_by_character.values():
		result.append(revision)
	result.sort_custom(func(left: CharacterVaultRevisionView, right: CharacterVaultRevisionView) -> bool: return left.name.naturalnocasecmp_to(right.name) < 0)
	return result


func _render_vault_current_row(parent: Container, revision: CharacterVaultRevisionView, view: GameView) -> void:
	var panel := _vault_screen.character_card_scene.instantiate() as PanelContainer
	if panel == null:
		push_error("Character File card scene must instantiate a PanelContainer.")
		return
	panel.name = "CharacterFile_%s" % revision.character_id.validate_node_name()
	var portrait := panel.get_node("CardContent/Record/StoredAppearancePair/StoredPortrait") as TextureRect
	portrait.texture = _vault_appearance_textures.get(revision.portrait_id) as Texture2D
	var tactical := panel.get_node("CardContent/Record/StoredAppearancePair/StoredTacticalIcon") as TextureRect
	if revision.character != null:
		tactical.texture = _vault_appearance_textures.get(revision.character.combat_icon_id) as Texture2D
	_bind_label(panel.get_node("CardContent/Record/Summary/Name") as Label, revision.name, GOLD, 18)
	var character := revision.character
	var identity := "Level %d • %s / %s" % [revision.level, character.race_name if character != null else revision.race_id, character.caste_name if character != null else revision.caste_id]
	_bind_label(panel.get_node("CardContent/Record/Summary/Identity") as Label, identity, Color("e0e2e5"), 14)
	var facts := "Stored character record"
	if character != null:
		facts = "ST %d/%d • SP %d/%d • AR %d • Load %d/%d" % [character.current_health, character.maximum_health, character.spell_points, character.maximum_spell_points, character.armor, character.carried_load, character.maximum_load]
	_bind_label(panel.get_node("CardContent/Record/Summary/Facts") as Label, facts, MUTED, 12)
	var origin := "Realmz character file" if revision.source_campaign_id.is_empty() else "From %s" % revision.source_campaign_id
	if not revision.publication_label.is_empty():
		origin += " • %s" % revision.publication_label
	_bind_label(panel.get_node("CardContent/Record/Summary/Origin") as Label, origin, MUTED, 11)
	_bind_label(panel.get_node("CardContent/CharacterFileActions/Eligibility") as Label, "Eligible" if revision.eligible else "Unavailable", Color("75c889") if revision.eligible else Color("ef7770"), 13)
	var inspect := panel.get_node("CardContent/CharacterFileActions/Inspect") as Button
	inspect.disabled = character == null
	inspect.tooltip_text = "Open the complete detached character record." if not inspect.disabled else "This vault revision has no valid character record."
	if not inspect.disabled:
		inspect.pressed.connect(_inspect_vault.bind(revision.revision_hash))
	_bind_vault_import_button(panel.get_node("CardContent/CharacterFileActions/AddToParty") as Button, revision, view)
	var archive := panel.get_node("CardContent/CharacterFileActions/Archive") as Button
	archive.tooltip_text = "Remove this character from the active list without deleting immutable history."
	archive.pressed.connect(_confirm_vault_archive.bind(revision))
	parent.add_child(panel)


func _bind_vault_import_button(button: Button, revision: CharacterVaultRevisionView, view: GameView) -> void:
	button.tooltip_text = "\n".join(revision.eligibility_reasons)
	if view == null or not view.session_started:
		button.disabled = true
		button.tooltip_text = "Choose a campaign before importing a character."
	else:
		var availability := view.availability(&"import_vault_character")
		button.disabled = not availability.enabled or not revision.eligible or revision.archived
		if not availability.enabled:
			button.tooltip_text = availability.reason
		elif revision.archived:
			button.tooltip_text = "Restore an archived revision before importing it."
	if not button.disabled:
		button.pressed.connect(func() -> void: intent_submitted.emit(PartyIntents.import_vault_character(revision.character_id, revision.revision_hash)))


func _render_vault_history(parent: Container, current_revisions: Array[CharacterVaultRevisionView]) -> void:
	var current_hashes: Dictionary = {}
	for revision: CharacterVaultRevisionView in current_revisions:
		current_hashes[revision.revision_hash] = true
	for revision: CharacterVaultRevisionView in _vault_revisions:
		if current_hashes.has(revision.revision_hash):
			continue
		var row := _vault_screen.history_row_scene.instantiate() as HBoxContainer
		if row == null:
			push_error("Character File history scene must instantiate an HBoxContainer.")
			return
		var state := "Archived" if revision.archived else "Earlier"
		_bind_label(row.get_node("Summary") as Label, "%s • %s • L%d • %s" % [revision.name, state, revision.level, revision.revision_hash.left(12)], MUTED, 13)
		var inspect := row.get_node("Inspect") as Button
		inspect.disabled = revision.character == null
		if not inspect.disabled:
			inspect.pressed.connect(_inspect_vault.bind(revision.revision_hash))
		var restore := row.get_node("Restore") as Button
		restore.visible = revision.archived
		if revision.archived:
			restore.pressed.connect(func() -> void: vault_restore_requested.emit(revision.character_id, revision.revision_hash))
		parent.add_child(row)


func _inspect_vault(revision_hash: String) -> void:
	_vault_inspection_revision_hash = revision_hash
	_selected_tab = &"overview"
	_refresh_vault()


func _refresh_vault() -> void:
	if is_instance_valid(_vault_target):
		present_vault(_vault_target, _vault_view, _vault_appearance_textures, _vault_text_scale, _vault_back_label, _vault_media)


func _render_vault_inspection() -> void:
	var revision: CharacterVaultRevisionView
	for candidate: CharacterVaultRevisionView in _vault_revisions:
		if candidate.revision_hash == _vault_inspection_revision_hash:
			revision = candidate
			break
	if revision == null or revision.character == null:
		_vault_inspection_revision_hash = ""
		_refresh_vault()
		return
	var back := _vault_screen.inspection_back_button()
	_clear_pressed_connections(back)
	back.pressed.connect(func() -> void:
		_vault_inspection_revision_hash = ""
		_refresh_vault()
	)
	_bind_label(_vault_screen.inspection_heading(), "Inspect %s" % revision.name, GOLD, 20)
	var eligibility := "Eligible for this campaign" if revision.eligible else "Not eligible for this campaign"
	var reasons := "" if revision.eligibility_reasons.is_empty() else "\n%s" % "\n".join(revision.eligibility_reasons)
	_bind_label(_vault_screen.inspection_eligibility(), "%s%s" % [eligibility, reasons], Color("75c889") if revision.eligible else Color("ef7770"), 13)
	var sheet := _vault_screen.character_sheet()
	sheet.present(
		[revision.character],
		revision.character.id,
		_vault_appearance_textures,
		_vault_text_scale,
		_selected_tab,
		_vault_view.portrait_options if _vault_view != null else [],
		_vault_view.combat_icon_options if _vault_view != null else [],
		ActionAvailabilityView.new(&"change_character_appearance", false, "Vault inspection never changes a stored revision."),
		_vault_media,
		_layout_profile
	)
	if not sheet.tab_changed.is_connected(_on_vault_sheet_tab_changed):
		sheet.tab_changed.connect(_on_vault_sheet_tab_changed)


func _on_vault_sheet_tab_changed(tab_id: StringName) -> void:
	_selected_tab = tab_id


func _confirm_vault_archive(revision: CharacterVaultRevisionView) -> void:
	if _vault_parent == null:
		return
	var confirmation := ConfirmationDialog.new()
	confirmation.title = "Archive character"
	confirmation.dialog_text = "Archive %s? Campaign saves are unchanged, and this revision can be restored later." % revision.name
	confirmation.ok_button_text = "Archive"
	confirmation.confirmed.connect(func() -> void: vault_archive_requested.emit(revision.character_id))
	confirmation.visibility_changed.connect(func() -> void:
		if not confirmation.visible:
			confirmation.queue_free()
	)
	_vault_parent.add_child(confirmation)
	confirmation.popup_centered(Vector2i(480, 180))


func draft_order_ids() -> Array[String]:
	return _draft_order_ids.duplicate()


func present(screen: CharacterScreen, view: GameView, appearance_textures: Dictionary, settings: PresentationSettings, media: ClassicMediaCatalog = null) -> void:
	if screen == null or view == null:
		return
	screen.prepare_for_render()
	if view.party_members.is_empty():
		screen.empty_state().visible = true
		return
	_render_party_order_summary(screen, view)
	if _party_order_open:
		_render_party_order(screen, view)
	var sheet := screen.character_sheet()
	sheet.visible = true
	sheet.name = "ClassicCharacterSheet"
	sheet.present(view.party_members, _selected_character_id, appearance_textures, settings.text_scale, _selected_tab, view.portrait_options, view.combat_icon_options, view.availability(&"change_character_appearance"), media, _layout_profile)
	_selected_character_id = sheet.selected_character_id()
	if not sheet.character_selected.is_connected(_on_sheet_character_selected):
		sheet.character_selected.connect(_on_sheet_character_selected)
	if not sheet.tab_changed.is_connected(_on_sheet_tab_changed):
		sheet.tab_changed.connect(_on_sheet_tab_changed)
	if not sheet.appearance_change_requested.is_connected(_submit_character_appearance):
		sheet.appearance_change_requested.connect(_submit_character_appearance)


func _on_sheet_character_selected(character_id: String) -> void:
	_selected_character_id = character_id


func _on_sheet_tab_changed(tab_id: StringName) -> void:
	_selected_tab = tab_id


func _render_party_order_summary(screen: CharacterScreen, view: GameView) -> void:
	var panel := screen.party_order_summary()
	panel.visible = true
	var row := panel.get_node("SummaryRow") as BoxContainer
	row.vertical = _layout_profile == UiLayoutProfile.COMPACT
	var names: Array[String] = []
	for index: int in view.party_members.size():
		names.append("%d. %s" % [index + 1, view.party_members[index].name])
	var summary_text := "%d characters in party order" % names.size() if _layout_profile == UiLayoutProfile.COMPACT else "Party order  •  %s" % "  →  ".join(names)
	var summary := row.get_node("Summary") as Label
	_bind_label(summary, summary_text, MUTED, 13)
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var toggle := row.get_node("Toggle") as Button
	toggle.text = "Done" if _layout_profile == UiLayoutProfile.COMPACT and _party_order_open else "Reorder" if _layout_profile == UiLayoutProfile.COMPACT else "Done Reordering" if _party_order_open else "Reorder Party"
	toggle.disabled = not view.availability(&"reorder_party").enabled
	toggle.tooltip_text = view.availability(&"reorder_party").reason if toggle.disabled else "Stage a new complete party order."
	_clear_pressed_connections(toggle)
	if not toggle.disabled:
		toggle.pressed.connect(func() -> void:
			_party_order_open = not _party_order_open
			refresh_requested.emit()
		)


func _submit_character_appearance(character_id: String, appearance_kind: StringName, appearance_id: String) -> void:
	_selected_character_id = character_id
	_selected_tab = &"appearance"
	intent_submitted.emit(PartyIntents.change_appearance(character_id, appearance_kind, appearance_id))


func _render_party_order(screen: CharacterScreen, view: GameView) -> void:
	var editor := screen.party_order_editor()
	editor.visible = true
	var parent := screen.party_order_rows()
	var current_ids: Array[String] = []
	var characters_by_id: Dictionary = {}
	for character: CharacterView in view.party_members:
		current_ids.append(character.id)
		characters_by_id[character.id] = character
	if current_ids != _source_order_ids:
		_source_order_ids = current_ids.duplicate()
		_draft_order_ids = current_ids.duplicate()
	elif not _valid_draft(current_ids, characters_by_id):
		_draft_order_ids = current_ids.duplicate()
	var availability := view.availability(&"reorder_party")
	for index: int in _draft_order_ids.size():
		var character: CharacterView = characters_by_id[_draft_order_ids[index]]
		var row := screen.party_order_row_scene.instantiate() as HBoxContainer
		if row == null:
			push_error("Party-order row scene must instantiate an HBoxContainer.")
			return
		var label := row.get_node("CharacterSummary") as Label
		_bind_label(label, "%d. %s • Level %d %s" % [index + 1, character.name, character.level, character.caste_name], Color("e0e2e5"), 14)
		var move_up := row.get_node("MoveUp") as Button
		move_up.disabled = not availability.enabled or index == 0
		move_up.tooltip_text = availability.reason if not availability.enabled else "Already first." if index == 0 else "Move %s one slot earlier." % character.name
		if not move_up.disabled:
			move_up.pressed.connect(_move_draft.bind(index, -1))
		var move_down := row.get_node("MoveDown") as Button
		move_down.disabled = not availability.enabled or index == _draft_order_ids.size() - 1
		move_down.tooltip_text = availability.reason if not availability.enabled else "Already last." if index == _draft_order_ids.size() - 1 else "Move %s one slot later." % character.name
		if not move_down.disabled:
			move_down.pressed.connect(_move_draft.bind(index, 1))
		parent.add_child(row)
	var apply := editor.get_node("EditorContent/Actions/Apply") as Button
	apply.disabled = not availability.enabled or _draft_order_ids == current_ids
	apply.tooltip_text = availability.reason if not availability.enabled else "Choose a different order first." if _draft_order_ids == current_ids else "Commit this complete party permutation."
	_clear_pressed_connections(apply)
	if not apply.disabled:
		apply.pressed.connect(func() -> void: intent_submitted.emit(PartyIntents.reorder(_draft_order_ids)))
	var cancel := editor.get_node("EditorContent/Actions/Cancel") as Button
	cancel.disabled = _draft_order_ids == current_ids
	cancel.tooltip_text = "The displayed order already matches the session." if cancel.disabled else "Discard the staged order without changing the party."
	_clear_pressed_connections(cancel)
	if not cancel.disabled:
		cancel.pressed.connect(func() -> void:
			_draft_order_ids = _source_order_ids.duplicate()
			refresh_requested.emit()
		)


func _clear_pressed_connections(button: Button) -> void:
	for connection: Dictionary in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"] as Callable)


func _bind_label(label: Label, text: String, color: Color, size: int) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)


func _valid_draft(current_ids: Array[String], characters_by_id: Dictionary) -> bool:
	if _draft_order_ids.size() != current_ids.size():
		return false
	var seen: Dictionary = {}
	for character_id: String in _draft_order_ids:
		if seen.has(character_id) or not characters_by_id.has(character_id):
			return false
		seen[character_id] = true
	return true


func _move_draft(index: int, offset: int) -> void:
	var destination := index + offset
	if index < 0 or index >= _draft_order_ids.size() or destination < 0 or destination >= _draft_order_ids.size():
		return
	var moved_character_id: String = _draft_order_ids[index]
	_draft_order_ids[index] = _draft_order_ids[destination]
	_draft_order_ids[destination] = moved_character_id
	refresh_requested.emit()
