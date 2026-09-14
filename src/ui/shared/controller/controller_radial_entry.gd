## Describes one ordered controller radial command and its current availability.

class_name ControllerRadialEntry
extends RefCounted

## Presentation data for one controller-radial command.
## The overlay never interprets the command id or disabled reason.

var id: StringName
var label: String
var enabled: bool
var disabled_reason: String
var icon: Texture2D
var fallback_symbol: String


func _init(command_id: StringName = &"", command_label: String = "", is_enabled: bool = true, reason: String = "", command_icon: Texture2D = null, symbol: String = "") -> void:
	id = command_id
	label = command_label
	enabled = is_enabled
	disabled_reason = reason
	icon = command_icon
	fallback_symbol = symbol
