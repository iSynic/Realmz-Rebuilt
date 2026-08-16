class_name CampaignPartySetupController
extends RefCounted

const CampaignLibraryControllerScript := preload("res://src/presentation/controllers/campaign_library_controller.gd")
const PartySetupCharacterRowScript := preload("res://src/presentation/party_setup_character_row.gd")
const PartySetupPartyListScript := preload("res://src/presentation/party_setup_party_list.gd")
const ClassicUiTheme := preload("res://src/presentation/classic_ui_theme.tres")

signal start_requested(package_path: String, seed: int)
signal cancel_package_requested
signal refresh_requested
signal intent_submitted(intent: PlayerIntent)
signal standalone_character_creation_requested
signal standalone_character_creation_cancelled
signal campaign_selection_requested
signal vault_requested
signal quit_requested

const GOLD := Color("d5b45d")
const MUTED := Color("9aa0a8")
const ERROR := Color("ef7770")
const MAXIMUM_MODAL_Z_INDEX: int = CampaignLibraryControllerScript.MAXIMUM_MODAL_Z_INDEX

var _campaign_library := CampaignLibraryControllerScript.new()
var campaign_overlay: PanelContainer:
	get:
		return _campaign_library.campaign_overlay
var setup_overlay: PanelContainer
var splash_overlay: PanelContainer:
	get:
		return _campaign_library.splash_overlay
var campaign_list: VBoxContainer:
	get:
		return _campaign_library.campaign_list
var campaign_scroll: ScrollContainer:
	get:
		return _campaign_library.campaign_scroll
var package_path: LineEdit:
	get:
		return _campaign_library.package_path
var campaigns: Array[CampaignPackageView]:
	get:
		return _campaign_library.campaigns
	set(value):
		_campaign_library.set_campaigns(value)
var package_operation_status: RefCounted:
	get:
		return _campaign_library.package_operation_status
	set(value):
		_campaign_library.set_package_operation(value)
var campaign_layout_rect: Rect2:
	get:
		return _campaign_library.campaign_layout_rect
	set(value):
		_campaign_library.campaign_layout_rect = value
var creator_scroll: ScrollContainer
var creator: BoxContainer
var creator_page: VBoxContainer
var creator_steps: HBoxContainer
var creator_action_bar: HBoxContainer
var creator_step_labels: Array[Label] = []
var race_class_columns: BoxContainer
var race_list: ItemList
var caste_list: ItemList
var name_edit: LineEdit
var gender_option: OptionButton
var starting_level_option: OptionButton
var portrait_option: OptionButton
var combat_icon_option: OptionButton
var party_list: VBoxContainer
var stored_character_list: VBoxContainer
var party_setup_options: VBoxContainer
var difficulty_option: OptionButton
var monster_set_option: OptionButton
var party_guidance_label: Label
var create_character_button: Button
var setup_message: Label
var review_label: Label
var spell_label: Label
var spell_list: ItemList
var begin_button: Button
var add_character_button: Button
var creator_back_button: Button
var creator_next_button: Button
var creator_cancel_button: Button
var setup_inspection_overlay: PanelContainer
var setup_inspection_body: VBoxContainer

var setup_inspection_character_id: String = ""
var creator_step: int = 0
var setup_mode: StringName = &"assembly"
var draft_name: String = ""
var draft_gender: int = 1
var draft_starting_level: int = 1
var draft_portrait_id: String = ""
var draft_combat_icon_id: String = ""
var awaiting_draft_generation: bool = false
var awaiting_draft_finalization: bool = false
var selected_race_id: String = ""
var selected_caste_id: String = ""
var combat_icon_touched: bool = false

var view: GameView
var vault_revisions: Array[CharacterVaultRevisionView] = []
var media: ClassicMediaCatalog
var settings: PresentationSettings = PresentationSettings.new()
var layout_profile: StringName = UiLayoutProfile.STANDARD
var standalone_character_creation_available: bool = false
var standalone_character_creation_reason: String = "The Classic character library is unavailable."
var standalone_character_creation_active: bool = false
var setup_layout_rect := Rect2(12.0, 36.0, 936.0, 556.0)

var _host: Control
var _appearance_textures: Dictionary = {}


func _init() -> void:
	var owner_ref: WeakRef = weakref(self)
	_campaign_library.start_requested.connect(func(package_path_value: String, seed: int) -> void:
		var owner: CampaignPartySetupController = owner_ref.get_ref() as CampaignPartySetupController
		if owner != null:
			owner.start_requested.emit(package_path_value, seed)
	)
	_campaign_library.cancel_package_requested.connect(func() -> void:
		var owner: CampaignPartySetupController = owner_ref.get_ref() as CampaignPartySetupController
		if owner != null:
			owner.cancel_package_requested.emit()
	)
	_campaign_library.refresh_requested.connect(func() -> void:
		var owner: CampaignPartySetupController = owner_ref.get_ref() as CampaignPartySetupController
		if owner != null:
			owner.refresh_requested.emit()
	)
	_campaign_library.campaign_selection_requested.connect(func() -> void:
		var owner: CampaignPartySetupController = owner_ref.get_ref() as CampaignPartySetupController
		if owner != null:
			owner.campaign_selection_requested.emit()
	)
	_campaign_library.vault_requested.connect(func() -> void:
		var owner: CampaignPartySetupController = owner_ref.get_ref() as CampaignPartySetupController
		if owner != null:
			owner.vault_requested.emit()
	)
	_campaign_library.quit_requested.connect(func() -> void:
		var owner: CampaignPartySetupController = owner_ref.get_ref() as CampaignPartySetupController
		if owner != null:
			owner.quit_requested.emit()
	)


func attach(host: Control) -> void:
	_host = host
	_campaign_library.attach(host)


func build_splash_overlay() -> void:
	_campaign_library.build_splash_overlay()


func build_campaign_overlay() -> void:
	_campaign_library.build_campaign_overlay()


func build_setup_overlay() -> void:
	if setup_overlay != null:
		return
	if campaign_overlay == null:
		build_campaign_overlay()
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
	_build_setup_character_inspection()
	render_creator_step()


func _build_setup_character_inspection() -> void:
	setup_inspection_overlay = PanelContainer.new()
	setup_inspection_overlay.name = "PartySetupCharacterInspection"
	var inspection_surface := ClassicUiTheme.get_stylebox("panel", "ClassicInset").duplicate() as StyleBoxTexture
	setup_inspection_overlay.add_theme_stylebox_override("panel", inspection_surface)
	setup_inspection_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	setup_inspection_overlay.clip_contents = true
	setup_inspection_overlay.z_index = 1
	setup_inspection_overlay.visible = false
	setup_overlay.add_child(setup_inspection_overlay)
	setup_inspection_overlay.position = Vector2.ZERO
	setup_inspection_overlay.size = setup_overlay.size
	setup_inspection_body = VBoxContainer.new()
	setup_inspection_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_inspection_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	setup_inspection_body.add_theme_constant_override("separation", 8)
	setup_inspection_overlay.add_child(setup_inspection_body)


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


func ensure_appearance_textures() -> void:
	_ensure_appearance_textures()


func appearance_textures() -> Dictionary:
	_ensure_appearance_textures()
	return _appearance_textures


func set_appearance_texture(asset_id: String, texture: Texture2D) -> void:
	_appearance_textures[asset_id] = texture


func set_presentation_settings(next_settings: PresentationSettings) -> void:
	if next_settings != null:
		settings = next_settings
	_campaign_library.set_presentation_settings(next_settings)


func set_standalone_character_creation_available(enabled: bool, reason: String = "") -> void:
	standalone_character_creation_available = enabled
	standalone_character_creation_reason = reason if not reason.is_empty() else "The Classic character library is unavailable."
	if setup_overlay != null and setup_overlay.visible and setup_mode == &"assembly":
		refresh_setup_options()


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


func begin_standalone_character_creation() -> void:
	standalone_character_creation_active = true
	setup_mode = &"creator"
	reset_creator(false)
	render_creator_step()


func finish_standalone_character_creation() -> void:
	standalone_character_creation_active = false
	reset_creator(true)


func refresh_setup_options() -> void:
	if view == null or not view.party_setup_available:
		campaign_overlay.tooltip_text = "Select an installed scenario to assemble a party."
		_refresh_party_list()
		_refresh_party_setup_options()
		render_creator_step()
		return
	var summary := view.campaign_summary
	if summary != null:
		var title_parts: Array[String] = [summary.title]
		if not summary.version.is_empty():
			title_parts.append("v%s" % summary.version)
		if not summary.author.is_empty():
			title_parts.append("by %s" % summary.author)
		var restriction_text := summary.restriction_description.strip_edges()
		if restriction_text.is_empty():
			restriction_text = "No authored party restrictions."
		var limits := "Up to %d characters" % summary.maximum_party_size
		if summary.maximum_level > 0:
			limits += " • Maximum level %d" % summary.maximum_level
		campaign_overlay.tooltip_text = "%s\n%s\n%s" % [" • ".join(title_parts), restriction_text, limits]
	else:
		campaign_overlay.tooltip_text = "The selected scenario has no campaign summary metadata."
	_refresh_party_list()
	_refresh_party_setup_options()
	var setup_count := view.party_members.size()
	_apply_availability(begin_button, &"begin_adventure")
	begin_button.text = "Begin adventure (%d/%d)" % [setup_count, _maximum_party_size()]
	render_creator_step()


func render_creator_step() -> void:
	if creator_page == null:
		return
	if setup_mode == &"assembly":
		_render_party_assembly()
		return
	create_character_button.visible = false
	begin_button.visible = false
	party_setup_options.visible = false
	creator_steps.visible = true
	creator_action_bar.visible = true
	setup_message.visible = true
	setup_message.tooltip_text = ""
	setup_message.modulate = MUTED
	setup_message.custom_minimum_size.y = 32.0
	setup_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_message.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	setup_message.text = _creator_step_message()
	_clear(creator_page)
	race_list = null
	caste_list = null
	race_class_columns = null
	name_edit = null
	gender_option = null
	portrait_option = null
	combat_icon_option = null
	review_label = null
	spell_label = null
	spell_list = null
	for index: int in creator_step_labels.size():
		creator_step_labels[index].modulate = GOLD if index == creator_step else Color("e0e2e5") if index < creator_step else MUTED
	match creator_step:
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
	creator_page.add_child(_label("Identity", GOLD, 20))
	_add_label(creator_page, "Name this character and choose the Classic gender value used by creation rules.", MUTED)
	name_edit = LineEdit.new()
	name_edit.name = "CharacterName"
	name_edit.placeholder_text = "Character name"
	name_edit.max_length = 24
	name_edit.text = draft_name
	name_edit.text_changed.connect(func(value: String) -> void: draft_name = value)
	creator_page.add_child(name_edit)
	gender_option = OptionButton.new()
	gender_option.name = "CharacterGender"
	gender_option.add_item("Male", 1)
	gender_option.add_item("Female", 2)
	gender_option.select(0 if draft_gender == 1 else 1)
	gender_option.item_selected.connect(func(_index: int) -> void: draft_gender = gender_option.get_selected_id())
	creator_page.add_child(gender_option)
	starting_level_option = OptionButton.new()
	starting_level_option.name = "StartingLevel"
	var maximum_level := view.campaign_summary.maximum_level if view != null and view.campaign_summary != null else 0
	for level: int in CharacterRules.STARTING_LEVELS:
		if maximum_level > 0 and level > maximum_level:
			continue
		starting_level_option.add_item("Starting level %d" % level, level)
	var selected_index := starting_level_option.get_item_index(draft_starting_level)
	if selected_index < 0:
		selected_index = 0
		draft_starting_level = starting_level_option.get_item_id(0)
	starting_level_option.select(selected_index)
	starting_level_option.item_selected.connect(func(_index: int) -> void: draft_starting_level = starting_level_option.get_selected_id())
	starting_level_option.tooltip_text = "Castle offers fixed starting levels and runs every intervening ordinary level-up roll. Campaign level restrictions remove unavailable choices."
	creator_page.add_child(starting_level_option)
	_focus_first(creator_page)


func _build_creator_race_class() -> void:
	creator_page.add_child(_label("Race & Class", GOLD, 20))
	_add_label(creator_page, "Race is chosen first and filters the classes available on the right.", MUTED)
	var columns := BoxContainer.new()
	race_class_columns = columns
	columns.vertical = layout_profile == UiLayoutProfile.COMPACT
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	var race_column := VBoxContainer.new()
	race_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_column.add_child(_label("Race", GOLD))
	race_list = ItemList.new()
	race_list.name = "RaceList"
	race_list.custom_minimum_size.y = 190.0
	race_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	race_list.item_selected.connect(_race_selected)
	race_column.add_child(race_list)
	columns.add_child(race_column)
	var caste_column := VBoxContainer.new()
	caste_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caste_column.add_child(_label("Class", GOLD))
	caste_list = ItemList.new()
	caste_list.name = "ClassList"
	caste_list.custom_minimum_size.y = 190.0
	caste_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caste_list.item_selected.connect(_caste_selected)
	caste_column.add_child(caste_list)
	columns.add_child(caste_column)
	creator_page.add_child(columns)
	_populate_race_class_options()


func _populate_race_class_options() -> void:
	if view == null or race_list == null or caste_list == null:
		return
	for option: DefinitionOptionView in view.race_options:
		race_list.add_item(option.name)
		race_list.set_item_metadata(race_list.item_count - 1, option.id)
		race_list.set_item_tooltip(race_list.item_count - 1, option.description)
		race_list.set_item_disabled(race_list.item_count - 1, view.campaign_summary != null and view.campaign_summary.banned_races.has(option.id))
	for option: DefinitionOptionView in view.caste_options:
		caste_list.add_item(option.name)
		caste_list.set_item_metadata(caste_list.item_count - 1, option.id)
		caste_list.set_item_tooltip(caste_list.item_count - 1, option.description)
		caste_list.set_item_disabled(caste_list.item_count - 1, view.campaign_summary != null and view.campaign_summary.banned_castes.has(option.id))
	if selected_race_id.is_empty() or not _option_is_enabled(race_list, selected_race_id):
		var first_race := _first_enabled_item(race_list)
		if first_race >= 0:
			selected_race_id = String(race_list.get_item_metadata(first_race))
	_select_item_by_id(race_list, selected_race_id)
	_apply_caste_filter()
	if selected_caste_id.is_empty() or not _option_is_enabled(caste_list, selected_caste_id):
		var first_caste := _first_enabled_item(caste_list)
		if first_caste >= 0:
			selected_caste_id = String(caste_list.get_item_metadata(first_caste))
	_select_item_by_id(caste_list, selected_caste_id)


func _build_creator_appearance() -> void:
	creator_page.add_child(_label("Appearance", GOLD, 20))
	_add_label(creator_page, "Choose the portrait shown on character screens and the icon used in battle. Castle's six race recommendations appear first.", MUTED)
	_ensure_appearance_textures()
	portrait_option = OptionButton.new()
	portrait_option.name = "PortraitOption"
	portrait_option.fit_to_longest_item = false
	var portrait_options := _sorted_appearance_options(view.portrait_options if view != null else [])
	for option: CharacterAppearanceOptionView in portrait_options:
		_add_appearance_option(portrait_option, option)
	_select_appearance_default(portrait_option, draft_portrait_id, true)
	portrait_option.item_selected.connect(_portrait_selected)
	creator_page.add_child(portrait_option)
	combat_icon_option = OptionButton.new()
	combat_icon_option.name = "CombatIconOption"
	combat_icon_option.fit_to_longest_item = false
	var combat_options := _sorted_appearance_options(view.combat_icon_options if view != null else [])
	for option: CharacterAppearanceOptionView in combat_options:
		_add_appearance_option(combat_icon_option, option)
	_select_appearance_default(combat_icon_option, draft_combat_icon_id, false)
	combat_icon_option.item_selected.connect(func(_index: int) -> void: combat_icon_touched = true)
	creator_page.add_child(combat_icon_option)
	if portrait_options.is_empty() or combat_options.is_empty():
		_add_label(creator_page, "This package does not expose the complete Classic appearance catalog. Character generation is unavailable until the package is re-exported.", ERROR)


func _sorted_appearance_options(source: Array[CharacterAppearanceOptionView]) -> Array[CharacterAppearanceOptionView]:
	var result := source.duplicate()
	result.sort_custom(func(left: CharacterAppearanceOptionView, right: CharacterAppearanceOptionView) -> bool:
		var left_recommended := left.is_recommended_for(selected_race_id)
		var right_recommended := right.is_recommended_for(selected_race_id)
		if left_recommended != right_recommended:
			return left_recommended
		return left.classic_resource_id < right.classic_resource_id
	)
	return result


func _add_appearance_option(control: OptionButton, option: CharacterAppearanceOptionView) -> void:
	var prefix := "Recommended • " if option.is_recommended_for(selected_race_id) else ""
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
			if option != null and option.is_recommended_for(selected_race_id):
				target_id = option.id
				break
	if target_id.is_empty() and not portrait:
		var portrait_value := _selected_appearance(portrait_option, true)
		if portrait_value != null:
			var wanted_resource_id := 9000 - 257 + portrait_value.classic_resource_id
			for option: CharacterAppearanceOptionView in view.combat_icon_options:
				if option.classic_resource_id == wanted_resource_id:
					target_id = option.id
					break
	for index: int in control.item_count:
		if String(control.get_item_metadata(index)) == target_id:
			control.select(index)
			return
	control.select(0)


func _portrait_selected(_index: int) -> void:
	if combat_icon_touched or combat_icon_option == null:
		return
	var portrait_value := _selected_appearance(portrait_option, true)
	if portrait_value == null:
		return
	var wanted_resource_id := 9000 - 257 + portrait_value.classic_resource_id
	for index: int in combat_icon_option.item_count:
		var icon := _appearance_option_by_id(String(combat_icon_option.get_item_metadata(index)), false)
		if icon != null and icon.classic_resource_id == wanted_resource_id:
			combat_icon_option.select(index)
			return


func _selected_appearance(control: OptionButton, portrait: bool) -> CharacterAppearanceOptionView:
	if control == null or control.selected < 0:
		return null
	return _appearance_option_by_id(String(control.get_item_metadata(control.selected)), portrait)


func _appearance_option_by_id(option_id: String, portrait: bool) -> CharacterAppearanceOptionView:
	var options := view.portrait_options if portrait else view.combat_icon_options
	for option: CharacterAppearanceOptionView in options:
		if option.id == option_id:
			return option
	return null


func _ensure_appearance_textures() -> void:
	if media == null or not _appearance_textures.is_empty():
		return
	var assets: Array[MediaAsset] = []
	assets.append_array(media.assets_of_kind("portrait"))
	assets.append_array(media.assets_of_kind("combat-icon"))
	var payloads := media.read_bytes_batch(assets)
	for asset: MediaAsset in assets:
		var bytes: PackedByteArray = payloads.get(asset.id, PackedByteArray())
		if bytes.is_empty():
			continue
		var image := Image.new()
		if image.load_png_from_buffer(bytes) == OK:
			_appearance_textures[asset.id] = ImageTexture.create_from_image(image)


func _build_creator_review() -> void:
	creator_page.add_child(_label("Review Classic Roll", GOLD, 20))
	review_label = _add_label(creator_page, "Generating the character through Classic rules…", MUTED)
	review_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_update_creator_review()


func _build_creator_spells() -> void:
	creator_page.add_child(_label("Starting Spells", GOLD, 20))
	spell_label = _add_label(creator_page, "", MUTED)
	spell_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if view == null or view.character_draft == null:
		spell_label.text = "Generate and review the character before choosing spells."
		return
	if view.character_draft.spellcaster_type < 1 or view.character_draft_spell_points_total < 1:
		spell_label.text = "Not applicable. This character has no Classic starting-spell selection points."
		return
	spell_label.text = "%d of %d selection points remain. Unspent points may be accepted, as in Classic." % [view.character_draft_spell_points_remaining, view.character_draft_spell_points_total]
	spell_list = ItemList.new()
	spell_list.name = "StartingSpellList"
	spell_list.select_mode = ItemList.SELECT_MULTI
	spell_list.custom_minimum_size.y = 190.0
	spell_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for option: CharacterSpellOptionView in view.character_draft_spell_options:
		spell_list.add_item("L%d • %s (%d)" % [option.level, option.name, option.selection_cost])
		var index := spell_list.item_count - 1
		spell_list.set_item_metadata(index, option.id)
		spell_list.set_item_tooltip(index, option.description)
		if option.selected:
			spell_list.select(index, false)
		elif option.selection_cost > view.character_draft_spell_points_remaining:
			spell_list.set_item_disabled(index, true)
			spell_list.set_item_tooltip(index, "This spell costs %d points; %d remain." % [option.selection_cost, view.character_draft_spell_points_remaining])
	spell_list.multi_selected.connect(_draft_spell_selection_changed)
	creator_page.add_child(spell_list)
	if view.character_draft_spell_options.is_empty():
		spell_label.text = "This caster has selection points, but the package exposes no matching Classic spell records. Finalization is blocked."


func creator_next() -> void:
	match creator_step:
		0:
			draft_name = name_edit.text.strip_edges()
			draft_gender = gender_option.get_selected_id()
			draft_starting_level = starting_level_option.get_selected_id()
			if draft_name.is_empty():
				setup_message.text = "Enter a character name before continuing."
				return
			creator_step = 1
		1:
			if selected_race_id.is_empty() or selected_caste_id.is_empty():
				setup_message.text = "Choose both a race and a compatible class."
				return
			creator_step = 2
		2:
			if view != null and view.party_members.size() >= _maximum_party_size():
				setup_message.text = "This campaign allows no more than %d characters." % _maximum_party_size()
				return
			var portrait_value := _selected_appearance(portrait_option, true)
			var combat_icon_value := _selected_appearance(combat_icon_option, false)
			if portrait_value == null or combat_icon_value == null:
				setup_message.text = "Choose a package-backed portrait and combat icon before continuing."
				return
			draft_portrait_id = portrait_value.id
			draft_combat_icon_id = combat_icon_value.id
			creator_step = 3
			awaiting_draft_generation = true
			intent_submitted.emit(PlayerIntent.generate_character_draft(_character_creation_spec()))
			return
		3:
			if view == null or view.character_draft == null:
				setup_message.text = "The Classic character roll did not complete. Review the action error before continuing."
				return
			creator_step = 4
		4:
			if view == null or view.character_draft == null:
				return
			if view.character_draft.spellcaster_type > 0 and view.character_draft_spell_points_total > 0 and view.character_draft_spell_options.is_empty():
				setup_message.text = "Starting spells are unavailable in this package, so this caster cannot be finalized safely."
				return
			awaiting_draft_finalization = true
			intent_submitted.emit(PlayerIntent.finalize_character())
			return
	setup_message.text = _creator_step_message()
	render_creator_step()


func creator_back() -> void:
	if creator_step <= 0:
		return
	if creator_step == 3 and view != null and view.character_draft != null:
		creator_step = 2
		intent_submitted.emit(PlayerIntent.cancel_character_draft())
		return
	creator_step -= 1
	setup_message.text = _creator_step_message()
	render_creator_step()


func _cancel_creator() -> void:
	var had_generated_draft := view != null and view.character_draft != null
	reset_creator(true)
	if had_generated_draft:
		intent_submitted.emit(PlayerIntent.cancel_character_draft())
	if standalone_character_creation_active:
		standalone_character_creation_cancelled.emit()
	elif not had_generated_draft:
		render_creator_step()


func reset_creator(return_to_assembly: bool = false) -> void:
	if return_to_assembly:
		setup_mode = &"assembly"
	creator_step = 0
	draft_name = ""
	draft_gender = 1
	draft_starting_level = 1
	draft_portrait_id = ""
	draft_combat_icon_id = ""
	combat_icon_touched = false
	selected_race_id = ""
	selected_caste_id = ""
	awaiting_draft_generation = false
	awaiting_draft_finalization = false
	if setup_message != null:
		setup_message.text = "Choose stored characters or create a new one." if setup_mode == &"assembly" else "Enter a name to begin creating another character."


func _reroll_character() -> void:
	if creator_step != 3 or view == null or view.character_draft == null:
		return
	awaiting_draft_generation = true
	intent_submitted.emit(PlayerIntent.generate_character_draft(_character_creation_spec()))


func _draft_spell_selection_changed(_index: int, _selected: bool) -> void:
	if spell_list == null:
		return
	var selected_ids: Array[String] = []
	for item_index: int in spell_list.item_count:
		if spell_list.is_selected(item_index):
			selected_ids.append(String(spell_list.get_item_metadata(item_index)))
	intent_submitted.emit(PlayerIntent.set_character_draft_spells(selected_ids))


func _character_creation_spec() -> CharacterCreationSpec:
	return CharacterCreationSpec.new(draft_name, selected_race_id, selected_caste_id, draft_gender, draft_portrait_id, draft_combat_icon_id, draft_starting_level)


func _creator_step_message() -> String:
	var final_step := "Choose starting spells, then create the Character File." if standalone_character_creation_active else "Choose starting spells, then add the character to the party."
	return ["Enter the character's identity.", "Choose a race, then a compatible class.", "Choose the character's appearance.", "Review or reroll the generated Classic character.", final_step][creator_step]


func _update_creator_actions() -> void:
	if creator_back_button == null:
		return
	creator_back_button.disabled = creator_step == 0
	add_character_button.visible = creator_step == 3
	_apply_availability(add_character_button, &"generate_character_draft")
	creator_next_button.text = ("Create Character File" if standalone_character_creation_active else "Add to party") if creator_step == 4 else "Choose spells" if creator_step == 3 else "Continue"
	if creator_step == 4:
		_apply_availability(creator_next_button, &"finalize_character")
	else:
		creator_next_button.disabled = false
		creator_next_button.tooltip_text = ""
	creator_cancel_button.disabled = false


func _race_selected(index: int) -> void:
	if index < 0 or race_list.is_item_disabled(index):
		return
	var selected_id := String(race_list.get_item_metadata(index))
	if selected_id != selected_race_id:
		draft_portrait_id = ""
		draft_combat_icon_id = ""
		combat_icon_touched = false
	selected_race_id = selected_id
	_apply_caste_filter()
	setup_message.text = "Race selected. Classes unavailable to this race are disabled on the right."


func _caste_selected(index: int) -> void:
	if index < 0 or caste_list.is_item_disabled(index):
		return
	selected_caste_id = String(caste_list.get_item_metadata(index))
	setup_message.text = "Class selected. Continue to appearance when ready."


func _apply_caste_filter() -> void:
	if view == null or caste_list == null:
		return
	var allowed_castes: Array[String] = []
	for option: DefinitionOptionView in view.race_options:
		if option.id == selected_race_id:
			allowed_castes = option.related_ids.duplicate()
			break
	for index: int in caste_list.item_count:
		var caste_id := String(caste_list.get_item_metadata(index))
		var restricted := view.campaign_summary != null and view.campaign_summary.banned_castes.has(caste_id)
		var compatible := allowed_castes.is_empty() or allowed_castes.has(caste_id)
		caste_list.set_item_disabled(index, restricted or not compatible)
	if not selected_caste_id.is_empty() and not _option_is_enabled(caste_list, selected_caste_id):
		selected_caste_id = ""
		var first_caste := _first_enabled_item(caste_list)
		if first_caste >= 0:
			selected_caste_id = String(caste_list.get_item_metadata(first_caste))
	_select_item_by_id(caste_list, selected_caste_id)


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


func _refresh_party_list() -> void:
	if party_list == null:
		return
	_clear(party_list)
	_ensure_appearance_textures()
	var import_available: bool = view != null and view.availability(&"import_vault_character").enabled and view.party_members.size() < _maximum_party_size()
	var import_reason := "" if import_available else "The party cannot accept another stored character right now."
	party_list.configure_drop_target(import_available, import_reason)
	var party_count := setup_overlay.find_child("PartyCount", true, false) as Label
	if party_count != null:
		party_count.text = "• %d / %d" % [view.party_members.size() if view != null else 0, _maximum_party_size()]
	for slot_index: int in _maximum_party_size():
		if view == null or not view.party_setup_available or slot_index >= view.party_members.size():
			var empty := PanelContainer.new()
			empty.name = "EmptyPartySlot%d" % (slot_index + 1)
			empty.custom_minimum_size.y = PartySetupCharacterRowScript.ROW_HEIGHT
			empty.add_theme_stylebox_override("panel", PartySetupCharacterRowScript.row_style())
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var empty_row := HBoxContainer.new()
			empty_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			empty_row.add_theme_constant_override("separation", 6)
			empty.add_child(empty_row)
			var portrait_space := Control.new()
			portrait_space.custom_minimum_size = Vector2(PartySetupCharacterRowScript.PORTRAIT_SIZE, PartySetupCharacterRowScript.PORTRAIT_SIZE)
			portrait_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
			empty_row.add_child(portrait_space)
			var empty_label := Label.new()
			empty_label.text = "%d. Empty position" % (slot_index + 1)
			empty_label.modulate = MUTED
			empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			empty_row.add_child(empty_label)
			var action_space := Control.new()
			action_space.custom_minimum_size.x = 130.0
			action_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
			empty_row.add_child(action_space)
			party_list.add_child(empty)
			continue
		var character: CharacterView = view.party_members[slot_index]
		var row_panel := PanelContainer.new()
		row_panel.name = "PartySlot_%s" % character.id.validate_node_name()
		row_panel.custom_minimum_size.y = PartySetupCharacterRowScript.ROW_HEIGHT
		row_panel.add_theme_stylebox_override("panel", PartySetupCharacterRowScript.row_style())
		row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row_panel.add_child(row)
		var portrait_view := TextureRect.new()
		portrait_view.name = "Portrait"
		portrait_view.custom_minimum_size = Vector2(PartySetupCharacterRowScript.PORTRAIT_SIZE, PartySetupCharacterRowScript.PORTRAIT_SIZE)
		portrait_view.texture = _appearance_textures.get(character.portrait_id) as Texture2D
		portrait_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait_view.tooltip_text = "%s's portrait" % character.name
		row.add_child(portrait_view)
		var label := Label.new()
		label.text = PartySetupCharacterRowScript._summary_text(character.name, character.level, character.race_name, character.caste_name, character, slot_index + 1)
		label.add_theme_font_size_override("font_size", 10)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.modulate = Color("e0e2e5")
		row.add_child(label)
		var inspect_button := Button.new()
		inspect_button.text = "Inspect"
		inspect_button.tooltip_text = "Open %s's complete character record without changing party state." % character.name
		inspect_button.pressed.connect(_inspect_setup_character.bind(character.id))
		row.add_child(inspect_button)
		var remove_button := Button.new()
		remove_button.text = "Remove"
		_apply_availability(remove_button, &"remove_party_member")
		remove_button.pressed.connect(_remove_setup_character.bind(character.id))
		row.add_child(remove_button)
		party_list.add_child(row_panel)


func _render_party_assembly() -> void:
	var campaign_setup := view != null and view.party_setup_available and not standalone_character_creation_active
	var party_full := campaign_setup and view.party_members.size() >= _maximum_party_size()
	create_character_button.visible = true
	begin_button.visible = true
	create_character_button.disabled = party_full or (not campaign_setup and not standalone_character_creation_available)
	if party_full:
		create_character_button.tooltip_text = "This party already has %d characters." % _maximum_party_size()
	elif campaign_setup:
		create_character_button.tooltip_text = "Create a character using this scenario's standard or custom race and class definitions."
	elif standalone_character_creation_available:
		create_character_button.tooltip_text = "Create a reusable Character File with the built-in Realmz races and classes."
	else:
		create_character_button.tooltip_text = standalone_character_creation_reason
	creator_steps.visible = false
	creator_action_bar.visible = false
	party_setup_options.visible = view != null and view.party_setup_available
	setup_message.visible = false
	_clear(creator_page)
	_ensure_appearance_textures()
	var heading := CenterContainer.new()
	heading.name = "CharacterFilesHeading"
	heading.custom_minimum_size.y = 28.0
	var heading_content := HBoxContainer.new()
	heading_content.add_child(_label("Character Files", GOLD, 20))
	var character_count := _label("• %d available" % _current_vault_revisions().size(), MUTED, 13)
	character_count.name = "CharacterFileCount"
	heading_content.add_child(character_count)
	heading.add_child(heading_content)
	creator_page.add_child(heading)
	var stored_scroll := ScrollContainer.new()
	stored_scroll.name = "StoredCharacterScroll"
	stored_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stored_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stored_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	creator_page.add_child(stored_scroll)
	stored_character_list = VBoxContainer.new()
	stored_character_list.name = "StoredCharacterList"
	stored_character_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stored_character_list.add_theme_constant_override("separation", 2)
	stored_scroll.add_child(stored_character_list)
	var current_revisions := _current_vault_revisions()
	if current_revisions.is_empty():
		var empty := _label("No Character Files yet. Create one here.", MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stored_character_list.add_child(empty)
		return
	var global_available: ActionAvailabilityView = view.availability(&"import_vault_character") if campaign_setup else ActionAvailabilityView.new(&"import_vault_character", false, "Choose a scenario before adding a Character File to a party.")
	for revision: CharacterVaultRevisionView in current_revisions:
		var reason := ""
		if not campaign_setup:
			reason = global_available.reason
		elif not revision.eligible:
			reason = "\n".join(revision.eligibility_reasons)
		elif not global_available.enabled:
			reason = global_available.reason
		elif party_full:
			reason = "This party already has %d characters." % _maximum_party_size()
		var row := PartySetupCharacterRowScript.new()
		row.name = "StoredCharacter_%s" % revision.character_id.validate_node_name()
		var portrait_id := revision.character.portrait_id if revision.character != null else revision.portrait_id
		var portrait := _appearance_textures.get(portrait_id) as Texture2D
		row.configure(revision, campaign_setup and revision.eligible and global_available.enabled and not party_full, reason, portrait)
		row.import_requested.connect(_import_stored_character)
		stored_character_list.add_child(row)


func render_party_assembly() -> void:
	_render_party_assembly()


func _refresh_party_setup_options() -> void:
	if difficulty_option == null:
		return
	if view == null or not view.party_setup_available or view.party_setup == null:
		party_setup_options.visible = false
		begin_button.disabled = true
		begin_button.text = "Begin adventure (0/6)"
		return
	party_setup_options.visible = setup_mode == &"assembly"
	monster_set_option.clear()
	var ordered_monster_sets: Array[int] = []
	for preferred_set_id: int in [0, -1, 1]:
		if view.party_setup.available_monster_sets.has(preferred_set_id):
			ordered_monster_sets.append(preferred_set_id)
	for set_id: int in view.party_setup.available_monster_sets:
		if not ordered_monster_sets.has(set_id):
			ordered_monster_sets.append(set_id)
	for set_id: int in ordered_monster_sets:
		monster_set_option.add_item(PartySetupView.monster_set_name(set_id))
		monster_set_option.set_item_metadata(monster_set_option.item_count - 1, set_id)
	_select_option_metadata(monster_set_option, view.party_setup.monster_set)
	_select_option_metadata(difficulty_option, view.party_setup.difficulty)
	var summary := view.campaign_summary
	var maximum := "None" if summary == null or summary.maximum_party_levels <= 0 else str(summary.maximum_party_levels)
	var recommended := "—" if summary == null or not summary.guidance_authored or summary.recommended_party_levels <= 0 else str(summary.recommended_party_levels)
	var gained := "—" if view.party_setup.experience_percent <= 0 else "%d%%" % view.party_setup.experience_percent
	party_guidance_label.text = "Maximum %s  •  Recommended %s  •  Current %d\nExperience gained at %s" % [maximum, recommended, view.party_setup.current_party_levels, gained]


func _party_setup_option_changed(_index: int) -> void:
	if view == null or view.party_setup == null:
		return
	var difficulty := int(difficulty_option.get_item_metadata(difficulty_option.selected))
	var monster_set := int(monster_set_option.get_item_metadata(monster_set_option.selected))
	intent_submitted.emit(PlayerIntent.set_party_setup_options(difficulty, monster_set))


func party_setup_option_changed(index: int) -> void:
	_party_setup_option_changed(index)


func apply_creator_layout(profile_id: StringName) -> void:
	_apply_creator_layout(profile_id)


static func _select_option_metadata(option: OptionButton, value: int) -> void:
	for index: int in option.item_count:
		if int(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func _current_vault_revisions() -> Array[CharacterVaultRevisionView]:
	var current_revisions: Array[CharacterVaultRevisionView] = []
	for revision: CharacterVaultRevisionView in vault_revisions:
		if revision.is_current and not revision.archived:
			current_revisions.append(revision)
	current_revisions.sort_custom(func(left: CharacterVaultRevisionView, right: CharacterVaultRevisionView) -> bool: return left.name.naturalnocasecmp_to(right.name) < 0)
	return current_revisions


func _start_creator() -> void:
	if view == null or not view.party_setup_available:
		if standalone_character_creation_available:
			standalone_character_creation_requested.emit()
			return
		setup_message.text = standalone_character_creation_reason
		return
	setup_mode = &"creator"
	reset_creator(false)
	render_creator_step()


func _import_stored_character(character_id: String, revision_hash: String) -> void:
	intent_submitted.emit(PlayerIntent.import_vault_character(character_id, revision_hash))


func _inspect_setup_character(character_id: String) -> void:
	setup_inspection_character_id = character_id
	_render_setup_character_inspection()


func _render_setup_character_inspection() -> void:
	if setup_inspection_overlay == null or setup_inspection_body == null or view == null:
		return
	var inspected: CharacterView = null
	for character: CharacterView in view.party_members:
		if character.id == setup_inspection_character_id:
			inspected = character
			break
	if inspected == null:
		close_setup_character_inspection()
		return
	_clear(setup_inspection_body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var back := Button.new()
	back.name = "BackToPartySetup"
	back.text = "Back to party setup"
	back.pressed.connect(close_setup_character_inspection)
	header.add_child(back)
	var heading := _label("Inspect %s" % inspected.name, GOLD, 20)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	setup_inspection_body.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.name = "CharacterInspectionScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	setup_inspection_body.add_child(scroll)
	_ensure_appearance_textures()
	var sheet := ClassicCharacterSheet.new()
	sheet.name = "PartySetupCharacterSheet"
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.present(view.party_members, setup_inspection_character_id, _appearance_textures, settings.text_scale, &"overview", view.portrait_options, view.combat_icon_options, ActionAvailabilityView.new(&"change_character_appearance", false, "Appearance changes are available after beginning the adventure."))
	sheet.character_selected.connect(func(character_id: String) -> void: setup_inspection_character_id = character_id)
	scroll.add_child(sheet)
	setup_inspection_overlay.visible = true
	_focus_first(setup_inspection_overlay)


func close_setup_character_inspection() -> void:
	setup_inspection_character_id = ""
	if setup_inspection_overlay != null:
		setup_inspection_overlay.visible = false
	_focus_first(setup_overlay)


func _remove_setup_character(character_id: String) -> void:
	intent_submitted.emit(PlayerIntent.remove_party_member(character_id))


func submit_party() -> void:
	if view == null or view.party_members.is_empty():
		return
	intent_submitted.emit(PlayerIntent.begin_adventure())


func _maximum_party_size() -> int:
	if view == null or view.campaign_summary == null:
		return 6
	return clampi(view.campaign_summary.maximum_party_size, 1, 6)


func _update_creator_review() -> void:
	if review_label == null:
		return
	if view == null or view.character_draft == null:
		review_label.text = "The Classic character roll has not completed."
		return
	var character := view.character_draft
	review_label.text = "%s • Level %d %s %s\nHP %d/%d • SP %d/%d • Age %d (%s)\nBrawn %d • Knowledge %d • Judgment %d • Agility %d • Vitality %d • Luck %d\nArmor %d • To Hit %d • Dodge %d • Missile %d • Two-Hand %d • Hand-to-Hand %d • Damage %+d\nMovement %d • Magic Resistance %d%%" % [character.name, character.level, character.race_name, character.caste_name, character.current_health, character.maximum_health, character.spell_points, character.maximum_spell_points, character.age_years, character.age_group_name, character.brawn, character.knowledge, character.judgment, character.agility, character.vitality, character.luck, character.armor, character.to_hit, character.dodge, character.missile, character.two_hand, character.hand_to_hand, character.damage_bonus, character.maximum_movement, character.magic_resistance]


func _apply_creator_layout(profile_id: StringName) -> void:
	if creator != null:
		creator.vertical = profile_id == UiLayoutProfile.COMPACT
	if race_class_columns != null:
		race_class_columns.vertical = profile_id == UiLayoutProfile.COMPACT


func _apply_availability(button: BaseButton, action_id: StringName) -> void:
	var availability := view.availability(action_id) if view != null else ActionAvailabilityView.new(action_id, false, "No active session.")
	button.disabled = not availability.enabled
	button.tooltip_text = availability.reason if not availability.enabled else ""


func _focus_first(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Control:
			var control := child as Control
			if control.is_inside_tree() and control.visible and control.focus_mode != Control.FOCUS_NONE and not (control is BaseButton and (control as BaseButton).disabled):
				control.grab_focus()
				return
		_focus_first(child)
		var viewport := _host.get_viewport() if _host != null else null
		var focus_owner := viewport.gui_get_focus_owner() if viewport != null else null
		if focus_owner != null and parent.is_ancestor_of(focus_owner):
			return


func _label(text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * settings.text_scale)))
	return label


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := _label(text, color, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _clear(parent: Node) -> void:
	if parent == null:
		return
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
