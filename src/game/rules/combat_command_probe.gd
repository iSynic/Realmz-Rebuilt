class_name CombatCommandProbe
extends RefCounted

var allowed: bool
var reason_text: String


func _init(is_allowed: bool, reason: String = "") -> void:
	allowed = is_allowed
	reason_text = reason
