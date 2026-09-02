class_name GameView
extends RefCounted

const ViewDomainRevisionsScript := preload("res://src/core/session/view_domain_revisions.gd")
const ViewChangeSetScript := preload("res://src/core/view/view_change_set.gd")

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
var party_allies: Array[MonsterView] = []
var bestiary_entries: Array[MonsterCatalogEntryView] = []
var party_fatigue: int = 0
var pooled_gold: int = 0
var character_spellcasting_blocked: bool = false
var combat_view: CombatView
# Direct session-owned battles accept typed player intents rather than
# suspending a Scenario VM frame. They still expose the same detached command
# contract so presentation never reconstructs combat legality.
var combat_action_request: InteractionRequest
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
var domain_revisions: RefCounted
var change_set: RefCounted
var projection_timings_usec: Dictionary = {}


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
	domain_revisions = ViewDomainRevisionsScript.new(current_revision)
	change_set = ViewChangeSetScript.new(true)


func set_action_availability(action_id: StringName, enabled: bool, reason: String = "") -> void:
	action_availability[action_id] = ActionAvailabilityView.new(action_id, enabled, reason)


func availability(action_id: StringName) -> ActionAvailabilityView:
	var value: Variant = action_availability.get(action_id)
	if value is ActionAvailabilityView:
		return value
	return ActionAvailabilityView.new(action_id, false, "This action is unavailable in the current gameplay slice.")


func active_interaction_request() -> InteractionRequest:
	return pending_interaction if pending_interaction != null else combat_action_request
