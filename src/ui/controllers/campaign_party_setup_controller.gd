## Binds detached campaign party setup data to scene-owned controls.

class_name CampaignPartySetupController
extends "res://src/ui/controllers/party_setup_controller_component.gd"

const SetupStateScript := preload("res://src/ui/controllers/campaign_party_setup_state.gd")
const PartySetupInspectionControllerScript := preload("res://src/ui/controllers/party_setup_inspection_controller.gd")
const PartySetupAssemblyControllerScript := preload("res://src/ui/controllers/party_setup_assembly_controller.gd")
const PartySetupCharacterCreationControllerScript := preload("res://src/ui/controllers/party_setup_character_creation_controller.gd")
const PARTY_SETUP_WORKSPACE_PATH := "res://src/ui/setup/party_setup_workspace.tscn"

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
	_bind_setup_workspace()
	_inspection._build_setup_character_inspection()
	_creation.render_creator_step()


func _bind_setup_workspace() -> void:
	var workspace_scene := load(PARTY_SETUP_WORKSPACE_PATH) as PackedScene
	assert(workspace_scene != null, "Party setup workspace scene is unavailable.")
	setup_overlay = workspace_scene.instantiate() as PanelContainer
	character_sheet_scene = setup_overlay.get("character_sheet_scene") as PackedScene
	setup_overlay.set_anchors_preset(Control.PRESET_CENTER)
	setup_overlay.z_index = 25
	_host.add_child(setup_overlay)
	setup_body = setup_overlay.get_node("ScenarioPartyWorkspace") as HBoxContainer
	_host.remove_child(campaign_overlay)
	setup_body.add_child(campaign_overlay)
	setup_body.move_child(campaign_overlay, 0)
	character_pane = setup_overlay.get_node("ScenarioPartyWorkspace/CharacterFilesPane") as PanelContainer
	party_pane = setup_overlay.get_node("ScenarioPartyWorkspace/CurrentPartyPane") as PanelContainer
	creator_steps = setup_overlay.get_node("%CreatorSteps") as HBoxContainer
	creator_step_labels.clear()
	for child: Node in creator_steps.get_children():
		if child is Label:
			creator_step_labels.append(child as Label)
	creator_scroll = setup_overlay.get_node("%CreatorScroll") as ScrollContainer
	creator = setup_overlay.get_node("%Creator") as BoxContainer
	creator_page = setup_overlay.get_node("%CreatorPage") as VBoxContainer
	_clear(creator_page)
	party_list = setup_overlay.get_node("%PartySlots") as VBoxContainer
	party_list.set_script(PartySetupPartyListScript)
	party_list.import_requested.connect(_assembly._import_stored_character)
	setup_message = setup_overlay.get_node("%SetupMessage") as Label
	party_setup_options = setup_overlay.get_node("%PartySetupOptions") as VBoxContainer
	party_guidance_label = setup_overlay.get_node("%PartyLevelGuidance") as Label
	monster_set_option = setup_overlay.get_node("%MonsterSetOption") as OptionButton
	monster_set_option.item_selected.connect(_assembly._party_setup_option_changed)
	difficulty_option = setup_overlay.get_node("%DifficultyOption") as OptionButton
	for value: int in range(-2, 3):
		difficulty_option.add_item(PartySetupView.difficulty_name(value))
		difficulty_option.set_item_metadata(difficulty_option.item_count - 1, value)
	difficulty_option.item_selected.connect(_assembly._party_setup_option_changed)
	creator_action_bar = setup_overlay.get_node("%CreatorActionBar") as HBoxContainer
	creator_cancel_button = setup_overlay.get_node("%CreatorCancel") as Button
	creator_cancel_button.pressed.connect(_creation._cancel_creator)
	creator_back_button = setup_overlay.get_node("%CreatorBack") as Button
	creator_back_button.pressed.connect(_creation.creator_back)
	add_character_button = setup_overlay.get_node("%RerollCharacter") as Button
	add_character_button.pressed.connect(_creation._reroll_character)
	creator_next_button = setup_overlay.get_node("%CreatorNext") as Button
	creator_next_button.pressed.connect(_creation.creator_next)
	create_character_button = setup_overlay.get_node("%CreateCharacter") as Button
	create_character_button.pressed.connect(_creation._start_creator)
	var load_adventure := setup_overlay.get_node("%LoadSavedAdventure") as Button
	load_adventure.pressed.connect(func() -> void: _state.load_saved_adventure_requested.emit())
	begin_button = setup_overlay.get_node("%BeginAdventure") as Button
	begin_button.pressed.connect(_assembly.submit_party)
	_state.apply_setup_mode_layout()

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
