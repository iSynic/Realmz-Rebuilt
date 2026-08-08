class_name ActionAvailabilityView
extends RefCounted

var action_id: StringName
var enabled: bool
var reason: String


func _init(id: StringName, is_enabled: bool, disabled_reason: String = "") -> void:
	action_id = id
	enabled = is_enabled
	reason = "" if enabled else disabled_reason
