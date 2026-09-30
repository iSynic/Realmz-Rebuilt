## Names one possession excluded from an explicit adventure transfer.
class_name PartyTransferOmission
extends RefCounted

var kind: StringName
var identity: String
var label: String
var reason: String


func _init(possession_kind: StringName, stable_identity: String, display_name: String, explanation: String) -> void:
	kind = possession_kind
	identity = stable_identity
	label = display_name
	reason = explanation
