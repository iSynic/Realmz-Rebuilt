class_name CharacterWorkspaceController
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


func present_vault(parent: VBoxContainer, view: GameView, appearance_textures: Dictionary, text_scale: float, back_label: String = "Back", media: ClassicMediaCatalog = null) -> void:
	if parent == null:
		return
	_vault_parent = parent
	_vault_view = view
	_vault_appearance_textures = appearance_textures
	_vault_text_scale = text_scale
	_vault_back_label = back_label
	_vault_media = media
	_clear(parent)
	if not _vault_inspection_revision_hash.is_empty():
		_render_vault_inspection()
		return
	var header := HBoxContainer.new()
	header.name = "CharacterFilesHeader"
	header.add_theme_constant_override("separation", 8)
	var back := Button.new()
	back.text = back_label
	back.pressed.connect(func() -> void: vault_back_requested.emit())
	header.add_child(back)
	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)
	var current_revisions := _current_vault_revisions()
	header.add_child(_label("%d available" % current_revisions.size(), MUTED, 13))
	parent.add_child(header)
	if _vault_revisions.is_empty():
		_add_card(parent, "Character vault is empty", "No immutable .r2char revisions are installed. New characters can be published after they are added to a campaign party.")
		return
	parent.add_child(_label("Current Character Files", GOLD, 15))
	if view != null and view.campaign_summary != null:
		parent.add_child(_label("Eligibility shown for %s" % view.campaign_summary.title, MUTED, 11))
	var list := GridContainer.new()
	list.name = "CharacterFileList"
	list.columns = 1 if _layout_profile == UiLayoutProfile.COMPACT else 2
	list.add_theme_constant_override("h_separation", 8)
	list.add_theme_constant_override("v_separation", 8)
	for revision: CharacterVaultRevisionView in current_revisions:
		_render_vault_current_row(list, revision, view)
	parent.add_child(list)
	var history_count := _vault_revisions.size() - current_revisions.size()
	var history_button := Button.new()
	history_button.text = ("Hide revision history" if _vault_show_history else "Revision history and archives") + " (%d)" % history_count
	history_button.disabled = history_count == 0
	history_button.pressed.connect(func() -> void:
		_vault_show_history = not _vault_show_history
		_refresh_vault()
	)
	parent.add_child(history_button)
	if _vault_show_history:
		_render_vault_history(parent, current_revisions)


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
	var panel := PanelContainer.new()
	panel.name = "CharacterFile_%s" % revision.character_id.validate_node_name()
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card := VBoxContainer.new()
	card.custom_minimum_size.y = 138.0
	card.add_theme_constant_override("separation", 6)
	panel.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var media_pair := HBoxContainer.new()
	media_pair.name = "StoredAppearancePair"
	media_pair.add_theme_constant_override("separation", 3)
	var portrait := TextureRect.new()
	portrait.name = "StoredPortrait"
	portrait.custom_minimum_size = Vector2(58.0, 58.0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.texture = _vault_appearance_textures.get(revision.portrait_id) as Texture2D
	media_pair.add_child(portrait)
	var tactical := TextureRect.new()
	tactical.name = "StoredTacticalIcon"
	tactical.custom_minimum_size = Vector2(58.0, 58.0)
	tactical.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tactical.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tactical.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if revision.character != null:
		tactical.texture = _vault_appearance_textures.get(revision.character.combat_icon_id) as Texture2D
	media_pair.add_child(tactical)
	row.add_child(media_pair)
	var summary := VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_child(_label(revision.name, GOLD, 18))
	var character := revision.character
	var identity := "Level %d • %s / %s" % [revision.level, character.race_name if character != null else revision.race_id, character.caste_name if character != null else revision.caste_id]
	summary.add_child(_label(identity, Color("e0e2e5"), 14))
	var facts := "Stored character record"
	if character != null:
		facts = "ST %d/%d • SP %d/%d • AR %d • Load %d/%d" % [character.current_health, character.maximum_health, character.spell_points, character.maximum_spell_points, character.armor, character.carried_load, character.maximum_load]
	summary.add_child(_label(facts, MUTED, 12))
	var origin := "Realmz character file" if revision.source_campaign_id.is_empty() else "From %s" % revision.source_campaign_id
	if not revision.publication_label.is_empty():
		origin += " • %s" % revision.publication_label
	summary.add_child(_label(origin, MUTED, 11))
	row.add_child(summary)
	var actions := HBoxContainer.new()
	actions.name = "CharacterFileActions"
	actions.add_theme_constant_override("separation", 6)
	actions.add_child(_label("Eligible" if revision.eligible else "Unavailable", Color("75c889") if revision.eligible else Color("ef7770"), 13))
	actions.add_spacer(true)
	var inspect := Button.new()
	inspect.text = "Inspect"
	inspect.disabled = character == null
	inspect.tooltip_text = "Open the complete detached character record." if not inspect.disabled else "This vault revision has no valid character record."
	if not inspect.disabled:
		inspect.pressed.connect(_inspect_vault.bind(revision.revision_hash))
	actions.add_child(inspect)
	var import_button := _vault_import_button(revision, view)
	actions.add_child(import_button)
	var archive := Button.new()
	archive.text = "Archive"
	archive.tooltip_text = "Remove this character from the active list without deleting immutable history."
	archive.pressed.connect(_confirm_vault_archive.bind(revision))
	actions.add_child(archive)
	card.add_child(actions)
	parent.add_child(panel)


func _vault_import_button(revision: CharacterVaultRevisionView, view: GameView) -> Button:
	var button := Button.new()
	button.text = "Add to party"
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
		button.pressed.connect(func() -> void: intent_submitted.emit(PlayerIntent.import_vault_character(revision.character_id, revision.revision_hash)))
	return button


func _render_vault_history(parent: Container, current_revisions: Array[CharacterVaultRevisionView]) -> void:
	var current_hashes: Dictionary = {}
	for revision: CharacterVaultRevisionView in current_revisions:
		current_hashes[revision.revision_hash] = true
	parent.add_child(_label("Earlier revisions", GOLD, 17))
	for revision: CharacterVaultRevisionView in _vault_revisions:
		if current_hashes.has(revision.revision_hash):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var state := "Archived" if revision.archived else "Earlier"
		var label := _label("%s • %s • L%d • %s" % [revision.name, state, revision.level, revision.revision_hash.left(12)], MUTED, 13)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var inspect := Button.new()
		inspect.text = "Inspect"
		inspect.disabled = revision.character == null
		if not inspect.disabled:
			inspect.pressed.connect(_inspect_vault.bind(revision.revision_hash))
		row.add_child(inspect)
		if revision.archived:
			var restore := Button.new()
			restore.text = "Restore as current"
			restore.pressed.connect(func() -> void: vault_restore_requested.emit(revision.character_id, revision.revision_hash))
			row.add_child(restore)
		parent.add_child(row)


func _inspect_vault(revision_hash: String) -> void:
	_vault_inspection_revision_hash = revision_hash
	_selected_tab = &"overview"
	_refresh_vault()


func _refresh_vault() -> void:
	if _vault_parent != null:
		present_vault(_vault_parent, _vault_view, _vault_appearance_textures, _vault_text_scale, _vault_back_label, _vault_media)


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
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var back := Button.new()
	back.text = "Back to character vault"
	back.pressed.connect(func() -> void:
		_vault_inspection_revision_hash = ""
		_refresh_vault()
	)
	header.add_child(back)
	var heading := _label("Inspect %s" % revision.name, GOLD, 20)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	_vault_parent.add_child(header)
	var eligibility := "Eligible for this campaign" if revision.eligible else "Not eligible for this campaign"
	var reasons := "" if revision.eligibility_reasons.is_empty() else "\n%s" % "\n".join(revision.eligibility_reasons)
	_vault_parent.add_child(_label("%s%s" % [eligibility, reasons], Color("75c889") if revision.eligible else Color("ef7770"), 13))
	var sheet := ClassicCharacterSheet.new()
	sheet.name = "VaultCharacterSheet"
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
	sheet.tab_changed.connect(func(tab_id: StringName) -> void: _selected_tab = tab_id)
	_vault_parent.add_child(sheet)


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


func present(parent: VBoxContainer, view: GameView, appearance_textures: Dictionary, settings: PresentationSettings, media: ClassicMediaCatalog = null) -> void:
	if parent == null or view == null:
		return
	if view.party_members.is_empty():
		_add_card(parent, "No characters", "Begin a campaign or import an eligible vault character.")
		return
	_render_party_order_summary(parent, view)
	if _party_order_open:
		_render_party_order(parent, view)
	var sheet := ClassicCharacterSheet.new()
	sheet.name = "ClassicCharacterSheet"
	sheet.present(view.party_members, _selected_character_id, appearance_textures, settings.text_scale, _selected_tab, view.portrait_options, view.combat_icon_options, view.availability(&"change_character_appearance"), media, _layout_profile)
	_selected_character_id = sheet.selected_character_id()
	sheet.character_selected.connect(func(character_id: String) -> void: _selected_character_id = character_id)
	sheet.tab_changed.connect(func(tab_id: StringName) -> void: _selected_tab = tab_id)
	sheet.appearance_change_requested.connect(_submit_character_appearance)
	parent.add_child(sheet)


func _render_party_order_summary(parent: VBoxContainer, view: GameView) -> void:
	var panel := PanelContainer.new()
	panel.name = "PartyOrderSummary"
	panel.theme_type_variation = &"ClassicInset"
	var row: BoxContainer = VBoxContainer.new() if _layout_profile == UiLayoutProfile.COMPACT else HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var names: Array[String] = []
	for index: int in view.party_members.size():
		names.append("%d. %s" % [index + 1, view.party_members[index].name])
	var summary_text := "%d characters in party order" % names.size() if _layout_profile == UiLayoutProfile.COMPACT else "Party order  •  %s" % "  →  ".join(names)
	var summary := _label(summary_text, MUTED, 13)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(summary)
	var toggle := Button.new()
	toggle.text = "Done" if _layout_profile == UiLayoutProfile.COMPACT and _party_order_open else "Reorder" if _layout_profile == UiLayoutProfile.COMPACT else "Done Reordering" if _party_order_open else "Reorder Party"
	toggle.disabled = not view.availability(&"reorder_party").enabled
	toggle.tooltip_text = view.availability(&"reorder_party").reason if toggle.disabled else "Stage a new complete party order."
	if not toggle.disabled:
		toggle.pressed.connect(func() -> void:
			_party_order_open = not _party_order_open
			refresh_requested.emit()
		)
	row.add_child(toggle)
	parent.add_child(panel)


func _submit_character_appearance(character_id: String, appearance_kind: StringName, appearance_id: String) -> void:
	_selected_character_id = character_id
	_selected_tab = &"appearance"
	intent_submitted.emit(PlayerIntent.change_character_appearance(character_id, appearance_kind, appearance_id))


func _render_party_order(parent: VBoxContainer, view: GameView) -> void:
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
	_add_section_heading(parent, "Reorder the party")
	var availability := view.availability(&"reorder_party")
	for index: int in _draft_order_ids.size():
		var character: CharacterView = characters_by_id[_draft_order_ids[index]]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var label := _label("%d. %s • Level %d %s" % [index + 1, character.name, character.level, character.caste_name], Color("e0e2e5"), 14)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var move_up := Button.new()
		move_up.text = "Move Up"
		move_up.disabled = not availability.enabled or index == 0
		move_up.tooltip_text = availability.reason if not availability.enabled else "Already first." if index == 0 else "Move %s one slot earlier." % character.name
		if not move_up.disabled:
			move_up.pressed.connect(_move_draft.bind(index, -1))
		row.add_child(move_up)
		var move_down := Button.new()
		move_down.text = "Move Down"
		move_down.disabled = not availability.enabled or index == _draft_order_ids.size() - 1
		move_down.tooltip_text = availability.reason if not availability.enabled else "Already last." if index == _draft_order_ids.size() - 1 else "Move %s one slot later." % character.name
		if not move_down.disabled:
			move_down.pressed.connect(_move_draft.bind(index, 1))
		row.add_child(move_down)
		parent.add_child(row)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	var apply := Button.new()
	apply.text = "Apply Party Order"
	apply.disabled = not availability.enabled or _draft_order_ids == current_ids
	apply.tooltip_text = availability.reason if not availability.enabled else "Choose a different order first." if _draft_order_ids == current_ids else "Commit this complete party permutation."
	if not apply.disabled:
		apply.pressed.connect(func() -> void: intent_submitted.emit(PlayerIntent.reorder_party(_draft_order_ids)))
	actions.add_child(apply)
	var cancel := Button.new()
	cancel.text = "Cancel Order Changes"
	cancel.disabled = _draft_order_ids == current_ids
	cancel.tooltip_text = "The displayed order already matches the session." if cancel.disabled else "Discard the staged order without changing the party."
	if not cancel.disabled:
		cancel.pressed.connect(func() -> void:
			_draft_order_ids = _source_order_ids.duplicate()
			refresh_requested.emit()
		)
	actions.add_child(cancel)
	parent.add_child(actions)
	parent.add_child(HSeparator.new())


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


func _add_section_heading(parent: Container, title: String, detail: String = "") -> void:
	var row := HBoxContainer.new()
	var heading := _label(title, GOLD, 18)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	if not detail.is_empty():
		var note := _label(detail, MUTED, 13)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(note)
	parent.add_child(row)


func _add_card(parent: Container, title: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	var column := VBoxContainer.new()
	panel.add_child(column)
	column.add_child(_label(title, GOLD, 16))
	var body := _label(detail, MUTED, 13)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)
	parent.add_child(panel)


func _label(text: String, color: Color, size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_color_override("font_color", color)
	result.add_theme_font_size_override("font_size", size)
	return result


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
