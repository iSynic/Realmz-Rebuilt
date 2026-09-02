class_name PartySetupControllerComponent
extends RefCounted

const PartySetupCharacterRowScript := preload("res://src/presentation/party_setup_character_row.gd")
const PartySetupPartyListScript := preload("res://src/presentation/party_setup_party_list.gd")
const CampaignPartySetupStateScript := preload("res://src/presentation/controllers/campaign_party_setup_state.gd")

const GOLD := CampaignPartySetupStateScript.GOLD
const MUTED := CampaignPartySetupStateScript.MUTED
const ERROR := CampaignPartySetupStateScript.ERROR
const MAXIMUM_MODAL_Z_INDEX := CampaignPartySetupStateScript.MAXIMUM_MODAL_Z_INDEX

var _state: RefCounted

var _campaign_library:
	get: return _state._campaign_library
var _host: Control:
	get: return _state._host
var _appearance_textures: Dictionary:
	get: return _state._appearance_textures
var campaign_overlay: PanelContainer:
	get: return _state.campaign_overlay
var setup_overlay: PanelContainer:
	get: return _state.setup_overlay
	set(value): _state.setup_overlay = value
var splash_overlay: PanelContainer:
	get: return _state.splash_overlay
var campaign_list: VBoxContainer:
	get: return _state.campaign_list
var campaign_scroll: ScrollContainer:
	get: return _state.campaign_scroll
var campaigns: Array[CampaignPackageView]:
	get: return _state.campaigns
	set(value): _state.campaigns = value
var package_operation_status: RefCounted:
	get: return _state.package_operation_status
	set(value): _state.package_operation_status = value
var campaign_layout_rect: Rect2:
	get: return _state.campaign_layout_rect
	set(value): _state.campaign_layout_rect = value
var setup_body: HBoxContainer:
	get: return _state.setup_body
	set(value): _state.setup_body = value
var character_pane: PanelContainer:
	get: return _state.character_pane
	set(value): _state.character_pane = value
var party_pane: PanelContainer:
	get: return _state.party_pane
	set(value): _state.party_pane = value
var creator_scroll: ScrollContainer:
	get: return _state.creator_scroll
	set(value): _state.creator_scroll = value
var creator: BoxContainer:
	get: return _state.creator
	set(value): _state.creator = value
var creator_page: VBoxContainer:
	get: return _state.creator_page
	set(value): _state.creator_page = value
var creator_steps: HBoxContainer:
	get: return _state.creator_steps
	set(value): _state.creator_steps = value
var creator_action_bar: HBoxContainer:
	get: return _state.creator_action_bar
	set(value): _state.creator_action_bar = value
var creator_step_labels: Array[Label]:
	get: return _state.creator_step_labels
var race_caste_columns: BoxContainer:
	get: return _state.race_caste_columns
	set(value): _state.race_caste_columns = value
var race_list: ClassicDefinitionToggleList:
	get: return _state.race_list
	set(value): _state.race_list = value
var caste_list: ClassicDefinitionToggleList:
	get: return _state.caste_list
	set(value): _state.caste_list = value
var name_edit: LineEdit:
	get: return _state.name_edit
	set(value): _state.name_edit = value
var gender_option: OptionButton:
	get: return _state.gender_option
	set(value): _state.gender_option = value
var starting_level_option: OptionButton:
	get: return _state.starting_level_option
	set(value): _state.starting_level_option = value
var portrait_option: OptionButton:
	get: return _state.portrait_option
	set(value): _state.portrait_option = value
var combat_icon_option: OptionButton:
	get: return _state.combat_icon_option
	set(value): _state.combat_icon_option = value
var portrait_preview: TextureRect:
	get: return _state.portrait_preview
	set(value): _state.portrait_preview = value
var combat_icon_preview: TextureRect:
	get: return _state.combat_icon_preview
	set(value): _state.combat_icon_preview = value
var party_list: VBoxContainer:
	get: return _state.party_list
	set(value): _state.party_list = value
var stored_character_list: VBoxContainer:
	get: return _state.stored_character_list
	set(value): _state.stored_character_list = value
var party_setup_options: VBoxContainer:
	get: return _state.party_setup_options
	set(value): _state.party_setup_options = value
var difficulty_option: OptionButton:
	get: return _state.difficulty_option
	set(value): _state.difficulty_option = value
var monster_set_option: OptionButton:
	get: return _state.monster_set_option
	set(value): _state.monster_set_option = value
var party_guidance_label: Label:
	get: return _state.party_guidance_label
	set(value): _state.party_guidance_label = value
var create_character_button: Button:
	get: return _state.create_character_button
	set(value): _state.create_character_button = value
var setup_message: Label:
	get: return _state.setup_message
	set(value): _state.setup_message = value
var review_label: Label:
	get: return _state.review_label
	set(value): _state.review_label = value
var spell_label: Label:
	get: return _state.spell_label
	set(value): _state.spell_label = value
var spell_list: VBoxContainer:
	get: return _state.spell_list
	set(value): _state.spell_list = value
var begin_button: Button:
	get: return _state.begin_button
	set(value): _state.begin_button = value
var add_character_button: Button:
	get: return _state.add_character_button
	set(value): _state.add_character_button = value
var creator_back_button: Button:
	get: return _state.creator_back_button
	set(value): _state.creator_back_button = value
var creator_next_button: Button:
	get: return _state.creator_next_button
	set(value): _state.creator_next_button = value
var creator_cancel_button: Button:
	get: return _state.creator_cancel_button
	set(value): _state.creator_cancel_button = value
var setup_inspection_overlay: PanelContainer:
	get: return _state.setup_inspection_overlay
var setup_inspection_character_id: String:
	get: return _state.setup_inspection_character_id
	set(value): _state.setup_inspection_character_id = value
var creator_step: int:
	get: return _state.creator_step
	set(value): _state.creator_step = value
var setup_mode: StringName:
	get: return _state.setup_mode
	set(value): _state.setup_mode = value
var draft_name: String:
	get: return _state.draft_name
	set(value): _state.draft_name = value
var draft_gender: int:
	get: return _state.draft_gender
	set(value): _state.draft_gender = value
var draft_starting_level: int:
	get: return _state.draft_starting_level
	set(value): _state.draft_starting_level = value
var draft_portrait_id: String:
	get: return _state.draft_portrait_id
	set(value): _state.draft_portrait_id = value
var draft_combat_icon_id: String:
	get: return _state.draft_combat_icon_id
	set(value): _state.draft_combat_icon_id = value
var awaiting_draft_generation: bool:
	get: return _state.awaiting_draft_generation
	set(value): _state.awaiting_draft_generation = value
var awaiting_draft_finalization: bool:
	get: return _state.awaiting_draft_finalization
	set(value): _state.awaiting_draft_finalization = value
var selected_race_id: String:
	get: return _state.selected_race_id
	set(value): _state.selected_race_id = value
var selected_caste_id: String:
	get: return _state.selected_caste_id
	set(value): _state.selected_caste_id = value
var combat_icon_touched: bool:
	get: return _state.combat_icon_touched
	set(value): _state.combat_icon_touched = value
var view: GameView:
	get: return _state.view
	set(value): _state.view = value
var vault_revisions: Array[CharacterVaultRevisionView]:
	get: return _state.vault_revisions
	set(value): _state.vault_revisions = value
var media: ClassicMediaCatalog:
	get: return _state.media
	set(value): _state.media = value
var settings: PresentationSettings:
	get: return _state.settings
	set(value): _state.settings = value
var layout_profile: StringName:
	get: return _state.layout_profile
	set(value): _state.layout_profile = value
var standalone_character_creation_available: bool:
	get: return _state.standalone_character_creation_available
	set(value): _state.standalone_character_creation_available = value
var standalone_character_creation_reason: String:
	get: return _state.standalone_character_creation_reason
	set(value): _state.standalone_character_creation_reason = value
var standalone_character_creation_active: bool:
	get: return _state.standalone_character_creation_active
	set(value): _state.standalone_character_creation_active = value
var setup_layout_rect: Rect2:
	get: return _state.setup_layout_rect
	set(value): _state.setup_layout_rect = value


func _init(state: RefCounted) -> void:
	_state = state


func attach(host: Control) -> void:
	_state.attach(host)


func _ensure_appearance_textures(requested_asset_ids: Array[String] = []) -> void:
	_state._ensure_appearance_textures(requested_asset_ids)


func _apply_availability(button: BaseButton, action_id: StringName) -> void:
	_state._apply_availability(button, action_id)


func _select_option_metadata(option: OptionButton, value: int) -> void:
	_state._select_option_metadata(option, value)


func _focus_first(parent: Node) -> void:
	_state._focus_first(parent)


func focus_first(parent: Node) -> void:
	_state._focus_first(parent)


func _label(text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	return _state._label(text, color, size)


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	return _state._add_label(parent, text, color, size)


func _clear(parent: Node) -> void:
	_state._clear(parent)


func _clear_creator_page() -> void:
	stored_character_list = null
	race_list = null
	caste_list = null
	race_caste_columns = null
	name_edit = null
	gender_option = null
	starting_level_option = null
	portrait_option = null
	combat_icon_option = null
	portrait_preview = null
	combat_icon_preview = null
	review_label = null
	spell_label = null
	spell_list = null
	_clear(creator_page)
