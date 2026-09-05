## Presents party setup party slot through the Godot interface.

class_name PartySetupPartySlot
extends PanelContainer

signal inspect_requested(character_id: String)
signal remove_requested(character_id: String)

const CharacterRow := preload("res://src/ui/setup/party_setup_character_row.gd")

var _character_id: String = ""
var _portrait: TextureRect
var _summary: Label
var _inspect: Button
var _remove: Button


func _bind_scene_nodes() -> void:
	if _portrait != null:
		return
	_portrait = get_node("Row/Portrait") as TextureRect
	_summary = get_node("Row/Summary") as Label
	_inspect = get_node("Row/InspectPartyCharacter") as Button
	_remove = get_node("Row/RemovePartyCharacter") as Button


func _request_inspection() -> void:
	if not _character_id.is_empty():
		inspect_requested.emit(_character_id)


func _request_removal() -> void:
	if not _character_id.is_empty():
		remove_requested.emit(_character_id)


func _can_drop_data(position: Vector2, data: Variant) -> bool:
	var target := get_parent() as PartySetupPartyList
	return target != null and target.accepts_drop_payload(data)


func _drop_data(position: Vector2, data: Variant) -> void:
	var target := get_parent() as PartySetupPartyList
	if target != null: target.submit_drop_payload(data)


func accepts_drop_payload(data: Variant) -> bool:
	var target := get_parent() as PartySetupPartyList
	return target != null and target.accepts_drop_payload(data)


func submit_drop_payload(data: Variant) -> void:
	var target := get_parent() as PartySetupPartyList
	if target != null: target.submit_drop_payload(data)


func configure(slot_index: int, character: CharacterView, portrait: Texture2D, compact: bool, remove_availability: ActionAvailabilityView) -> void:
	_bind_scene_nodes()
	name = ("PartySlot%d" if character != null else "EmptyPartySlot%d") % (slot_index + 1)
	_character_id = character.id if character != null else ""
	_portrait.texture = portrait
	_portrait.tooltip_text = "%s's portrait" % character.name if character != null else ""
	if character == null:
		_summary.text = "%d. Empty position" % (slot_index + 1)
		_summary.modulate = Color("9aa0a8")
		_inspect.visible = false
		_remove.visible = false
		return
	_summary.text = CharacterRow.summary_text(character.name, character.level, character.race_name, character.caste_name, character, slot_index + 1)
	_summary.modulate = Color("e0e2e5")
	_inspect.visible = true
	_inspect.text = "View" if compact else "Inspect"
	_inspect.tooltip_text = "Open %s's complete character record without changing party state." % character.name
	_remove.visible = true
	_remove.text = "−" if compact else "Remove"
	_remove.disabled = remove_availability == null or not remove_availability.enabled
	_remove.tooltip_text = remove_availability.reason if _remove.disabled and remove_availability != null else "Remove %s from the current party." % character.name
