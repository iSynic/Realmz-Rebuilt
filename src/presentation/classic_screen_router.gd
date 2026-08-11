class_name ClassicScreenRouter
extends Control

signal screen_changed(screen_id: StringName)
signal start_requested(package_path: String, seed: int)
signal refresh_requested
signal intent_submitted(intent: PlayerIntent)
signal system_action_requested(action_id: StringName, value: Variant)
signal presentation_setting_changed(setting_id: StringName, value: Variant)
signal vault_archive_requested(character_id: String)
signal vault_restore_requested(character_id: String, revision_hash: String)
signal presentation_sound_requested(sound_id: int, wait_for_completion: bool, stop_existing: bool)

const GOLD := Color("d5b45d")
const INK := Color("17191d")
const PANEL := Color("272b31")
const PANEL_DARK := Color("1d2025")
const MUTED := Color("9aa0a8")
const SWAP_OPEN_SOUND_ID: int = 3003
const SWAP_DONE_SOUND_ID: int = 141

var _view: GameView
var _campaigns: Array[PackageDiscoveryResult] = []
var _screen_id: StringName = &"exploration"
var _body_scroll: ScrollContainer
var _body: VBoxContainer
var _body_frame: PanelContainer
var _workspace_view: ClassicRouteScreen
var _campaign_overlay: PanelContainer
var _campaign_list: VBoxContainer
var _campaign_scroll: ScrollContainer
var _campaign_detail: RichTextLabel
var _package_path: LineEdit
var _seed: SpinBox
var _setup_overlay: PanelContainer
var _setup_body: VBoxContainer
var _creator_scroll: ScrollContainer
var _creator: BoxContainer
var _creator_page: VBoxContainer
var _creator_step_labels: Array[Label] = []
var _race_class_columns: BoxContainer
var _setup_campaign_label: Label
var _setup_restriction_label: Label
var _race_list: ItemList
var _caste_list: ItemList
var _name_edit: LineEdit
var _gender_option: OptionButton
var _starting_level_option: OptionButton
var _portrait_option: OptionButton
var _combat_icon_option: OptionButton
var _party_list: VBoxContainer
var _setup_message: Label
var _review_label: Label
var _spell_label: Label
var _spell_list: ItemList
var _begin_button: Button
var _add_character_button: Button
var _creator_back_button: Button
var _creator_next_button: Button
var _creator_cancel_button: Button
var _setup_import_button: Button
var _vault_revisions: Array[CharacterVaultRevisionView] = []
var _selected_race_id: String = ""
var _selected_caste_id: String = ""
var _creator_step: int = 0
var _draft_name: String = ""
var _draft_gender: int = 1
var _draft_starting_level: int = 1
var _draft_portrait_id: String = ""
var _draft_combat_icon_id: String = ""
var _awaiting_draft_generation: bool = false
var _awaiting_draft_finalization: bool = false
var _settings: PresentationSettings = PresentationSettings.new()
var _media: PackageMediaCatalog
var _route_history: Array[StringName] = []
var _focus_keys: Dictionary = {}
var _workspace_rect := Rect2(220.0, 100.0, 512.0, 430.0)
var _layout_profile: StringName = UiLayoutProfile.STANDARD
var _modal_layout_rect := Rect2(12.0, 36.0, 680.0, 556.0)
var _campaign_layout_rect := Rect2(12.0, 36.0, 680.0, 556.0)
var _content_parent: Container
var _inventory_query: String = ""
var _inventory_character_id: String = ""
var _inventory_item_id: String = ""
var _money_character_id: String = ""
var _party_order_source_ids: Array[String] = []
var _party_order_draft_ids: Array[String] = []
var _character_sheet_character_id: String = ""
var _character_sheet_tab: StringName = &"overview"
var _presented_campaign_id: String = ""
var _appearance_textures: Dictionary = {}
var _combat_icon_touched: bool = false
var _vault_return_to_setup: bool = false
var _vault_return_to_campaign: bool = false
var _ordinary_money_workspace_open: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The router spans the window for layout only. Its panels and workspace own
	# input; the router itself must not cover menus or other shell controls.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_body()
	_build_campaign_overlay()
	_build_setup_overlay()
	show_campaign_selection()


func present(view: GameView) -> void:
	_view = view
	if view == null or not view.session_started:
		_body_frame.visible = false
		return
	if not _presented_campaign_id.is_empty() and _presented_campaign_id != view.campaign_id:
		_reset_creator()
		_inventory_character_id = ""
		_inventory_item_id = ""
		_money_character_id = ""
		_party_order_source_ids.clear()
		_party_order_draft_ids.clear()
		_character_sheet_character_id = ""
		_character_sheet_tab = &"overview"
	_presented_campaign_id = view.campaign_id
	if view.party_setup_available:
		if _awaiting_draft_generation and view.character_draft != null:
			_awaiting_draft_generation = false
		if _awaiting_draft_finalization and view.character_draft == null:
			_awaiting_draft_finalization = false
			_reset_creator()
		_campaign_overlay.visible = false
		_setup_overlay.visible = true
		_body_frame.visible = false
		_refresh_setup_options()
		call_deferred("_apply_modal_layouts")
		call_deferred("_focus_first", _setup_overlay)
		return
	_setup_overlay.visible = false
	_campaign_overlay.visible = false
	_render_screen()


func set_campaigns(campaigns: Array[PackageDiscoveryResult]) -> void:
	_campaigns = campaigns.duplicate()
	_campaigns.sort_custom(_campaign_precedes)
	_clear(_campaign_list)
	if _campaigns.is_empty():
		_add_label(_campaign_list, "No installed packages. Open a Providence .realmz2 export.", MUTED)
		call_deferred("_refresh_campaign_layout")
		return
	for campaign: PackageDiscoveryResult in _campaigns:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 48)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s\n%s" % [_display_name(campaign), "Ready • %s" % campaign.rules_version if campaign.ready else "Rejected • %s" % campaign.error_message]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.tooltip_text = campaign.path
		row.add_child(label)
		var action := Button.new()
		action.text = "Play" if campaign.ready else "Details"
		action.disabled = not campaign.ready
		action.pressed.connect(_campaign_pressed.bind(campaign))
		row.add_child(action)
		_campaign_list.add_child(row)
	# Container minimum-size propagation runs after rows enter the tree. Restore
	# the bounded modal rect once that layout pass has settled.
	call_deferred("_refresh_campaign_layout")


func set_vault_revisions(revisions: Array[CharacterVaultRevisionView]) -> void:
	_vault_revisions = revisions.duplicate()
	if _screen_id == &"vault":
		_render_screen()


func set_media_catalog(media: PackageMediaCatalog) -> void:
	_media = media
	_appearance_textures.clear()
	if _view != null and _view.session_started:
		_render_screen()


func set_presentation_settings(settings: PresentationSettings) -> void:
	if settings == null:
		return
	_settings = settings
	if _screen_id == &"system":
		_render_screen()


func set_layout_profile(profile: UiLayoutProfile, viewport_size: Vector2) -> void:
	if profile == null:
		return
	_layout_profile = profile.id
	var top := profile.menu_height
	var bottom := profile.bottom_height
	_workspace_rect = Rect2(0.0, top, maxf(320.0, viewport_size.x - profile.party_width), maxf(220.0, viewport_size.y - top - bottom))
	if _body_frame != null:
		_workspace_view.set_workspace_rect(_workspace_rect)
	_modal_layout_rect = Rect2(12.0, top + 8.0, maxf(320.0, viewport_size.x - profile.party_width - 24.0), maxf(300.0, viewport_size.y - top - 16.0))
	_campaign_layout_rect = ClassicScreenRouter.campaign_rect_for(profile, viewport_size)
	if _setup_overlay != null:
		_apply_creator_layout(profile.id)
		_creator_scroll.custom_minimum_size.y = 140.0 if profile.id == UiLayoutProfile.COMPACT else 220.0
	_apply_modal_layouts()
	_render_screen()


func _apply_creator_layout(profile_id: StringName) -> void:
	if _creator != null:
		_creator.vertical = profile_id == UiLayoutProfile.COMPACT
	if _race_class_columns != null:
		_race_class_columns.vertical = profile_id == UiLayoutProfile.COMPACT


static func campaign_rect_for(profile: UiLayoutProfile, viewport_size: Vector2) -> Rect2:
	var modal_rect := Rect2(12.0, profile.menu_height + 8.0, maxf(320.0, viewport_size.x - profile.party_width - 24.0), maxf(300.0, viewport_size.y - profile.menu_height - 16.0))
	var campaign_width := minf(680.0 * profile.ui_scale, modal_rect.size.x)
	return Rect2(
		Vector2(modal_rect.position.x + (modal_rect.size.x - campaign_width) * 0.5, modal_rect.position.y),
		Vector2(campaign_width, modal_rect.size.y)
	)


func _apply_modal_layouts() -> void:
	if _setup_overlay != null:
		_setup_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_setup_overlay.position = _modal_layout_rect.position
		_setup_overlay.size = _modal_layout_rect.size
	if _campaign_overlay != null:
		_campaign_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_campaign_overlay.position = _campaign_layout_rect.position
		_campaign_overlay.size = _campaign_layout_rect.size


func _refresh_campaign_layout() -> void:
	_apply_modal_layouts()
	_campaign_scroll.scroll_vertical = 0


func _prepare_campaign_selection() -> void:
	_refresh_campaign_layout()
	_focus_first(_campaign_overlay)
	_campaign_scroll.scroll_vertical = 0


func show_campaign_selection() -> void:
	_vault_return_to_campaign = false
	_vault_return_to_setup = false
	_campaign_overlay.visible = true
	_setup_overlay.visible = false
	_body_frame.visible = false
	call_deferred("_prepare_campaign_selection")


func full_stage_overlay_visible() -> bool:
	return _campaign_overlay != null and _campaign_overlay.visible or _setup_overlay != null and _setup_overlay.visible


func accepts_exploration_input() -> bool:
	return not _campaign_overlay.visible and not _setup_overlay.visible and _screen_id == &"exploration"


func open_screen(screen_id: StringName) -> void:
	if not UiRouteCatalog.has_route(screen_id):
		return
	if screen_id == &"vault":
		_vault_return_to_campaign = false
		_vault_return_to_setup = false
	_store_focus()
	if screen_id != _screen_id:
		_route_history.append(_screen_id)
	_screen_id = screen_id
	_campaign_overlay.visible = false
	_setup_overlay.visible = false
	_sync_ordinary_money_workspace_audio(screen_id)
	screen_changed.emit(screen_id)
	_render_screen()


func handle_back() -> bool:
	if _screen_id == &"vault" and _vault_return_to_setup and _view != null and _view.party_setup_available:
		_vault_return_to_setup = false
		_screen_id = &"exploration"
		_setup_overlay.visible = true
		_body_frame.visible = false
		_refresh_setup_options()
		return true
	if _screen_id == &"vault" and _vault_return_to_campaign:
		show_campaign_selection()
		return true
	if _campaign_overlay.visible:
		if _view != null and _view.session_started:
			_campaign_overlay.visible = false
			_render_screen()
			return true
		return false
	if _setup_overlay.visible:
		if _creator_step > 0:
			_creator_back()
			return true
		return false
	if not _route_history.is_empty():
		var previous: StringName = _route_history.pop_back()
		_screen_id = previous
		_sync_ordinary_money_workspace_audio(previous)
		screen_changed.emit(previous)
		_render_screen()
		return true
	if _screen_id != &"exploration":
		_screen_id = &"exploration"
		_sync_ordinary_money_workspace_audio(_screen_id)
		screen_changed.emit(_screen_id)
		_render_screen()
		return true
	return false


func _sync_ordinary_money_workspace_audio(screen_id: StringName) -> void:
	var service_interaction_open := _view != null and _view.pending_interaction != null and _view.pending_interaction.kind in [InteractionRequest.SHOP, InteractionRequest.TEMPLE, InteractionRequest.BANK]
	var should_be_open := screen_id == &"services" and _view != null and _view.session_started and not service_interaction_open
	if should_be_open == _ordinary_money_workspace_open:
		return
	_ordinary_money_workspace_open = should_be_open
	if should_be_open:
		presentation_sound_requested.emit(SWAP_DONE_SOUND_ID, false, false)
		presentation_sound_requested.emit(SWAP_OPEN_SOUND_ID, false, true)
	else:
		presentation_sound_requested.emit(SWAP_DONE_SOUND_ID, false, false)


func current_screen() -> StringName:
	return _screen_id


func _build_body() -> void:
	_mount_workspace(_screen_id)


func _mount_workspace(screen_id: StringName) -> void:
	if _workspace_view != null and _workspace_view.route_id == screen_id:
		return
	if _workspace_view != null:
		remove_child(_workspace_view)
		_workspace_view.queue_free()
	var definition := UiRouteCatalog.route(screen_id)
	var scene := load(String(definition.get("scene", ""))) as PackedScene
	if scene == null:
		push_error("Missing Classic route scene for %s" % screen_id)
		return
	_workspace_view = scene.instantiate() as ClassicRouteScreen
	_workspace_view.name = "WorkspaceFrame"
	add_child(_workspace_view)
	move_child(_workspace_view, 0)
	_workspace_view.set_workspace_rect(_workspace_rect)
	_body_frame = _workspace_view
	_body_scroll = _workspace_view.scroll
	_body = _workspace_view.body


func _build_campaign_overlay() -> void:
	_campaign_overlay = PanelContainer.new()
	_campaign_overlay.name = "CampaignLibrary"
	_campaign_overlay.theme_type_variation = &"ClassicSharedStone"
	_campaign_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_campaign_overlay.offset_left = -300.0
	_campaign_overlay.offset_top = -220.0
	_campaign_overlay.offset_right = 300.0
	_campaign_overlay.offset_bottom = 220.0
	_campaign_overlay.z_index = 30
	add_child(_campaign_overlay)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_campaign_overlay.add_child(column)
	_add_label(column, "Choose a Realmz campaign", GOLD, 24)
	_add_label(column, "Providence packages are validated before play.", MUTED)
	_campaign_list = VBoxContainer.new()
	_campaign_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_campaign_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_campaign_scroll = ScrollContainer.new()
	_campaign_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_campaign_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_campaign_scroll.follow_focus = true
	_campaign_scroll.add_child(_campaign_list)
	column.add_child(_campaign_scroll)
	var details := HBoxContainer.new()
	_package_path = LineEdit.new()
	_package_path.placeholder_text = "Path to .realmz2 package"
	_package_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(_package_path)
	_details_button(details)
	column.add_child(details)
	var seed_row := HBoxContainer.new()
	_seed = SpinBox.new()
	_seed.name = "Seed"
	_seed.min_value = 1
	_seed.max_value = 2147483647
	_seed.value = 1
	_seed.tooltip_text = "Deterministic Realmz seed"
	seed_row.add_child(_label("Seed"))
	seed_row.add_child(_seed)
	column.add_child(seed_row)
	var refresh := Button.new()
	refresh.text = "Refresh installed packages"
	refresh.pressed.connect(func() -> void: refresh_requested.emit())
	var library_actions := HBoxContainer.new()
	library_actions.add_child(refresh)
	var vault := Button.new()
	vault.text = "Character vault"
	vault.pressed.connect(_show_vault_from_campaign)
	library_actions.add_child(vault)
	column.add_child(library_actions)


func _details_button(row: HBoxContainer) -> void:
	var open := Button.new()
	open.text = "Open path"
	open.pressed.connect(_open_typed_path)
	row.add_child(open)


func _build_setup_overlay() -> void:
	_setup_overlay = PanelContainer.new()
	_setup_overlay.name = "PartySetup"
	_setup_overlay.theme_type_variation = &"ClassicSharedStone"
	_setup_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_setup_overlay.offset_left = -440.0
	_setup_overlay.offset_top = -238.0
	_setup_overlay.offset_right = 440.0
	_setup_overlay.offset_bottom = 238.0
	_setup_overlay.z_index = 25
	add_child(_setup_overlay)
	_setup_body = VBoxContainer.new()
	_setup_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_setup_body.add_theme_constant_override("separation", 6)
	_setup_overlay.add_child(_setup_body)
	_setup_campaign_label = _add_label(_setup_body, "Assemble your party", GOLD, 24)
	_setup_campaign_label.custom_minimum_size.y = 28.0
	_setup_campaign_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_setup_restriction_label = _add_label(_setup_body, "", MUTED)
	_setup_restriction_label.custom_minimum_size.y = 34.0
	_setup_restriction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 6)
	steps.custom_minimum_size.y = 24.0
	for step: String in ["1 Identity", "2 Race & Class", "3 Appearance", "4 Review", "5 Spells"]:
		var step_label := _label(step, GOLD if step.begins_with("1") else MUTED, 13)
		step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		steps.add_child(step_label)
		_creator_step_labels.append(step_label)
	_setup_body.add_child(steps)
	_creator_scroll = ScrollContainer.new()
	_creator_scroll.name = "CreatorScroll"
	_creator_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_creator_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_creator_scroll.custom_minimum_size.y = 220.0
	_creator_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_creator_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_creator_scroll.follow_focus = true
	_setup_body.add_child(_creator_scroll)
	_creator = BoxContainer.new()
	_creator.custom_minimum_size.y = 250.0
	_creator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_creator.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_creator.add_theme_constant_override("separation", 12)
	_creator_scroll.add_child(_creator)
	_creator_page = VBoxContainer.new()
	_creator_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_creator_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_creator.add_child(_creator_page)
	var party_column := VBoxContainer.new()
	party_column.custom_minimum_size.x = 190.0
	party_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	party_column.add_child(_label("Current Party", GOLD))
	_party_list = VBoxContainer.new()
	_party_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	party_column.add_child(_party_list)
	_creator.add_child(party_column)
	_setup_message = _add_label(_setup_body, "Enter a name to begin creating a character.", MUTED)
	_setup_message.custom_minimum_size.y = 32.0
	_setup_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var action_bar := HBoxContainer.new()
	action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_creator_cancel_button = Button.new()
	_creator_cancel_button.text = "Cancel character"
	_creator_cancel_button.pressed.connect(_cancel_creator)
	action_bar.add_child(_creator_cancel_button)
	action_bar.add_spacer(true)
	_creator_back_button = Button.new()
	_creator_back_button.text = "Back"
	_creator_back_button.pressed.connect(_creator_back)
	action_bar.add_child(_creator_back_button)
	_add_character_button = Button.new()
	_add_character_button.text = "Reroll"
	_add_character_button.pressed.connect(_reroll_character)
	action_bar.add_child(_add_character_button)
	_creator_next_button = Button.new()
	_creator_next_button.text = "Continue"
	_creator_next_button.pressed.connect(_creator_next)
	action_bar.add_child(_creator_next_button)
	_setup_import_button = Button.new()
	_setup_import_button.text = "Import from vault"
	_setup_import_button.pressed.connect(_show_vault_for_setup)
	_setup_body.add_child(action_bar)
	_setup_body.add_child(_setup_import_button)
	_begin_button = Button.new()
	_begin_button.text = "Begin adventure"
	_begin_button.custom_minimum_size.y = 34.0
	_begin_button.disabled = true
	_begin_button.pressed.connect(_submit_party)
	_setup_body.add_child(_begin_button)
	_render_creator_step()


func _refresh_setup_options() -> void:
	if _view == null:
		return
	var summary := _view.campaign_summary
	if summary != null:
		var title_parts: Array[String] = [summary.title]
		if not summary.version.is_empty():
			title_parts.append("v%s" % summary.version)
		if not summary.author.is_empty():
			title_parts.append("by %s" % summary.author)
		_setup_campaign_label.text = " • ".join(title_parts)
		var restriction_text := summary.restriction_description.strip_edges()
		if restriction_text.is_empty():
			restriction_text = "No authored party restrictions."
		var limits := "Up to %d characters" % summary.maximum_party_size
		if summary.maximum_level > 0:
			limits += " • Maximum level %d" % summary.maximum_level
		_setup_restriction_label.text = "%s\n%s" % [restriction_text, limits]
	else:
		_setup_campaign_label.text = "Assemble your party"
		_setup_restriction_label.text = "No campaign metadata is available."
	_refresh_party_list()
	var setup_count := _view.party_members.size()
	_apply_availability(_setup_import_button, &"import_vault_character")
	_apply_availability(_begin_button, &"begin_adventure")
	_begin_button.text = "Begin adventure (%d/%d)" % [setup_count, _maximum_party_size()]
	_render_creator_step()


func _render_creator_step() -> void:
	if _creator_page == null:
		return
	_setup_message.text = _creator_step_message()
	_clear(_creator_page)
	_race_list = null
	_caste_list = null
	_race_class_columns = null
	_name_edit = null
	_gender_option = null
	_portrait_option = null
	_combat_icon_option = null
	_review_label = null
	_spell_label = null
	_spell_list = null
	for index: int in _creator_step_labels.size():
		_creator_step_labels[index].modulate = GOLD if index == _creator_step else Color("e0e2e5") if index < _creator_step else MUTED
	match _creator_step:
		0:
			_build_creator_identity()
		1:
			_build_creator_race_class()
		2:
			_build_creator_appearance()
		3:
			_build_creator_review()
		4:
			_build_creator_spells()
	_update_creator_actions()


func _build_creator_identity() -> void:
	_creator_page.add_child(_label("Identity", GOLD, 20))
	_add_label(_creator_page, "Name this character and choose the Classic gender value used by creation rules.", MUTED)
	_name_edit = LineEdit.new()
	_name_edit.name = "CharacterName"
	_name_edit.placeholder_text = "Character name"
	_name_edit.max_length = 24
	_name_edit.text = _draft_name
	_name_edit.text_changed.connect(func(value: String) -> void: _draft_name = value)
	_creator_page.add_child(_name_edit)
	_gender_option = OptionButton.new()
	_gender_option.name = "CharacterGender"
	_gender_option.add_item("Male", 1)
	_gender_option.add_item("Female", 2)
	_gender_option.select(0 if _draft_gender == 1 else 1)
	_gender_option.item_selected.connect(func(_index: int) -> void: _draft_gender = _gender_option.get_selected_id())
	_creator_page.add_child(_gender_option)
	_starting_level_option = OptionButton.new()
	_starting_level_option.name = "StartingLevel"
	var maximum_level := _view.campaign_summary.maximum_level if _view != null and _view.campaign_summary != null else 0
	for level: int in CharacterRules.STARTING_LEVELS:
		if maximum_level > 0 and level > maximum_level:
			continue
		_starting_level_option.add_item("Starting level %d" % level, level)
	var selected_index := _starting_level_option.get_item_index(_draft_starting_level)
	if selected_index < 0:
		selected_index = 0
		_draft_starting_level = _starting_level_option.get_item_id(0)
	_starting_level_option.select(selected_index)
	_starting_level_option.item_selected.connect(func(_index: int) -> void: _draft_starting_level = _starting_level_option.get_selected_id())
	_starting_level_option.tooltip_text = "Castle offers fixed starting levels and runs every intervening ordinary level-up roll. Campaign level restrictions remove unavailable choices."
	_creator_page.add_child(_starting_level_option)
	call_deferred("_focus_first", _creator_page)


func _build_creator_race_class() -> void:
	_creator_page.add_child(_label("Race & Class", GOLD, 20))
	_add_label(_creator_page, "Race is chosen first and filters the classes available on the right.", MUTED)
	var columns := BoxContainer.new()
	_race_class_columns = columns
	columns.vertical = _layout_profile == UiLayoutProfile.COMPACT
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	var race_column := VBoxContainer.new()
	race_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_column.add_child(_label("Race", GOLD))
	_race_list = ItemList.new()
	_race_list.name = "RaceList"
	_race_list.custom_minimum_size.y = 190.0
	_race_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_race_list.item_selected.connect(_race_selected)
	race_column.add_child(_race_list)
	columns.add_child(race_column)
	var caste_column := VBoxContainer.new()
	caste_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caste_column.add_child(_label("Class", GOLD))
	_caste_list = ItemList.new()
	_caste_list.name = "ClassList"
	_caste_list.custom_minimum_size.y = 190.0
	_caste_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_caste_list.item_selected.connect(_caste_selected)
	caste_column.add_child(_caste_list)
	columns.add_child(caste_column)
	_creator_page.add_child(columns)
	_populate_race_class_options()


func _populate_race_class_options() -> void:
	if _view == null or _race_list == null or _caste_list == null:
		return
	for option: DefinitionOptionView in _view.race_options:
		_race_list.add_item(option.name)
		_race_list.set_item_metadata(_race_list.item_count - 1, option.id)
		_race_list.set_item_tooltip(_race_list.item_count - 1, option.description)
		_race_list.set_item_disabled(_race_list.item_count - 1, _view.campaign_summary != null and _view.campaign_summary.banned_races.has(option.id))
	for option: DefinitionOptionView in _view.caste_options:
		_caste_list.add_item(option.name)
		_caste_list.set_item_metadata(_caste_list.item_count - 1, option.id)
		_caste_list.set_item_tooltip(_caste_list.item_count - 1, option.description)
		_caste_list.set_item_disabled(_caste_list.item_count - 1, _view.campaign_summary != null and _view.campaign_summary.banned_castes.has(option.id))
	if _selected_race_id.is_empty() or not _option_is_enabled(_race_list, _selected_race_id):
		var first_race := _first_enabled_item(_race_list)
		if first_race >= 0:
			_selected_race_id = String(_race_list.get_item_metadata(first_race))
	_select_item_by_id(_race_list, _selected_race_id)
	_apply_caste_filter()
	if _selected_caste_id.is_empty() or not _option_is_enabled(_caste_list, _selected_caste_id):
		var first_caste := _first_enabled_item(_caste_list)
		if first_caste >= 0:
			_selected_caste_id = String(_caste_list.get_item_metadata(first_caste))
	_select_item_by_id(_caste_list, _selected_caste_id)


func _build_creator_appearance() -> void:
	_creator_page.add_child(_label("Appearance", GOLD, 20))
	_add_label(_creator_page, "Choose the portrait shown on character screens and the icon used in battle. Castle's six race recommendations appear first.", MUTED)
	_ensure_appearance_textures()
	_portrait_option = OptionButton.new()
	_portrait_option.name = "PortraitOption"
	_portrait_option.fit_to_longest_item = false
	var portrait_options := _sorted_appearance_options(_view.portrait_options if _view != null else [])
	for option: CharacterAppearanceOptionView in portrait_options:
		_add_appearance_option(_portrait_option, option)
	_select_appearance_default(_portrait_option, _draft_portrait_id, true)
	_portrait_option.item_selected.connect(_portrait_selected)
	_creator_page.add_child(_portrait_option)
	_combat_icon_option = OptionButton.new()
	_combat_icon_option.name = "CombatIconOption"
	_combat_icon_option.fit_to_longest_item = false
	var combat_options := _sorted_appearance_options(_view.combat_icon_options if _view != null else [])
	for option: CharacterAppearanceOptionView in combat_options:
		_add_appearance_option(_combat_icon_option, option)
	_select_appearance_default(_combat_icon_option, _draft_combat_icon_id, false)
	_combat_icon_option.item_selected.connect(func(_index: int) -> void: _combat_icon_touched = true)
	_creator_page.add_child(_combat_icon_option)
	if portrait_options.is_empty() or combat_options.is_empty():
		_add_label(_creator_page, "This package does not expose the complete Classic appearance catalog. Character generation is unavailable until the package is re-exported.", Color("ef7770"))


func _sorted_appearance_options(source: Array[CharacterAppearanceOptionView]) -> Array[CharacterAppearanceOptionView]:
	var result := source.duplicate()
	result.sort_custom(func(left: CharacterAppearanceOptionView, right: CharacterAppearanceOptionView) -> bool:
		var left_recommended := left.is_recommended_for(_selected_race_id)
		var right_recommended := right.is_recommended_for(_selected_race_id)
		if left_recommended != right_recommended:
			return left_recommended
		return left.classic_resource_id < right.classic_resource_id
	)
	return result


func _add_appearance_option(control: OptionButton, option: CharacterAppearanceOptionView) -> void:
	var prefix := "Recommended • " if option.is_recommended_for(_selected_race_id) else ""
	var label := "%s%s • CICN %d" % [prefix, option.label, option.classic_resource_id]
	var texture := _appearance_textures.get(option.id) as Texture2D
	if texture != null:
		control.add_icon_item(texture, label)
	else:
		control.add_item(label)
	var index := control.item_count - 1
	control.set_item_metadata(index, option.id)
	control.set_item_tooltip(index, "%s character resource %d" % ["Portrait" if option.kind == CharacterAppearanceDefinition.PORTRAIT else "Combat icon", option.classic_resource_id])


func _select_appearance_default(control: OptionButton, selected_id: String, portrait: bool) -> void:
	if control.item_count == 0:
		return
	var target_id := selected_id
	if target_id.is_empty() and portrait:
		for index: int in control.item_count:
			var option := _appearance_option_by_id(String(control.get_item_metadata(index)), true)
			if option != null and option.is_recommended_for(_selected_race_id):
				target_id = option.id
				break
	if target_id.is_empty() and not portrait:
		var portrait_option := _selected_appearance(_portrait_option, true)
		if portrait_option != null:
			var wanted_resource_id := 9000 - 257 + portrait_option.classic_resource_id
			for option: CharacterAppearanceOptionView in _view.combat_icon_options:
				if option.classic_resource_id == wanted_resource_id:
					target_id = option.id
					break
	for index: int in control.item_count:
		if String(control.get_item_metadata(index)) == target_id:
			control.select(index)
			return
	control.select(0)


func _portrait_selected(_index: int) -> void:
	if _combat_icon_touched or _combat_icon_option == null:
		return
	var portrait := _selected_appearance(_portrait_option, true)
	if portrait == null:
		return
	var wanted_resource_id := 9000 - 257 + portrait.classic_resource_id
	for index: int in _combat_icon_option.item_count:
		var icon := _appearance_option_by_id(String(_combat_icon_option.get_item_metadata(index)), false)
		if icon != null and icon.classic_resource_id == wanted_resource_id:
			_combat_icon_option.select(index)
			return


func _selected_appearance(control: OptionButton, portrait: bool) -> CharacterAppearanceOptionView:
	if control == null or control.selected < 0:
		return null
	return _appearance_option_by_id(String(control.get_item_metadata(control.selected)), portrait)


func _appearance_option_by_id(option_id: String, portrait: bool) -> CharacterAppearanceOptionView:
	var options := _view.portrait_options if portrait else _view.combat_icon_options
	for option: CharacterAppearanceOptionView in options:
		if option.id == option_id:
			return option
	return null


func _ensure_appearance_textures() -> void:
	if _media == null or not _appearance_textures.is_empty():
		return
	var assets: Array[PackageMediaAsset] = []
	assets.append_array(_media.assets_of_kind("portrait"))
	assets.append_array(_media.assets_of_kind("combat-icon"))
	var payloads := _media.read_bytes_batch(assets)
	for asset: PackageMediaAsset in assets:
		var bytes: PackedByteArray = payloads.get(asset.id, PackedByteArray())
		if bytes.is_empty():
			continue
		var image := Image.new()
		var error := image.load_png_from_buffer(bytes)
		if error == OK:
			_appearance_textures[asset.id] = ImageTexture.create_from_image(image)


func _build_creator_review() -> void:
	_creator_page.add_child(_label("Review Classic Roll", GOLD, 20))
	_review_label = _add_label(_creator_page, "Generating the character through Classic rules…", MUTED)
	_review_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_update_creator_review()


func _build_creator_spells() -> void:
	_creator_page.add_child(_label("Starting Spells", GOLD, 20))
	_spell_label = _add_label(_creator_page, "", MUTED)
	_spell_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _view == null or _view.character_draft == null:
		_spell_label.text = "Generate and review the character before choosing spells."
		return
	if _view.character_draft.spellcaster_type < 1 or _view.character_draft_spell_points_total < 1:
		_spell_label.text = "Not applicable. This character has no Classic starting-spell selection points."
		return
	_spell_label.text = "%d of %d selection points remain. Unspent points may be accepted, as in Classic." % [_view.character_draft_spell_points_remaining, _view.character_draft_spell_points_total]
	_spell_list = ItemList.new()
	_spell_list.name = "StartingSpellList"
	_spell_list.select_mode = ItemList.SELECT_MULTI
	_spell_list.custom_minimum_size.y = 190.0
	_spell_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for option: CharacterSpellOptionView in _view.character_draft_spell_options:
		_spell_list.add_item("L%d • %s (%d)" % [option.level, option.name, option.selection_cost])
		var index := _spell_list.item_count - 1
		_spell_list.set_item_metadata(index, option.id)
		_spell_list.set_item_tooltip(index, option.description)
		if option.selected:
			_spell_list.select(index, false)
		elif option.selection_cost > _view.character_draft_spell_points_remaining:
			_spell_list.set_item_disabled(index, true)
			_spell_list.set_item_tooltip(index, "This spell costs %d points; %d remain." % [option.selection_cost, _view.character_draft_spell_points_remaining])
	_spell_list.multi_selected.connect(_draft_spell_selection_changed)
	_creator_page.add_child(_spell_list)
	if _view.character_draft_spell_options.is_empty():
		_spell_label.text = "This caster has selection points, but the package exposes no matching Classic spell records. Finalization is blocked."


func _creator_next() -> void:
	match _creator_step:
		0:
			_draft_name = _name_edit.text.strip_edges()
			_draft_gender = _gender_option.get_selected_id()
			_draft_starting_level = _starting_level_option.get_selected_id()
			if _draft_name.is_empty():
				_setup_message.text = "Enter a character name before continuing."
				return
			_creator_step = 1
		1:
			if _selected_race_id.is_empty() or _selected_caste_id.is_empty():
				_setup_message.text = "Choose both a race and a compatible class."
				return
			_creator_step = 2
		2:
			if _view.party_members.size() >= _maximum_party_size():
				_setup_message.text = "This campaign allows no more than %d characters." % _maximum_party_size()
				return
			var portrait := _selected_appearance(_portrait_option, true)
			var combat_icon := _selected_appearance(_combat_icon_option, false)
			if portrait == null or combat_icon == null:
				_setup_message.text = "Choose a package-backed portrait and combat icon before continuing."
				return
			_draft_portrait_id = portrait.id
			_draft_combat_icon_id = combat_icon.id
			_creator_step = 3
			_awaiting_draft_generation = true
			intent_submitted.emit(PlayerIntent.generate_character_draft(_character_creation_spec()))
			return
		3:
			if _view.character_draft == null:
				_setup_message.text = "The Classic character roll did not complete. Review the action error before continuing."
				return
			_creator_step = 4
		4:
			if _view.character_draft == null:
				return
			if _view.character_draft.spellcaster_type > 0 and _view.character_draft_spell_points_total > 0 and _view.character_draft_spell_options.is_empty():
				_setup_message.text = "Starting spells are unavailable in this package, so this caster cannot be finalized safely."
				return
			_awaiting_draft_finalization = true
			intent_submitted.emit(PlayerIntent.finalize_character())
			return
	_setup_message.text = _creator_step_message()
	_render_creator_step()


func _creator_back() -> void:
	if _creator_step <= 0:
		return
	if _creator_step == 3 and _view != null and _view.character_draft != null:
		_creator_step = 2
		intent_submitted.emit(PlayerIntent.cancel_character_draft())
		return
	_creator_step -= 1
	_setup_message.text = _creator_step_message()
	_render_creator_step()


func _cancel_creator() -> void:
	var had_generated_draft := _view != null and _view.character_draft != null
	_reset_creator()
	if had_generated_draft:
		intent_submitted.emit(PlayerIntent.cancel_character_draft())
	else:
		_render_creator_step()


func _reset_creator() -> void:
	_creator_step = 0
	_draft_name = ""
	_draft_gender = 1
	_draft_starting_level = 1
	_draft_portrait_id = ""
	_draft_combat_icon_id = ""
	_combat_icon_touched = false
	_selected_race_id = ""
	_selected_caste_id = ""
	_awaiting_draft_generation = false
	_awaiting_draft_finalization = false
	_setup_message.text = "Enter a name to begin creating another character."


func _reroll_character() -> void:
	if _creator_step != 3 or _view == null or _view.character_draft == null:
		return
	_awaiting_draft_generation = true
	intent_submitted.emit(PlayerIntent.generate_character_draft(_character_creation_spec()))


func _draft_spell_selection_changed(_index: int, _selected: bool) -> void:
	if _spell_list == null:
		return
	var selected_ids: Array[String] = []
	for item_index: int in _spell_list.item_count:
		if _spell_list.is_selected(item_index):
			selected_ids.append(String(_spell_list.get_item_metadata(item_index)))
	intent_submitted.emit(PlayerIntent.set_character_draft_spells(selected_ids))


func _character_creation_spec() -> CharacterCreationSpec:
	return CharacterCreationSpec.new(_draft_name, _selected_race_id, _selected_caste_id, _draft_gender, _draft_portrait_id, _draft_combat_icon_id, _draft_starting_level)


func _creator_step_message() -> String:
	return ["Enter the character's identity.", "Choose a race, then a compatible class.", "Choose the character's appearance.", "Review or reroll the generated Classic character.", "Choose starting spells, then add the character to the party."][_creator_step]


func _update_creator_actions() -> void:
	if _creator_back_button == null:
		return
	_creator_back_button.disabled = _creator_step == 0
	_add_character_button.visible = _creator_step == 3
	_apply_availability(_add_character_button, &"generate_character_draft")
	_creator_next_button.text = "Add to party" if _creator_step == 4 else "Choose spells" if _creator_step == 3 else "Continue"
	if _creator_step == 4:
		_apply_availability(_creator_next_button, &"finalize_character")
	else:
		_creator_next_button.disabled = false
		_creator_next_button.tooltip_text = ""
	_creator_cancel_button.disabled = _creator_step == 0 and _draft_name.is_empty() and (_view == null or _view.character_draft == null)


func _race_selected(index: int) -> void:
	if index < 0 or _race_list.is_item_disabled(index):
		return
	var selected_id := String(_race_list.get_item_metadata(index))
	if selected_id != _selected_race_id:
		_draft_portrait_id = ""
		_draft_combat_icon_id = ""
		_combat_icon_touched = false
	_selected_race_id = selected_id
	_apply_caste_filter()
	_setup_message.text = "Race selected. Classes unavailable to this race are disabled on the right."


func _caste_selected(index: int) -> void:
	if index < 0 or _caste_list.is_item_disabled(index):
		return
	_selected_caste_id = String(_caste_list.get_item_metadata(index))
	_setup_message.text = "Class selected. Continue to appearance when ready."


func _apply_caste_filter() -> void:
	if _view == null or _caste_list == null:
		return
	var allowed_castes: Array[String] = []
	for option: DefinitionOptionView in _view.race_options:
		if option.id == _selected_race_id:
			allowed_castes = option.related_ids.duplicate()
			break
	for index: int in _caste_list.item_count:
		var caste_id := String(_caste_list.get_item_metadata(index))
		var restricted := _view.campaign_summary != null and _view.campaign_summary.banned_castes.has(caste_id)
		var compatible := allowed_castes.is_empty() or allowed_castes.has(caste_id)
		_caste_list.set_item_disabled(index, restricted or not compatible)
	if not _selected_caste_id.is_empty() and not _option_is_enabled(_caste_list, _selected_caste_id):
		_selected_caste_id = ""
		var first_caste := _first_enabled_item(_caste_list)
		if first_caste >= 0:
			_selected_caste_id = String(_caste_list.get_item_metadata(first_caste))
	_select_item_by_id(_caste_list, _selected_caste_id)


func _select_item_by_id(list: ItemList, option_id: String) -> void:
	if list == null or option_id.is_empty():
		return
	for index: int in list.item_count:
		if String(list.get_item_metadata(index)) == option_id:
			list.select(index)
			return


func _option_is_enabled(list: ItemList, option_id: String) -> bool:
	for index: int in list.item_count:
		if String(list.get_item_metadata(index)) == option_id:
			return not list.is_item_disabled(index)
	return false


func _first_enabled_item(list: ItemList) -> int:
	for index: int in list.item_count:
		if not list.is_item_disabled(index):
			return index
	return -1


func _refresh_party_list() -> void:
	_clear(_party_list)
	if _view != null:
		for character: CharacterView in _view.party_members:
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var label := Label.new()
			label.text = "%d. %s" % [_party_list.get_child_count() + 1, character.name]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.modulate = Color("e0e2e5")
			row.add_child(label)
			var remove_button := Button.new()
			remove_button.text = "Remove"
			_apply_availability(remove_button, &"remove_party_member")
			remove_button.pressed.connect(_remove_setup_character.bind(character.id))
			row.add_child(remove_button)
			_party_list.add_child(row)


func _remove_setup_character(character_id: String) -> void:
	intent_submitted.emit(PlayerIntent.remove_party_member(character_id))


func _submit_party() -> void:
	if _view == null or _view.party_members.is_empty():
		return
	intent_submitted.emit(PlayerIntent.begin_adventure())


func _maximum_party_size() -> int:
	if _view == null or _view.campaign_summary == null:
		return 6
	return clampi(_view.campaign_summary.maximum_party_size, 1, 6)


func _update_creator_review() -> void:
	if _review_label == null:
		return
	if _view == null or _view.character_draft == null:
		_review_label.text = "The Classic character roll has not completed."
		return
	var character := _view.character_draft
	_review_label.text = "%s • Level %d %s %s\nHP %d/%d • SP %d/%d • Age %d (%s)\nBrawn %d • Knowledge %d • Judgment %d • Agility %d • Vitality %d • Luck %d\nArmor %d • To Hit %d • Dodge %d • Missile %d • Two-Hand %d • Hand-to-Hand %d • Damage %+d\nMovement %d • Magic Resistance %d%%" % [character.name, character.level, character.race_name, character.caste_name, character.current_health, character.maximum_health, character.spell_points, character.maximum_spell_points, character.age_years, character.age_group_name, character.brawn, character.knowledge, character.judgment, character.agility, character.vitality, character.luck, character.armor, character.to_hit, character.dodge, character.missile, character.two_hand, character.hand_to_hand, character.damage_bonus, character.maximum_movement, character.magic_resistance]


func _option_name(list: ItemList, option_id: String) -> String:
	if list == null or option_id.is_empty():
		return ""
	for index: int in list.item_count:
		if String(list.get_item_metadata(index)) == option_id:
			return list.get_item_text(index)
	return ""


func _campaign_pressed(campaign: PackageDiscoveryResult) -> void:
	if not campaign.ready:
		return
	start_requested.emit(campaign.path, int(_seed.value) if _seed != null else 1)


func _open_typed_path() -> void:
	var path := _package_path.text.strip_edges()
	if not path.is_empty():
		start_requested.emit(path, int(_seed.value))


func _render_screen() -> void:
	var mounted_new_route := _workspace_view == null or _workspace_view.route_id != _screen_id
	var previous_scroll_horizontal := _body_scroll.scroll_horizontal if _body_scroll != null else 0
	var previous_scroll_vertical := _body_scroll.scroll_vertical if _body_scroll != null else 0
	_mount_workspace(_screen_id)
	if _body == null:
		return
	_clear(_body)
	_content_parent = _body
	_body_frame.visible = not _campaign_overlay.visible and not _setup_overlay.visible and _screen_id not in [&"exploration", &"combat"]
	if _screen_id in [&"exploration", &"combat"]:
		return
	if (_view == null or not _view.session_started) and _screen_id != &"vault":
		_add_label(_body, "No active session. Choose a validated campaign to begin.", MUTED)
		return
	match _screen_id:
		&"exploration":
			_add_card("Exploration", "The map presenter occupies the central Classic viewport. Use the command rail and textbox overlay for player-facing actions.", "Day %d • %02d:%02d" % [_view.realmz_day, _view.realmz_hour, _view.realmz_minute])
		&"character":
			_render_characters()
		&"vault":
			_render_vault()
		&"inventory":
			_render_inventory()
		&"spells":
			_render_spells()
		&"services":
			_render_services()
		&"journal":
			_render_journal()
		&"system":
			_render_system()
	_assign_focus_keys(_body)
	call_deferred("_restore_focus", mounted_new_route, previous_scroll_horizontal, previous_scroll_vertical)


func _render_characters() -> void:
	if _view.party_members.is_empty():
		_add_empty_state("No characters", "Begin a campaign or import an eligible vault character.")
		return
	_render_party_order()
	_ensure_appearance_textures()
	var sheet := ClassicCharacterSheet.new()
	sheet.name = "ClassicCharacterSheet"
	sheet.present(_view.party_members, _character_sheet_character_id, _appearance_textures, _settings.text_scale, _character_sheet_tab, _view.portrait_options, _view.combat_icon_options, _view.availability(&"change_character_appearance"))
	_character_sheet_character_id = sheet.selected_character_id()
	sheet.character_selected.connect(func(character_id: String) -> void: _character_sheet_character_id = character_id)
	sheet.tab_changed.connect(func(tab_id: StringName) -> void: _character_sheet_tab = tab_id)
	sheet.appearance_change_requested.connect(_submit_character_appearance)
	_body.add_child(sheet)


func _submit_character_appearance(character_id: String, appearance_kind: StringName, appearance_id: String) -> void:
	_character_sheet_character_id = character_id
	_character_sheet_tab = &"appearance"
	intent_submitted.emit(PlayerIntent.change_character_appearance(character_id, appearance_kind, appearance_id))


func _render_party_order() -> void:
	var current_ids: Array[String] = []
	var characters_by_id: Dictionary = {}
	for character: CharacterView in _view.party_members:
		current_ids.append(character.id)
		characters_by_id[character.id] = character
	if current_ids != _party_order_source_ids:
		_party_order_source_ids = current_ids.duplicate()
		_party_order_draft_ids = current_ids.duplicate()
	else:
		var seen_draft_ids: Dictionary = {}
		var valid_draft := _party_order_draft_ids.size() == current_ids.size()
		for character_id: String in _party_order_draft_ids:
			if seen_draft_ids.has(character_id) or not characters_by_id.has(character_id):
				valid_draft = false
				break
			seen_draft_ids[character_id] = true
		if not valid_draft:
			_party_order_draft_ids = current_ids.duplicate()
	_add_section_heading("Party Order", "Selection and battle formation use this order")
	var availability := _view.availability(&"reorder_party")
	for index: int in _party_order_draft_ids.size():
		var character: CharacterView = characters_by_id[_party_order_draft_ids[index]]
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
			move_up.pressed.connect(_move_party_order_draft.bind(index, -1))
		row.add_child(move_up)
		var move_down := Button.new()
		move_down.text = "Move Down"
		move_down.disabled = not availability.enabled or index == _party_order_draft_ids.size() - 1
		move_down.tooltip_text = availability.reason if not availability.enabled else "Already last." if index == _party_order_draft_ids.size() - 1 else "Move %s one slot later." % character.name
		if not move_down.disabled:
			move_down.pressed.connect(_move_party_order_draft.bind(index, 1))
		row.add_child(move_down)
		_body.add_child(row)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	var apply := Button.new()
	apply.text = "Apply Party Order"
	apply.disabled = not availability.enabled or _party_order_draft_ids == current_ids
	apply.tooltip_text = availability.reason if not availability.enabled else "Choose a different order first." if _party_order_draft_ids == current_ids else "Commit this complete party permutation."
	if not apply.disabled:
		apply.pressed.connect(_submit_party_order)
	actions.add_child(apply)
	var cancel := Button.new()
	cancel.text = "Cancel Order Changes"
	cancel.disabled = _party_order_draft_ids == current_ids
	cancel.tooltip_text = "The displayed order already matches the session." if cancel.disabled else "Discard the staged order without changing the party."
	if not cancel.disabled:
		cancel.pressed.connect(_cancel_party_order_draft)
	actions.add_child(cancel)
	_body.add_child(actions)
	_body.add_child(HSeparator.new())


func _move_party_order_draft(index: int, offset: int) -> void:
	var destination := index + offset
	if index < 0 or index >= _party_order_draft_ids.size() or destination < 0 or destination >= _party_order_draft_ids.size():
		return
	var moved_character_id: String = _party_order_draft_ids[index]
	_party_order_draft_ids[index] = _party_order_draft_ids[destination]
	_party_order_draft_ids[destination] = moved_character_id
	_render_screen()


func _cancel_party_order_draft() -> void:
	_party_order_draft_ids = _party_order_source_ids.duplicate()
	_render_screen()


func _submit_party_order() -> void:
	intent_submitted.emit(PlayerIntent.reorder_party(_party_order_draft_ids))


func _render_vault() -> void:
	var back_button := Button.new()
	back_button.text = "Back to party setup" if _vault_return_to_setup else "Back to campaigns" if _vault_return_to_campaign else "Back"
	back_button.pressed.connect(func() -> void: handle_back())
	_mark_focus(back_button, "vault:back")
	_body.add_child(back_button)
	if _vault_revisions.is_empty():
		_add_empty_state("Character vault is empty", "No immutable .r2char revisions are installed. New characters can be published after they are added to a campaign party.")
		return
	var campaign_label := _view.campaign_summary.title if _view != null and _view.campaign_summary != null else "No campaign selected"
	_add_label(_body, "Eligibility for %s" % campaign_label, GOLD, 16)
	var previous_character_id := ""
	for revision: CharacterVaultRevisionView in _vault_revisions:
		if revision.character_id != previous_character_id:
			if not previous_character_id.is_empty():
				_body.add_child(HSeparator.new())
			_add_label(_body, revision.name, GOLD, 20)
			previous_character_id = revision.character_id
		var state_label := "Current revision" if revision.is_current else "Archived revision" if revision.archived else "Earlier revision"
		var eligibility_label := "Eligible" if revision.eligible else "Not eligible"
		var detail := "Level %d • %s / %s\nSource campaign %s • package %s\n%s" % [revision.level, revision.race_id, revision.caste_id, revision.source_campaign_id, revision.source_package_hash.left(12), revision.publication_label]
		if not revision.eligibility_reasons.is_empty():
			detail += "\n%s" % "\n".join(revision.eligibility_reasons)
		_add_card(state_label, "%s • %s" % [eligibility_label, revision.revision_hash.left(12)], detail)
		var actions := HBoxContainer.new()
		var import_button := Button.new()
		import_button.text = "Import this revision"
		import_button.tooltip_text = "\n".join(revision.eligibility_reasons)
		if _view == null or not _view.session_started:
			import_button.disabled = true
			import_button.tooltip_text = "Choose a campaign before importing a character."
		else:
			_apply_availability(import_button, &"import_vault_character")
			if not revision.eligible or revision.archived:
				import_button.disabled = true
				if revision.archived:
					import_button.tooltip_text = "Restore an archived revision before importing it."
		import_button.pressed.connect(func() -> void: intent_submitted.emit(PlayerIntent.import_vault_character(revision.character_id, revision.revision_hash)))
		_mark_focus(import_button, "vault:%s" % revision.revision_hash)
		actions.add_child(import_button)
		if revision.is_current:
			var archive_button := Button.new()
			archive_button.text = "Archive character"
			archive_button.tooltip_text = "Remove this character from the active vault without deleting immutable history."
			archive_button.pressed.connect(_confirm_vault_archive.bind(revision))
			actions.add_child(archive_button)
		elif revision.archived:
			var restore_button := Button.new()
			restore_button.text = "Restore as current"
			restore_button.pressed.connect(func() -> void: vault_restore_requested.emit(revision.character_id, revision.revision_hash))
			actions.add_child(restore_button)
		_body.add_child(actions)


func _confirm_vault_archive(revision: CharacterVaultRevisionView) -> void:
	var confirmation := ConfirmationDialog.new()
	confirmation.title = "Archive character"
	confirmation.dialog_text = "Archive %s? Campaign saves are unchanged, and this revision can be restored later." % revision.name
	confirmation.ok_button_text = "Archive"
	confirmation.confirmed.connect(func() -> void: vault_archive_requested.emit(revision.character_id))
	confirmation.visibility_changed.connect(func() -> void:
		if not confirmation.visible:
			confirmation.queue_free()
	)
	add_child(confirmation)
	confirmation.popup_centered(Vector2i(480, 180))


func _show_vault_for_setup() -> void:
	_vault_return_to_setup = true
	_vault_return_to_campaign = false
	_setup_overlay.visible = false
	_campaign_overlay.visible = false
	_screen_id = &"vault"
	_render_screen()


func _show_vault_from_campaign() -> void:
	_vault_return_to_campaign = true
	_vault_return_to_setup = false
	_campaign_overlay.visible = false
	_setup_overlay.visible = false
	_screen_id = &"vault"
	_body_frame.visible = true
	_render_screen()


func _render_inventory() -> void:
	if _view.party_members.is_empty():
		_add_empty_state("No party inventory", "The party has no characters.")
		return
	var selected_character: CharacterView = null
	for candidate: CharacterView in _view.party_members:
		if candidate.id == _inventory_character_id:
			selected_character = candidate
			break
	if selected_character == null:
		selected_character = _view.party_members[0]
		_inventory_character_id = selected_character.id
		_inventory_item_id = ""
	_add_section_heading("Whose items?", "%d party members" % _view.party_members.size())
	var character_row := HFlowContainer.new()
	character_row.add_theme_constant_override("h_separation", 6)
	character_row.add_theme_constant_override("v_separation", 6)
	for character: CharacterView in _view.party_members:
		var character_button := Button.new()
		character_button.text = "%s  %d/%d" % [character.name, character.carried_load, character.maximum_load]
		character_button.button_pressed = character.id == selected_character.id
		character_button.toggle_mode = true
		character_button.pressed.connect(func() -> void:
			_inventory_character_id = character.id
			_inventory_item_id = ""
			_render_screen()
		)
		character_row.add_child(character_button)
	_body.add_child(character_row)
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	var search := LineEdit.new()
	search.placeholder_text = "Filter visible item names…"
	search.text = _inventory_query
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_submitted.connect(func(value: String) -> void:
		_inventory_query = value.strip_edges()
		_render_screen()
	)
	filter_row.add_child(search)
	var clear_filter := Button.new()
	clear_filter.text = "Clear"
	clear_filter.disabled = _inventory_query.is_empty()
	clear_filter.pressed.connect(func() -> void:
		_inventory_query = ""
		_render_screen()
	)
	filter_row.add_child(clear_filter)
	_body.add_child(filter_row)
	var visible_items: Array[ItemView] = []
	for item: ItemView in selected_character.items:
		if _inventory_query.is_empty() or item.name.findn(_inventory_query) >= 0:
			visible_items.append(item)
	var selected_item: ItemView = null
	for item: ItemView in visible_items:
		if item.instance_id == _inventory_item_id:
			selected_item = item
			break
	if selected_item == null and not visible_items.is_empty():
		selected_item = visible_items[0]
		_inventory_item_id = selected_item.instance_id
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var item_list := VBoxContainer.new()
	item_list.custom_minimum_size.x = 250.0
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(item_list)
	_add_label(item_list, "%s's carried items" % selected_character.name, GOLD, 16)
	if visible_items.is_empty():
		_add_label(item_list, "No items match this filter." if not _inventory_query.is_empty() else "No carried items.", MUTED)
	for item: ItemView in visible_items:
		var item_button := Button.new()
		item_button.text = "%s%s  %s" % ["◆ " if item.equipped else "", item.name, "(%d)" % item.charges if item.charges > 0 else ""]
		item_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item_button.toggle_mode = true
		item_button.button_pressed = item.instance_id == selected_item.instance_id
		item_button.tooltip_text = "Equipped" if item.equipped else "Carried"
		item_button.pressed.connect(func() -> void:
			_inventory_item_id = item.instance_id
			_render_screen()
		)
		item_list.add_child(item_button)
	var detail := VBoxContainer.new()
	detail.custom_minimum_size.x = 300.0
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	columns.add_child(detail)
	if selected_item != null:
		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 10)
		title_row.add_child(_content_icon(selected_item.icon_resource_type, selected_item.icon_id))
		var title_box := VBoxContainer.new()
		title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_add_label(title_box, selected_item.name, GOLD, 20)
		_add_label(title_box, "%s • Weight %d • Charges %d" % ["Equipped" if selected_item.equipped else "Carried", selected_item.weight, selected_item.charges], MUTED, 13)
		title_row.add_child(title_box)
		detail.add_child(title_row)
		_add_label(detail, selected_item.description, Color("e0e2e5"))
		_add_label(detail, "Value %s" % [str(selected_item.value) if selected_item.identified else "Unknown until identified"], MUTED, 13)
		var actions := HFlowContainer.new()
		actions.add_theme_constant_override("h_separation", 5)
		actions.add_theme_constant_override("v_separation", 5)
		if selected_item.equipped:
			_add_item_intent_action(actions, &"inventory.action.equipped", "Unequip", selected_item.actions.unequip, PlayerIntent.item_action(PlayerIntent.Kind.UNEQUIP_ITEM, selected_item.instance_id, selected_character.id))
		else:
			_add_item_intent_action(actions, &"inventory.action.equipped", "Equip", selected_item.actions.equip, PlayerIntent.item_action(PlayerIntent.Kind.EQUIP_ITEM, selected_item.instance_id, selected_character.id))
		_add_item_intent_action(actions, &"inventory.action.use", "Use", selected_item.actions.use, PlayerIntent.use_item(selected_item.instance_id, selected_character.id))
		_add_item_intent_action(actions, &"inventory.action.identify", "Identify", selected_item.actions.identify, PlayerIntent.item_action(PlayerIntent.Kind.IDENTIFY_ITEM, selected_item.instance_id, selected_character.id))
		_add_item_intent_action(actions, &"inventory.action.join", "Join", selected_item.actions.join, PlayerIntent.item_action(PlayerIntent.Kind.JOIN_ITEM, selected_item.instance_id, selected_character.id))
		_add_item_intent_action(actions, &"inventory.action.split", "Split", selected_item.actions.split, PlayerIntent.item_action(PlayerIntent.Kind.SPLIT_ITEM, selected_item.instance_id, selected_character.id))
		_add_item_intent_action(actions, &"inventory.action.drop", "Drop", selected_item.actions.drop, PlayerIntent.item_action(PlayerIntent.Kind.DROP_ITEM, selected_item.instance_id, selected_character.id))
		detail.add_child(actions)
		_add_label(detail, "Trade with", GOLD, 15)
		if selected_item.actions.trade_targets.is_empty():
			_add_label(detail, "No other party member is available.", MUTED, 13)
		else:
			var trade_row := HFlowContainer.new()
			trade_row.add_theme_constant_override("h_separation", 5)
			for target: ItemTransferTargetView in selected_item.actions.trade_targets:
				var trade_button := Button.new()
				trade_button.text = "Give to %s" % target.character_name
				trade_button.disabled = not target.enabled
				trade_button.tooltip_text = target.reason
				if target.enabled:
					trade_button.pressed.connect(func() -> void: intent_submitted.emit(PlayerIntent.trade_item(selected_item.instance_id, selected_character.id, target.character_id)))
				trade_row.add_child(trade_button)
			detail.add_child(trade_row)
		_add_label(detail, "Classic has no ordinary party stash. Scenario opcode 36 equipment escrow is automatic and does not appear here.", MUTED, 12)
	_body.add_child(columns)


func _render_spells() -> void:
	var any_spells := false
	if _view.party_summary != null:
		_add_section_heading("Field spellbook", "Camped" if _view.party_summary.camping else "Exploring")
	for character: CharacterView in _view.party_members:
		_add_section_heading(character.name, "SP %d/%d" % [character.spell_points, character.maximum_spell_points])
		for spell: SpellView in character.spells:
			any_spells = true
			var context := "Combat%s • Camp%s" % [" yes" if spell.castable_in_combat else " no", " yes" if spell.castable_in_camp else " no"]
			_add_content_card(spell.icon_resource_type, spell.icon_id, spell.name, "%s • Cost %d" % [character.name, spell.cost], "%s\nRange %d–%d • Duration %d–%d • %s" % [spell.description, spell.range_min, spell.range_max, spell.duration_min, spell.duration_max, context])
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 5)
			row.add_theme_constant_override("v_separation", 5)
			if spell.power_levels.is_empty():
				_add_item_intent_action(row, &"spells.action.cast", "Cast", spell.field_cast, PlayerIntent.cast_spell(spell.id, character.id))
			else:
				for power: int in spell.power_levels:
					var cost := absi(spell.cost * power)
					_add_item_intent_action(row, &"", "Cast P%d (%d SP)" % [power, cost], spell.field_cast, PlayerIntent.cast_spell(spell.id, character.id, "", power))
			if spell.scroll_power_levels.is_empty():
				_add_item_intent_action(row, &"", "Make Scroll", spell.make_scroll, PlayerIntent.make_scroll(spell.id, character.id))
			else:
				for power: int in spell.scroll_power_levels:
					var scribing_cost := absi(spell.cost * power * 2)
					_add_item_intent_action(row, &"", "Make P%d Scroll (%d SP)" % [power, scribing_cost], spell.make_scroll, PlayerIntent.make_scroll(spell.id, character.id, power))
			var abort := _bitmap_button(&"spells.action.abort", "Abort")
			abort.tooltip_text = "Return to exploration without casting."
			abort.command_requested.connect(func(_command_id: StringName) -> void: open_screen(&"exploration"))
			row.add_child(abort)
			_body.add_child(row)
		_add_section_heading("%s's scroll case" % character.name, "Five fixed Classic slots")
		for scroll: SpellScrollView in character.scrolls:
			var scroll_row := HBoxContainer.new()
			scroll_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll_row.add_theme_constant_override("separation", 8)
			var scroll_label := _add_label(scroll_row, "Slot %d • %s%s" % [scroll.slot_index + 1, scroll.spell_name, "" if scroll.power == 0 else " • Power %d" % scroll.power], MUTED if scroll.power == 0 else Color("e0e2e5"), 13)
			scroll_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_add_item_intent_action(scroll_row, &"", "Use", scroll.use, PlayerIntent.use_scroll(character.id, scroll.slot_index))
			_body.add_child(scroll_row)
	if _view.party_members.is_empty():
		_add_empty_state("No spellbooks", "The party has no characters.")
	elif not any_spells:
		_add_empty_state("No known spells", "No party member currently knows a spell.")


func _render_services() -> void:
	_render_money_workspace()
	_add_section_heading("Location services", "%d available" % _view.services.size())
	if _view.services.is_empty():
		_add_empty_state("No active service", "Shops, temples, banks, storage, and treasure open here only when the session supplies a typed service interaction.")
		for title: String in ["Shop", "Temple", "Bank", "Storage", "Treasure"]:
			_add_card(title, "Unavailable at this location", "No service facts were supplied; Realmz 2 does not infer availability from the map or scenario name.")
		return
	for service: ServiceView in _view.services:
		_add_card(service.title, String(service.service_kind).replace("_", " ").capitalize(), "Available actions: %s" % [", ".join(service.actions)])
		for action: StringName in service.actions:
			var button := Button.new()
			button.text = String(action).capitalize()
			var reason := String(service.disabled_reasons.get(action, ""))
			var availability := _view.availability(&"service_action")
			button.disabled = not reason.is_empty() or not availability.enabled
			button.tooltip_text = reason if not reason.is_empty() else availability.reason if not availability.enabled else "Enter %s" % service.title
			if not button.disabled:
				button.pressed.connect(_submit_service_action.bind(service.service_id, action))
			_body.add_child(button)


func _render_money_workspace() -> void:
	_add_section_heading("Money", "Classic Pool, Share, and Swap")
	var workspace := _view.money_workspace
	if workspace == null:
		_add_empty_state("Money management unavailable", "Begin the adventure before pooling or transferring wealth.")
		return
	_add_card("Party pool", "%d gold • %d gems • %d jewelry" % [workspace.pooled_gold, workspace.pooled_gems, workspace.pooled_jewelry], "Banked: %d gold • %d gems • %d jewelry" % [workspace.banked_gold, workspace.banked_gems, workspace.banked_jewelry])
	var party_actions := HFlowContainer.new()
	party_actions.add_theme_constant_override("h_separation", 5)
	party_actions.add_theme_constant_override("v_separation", 5)
	_add_money_intent_action(party_actions, "Pool party wealth", workspace.pool, PlayerIntent.money_action(&"pool"))
	_add_money_intent_action(party_actions, "Share pooled wealth", workspace.share, PlayerIntent.money_action(&"share"))
	_body.add_child(party_actions)
	if workspace.characters.is_empty():
		_add_empty_state("No adventurers", "A party member is required for Classic Swap.")
		return
	if workspace.character(_money_character_id) == null:
		_money_character_id = workspace.characters[0].character_id
	var selector := OptionButton.new()
	selector.tooltip_text = "Choose the adventurer whose carried wealth will be exchanged with the party pool."
	for character: MoneyCharacterView in workspace.characters:
		selector.add_item("%s • Load %d/%d" % [character.name, character.carried_load, character.maximum_load])
		selector.set_item_metadata(selector.item_count - 1, character.character_id)
		if character.character_id == _money_character_id:
			selector.select(selector.item_count - 1)
	selector.item_selected.connect(func(index: int) -> void:
		_money_character_id = String(selector.get_item_metadata(index))
		_render_screen()
	)
	_body.add_child(selector)
	var selected := workspace.character(_money_character_id)
	_add_card(selected.name, "%d gold • %d gems • %d jewelry" % [selected.gold, selected.gems, selected.jewelry], "Carried load %d/%d" % [selected.carried_load, selected.maximum_load])
	for transfer: MoneyTransferView in selected.transfers:
		var denomination_label := String(transfer.denomination).capitalize()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var label := _label("%s • %d per step" % [denomination_label, transfer.amount], MUTED, 14)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		_add_money_intent_action(row, "To pool", transfer.to_pool, PlayerIntent.money_action(&"to-pool", selected.character_id, String(transfer.denomination), transfer.amount))
		_add_money_intent_action(row, "To %s" % selected.name, transfer.to_character, PlayerIntent.money_action(&"to-character", selected.character_id, String(transfer.denomination), transfer.amount))
		_body.add_child(row)
	var done := Button.new()
	done.text = "Done"
	done.tooltip_text = "Return to exploration without another money mutation."
	done.pressed.connect(func() -> void: open_screen(&"exploration"))
	_body.add_child(done)


func _add_money_intent_action(parent: Container, label: String, local_availability: ActionAvailabilityView, intent: PlayerIntent) -> Button:
	var button := Button.new()
	button.text = label
	var workspace_availability := _view.availability(&"money_action")
	button.disabled = not workspace_availability.enabled or local_availability == null or not local_availability.enabled
	if not workspace_availability.enabled:
		button.tooltip_text = workspace_availability.reason
	elif local_availability == null:
		button.tooltip_text = "This money action is unavailable."
	elif not local_availability.enabled:
		button.tooltip_text = local_availability.reason
	else:
		button.pressed.connect(func() -> void: intent_submitted.emit(intent))
	parent.add_child(button)
	return button


func _submit_service_action(service_id: String, action: StringName) -> void:
	intent_submitted.emit(PlayerIntent.service_action(service_id, action))


func _render_journal() -> void:
	_add_section_heading("Acquired maps", "%d available" % _view.party_summary.acquired_map_ids.size() if _view.party_summary != null else "0 available")
	if _view.party_summary == null or _view.party_summary.acquired_map_ids.is_empty():
		_add_empty_state("No acquired maps", "Maps appear only after the session records their acquisition.")
	else:
		for map_id: String in _view.party_summary.acquired_map_ids:
			_add_card(map_id, "Acquired map", "Map viewing is not implemented in the current gameplay slice.")
	_add_section_heading("Journal entries", "%d entries" % _view.journal_entries.size())
	if _view.journal_entries.is_empty():
		_add_empty_state("The journal is empty", "No journal records were supplied by the current session.")
	else:
		for entry: JournalEntryView in _view.journal_entries:
			_add_card(entry.title, "Day %d • %s" % [entry.day, entry.map_id], entry.text)
	_add_disabled_action(_body, "Open Classic journal", &"open_journal")
	_add_disabled_action(_body, "Open acquired maps", &"open_maps")


func _render_system() -> void:
	_add_card("Current campaign", _view.campaign_summary.title if _view.campaign_summary != null else _view.campaign_id, "Package %s\nRules %s" % [_view.campaign_summary.package_hash if _view.campaign_summary != null else "Unavailable", _view.rules_version])
	_add_section_heading("Save and restore", "Committed session boundaries only")
	var save_row := HBoxContainer.new()
	var save := Button.new()
	save.text = "Quick save"
	save.pressed.connect(func() -> void: system_action_requested.emit(&"save", "quick"))
	save_row.add_child(save)
	var load := Button.new()
	load.text = "Quick load"
	load.pressed.connect(func() -> void: system_action_requested.emit(&"load", "quick"))
	save_row.add_child(load)
	var campaigns := Button.new()
	campaigns.text = "Campaign library"
	campaigns.pressed.connect(func() -> void: system_action_requested.emit(&"campaigns", null))
	save_row.add_child(campaigns)
	_body.add_child(save_row)
	_add_section_heading("Display", "Interface scale and text size are independent")
	var ui_scale := OptionButton.new()
	for entry: Dictionary in [{"label": "UI scale: Auto", "id": PresentationSettings.UI_SCALE_AUTO}, {"label": "UI scale: 100%", "id": PresentationSettings.UI_SCALE_100}, {"label": "UI scale: 125%", "id": PresentationSettings.UI_SCALE_125}, {"label": "UI scale: 150%", "id": PresentationSettings.UI_SCALE_150}]:
		ui_scale.add_item(entry["label"])
		ui_scale.set_item_metadata(ui_scale.item_count - 1, entry["id"])
		if entry["id"] == _settings.ui_scale_mode:
			ui_scale.select(ui_scale.item_count - 1)
	ui_scale.item_selected.connect(func(index: int) -> void: presentation_setting_changed.emit(&"ui_scale_mode", String(ui_scale.get_item_metadata(index))))
	_body.add_child(ui_scale)
	var text_scale := HSlider.new()
	text_scale.min_value = 0.8
	text_scale.max_value = 1.5
	text_scale.step = 0.1
	text_scale.value = _settings.text_scale
	text_scale.tooltip_text = "Text scale %d%%" % int(round(_settings.text_scale * 100.0))
	text_scale.value_changed.connect(func(value: float) -> void: presentation_setting_changed.emit(&"text_scale", value))
	_body.add_child(text_scale)
	var window_mode := OptionButton.new()
	window_mode.add_item("Windowed")
	window_mode.set_item_metadata(0, PresentationSettings.WINDOWED)
	window_mode.add_item("Borderless fullscreen")
	window_mode.set_item_metadata(1, PresentationSettings.BORDERLESS_FULLSCREEN)
	window_mode.select(1 if _settings.window_mode == PresentationSettings.BORDERLESS_FULLSCREEN else 0)
	window_mode.item_selected.connect(func(index: int) -> void: presentation_setting_changed.emit(&"window_mode", String(window_mode.get_item_metadata(index))))
	_body.add_child(window_mode)
	_add_section_heading("Accessibility and presentation", "These preferences never change simulation")
	_add_setting_toggle("Reduced motion", _settings.reduced_motion, &"reduced_motion")
	_add_setting_toggle("Use topology-derived 3D dungeons", _settings.dungeon_3d, &"dungeon_3d")
	_add_setting_toggle("Show topology diagnostics", _settings.topology_debug, &"topology_debug")
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = _settings.master_volume
	volume.tooltip_text = "Master volume"
	volume.value_changed.connect(func(value: float) -> void: presentation_setting_changed.emit(&"master_volume", value))
	_body.add_child(volume)


func _add_card(title: String, subtitle: String, detail: String) -> void:
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
	_content_parent.add_child(panel)


func _add_content_card(resource_type: String, icon_id: int, title: String, subtitle: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = 280.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	row.add_child(_content_icon(resource_type, icon_id))
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	row.add_child(box)
	_add_label(box, title, Color("e7d078"), 17)
	_add_label(box, subtitle, Color("e0e2e5"))
	if not detail.is_empty():
		_add_label(box, detail, MUTED)
	_content_parent.add_child(panel)


func _content_icon(resource_type: String, resource_id: int) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(52.0, 52.0)
	var asset: PackageMediaAsset = _media.asset_by_resource(resource_type, resource_id) if _media != null and resource_id != 0 else null
	if asset != null:
		var bytes := _media.read_bytes(asset)
		var image := Image.new()
		var error := ERR_UNAVAILABLE
		match asset.path.get_extension().to_lower():
			"png":
				error = image.load_png_from_buffer(bytes)
			"jpg", "jpeg":
				error = image.load_jpg_from_buffer(bytes)
			"webp":
				error = image.load_webp_from_buffer(bytes)
		if error == OK:
			var texture := TextureRect.new()
			texture.texture = ImageTexture.create_from_image(image)
			texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			texture.tooltip_text = asset.label
			frame.add_child(texture)
			return frame
	var fallback := Label.new()
	fallback.text = "◈\n%d" % resource_id if resource_id != 0 else "◈"
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_theme_color_override("font_color", MUTED)
	fallback.tooltip_text = "Package media unavailable for %s %d." % [resource_type, resource_id] if resource_id != 0 else "No package media identity was supplied."
	frame.add_child(fallback)
	return frame


func _add_section_heading(title: String, detail: String = "") -> void:
	var row := HBoxContainer.new()
	var heading := _label(title, GOLD, 18)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	if not detail.is_empty():
		var note := _label(detail, MUTED, 13)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(note)
	_body.add_child(row)


func _add_empty_state(title: String, detail: String) -> void:
	_add_card(title, detail, "Realmz 2 shows only facts supplied by the detached session view.")


func _add_disabled_action(parent: Container, label: String, action_id: StringName) -> Button:
	var button := Button.new()
	button.text = label
	_apply_availability(button, action_id)
	parent.add_child(button)
	return button


func _bitmap_button(asset_id: StringName, label: String) -> ClassicBitmapButton:
	var button := ClassicBitmapButton.new()
	button.configure({
		"id": asset_id,
		"asset_id": asset_id,
		"tooltip": label,
		"accelerator": "",
	}, 1)
	return button


func _add_bitmap_intent_action(parent: Container, asset_id: StringName, label: String, action_id: StringName, intent: PlayerIntent) -> ClassicBitmapButton:
	var button := _bitmap_button(asset_id, label)
	_apply_availability(button, action_id)
	if not button.disabled:
		button.command_requested.connect(func(_command_id: StringName) -> void: intent_submitted.emit(intent))
	parent.add_child(button)
	return button


func _add_item_intent_action(parent: Container, asset_id: StringName, label: String, availability: ActionAvailabilityView, intent: PlayerIntent) -> BaseButton:
	var button: BaseButton
	if ClassicUiAssetCatalog.definition(asset_id).is_empty():
		var text_button := Button.new()
		text_button.text = label
		text_button.custom_minimum_size = Vector2(64.0, 56.0)
		button = text_button
	else:
		button = _bitmap_button(asset_id, label)
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if not availability.enabled else label
	if not button.disabled:
		if button is ClassicBitmapButton:
			(button as ClassicBitmapButton).command_requested.connect(func(_command_id: StringName) -> void: intent_submitted.emit(intent))
		else:
			button.pressed.connect(func() -> void: intent_submitted.emit(intent))
	parent.add_child(button)
	return button


func _apply_availability(button: BaseButton, action_id: StringName) -> void:
	var availability := _view.availability(action_id) if _view != null else ActionAvailabilityView.new(action_id, false, "No active session.")
	button.disabled = not availability.enabled
	button.tooltip_text = availability.reason if not availability.enabled else ""


func _add_setting_toggle(label: String, enabled: bool, setting_id: StringName) -> void:
	var toggle := CheckButton.new()
	toggle.text = label
	toggle.button_pressed = enabled
	toggle.toggled.connect(func(value: bool) -> void: presentation_setting_changed.emit(setting_id, value))
	_body.add_child(toggle)


func _screen_definition(screen_id: StringName) -> Dictionary:
	return UiRouteCatalog.route(screen_id)


func _display_screen_label(screen_id: StringName) -> String:
	var definition := _screen_definition(screen_id)
	if not definition.is_empty():
		return String(definition["label"])
	return "Realmz"


func _mark_focus(control: Control, key: String) -> void:
	control.set_meta("focus_key", key)


func _assign_focus_keys(parent: Node, next_index: int = 0) -> int:
	for child: Node in parent.get_children():
		if child is Control and (child as Control).focus_mode != Control.FOCUS_NONE:
			if not child.has_meta("focus_key"):
				child.set_meta("focus_key", "%s:%d" % [_screen_id, next_index])
			next_index += 1
		next_index = _assign_focus_keys(child, next_index)
	return next_index


func _store_focus() -> void:
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and is_ancestor_of(owner) and owner.has_meta("focus_key"):
		_focus_keys[_screen_id] = String(owner.get_meta("focus_key"))


func _restore_focus(reset_scroll_to_top: bool = false, previous_scroll_horizontal: int = 0, previous_scroll_vertical: int = 0) -> void:
	var wanted := String(_focus_keys.get(_screen_id, ""))
	var restored := false
	if not wanted.is_empty():
		var focus_match := _find_focus_key(_body, wanted)
		if focus_match != null:
			focus_match.grab_focus()
			restored = true
	if not restored:
		_focus_first(_body)
	if _body_scroll != null:
		# Focus restoration runs before the rebuilt layout has settled and can
		# otherwise force the ScrollContainer to its final focusable control.
		_body_scroll.scroll_horizontal = 0 if reset_scroll_to_top else previous_scroll_horizontal
		_body_scroll.scroll_vertical = 0 if reset_scroll_to_top else previous_scroll_vertical


func _find_focus_key(parent: Node, key: String) -> Control:
	for child: Node in parent.get_children():
		if child is Control and child.has_meta("focus_key") and String(child.get_meta("focus_key")) == key:
			return child
		var nested := _find_focus_key(child, key)
		if nested != null:
			return nested
	return null


func _focus_first(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Control:
			var control := child as Control
			if control.is_inside_tree() and control.visible and control.focus_mode != Control.FOCUS_NONE and not (control is BaseButton and (control as BaseButton).disabled):
				control.grab_focus()
				return
		_focus_first(child)
		var viewport := get_viewport()
		var focus_owner := viewport.gui_get_focus_owner() if viewport != null else null
		if focus_owner != null and parent.is_ancestor_of(focus_owner):
			return


func _display_name(campaign: PackageDiscoveryResult) -> String:
	return campaign.campaign_id.replace("-", " ").capitalize()


func _campaign_precedes(left: PackageDiscoveryResult, right: PackageDiscoveryResult) -> bool:
	if left.ready != right.ready:
		return left.ready
	return _display_name(left).naturalnocasecmp_to(_display_name(right)) < 0


func _label(text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * _settings.text_scale)))
	return label


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := _label(text, color, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
