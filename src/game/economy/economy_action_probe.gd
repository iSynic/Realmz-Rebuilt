## Implements deterministic economy action probe rules without presentation dependencies.

class_name EconomyActionProbe
extends RefCounted

var allowed: bool
var reason: String


func _init(is_allowed: bool, unavailable_reason: String = "") -> void:
	allowed = is_allowed
	reason = "" if is_allowed else unavailable_reason
