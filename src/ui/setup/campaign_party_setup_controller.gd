## Binds detached campaign party setup data to scene-owned controls.

class_name CampaignPartySetupController
extends "res://src/ui/setup/party_setup_controller_component.gd"

const PARTY_SETUP_WORKSPACE_PATH := "res://src/ui/setup/party_setup_workspace.tscn"

var intent_submitted: Signal:
	get: return _state.intent_submitted
var standalone_character_creation_requested: Signal:
	get: return _state.standalone_character_creation_requested
var standalone_character_creation_cancelled: Signal:
	get: return _state.standalone_character_creation_cancelled
var load_saved_adventure_requested: Signal:
	get: return _state.load_saved_adventure_requested

var campaign_library: CampaignLibraryController:
	get: return _campaign_library
var character_creation: PartySetupCharacterCreationController:
	get: return _creation

var _inspection: PartySetupInspectionController
var _assembly: PartySetupAssemblyController
var _creation: PartySetupCharacterCreationController


func _init() -> void:
	var state := CampaignPartySetupState.new()
	super(state)
	_inspection = PartySetupInspectionController.new(state)
	_assembly = PartySetupAssemblyController.new(state, _inspection)
	_creation = PartySetupCharacterCreationController.new(state, _assembly)

func build_setup_overlay() -> void:
	if setup_overlay != null:
		return
	if campaign_overlay == null:
		_campaign_library.build_campaign_overlay()
	var workspace_scene := load(PARTY_SETUP_WORKSPACE_PATH) as PackedScene
	assert(workspace_scene != null, "Party setup workspace scene is unavailable.")
	var workspace := workspace_scene.instantiate() as PartySetupWorkspace
	workspace.set_anchors_preset(Control.PRESET_CENTER)
	workspace.z_index = 25
	_host.add_child(workspace)
	bind_setup_workspace(workspace)


func bind_setup_workspace(workspace: PartySetupWorkspace) -> void:
	assert(workspace != null, "Party setup workspace is unavailable.")
	assert(setup_overlay == null or setup_overlay == workspace, "A different party setup workspace is already bound.")
	_bind_setup_workspace_controls(workspace)
	_inspection.build_setup_character_inspection()
	_creation.render_creator_step()


func _bind_setup_workspace_controls(workspace: PartySetupWorkspace) -> void:
	setup_overlay = workspace
	character_sheet_scene = setup_overlay.get("character_sheet_scene") as PackedScene
	identity_step_scene_path = setup_overlay.get("identity_step_scene_path") as String
	race_caste_step_scene_path = setup_overlay.get("race_caste_step_scene_path") as String
	appearance_step_scene = setup_overlay.get("appearance_step_scene") as PackedScene
	review_step_scene_path = setup_overlay.get("review_step_scene_path") as String
	spells_step_scene_path = setup_overlay.get("spells_step_scene_path") as String
	setup_body = setup_overlay.get_node("ScenarioPartyWorkspace") as HBoxContainer
	_host.remove_child(campaign_overlay)
	setup_body.add_child(campaign_overlay)
	setup_body.move_child(campaign_overlay, 0)
	campaign_overlay.position = Vector2.ZERO
	character_pane = setup_overlay.get_node("ScenarioPartyWorkspace/CharacterFilesPane") as PanelContainer
	party_pane = setup_overlay.get_node("ScenarioPartyWorkspace/CurrentPartyPane") as PanelContainer
	creator_steps = setup_overlay.get_node("%CreatorSteps") as HBoxContainer
	creator_step_labels.clear()
	for child: Node in creator_steps.get_children():
		if child is Label:
			creator_step_labels.append(child as Label)
	creator_scroll = setup_overlay.get_node("%CreatorScroll") as ScrollContainer
	creator_scroll.resized.connect(_assembly.refresh_stored_character_capacity)
	creator = setup_overlay.get_node("%Creator") as BoxContainer
	creator_page = setup_overlay.get_node("%CreatorPage") as VBoxContainer
	_clear(creator_page)
	party_list = setup_overlay.get_node("%PartySlots") as VBoxContainer
	party_list.set_script(PartySetupPartyList)
	party_list.import_requested.connect(_assembly.import_stored_character)
	setup_message = setup_overlay.get_node("%SetupMessage") as Label
	party_setup_options = setup_overlay.get_node("%PartySetupOptions") as VBoxContainer
	party_guidance_label = setup_overlay.get_node("%PartyLevelGuidance") as Label
	monster_set_option = setup_overlay.get_node("%MonsterSetOption") as OptionButton
	monster_set_option.item_selected.connect(_assembly.party_setup_option_changed)
	difficulty_option = setup_overlay.get_node("%DifficultyOption") as OptionButton
	for value: int in range(-2, 3):
		difficulty_option.add_item(PartySetupView.difficulty_name(value))
		difficulty_option.set_item_metadata(difficulty_option.item_count - 1, value)
	difficulty_option.item_selected.connect(_assembly.party_setup_option_changed)
	creator_action_bar = setup_overlay.get_node("%CreatorActionBar") as HBoxContainer
	creator_cancel_button = setup_overlay.get_node("%CreatorCancel") as Button
	creator_cancel_button.pressed.connect(_creation.cancel_creator)
	creator_back_button = setup_overlay.get_node("%CreatorBack") as Button
	creator_back_button.pressed.connect(_creation.creator_back)
	add_character_button = setup_overlay.get_node("%RerollCharacter") as Button
	add_character_button.pressed.connect(_creation.reroll_character)
	creator_next_button = setup_overlay.get_node("%CreatorNext") as Button
	creator_next_button.pressed.connect(_creation.creator_next)
	create_character_button = setup_overlay.get_node("%CreateCharacter") as Button
	create_character_button.pressed.connect(_creation.start_creator)
	var load_adventure := setup_overlay.get_node("%LoadSavedAdventure") as Button
	load_adventure.pressed.connect(func() -> void: _state.load_saved_adventure_requested.emit())
	begin_button = setup_overlay.get_node("%BeginAdventure") as Button
	begin_button.pressed.connect(_assembly.submit_party)
	_state.apply_setup_mode_layout()

func set_view(next_view: GameView) -> void:
	view = next_view
	if setup_overlay != null and setup_overlay.visible:
		_creation.refresh_setup_options()

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
	_creation.apply_creator_layout(profile.id)
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

func show_splash() -> void:
	_campaign_library.show_splash()
	if setup_overlay != null:
		setup_overlay.visible = false

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
			_inspection.render_setup_character_inspection()
