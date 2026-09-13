class_name ControllerRadialEntry
extends RefCounted

## Presentation data for one controller-radial command.
## The overlay never interprets the command id or disabled reason.

var id: StringName
var label: String
var enabled: bool
var disabled_reason: String


func _init(command_id: StringName = &"", command_label: String = "", is_enabled: bool = true, reason: String = "") -> void:
	id = command_id
	label = command_label
	enabled = is_enabled
	disabled_reason = reason
