## Binds detached campaign party setup state data to scene-owned controls.

class_name CampaignPartySetupState
extends RefCounted


signal intent_submitted(intent: PlayerIntent)
signal load_saved_adventure_requested
signal standalone_character_creation_requested
signal standalone_character_creation_cancelled

const GOLD := Color("d5b45d")
const MUTED := Color("9aa0a8")
const ERROR := Color("ef7770")
const MAXIMUM_MODAL_Z_INDEX: int = CampaignLibraryController.MAXIMUM_MODAL_Z_INDEX

var campaign_library := CampaignLibraryController.new()
var campaign_overlay: PanelContainer:
	get:
		return campaign_library.campaign_overlay
var setup_overlay: PanelContainer
var splash_overlay: PanelContainer:
	get:
		return campaign_library.splash_overlay
var campaign_list: VBoxContainer:
	get:
		return campaign_library.campaign_list
var campaign_scroll: ScrollContainer:
	get:
		return campaign_library.campaign_scroll
var campaigns: Array[CampaignPackageView]:
	get:
		return campaign_library.campaigns
	set(value):
		campaign_library.set_campaigns(value)
var package_operation_status: RefCounted:
	get:
		return campaign_library.package_operation_status
	set(value):
		campaign_library.set_package_operation(value)
var campaign_layout_rect: Rect2:
	get:
		return campaign_library.campaign_layout_rect
	set(value):
		campaign_library.campaign_layout_rect = value
var setup_body: HBoxContainer
var character_pane: PanelContainer
var party_pane: PanelContainer
var creator_scroll: ScrollContainer
var creator: BoxContainer
var creator_page: VBoxContainer
var creator_steps: HBoxContainer
var creator_action_bar: HBoxContainer
var creator_step_labels: Array[Label] = []
var race_caste_columns: BoxContainer
var race_list: ClassicDefinitionToggleList
var caste_list: ClassicDefinitionToggleList
var name_edit: LineEdit
var gender_option: OptionButton
var starting_level_option: OptionButton
var portrait_option: OptionButton
var combat_icon_option: OptionButton
var portrait_preview: TextureRect
var combat_icon_preview: TextureRect
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
var spell_list: VBoxContainer
var begin_button: Button
var add_character_button: Button
var creator_back_button: Button
var creator_next_button: Button
var creator_cancel_button: Button
var setup_inspection_overlay: PanelContainer
var setup_inspection_body: VBoxContainer
var character_sheet_scene: PackedScene
var identity_step_scene_path: String
var race_caste_step_scene_path: String
var appearance_step_scene: PackedScene
var review_step_scene_path: String
var spells_step_scene_path: String

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
var layout_profile: StringName = UiLayoutProfile.WIDE
var standalone_character_creation_available: bool = false
var standalone_character_creation_reason: String = "The Classic character library is unavailable."
var standalone_character_creation_active: bool = false
var setup_layout_rect := Rect2(12.0, 36.0, 936.0, 556.0)

var host: Control
var appearance_textures: Dictionary = {}

func apply_setup_mode_layout() -> void:
	if setup_body == null or character_pane == null or party_pane == null:
		return
	var creator_active := setup_mode == &"creator"
	var compact := layout_profile == UiLayoutProfile.COMPACT
	if campaign_overlay != null:
		var setup_visible := setup_overlay != null and setup_overlay.visible
		var splash_visible := splash_overlay != null and splash_overlay.visible
		campaign_overlay.visible = setup_visible and not splash_visible and not creator_active
		campaign_overlay.custom_minimum_size.x = 190.0 if compact else 210.0
	if creator_active:
		party_pane.visible = false
		character_pane.custom_minimum_size.x = 0.0
		character_pane.size_flags_stretch_ratio = 1.0
		return
	party_pane.visible = true
	character_pane.custom_minimum_size.x = 500.0 if creator_active else 240.0 if compact else 286.0
	party_pane.custom_minimum_size.x = 270.0 if creator_active else 236.0 if compact else 286.0
	character_pane.size_flags_stretch_ratio = 1.85 if creator_active else 1.15
	party_pane.size_flags_stretch_ratio = 1.0 if creator_active else 1.15

func attach(host: Control) -> void:
	self.host = host
	campaign_library.attach(host)

func ensure_appearance_textures(requested_asset_ids: Array[String] = []) -> void:
	if media == null:
		return
	var asset_ids: Array[String] = requested_asset_ids.duplicate()
	if view != null:
		for character: CharacterView in view.party_members:
			if not character.portrait_id.is_empty() and not asset_ids.has(character.portrait_id):
				asset_ids.append(character.portrait_id)
			if not character.combat_icon_id.is_empty() and not asset_ids.has(character.combat_icon_id):
				asset_ids.append(character.combat_icon_id)
	for asset_id: String in asset_ids:
		if asset_id.is_empty() or appearance_textures.has(asset_id):
			continue
		var asset := media.asset_by_id(asset_id)
		if asset == null:
			continue
		if appearance_textures.has(asset.id):
			continue
		var texture := media.image_texture(asset)
		if texture != null:
			appearance_textures[asset.id] = texture

func apply_availability(button: BaseButton, action_id: StringName) -> void:
	var availability := view.availability(action_id) if view != null else ActionAvailabilityView.new(action_id, false, "No active session.")
	button.disabled = not availability.enabled
	button.tooltip_text = availability.reason if not availability.enabled else ""

static func select_option_metadata(option: OptionButton, value: int) -> void:
	for index: int in option.item_count:
		if int(option.get_item_metadata(index)) == value:
			option.select(index)
			return

func focus_first(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Control:
			var control := child as Control
			if control.is_inside_tree() and control.visible and control.focus_mode != Control.FOCUS_NONE and not (control is BaseButton and (control as BaseButton).disabled):
				control.grab_focus()
				return
		focus_first(child)
		var viewport := host.get_viewport() if host != null else null
		var focus_owner := viewport.gui_get_focus_owner() if viewport != null else null
		if focus_owner != null and parent.is_ancestor_of(focus_owner):
			return

func clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
