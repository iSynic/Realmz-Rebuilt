class_name PartySetupPartyList
extends VBoxContainer

signal import_requested(character_id: String, revision_hash: String)

var accepts_imports: bool = false
var disabled_reason: String = ""


func configure_drop_target(enabled: bool, reason: String) -> void:
	accepts_imports = enabled
	disabled_reason = reason
	tooltip_text = "Drop a stored character into an empty party slot." if enabled else reason
	self_modulate = Color.WHITE


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data() if get_viewport() != null else null
		if _can_drop_data(Vector2.ZERO, data):
			self_modulate = Color(0.78, 1.0, 0.78, 1.0)
	elif what == NOTIFICATION_DRAG_END:
		self_modulate = Color.WHITE


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return accepts_drop_payload(data)


func _drop_data(_position: Vector2, data: Variant) -> void:
	submit_drop_payload(data)


func accepts_drop_payload(data: Variant) -> bool:
	return accepts_imports and data is Dictionary and data.get("kind") == "party-setup-character" and data.get("characterId") is String and data.get("revisionHash") is String


func submit_drop_payload(data: Variant) -> void:
	if accepts_drop_payload(data): import_requested.emit(String(data["characterId"]), String(data["revisionHash"]))
