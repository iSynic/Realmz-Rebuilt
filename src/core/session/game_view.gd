class_name GameView
extends RefCounted

var revision: int
var session_started: bool
var pending_interaction: InteractionRequest
var party_map_id: String
var party_coordinate: Vector2i
var realmz_day: int
var realmz_hour: int


func _init(current_revision: int, started: bool, interaction: InteractionRequest, map_id: String = "", coordinate: Vector2i = Vector2i.ZERO, day: int = 0, hour: int = 0) -> void:
	revision = current_revision
	session_started = started
	pending_interaction = interaction
	party_map_id = map_id
	party_coordinate = coordinate
	realmz_day = day
	realmz_hour = hour
