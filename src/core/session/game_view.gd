class_name GameView
extends RefCounted

var revision: int
var session_started: bool
var pending_interaction: InteractionRequest


func _init(current_revision: int, started: bool, interaction: InteractionRequest) -> void:
	revision = current_revision
	session_started = started
	pending_interaction = interaction
