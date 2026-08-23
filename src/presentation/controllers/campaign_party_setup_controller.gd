class_name CampaignPartySetupController
extends "res://src/presentation/controllers/party_setup_controller_component.gd"

const SetupStateScript := preload("res://src/presentation/controllers/campaign_party_setup_state.gd")
const PartySetupInspectionControllerScript := preload("res://src/presentation/controllers/party_setup_inspection_controller.gd")
const PartySetupAssemblyControllerScript := preload("res://src/presentation/controllers/party_setup_assembly_controller.gd")
const PartySetupCharacterCreationControllerScript := preload("res://src/presentation/controllers/party_setup_character_creation_controller.gd")

var start_requested: Signal:
	get: return _campaign_library.start_requested
var cancel_package_requested: Signal:
	get: return _campaign_library.cancel_package_requested
var refresh_requested: Signal:
	get: return _campaign_library.refresh_requested
var intent_submitted: Signal:
	get: return _state.intent_submitted
var standalone_character_creation_requested: Signal:
	get: return _state.standalone_character_creation_requested
var standalone_character_creation_cancelled: Signal:
	get: return _state.standalone_character_creation_cancelled
var campaign_selection_requested: Signal:
	get: return _campaign_library.campaign_selection_requested
var load_adventure_requested: Signal:
	get: return _campaign_library.load_adventure_requested
var load_saved_adventure_requested: Signal:
	get: return _state.load_saved_adventure_requested
var vault_requested: Signal:
	get: return _campaign_library.vault_requested
var quit_requested: Signal:
	get: return _campaign_library.quit_requested

var _inspection: RefCounted
var _assembly: RefCounted
var _creation: RefCounted


func _init() -> void:
	var state := SetupStateScript.new()
	super(state)
	_inspection = PartySetupInspectionControllerScript.new(state)
	_assembly = PartySetupAssemblyControllerScript.new(state, _inspection)
	_creation = PartySetupCharacterCreationControllerScript.new(state, _assembly)

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
	_inspection._build_setup_character_inspection()
	_creation.render_creator_step()


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
	setup_body = HBoxContainer.new()
	setup_body.name = "ScenarioPartyWorkspace"
	setup_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	setup_body.add_theme_constant_override("separation", 10)
	_host.remove_child(campaign_overlay)
	setup_body.add_child(campaign_overlay)
	setup_overlay.add_child(setup_body)

	character_pane = PanelContainer.new()
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

	party_pane = PanelContainer.new()
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
	_state.apply_setup_mode_layout()
	return [character_column, party_column]


func _build_creator_stage(character_column: VBoxContainer) -> void:
	creator_steps = HBoxContainer.new()
	creator_steps.add_theme_constant_override("separation", 6)
	creator_steps.custom_minimum_size.y = 24.0
	for step: String in ["1 Identity", "2 Race & Caste", "3 Appearance", "4 Review", "5 Spells"]:
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
	creator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creator.size_flags_vertical = Control.SIZE_EXPAND_FILL
	creator.add_theme_constant_override("separation", 12)
	creator_scroll.add_child(creator)
	creator_page = VBoxContainer.new()
	creator_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creator_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	party_list.import_requested.connect(_assembly._import_stored_character)
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
	var experience_ratio := _label("Experience gained at —", GOLD, 14)
	experience_ratio.name = "ExperienceRatio"
	experience_ratio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	party_setup_options.add_child(experience_ratio)
	var selectors := HBoxContainer.new()
	selectors.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selectors.add_theme_constant_override("separation", 6)
	var monster_column := VBoxContainer.new()
	monster_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	monster_column.add_child(_label("Monster Set", MUTED, 12))
	monster_set_option = OptionButton.new()
	monster_set_option.name = "MonsterSetOption"
	monster_set_option.theme_type_variation = &"ClassicTheldrowOptionButton"
	monster_set_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	monster_set_option.item_selected.connect(_assembly._party_setup_option_changed)
	monster_column.add_child(monster_set_option)
	selectors.add_child(monster_column)
	var difficulty_column := VBoxContainer.new()
	difficulty_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	difficulty_column.add_child(_label("Difficulty", MUTED, 12))
	difficulty_option = OptionButton.new()
	difficulty_option.name = "DifficultyOption"
	difficulty_option.theme_type_variation = &"ClassicTheldrowOptionButton"
	difficulty_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value: int in range(-2, 3):
		difficulty_option.add_item(PartySetupView.difficulty_name(value))
		difficulty_option.set_item_metadata(difficulty_option.item_count - 1, value)
	difficulty_option.item_selected.connect(_assembly._party_setup_option_changed)
	difficulty_column.add_child(difficulty_option)
	selectors.add_child(difficulty_column)
	party_setup_options.add_child(selectors)
	party_column.add_child(party_setup_options)


func _build_setup_actions(character_column: VBoxContainer, party_column: VBoxContainer) -> void:
	creator_action_bar = HBoxContainer.new()
	creator_action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	creator_cancel_button = Button.new()
	creator_cancel_button.text = "Cancel character"
	creator_cancel_button.theme_type_variation = &"ClassicTheldrowButton"
	creator_cancel_button.pressed.connect(_creation._cancel_creator)
	creator_action_bar.add_child(creator_cancel_button)
	creator_action_bar.add_spacer(true)
	creator_back_button = Button.new()
	creator_back_button.text = "Back"
	creator_back_button.theme_type_variation = &"ClassicTheldrowButton"
	creator_back_button.pressed.connect(_creation.creator_back)
	creator_action_bar.add_child(creator_back_button)
	add_character_button = Button.new()
	add_character_button.text = "Reroll"
	add_character_button.theme_type_variation = &"ClassicTheldrowButton"
	add_character_button.pressed.connect(_creation._reroll_character)
	creator_action_bar.add_child(add_character_button)
	creator_next_button = Button.new()
	creator_next_button.text = "Continue"
	creator_next_button.theme_type_variation = &"ClassicTheldrowButton"
	creator_next_button.pressed.connect(_creation.creator_next)
	creator_action_bar.add_child(creator_next_button)
	character_column.add_child(creator_action_bar)
	var character_footer := HBoxContainer.new()
	create_character_button = Button.new()
	create_character_button.name = "CreateCharacter"
	create_character_button.text = "Create character"
	create_character_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_character_button.pressed.connect(_creation._start_creator)
	character_footer.add_child(create_character_button)
	character_column.add_child(character_footer)
	var party_footer := HBoxContainer.new()
	var load_adventure := Button.new()
	load_adventure.name = "LoadSavedAdventure"
	load_adventure.text = "Load saved adventure"
	load_adventure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_adventure.custom_minimum_size.y = 34.0
	load_adventure.pressed.connect(func() -> void: _state.load_saved_adventure_requested.emit())
	party_footer.add_child(load_adventure)
	begin_button = Button.new()
	begin_button.name = "BeginAdventure"
	begin_button.text = "Begin adventure"
	begin_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	begin_button.custom_minimum_size.y = 34.0
	begin_button.disabled = true
	begin_button.pressed.connect(_assembly.submit_party)
	party_footer.add_child(begin_button)
	party_column.add_child(party_footer)

func set_view(next_view: GameView) -> void:
	view = next_view
	if setup_overlay != null and setup_overlay.visible:
		_creation.refresh_setup_options()

func set_campaigns(next_campaigns: Array[CampaignPackageView]) -> void:
	_campaign_library.set_campaigns(next_campaigns)

func set_package_operation(status: RefCounted) -> void:
	_campaign_library.set_package_operation(status)

func render_campaign_list() -> void:
	_campaign_library.render_campaign_list()

func set_vault_revisions(revisions: Array[CharacterVaultRevisionView]) -> void:
	vault_revisions = revisions.duplicate()
	if setup_overlay != null and setup_overlay.visible:
		_creation.refresh_setup_options()

func set_media_catalog(next_media: ClassicMediaCatalog) -> void:
	media = next_media
	_campaign_library.set_media_catalog(next_media)
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
	_creation._apply_creator_layout(profile.id)
	_state.apply_setup_mode_layout()
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
		# Dynamic Character File rows may lower the panel's minimum size after a
		# previous render. Reapply the requested viewport rect after containers
		# have propagated that lower minimum instead of retaining the old height.
		setup_overlay.set_deferred(&"size", setup_layout_rect.size)
		if setup_inspection_overlay != null:
			setup_inspection_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
			setup_inspection_overlay.position = Vector2.ZERO
			setup_inspection_overlay.size = setup_overlay.size

func show_campaign_selection() -> void:
	if campaign_overlay == null or setup_overlay == null:
		return
	_campaign_library.show_campaign()
	setup_overlay.visible = true
	_creation.refresh_setup_options()
	apply_modal_layouts()
	_focus_first(setup_overlay)

func show_party_setup() -> void:
	if setup_overlay == null:
		return
	_campaign_library.hide_overlays()
	setup_overlay.visible = true
	_creation.refresh_setup_options()
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
	_creation.reset_creator(true)

func handle_back() -> bool:
	if setup_overlay != null and setup_inspection_overlay != null and setup_inspection_overlay.visible:
		_inspection.close_setup_character_inspection()
		return true
	if campaign_overlay != null and campaign_overlay.visible:
		if view != null and view.party_setup_available:
			return false
		return false
	if setup_overlay != null and setup_overlay.visible:
		if creator_step > 0:
			_creation.creator_back()
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
		_creation.reset_creator(true)
	if setup_overlay != null:
		_creation.refresh_setup_options()
		if setup_overlay.visible and not setup_inspection_character_id.is_empty():
			_inspection._render_setup_character_inspection()


func set_presentation_settings(next_settings: PresentationSettings) -> void:
	_creation.set_presentation_settings(next_settings)


func set_standalone_character_creation_available(enabled: bool, reason: String = "") -> void:
	_creation.set_standalone_character_creation_available(enabled, reason)


func begin_standalone_character_creation() -> void:
	_creation.begin_standalone_character_creation()


func finish_standalone_character_creation() -> void:
	_creation.finish_standalone_character_creation()


func refresh_setup_options() -> void:
	_creation.refresh_setup_options()


func reset_creator(return_to_assembly: bool = false) -> void:
	_creation.reset_creator(return_to_assembly)


func render_creator_step() -> void:
	_creation.render_creator_step()


func creator_next() -> void:
	_creation.creator_next()


func creator_back() -> void:
	_creation.creator_back()


func apply_creator_layout(profile_id: StringName) -> void:
	_creation.apply_creator_layout(profile_id)


func ensure_appearance_textures() -> void:
	_creation.ensure_appearance_textures()


func appearance_textures() -> Dictionary:
	return _creation.appearance_textures()


func set_appearance_texture(asset_id: String, texture: Texture2D) -> void:
	_creation.set_appearance_texture(asset_id, texture)


func render_party_assembly() -> void:
	_assembly.render_party_assembly()


func party_setup_option_changed(index: int) -> void:
	_assembly.party_setup_option_changed(index)


func submit_party() -> void:
	_assembly.submit_party()


func close_setup_character_inspection() -> void:
	_inspection.close_setup_character_inspection()
