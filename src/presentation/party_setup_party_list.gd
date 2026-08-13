class_name PartySetupPartyList
extends VBoxContainer

signal import_requested(character_id: String, revision_hash: String)

var accepts_imports: bool = false
var disabled_reason: String = ""


func configure_drop_target(enabled: bool, reason: String) -> void:
	accepts_imports = enabled
	disabled_reason = reason
	tooltip_text = "Drop a stored character into an empty party slot." if enabled else reason


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return accepts_imports and data is Dictionary and data.get("kind") == "party-setup-character" and data.get("characterId") is String and data.get("revisionHash") is String


func _drop_data(_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(_position, data):
		return
	import_requested.emit(String(data["characterId"]), String(data["revisionHash"]))
