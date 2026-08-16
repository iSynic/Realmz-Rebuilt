class_name CampaignPartySetupController
extends "res://src/presentation/controllers/party_setup_character_creation_controller.gd"

func build_splash_overlay() -> void:
	_campaign_library.build_splash_overlay()

func build_campaign_overlay() -> void:
	_campaign_library.build_campaign_overlay()

func build_setup_overlay() -> void:
	if setup_overlay != null:
		return
	if campaign_overlay == null:
		build_campaign_overlay()
	var columns := _build_setup_columns()
	_build_creator_stage(columns[0])
	_build_party_stage(columns[1])
	_build_setup_options(columns[0], columns[1])
	_build_setup_actions(columns[0], columns[1])
	_build_setup_character_inspection()
	render_creator_step()


func _build_setup_columns() -> Array[VBoxContainer]:
	setup_overlay = PanelContainer.new()
	setup_overlay.name = "PartySetup"
	setup_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var setup_surface := StyleBoxFlat.new()
	setup_surface.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	setup_surface.set_border_width_all(0)
	setup_surface.content_margin_left = 10.0
	setup_surface.content_margin_top = 10.0
	setup_surface.content_margin_right = 10.0
	setup_surface.content_margin_bottom = 10.0
	setup_overlay.add_theme_stylebox_override("panel", setup_surface)
	setup_overlay.set_anchors_preset(Control.PRESET_CENTER)
	setup_overlay.offset_left = -440.0
	setup_overlay.offset_top = -238.0
	setup_overlay.offset_right = 440.0
	setup_overlay.offset_bottom = 238.0
	setup_overlay.z_index = 25
	_host.add_child(setup_overlay)
	var setup_body := HBoxContainer.new()
	setup_body.name = "ScenarioPartyWorkspace"
	setup_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	setup_body.add_theme_constant_override("separation", 10)
	_host.remove_child(campaign_overlay)
	setup_body.add_child(campaign_overlay)
	setup_overlay.add_child(setup_body)

	var character_pane := PanelContainer.new()
	character_pane.name = "CharacterFilesPane"
	character_pane.theme_type_variation = &"ClassicInset"
	character_pane.custom_minimum_size.x = 286.0
	character_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_pane.size_flags_stretch_ratio = 1.15
	setup_body.add_child(character_pane)
	var character_column := VBoxContainer.new()
	character_column.name = "CharacterFilesPaneContent"
	character_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_column.add_theme_constant_override("separation", 6)
	character_pane.add_child(character_column)

	var party_pane := PanelContainer.new()
	party_pane.name = "CurrentPartyPane"
	party_pane.theme_type_variation = &"ClassicInset"
	party_pane.custom_minimum_size.x = 286.0
	party_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	party_pane.size_flags_stretch_ratio = 1.15
	setup_body.add_child(party_pane)
	var party_column := VBoxContainer.new()
	party_column.name = "PartyColumn"
	party_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	party_column.add_theme_constant_override("separation", 6)
	party_pane.add_child(party_column)
	return [character_column, party_column]


func _build_creator_stage(character_column: VBoxContainer) -> void:
	creator_steps = HBoxContainer.new()
	creator_steps.add_theme_constant_override("separation", 6)
	creator_steps.custom_minimum_size.y = 24.0
	for step: String in ["1 Identity", "2 Race & Class", "3 Appearance", "4 Review", "5 Spells"]:
		var step_label := _label(step, GOLD if step.begins_with("1") else MUTED, 13)
		step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		creator_steps.add_child(step_label)
		creator_step_labels.append(step_label)
	character_column.add_child(creator_steps)
	creator_scroll = ScrollContainer.new()
	creator_scroll.name = "CreatorScroll"
	creator_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creator_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	creator_scroll.custom_minimum_size.y = 220.0
	creator_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	creator_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	creator_scroll.follow_focus = true
	character_column.add_child(creator_scroll)
	creator = BoxContainer.new()
	creator.custom_minimum_size.y = 310.0
	creator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creator.size_flags_vertical = Control.SIZE_EXPAND_FILL
	creator.add_theme_constant_override("separation", 12)
	creator_scroll.add_child(creator)
	creator_page = VBoxContainer.new()
	creator_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creator_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	creator_page.size_flags_stretch_ratio = 1.0
	creator.add_child(creator_page)


func _build_party_stage(party_column: VBoxContainer) -> void:
	var party_heading := CenterContainer.new()
	party_heading.name = "PartyHeading"
	party_heading.custom_minimum_size.y = 28.0
	var party_heading_content := HBoxContainer.new()
	party_heading_content.add_child(_label("Current Party", GOLD, 20))
	var party_count := _label("• 0 / 6", MUTED, 13)
	party_count.name = "PartyCount"
	party_heading_content.add_child(party_count)
	party_heading.add_child(party_heading_content)
	party_column.add_child(party_heading)
	var party_scroll := ScrollContainer.new()
	party_scroll.name = "PartySlotScroll"
	party_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	party_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	party_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	party_scroll.follow_focus = true
	party_list = PartySetupPartyListScript.new()
	party_list.name = "PartySlots"
	party_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	party_list.add_theme_constant_override("separation", 2)
	party_list.import_requested.connect(_import_stored_character)
	party_scroll.add_child(party_list)
	party_column.add_child(party_scroll)


func _build_setup_options(character_column: VBoxContainer, party_column: VBoxContainer) -> void:
	setup_message = _add_label(character_column, "Enter a name to begin creating a character.", MUTED)
	setup_message.custom_minimum_size.y = 32.0
	setup_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	party_setup_options = VBoxContainer.new()
	party_setup_options.name = "PartySetupOptions"
	party_setup_options.add_theme_constant_override("separation", 4)
	party_guidance_label = _label("", Color("e0e2e5"), 12)
	party_guidance_label.name = "PartyLevelGuidance"
	party_guidance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	party_guidance_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_setup_options.add_child(party_guidance_label)
	var selectors := HBoxContainer.new()
	selectors.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selectors.add_theme_constant_override("separation", 6)
	var monster_column := VBoxContainer.new()
	monster_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	monster_column.add_child(_label("Monster Set", MUTED, 12))
	monster_set_option = OptionButton.new()
	monster_set_option.name = "MonsterSetOption"
	monster_set_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	monster_set_option.item_selected.connect(_party_setup_option_changed)
	monster_column.add_child(monster_set_option)
	selectors.add_child(monster_column)
	var difficulty_column := VBoxContainer.new()
	difficulty_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	difficulty_column.add_child(_label("Difficulty", MUTED, 12))
	difficulty_option = OptionButton.new()
	difficulty_option.name = "DifficultyOption"
	difficulty_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value: int in range(-2, 3):
		difficulty_option.add_item(PartySetupView.difficulty_name(value))
		difficulty_option.set_item_metadata(difficulty_option.item_count - 1, value)
	difficulty_option.item_selected.connect(_party_setup_option_changed)
	difficulty_column.add_child(difficulty_option)
	selectors.add_child(difficulty_column)
	party_setup_options.add_child(selectors)
	party_column.add_child(party_setup_options)


func _build_setup_actions(character_column: VBoxContainer, party_column: VBoxContainer) -> void:
	creator_action_bar = HBoxContainer.new()
	creator_action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	creator_cancel_button = Button.new()
	creator_cancel_button.text = "Cancel character"
	creator_cancel_button.pressed.connect(_cancel_creator)
	creator_action_bar.add_child(creator_cancel_button)
	creator_action_bar.add_spacer(true)
	creator_back_button = Button.new()
	creator_back_button.text = "Back"
	creator_back_button.pressed.connect(creator_back)
	creator_action_bar.add_child(creator_back_button)
	add_character_button = Button.new()
	add_character_button.text = "Reroll"
	add_character_button.pressed.connect(_reroll_character)
	creator_action_bar.add_child(add_character_button)
	creator_next_button = Button.new()
	creator_next_button.text = "Continue"
	creator_next_button.pressed.connect(creator_next)
	creator_action_bar.add_child(creator_next_button)
	character_column.add_child(creator_action_bar)
	var character_footer := HBoxContainer.new()
	create_character_button = Button.new()
	create_character_button.name = "CreateCharacter"
	create_character_button.text = "Create character"
	create_character_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_character_button.pressed.connect(_start_creator)
	character_footer.add_child(create_character_button)
	character_column.add_child(character_footer)
	var party_footer := HBoxContainer.new()
	begin_button = Button.new()
	begin_button.name = "BeginAdventure"
	begin_button.text = "Begin adventure"
	begin_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	begin_button.custom_minimum_size.y = 34.0
	begin_button.disabled = true
	begin_button.pressed.connect(submit_party)
	party_footer.add_child(begin_button)
	party_column.add_child(party_footer)

func set_view(next_view: GameView) -> void:
	view = next_view
	if setup_overlay != null and setup_overlay.visible:
		refresh_setup_options()

func set_campaigns(next_campaigns: Array[CampaignPackageView]) -> void:
	_campaign_library.set_campaigns(next_campaigns)

func set_package_operation(status: RefCounted) -> void:
	_campaign_library.set_package_operation(status)

func render_campaign_list() -> void:
	_campaign_library.render_campaign_list()

func set_vault_revisions(revisions: Array[CharacterVaultRevisionView]) -> void:
	vault_revisions = revisions.duplicate()
	if setup_overlay != null and setup_overlay.visible:
		refresh_setup_options()

func set_media_catalog(next_media: ClassicMediaCatalog) -> void:
	media = next_media
	_appearance_textures.clear()

func present_party_setup_status(text: String, is_error: bool = false) -> void:
	if view == null or not view.party_setup_available or setup_mode != &"assembly":
		return
	if setup_overlay == null or not setup_overlay.visible or setup_inspection_overlay.visible:
		return
	setup_message.text = text
	setup_message.tooltip_text = text
	setup_message.modulate = ERROR if is_error else MUTED
	setup_message.custom_minimum_size.y = 20.0
	setup_message.autowrap_mode = TextServer.AUTOWRAP_OFF
	setup_message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	setup_message.visible = not text.strip_edges().is_empty()

func apply_layout(profile: UiLayoutProfile, campaign_rect: Rect2, setup_rect: Rect2) -> void:
	if profile == null:
		return
	layout_profile = profile.id
	setup_layout_rect = setup_rect
	_apply_creator_layout(profile.id)
	if creator_scroll != null:
		creator_scroll.custom_minimum_size.y = 140.0 if profile.id == UiLayoutProfile.COMPACT else 220.0
	_campaign_library.apply_layout(profile, campaign_rect, setup_rect)
	apply_modal_layouts()

func apply_modal_layouts() -> void:
	_campaign_library.apply_modal_layouts()
	if setup_overlay != null:
		setup_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		setup_overlay.position = setup_layout_rect.position
		setup_overlay.size = setup_layout_rect.size
		if setup_inspection_overlay != null:
			setup_inspection_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
			setup_inspection_overlay.position = Vector2.ZERO
			setup_inspection_overlay.size = setup_overlay.size

func show_campaign_selection() -> void:
	if campaign_overlay == null or setup_overlay == null:
		return
	_campaign_library.show_campaign()
	setup_overlay.visible = true
	refresh_setup_options()
	apply_modal_layouts()
	_focus_first(setup_overlay)

func show_party_setup() -> void:
	if setup_overlay == null:
		return
	_campaign_library.hide_overlays()
	setup_overlay.visible = true
	refresh_setup_options()
	apply_modal_layouts()
	_focus_first(setup_overlay)

func hide_overlays() -> void:
	_campaign_library.hide_overlays()
	if setup_overlay != null:
		setup_overlay.visible = false

func full_stage_overlay_visible() -> bool:
	return _campaign_library.full_stage_overlay_visible() or setup_overlay != null and setup_overlay.visible

func accepts_exploration_input() -> bool:
	return not full_stage_overlay_visible()

func show_splash() -> void:
	_campaign_library.show_splash()
	if setup_overlay != null:
		setup_overlay.visible = false

func splash_visible() -> bool:
	return _campaign_library.splash_visible()

func finish_party_setup_navigation() -> void:
	setup_inspection_character_id = ""
	if setup_inspection_overlay != null:
		setup_inspection_overlay.visible = false
	reset_creator(true)

func handle_back() -> bool:
	if setup_overlay != null and setup_inspection_overlay != null and setup_inspection_overlay.visible:
		close_setup_character_inspection()
		return true
	if campaign_overlay != null and campaign_overlay.visible:
		if view != null and view.party_setup_available:
			return false
		return false
	if setup_overlay != null and setup_overlay.visible:
		if creator_step > 0:
			creator_back()
			return true
	return false

func present(next_view: GameView) -> void:
	view = next_view
	if view == null or not view.party_setup_available:
		return
	if awaiting_draft_generation and view.character_draft != null:
		awaiting_draft_generation = false
	if awaiting_draft_finalization and view.character_draft == null:
		awaiting_draft_finalization = false
		reset_creator(true)
	if setup_overlay != null:
		refresh_setup_options()
		if setup_overlay.visible and not setup_inspection_character_id.is_empty():
			_render_setup_character_inspection()
