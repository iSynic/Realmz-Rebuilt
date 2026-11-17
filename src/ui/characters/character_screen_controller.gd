## Binds detached character records and party-order actions to the Character screen.
class_name CharacterScreenController
extends RefCounted

signal intent_submitted(intent: PlayerIntent)
signal refresh_requested
signal vault_back_requested
signal vault_character_requested(operation: StringName, character_id: String, revision_hash: String)
signal vault_maintenance_requested(operation: StringName)

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
var _vault_view: GameView
var _vault_appearance_textures: Dictionary = {}
var _vault_text_scale: float = 1.0
var _vault_back_label: String = "Back"
var _vault_media: ClassicMediaCatalog
var _vault_binder := VaultScreenBinder.new()
var _editor_session: CharacterEditorSession
var _editor_textures: Dictionary = {}
var _layout_profile: StringName = UiLayoutProfile.WIDE
var character_art_dialog: CharacterArtDialog


func _init() -> void:
	_bind_vault_binder()


func set_layout_profile(profile_id: StringName) -> void:
	_layout_profile = profile_id
	if _editor_session != null and is_instance_valid(_vault_screen):
		_vault_screen.character_editor.apply_compact(profile_id == UiLayoutProfile.COMPACT)


func reset() -> void:
	_selected_character_id = ""
	_selected_tab = &"overview"
	_party_order_open = false
	_source_order_ids.clear()
	_draft_order_ids.clear()
	_vault_inspection_revision_hash = ""
	_vault_target = null
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


func set_vault_revisions(revisions: Array[CharacterVaultRevisionView], notice: String = "") -> void:
	_vault_revisions = revisions.duplicate()
	_vault_binder.set_revisions(revisions, notice)


func clear_vault_inspection() -> void:
	_vault_inspection_revision_hash = ""


func present_repair(details: String, review: bool, can_repair: bool, has_backup: bool) -> void:
	if is_instance_valid(_vault_screen) and _vault_screen.is_visible_in_tree():
		_vault_screen.repair_dialog.present(details, review, can_repair, has_backup)


## Opens the Character Files editor over the library until `session` closes. The draft
## survives leaving the route; returning rebinds it to the re-created screen.
func present_editor(session: CharacterEditorSession) -> void:
	if not is_instance_valid(_vault_screen):
		return
	_editor_session = session
	_vault_inspection_revision_hash = ""
	_editor_textures = _vault_appearance_textures.duplicate()
	var imported: Array[CharacterAppearanceOptionView] = []
	if _vault_media != null:
		imported.append_array(_vault_media.imported_appearance_options(CharacterAppearanceDefinition.PORTRAIT))
		imported.append_array(_vault_media.imported_appearance_options(CharacterAppearanceDefinition.COMBAT_ICON))
	_vault_screen.prepare_editor_layout()
	_vault_screen.character_editor.bind(session, _editor_texture, imported, _layout_profile == UiLayoutProfile.COMPACT)


## Decodes one portrait or icon the first time the editor shows it.
func _editor_texture(asset_id: String) -> Texture2D:
	_cache_texture(_editor_textures, asset_id)
	return _editor_textures.get(asset_id) as Texture2D


## Returns from the editor to the library, selecting the edited character.
func close_editor() -> void:
	_editor_session = null
	_editor_textures.clear()
	_refresh_vault()
	restore_vault_focus(false)


func handle_vault_back() -> bool:
	if _editor_session != null and is_instance_valid(_vault_screen):
		return _vault_screen.character_editor.handle_back()
	if is_instance_valid(_vault_screen) and _vault_screen.repair_dialog.visible:
		if not _vault_screen.repair_dialog.committing():
			_vault_screen.repair_dialog.hide()
			vault_maintenance_requested.emit(&"cancel")
		return true
	if _vault_inspection_revision_hash.is_empty():
		return _vault_binder.handle_back()
	_vault_inspection_revision_hash = ""
	_refresh_vault()
	return true


func present_vault(target: Control, view: GameView, appearance_textures: Dictionary, text_scale: float, back_label: String = "Back", media: ClassicMediaCatalog = null) -> void:
	var screen := target as VaultScreen
	if screen == null:
		return
	_vault_target = target
	_vault_screen = screen
	if not screen.repair_dialog.operation_requested.is_connected(vault_maintenance_requested.emit):
		screen.repair_dialog.operation_requested.connect(vault_maintenance_requested.emit)
	_vault_view = view
	_vault_appearance_textures = appearance_textures
	_vault_text_scale = text_scale
	_vault_back_label = back_label
	_vault_media = media
	if _editor_session != null:
		if screen.character_editor.session() != _editor_session:
			present_editor(_editor_session)
		else:
			screen.prepare_editor_layout()
			screen.character_editor.apply_compact(_layout_profile == UiLayoutProfile.COMPACT)
		return
	if not _vault_inspection_revision_hash.is_empty():
		screen.prepare_inspection_layout()
		_render_vault_inspection()
		return
	_vault_binder.media_catalog = media
	_vault_binder.present(screen, view, appearance_textures, back_label, _layout_profile == UiLayoutProfile.COMPACT)


func present_vault_status(text: String, is_error: bool) -> void:
	_vault_binder.present_status(text, is_error)


func set_vault_controller_prompts(family: String, preferences: ControllerPreferences) -> void:
	_vault_binder.set_controller_prompts(family, preferences)


func restore_vault_focus(opened: bool) -> void:
	if _vault_inspection_revision_hash.is_empty():
		_vault_binder.restore_focus(opened)


## The open vault dialog or editor overlay owns controller focus until it closes.
func vault_dialog_focus_root() -> Node:
	if not is_instance_valid(_vault_screen) or not _vault_screen.is_visible_in_tree():
		return null
	if _editor_session != null and _vault_screen.character_editor.overlay_focus_root() != null:
		return _vault_screen.character_editor.overlay_focus_root()
	if _vault_screen.repair_dialog.visible:
		return _vault_screen.repair_dialog
	return _vault_screen.archive_confirmation if _vault_screen.archive_confirmation.visible else null


func cycle_vault_tab(delta: int) -> bool:
	if _editor_session != null and is_instance_valid(_vault_screen):
		return _vault_screen.character_editor.cycle_tab(delta)
	return _vault_inspection_revision_hash.is_empty() and _vault_binder.cycle_tab(delta)


func _bind_vault_binder() -> void:
	# Method callables keep the controller and its binder free of a reference cycle.
	_vault_binder.back_requested.connect(vault_back_requested.emit)
	_vault_binder.inspect_requested.connect(_inspect_vault)
	_vault_binder.import_requested.connect(_import_vault)
	_vault_binder.character_requested.connect(vault_character_requested.emit)


func _import_vault(character_id: String, revision_hash: String) -> void:
	intent_submitted.emit(PartyIntents.import_vault_character(character_id, revision_hash))


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
	_ensure_vault_appearance(revision)
	var back := _vault_screen.inspection_back_button
	_clear_pressed_connections(back)
	back.pressed.connect(func() -> void:
		_vault_inspection_revision_hash = ""
		_refresh_vault()
	)
	_vault_screen.inspection_heading.text = "Inspect %s" % revision.name
	var eligibility := VaultDetailBinder.revision_eligibility(revision, _vault_view)
	_vault_screen.inspection_eligibility.text = RowFields.text(eligibility, "text")
	_vault_screen.inspection_eligibility.theme_type_variation = eligibility["variation"] as StringName
	var sheet := _vault_screen.character_sheet
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
	# Opening an inspection gives controller users a visible exit to start from.
	var focus_owner := _vault_screen.get_viewport().gui_get_focus_owner()
	if focus_owner == null or not _vault_screen.inspection_area.is_ancestor_of(focus_owner):
		back.grab_focus.call_deferred()


func _on_vault_sheet_tab_changed(tab_id: StringName) -> void:
	_selected_tab = tab_id


func _ensure_vault_appearance(revision: CharacterVaultRevisionView) -> void:
	if _vault_media == null:
		return
	var asset_ids: Array[String] = [revision.portrait_id, revision.character.combat_icon_id if revision.character != null else ""]
	for asset_id: String in asset_ids:
		_cache_texture(_vault_appearance_textures, asset_id)


func _cache_texture(textures: Dictionary, asset_id: String) -> void:
	if _vault_media == null or asset_id.is_empty() or textures.get(asset_id) != null:
		return
	var asset := _vault_media.asset_by_id(asset_id)
	var texture: Texture2D = _vault_media.image_texture(asset) if asset != null else null
	if texture != null:
		textures[asset_id] = texture


func draft_order_ids() -> Array[String]:
	return _draft_order_ids.duplicate()


func present(screen: CharacterScreen, view: GameView, appearance_textures: Dictionary, settings: PresentationSettings, media: ClassicMediaCatalog = null) -> void:
	if screen == null or view == null:
		return
	screen.prepare_for_render()
	var allies_button := screen.current_allies_button()
	var allies_reason := GameShellAvailability.allies_reason(view)
	allies_button.disabled = not allies_reason.is_empty()
	allies_button.tooltip_text = allies_reason if allies_button.disabled else "Inspect allies currently traveling with the party."
	_render_party_order_summary(screen, view)
	if view.party_members.is_empty():
		screen.empty_state().visible = true
		return
	if _party_order_open:
		_render_party_order(screen, view)
	var sheet := screen.character_sheet()
	sheet.character_art_dialog = character_art_dialog
	sheet.visible = true
	sheet.name = "ClassicCharacterSheet"
	sheet.present(view.party_members, _selected_character_id, appearance_textures, settings.interface_text_scale, _selected_tab, view.portrait_options, view.combat_icon_options, view.availability(&"change_character_appearance"), media, _layout_profile)
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
	var summary_text := "%d characters in party order" % names.size() if _layout_profile == UiLayoutProfile.COMPACT else ""
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
	UiSizing.font_size(label, &"font_size", size)


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
