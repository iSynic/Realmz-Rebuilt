class_name GameView
extends RefCounted

var revision: int
var session_started: bool
var pending_interaction: InteractionRequest
var party_map_id: String
var party_coordinate: Vector2i
var realmz_day: int
var realmz_hour: int
var map_view: MapView
var party_members: Array[CharacterView] = []
var party_fatigue: int = 0
var pooled_gold: int = 0
var combat_view: CombatView
var campaign_id: String = ""
var rules_version: String = ""
var party_setup_available: bool = false
var race_options: Array[DefinitionOptionView] = []
var caste_options: Array[DefinitionOptionView] = []


func _init(current_revision: int, started: bool, interaction: InteractionRequest, map_id: String = "", coordinate: Vector2i = Vector2i.ZERO, day: int = 0, hour: int = 0, current_map_view: MapView = null, members: Array[CharacterView] = [], fatigue: int = 0, gold: int = 0, current_combat: CombatView = null) -> void:
	revision = current_revision
	session_started = started
	pending_interaction = interaction
	party_map_id = map_id
	party_coordinate = coordinate
	realmz_day = day
	realmz_hour = hour
	map_view = current_map_view
	party_members = members.duplicate()
	party_fatigue = fatigue
	pooled_gold = gold
	combat_view = current_combat
