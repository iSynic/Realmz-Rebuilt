class_name ItemTransferTargetView
extends RefCounted

var character_id: String
var character_name: String
var enabled: bool
var reason: String
var current_load: int
var resulting_load: int
var maximum_load: int
var has_load_facts: bool


func _init(id: String, display_name: String, is_enabled: bool, disabled_reason: String = "", load: int = -1, result_load: int = -1, load_maximum: int = -1) -> void:
	character_id = id
	character_name = display_name
	enabled = is_enabled
	reason = "" if enabled else disabled_reason
	current_load = load
	resulting_load = result_load
	maximum_load = load_maximum
	has_load_facts = current_load >= 0 and resulting_load >= 0 and maximum_load >= 0
