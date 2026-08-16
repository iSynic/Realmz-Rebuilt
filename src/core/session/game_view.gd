class_name GameView
extends RefCounted

var revision: int
var session_started: bool
var pending_interaction: InteractionRequest
var party_map_id: String
var party_coordinate: Vector2i
var realmz_day: int
var realmz_hour: int
var realmz_minute: int
var map_view: MapView
var party_members: Array[CharacterView] = []
var party_fatigue: int = 0
var pooled_gold: int = 0
var combat_view: CombatView
var campaign_id: String = ""
var rules_version: String = ""
var party_setup_available: bool = false
var character_draft: CharacterView
var character_draft_spell_options: Array[CharacterSpellOptionView] = []
var character_draft_spell_points_total: int = 0
var character_draft_spell_points_remaining: int = 0
var race_options: Array[DefinitionOptionView] = []
var caste_options: Array[DefinitionOptionView] = []
var portrait_options: Array[CharacterAppearanceOptionView] = []
var combat_icon_options: Array[CharacterAppearanceOptionView] = []
var campaign_summary: CampaignSummaryView
var party_setup: PartySetupView
var party_summary: PartySummaryView
var journal_entries: Array[JournalEntryView] = []
var acquired_player_maps: Array[PlayerMapView] = []
var player_map_menu_entries: Array[PlayerMapView] = []
var location_notes: Array[LocationNoteView] = []
var current_location_note: LocationNoteView
var services: Array[ServiceView] = []
var money_workspace: MoneyWorkspaceView
var action_availability: Dictionary = {}
var domain_revisions: ViewDomainRevisions


func _init(current_revision: int, started: bool, interaction: InteractionRequest, map_id: String = "", coordinate: Vector2i = Vector2i.ZERO, day: int = 0, hour: int = 0, minute: int = 0, current_map_view: MapView = null, members: Array[CharacterView] = [], fatigue: int = 0, gold: int = 0, current_combat: CombatView = null) -> void:
	revision = current_revision
	session_started = started
	pending_interaction = interaction
	party_map_id = map_id
	party_coordinate = coordinate
	realmz_day = day
	realmz_hour = hour
	realmz_minute = minute
	map_view = current_map_view
	party_members = members.duplicate()
	party_fatigue = fatigue
	pooled_gold = gold
	combat_view = current_combat
	domain_revisions = ViewDomainRevisions.all_at(current_revision)


func set_action_availability(action_id: StringName, enabled: bool, reason: String = "") -> void:
	action_availability[action_id] = ActionAvailabilityView.new(action_id, enabled, reason)


func availability(action_id: StringName) -> ActionAvailabilityView:
	var value: Variant = action_availability.get(action_id)
	if value is ActionAvailabilityView:
		return value
	return ActionAvailabilityView.new(action_id, false, "This action is unavailable in the current gameplay slice.")
