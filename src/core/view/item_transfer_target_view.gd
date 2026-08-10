class_name ItemTransferTargetView
extends RefCounted

var character_id: String
var character_name: String
var enabled: bool
var reason: String


func _init(id: String, display_name: String, is_enabled: bool, disabled_reason: String = "") -> void:
	character_id = id
	character_name = display_name
	enabled = is_enabled
	reason = "" if enabled else disabled_reason
