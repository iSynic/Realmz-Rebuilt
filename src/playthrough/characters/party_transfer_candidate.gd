## One detached hero and the explicit outcomes of preparing its transfer.
class_name PartyTransferCandidate
extends RefCounted

var character: CharacterState
var reasons: Array[String] = []
var removed: Array[String] = []
var retained: Array[String] = []
var omissions: Array[PartyTransferOmission] = []


func omit(kind: StringName, identity: String, label: String, reason: String) -> void:
	omissions.append(PartyTransferOmission.new(kind, identity, label, reason))
	removed.append("%s: %s — %s" % [String(kind).capitalize(), label, reason])

func eligible() -> bool:
	return character != null and reasons.is_empty()
