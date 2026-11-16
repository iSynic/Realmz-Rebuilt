## Presents party setup party slot through the Godot interface.

class_name PartySetupPartySlot
extends PanelContainer

signal inspect_requested(character_id: String)
signal remove_requested(character_id: String)

const CharacterRow := preload("res://src/ui/setup/party_setup_character_row.gd")
const CARD_STYLE := preload("res://src/ui/setup/setup_styles/character_card.tres")
const OPEN_STYLE := preload("res://src/ui/setup/setup_styles/open_slot.tres")

## Narrower cards drop the slot number and tactical icon so identities keep readable room.
const NUMBER_MINIMUM_CARD_WIDTH: float = 300.0

var _character_id: String = ""
var _portrait: TextureRect
var _icon: TextureRect
var _number: Label
var _name: Label
var _summary: Label
var _inspect: Button
var _remove: Button


func _bind_scene_nodes() -> void:
	if _portrait != null:
		return
	_portrait = get_node("Row/Portrait") as TextureRect
	_icon = get_node("Row/TacticalIcon") as TextureRect
	_number = get_node("Row/Number") as Label
	_name = get_node("Row/Text/Name") as Label
	_summary = get_node("Row/Text/Summary") as Label
	_inspect = get_node("%InspectPartyCharacter") as Button
	_remove = get_node("%RemovePartyCharacter") as Button


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _icon != null:
		_fit_width()


func _fit_width() -> void:
	_number.visible = size.x >= NUMBER_MINIMUM_CARD_WIDTH or _character_id.is_empty()
	_icon.visible = not _character_id.is_empty() and _icon.texture != null and size.x >= CharacterRow.ICON_MINIMUM_CARD_WIDTH
	var compact := size.x < CharacterRow.COMPACT_CARD_WIDTH
	_inspect.text = "i" if compact else "Inspect"
	_inspect.custom_minimum_size.x = 26.0 if compact else 0.0


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


## A filled slot is a card with art, identity, Inspect and ×; an open slot is an outlined card.
func configure(slot_index: int, character: CharacterView, portrait: Texture2D, compact: bool, remove_availability: ActionAvailabilityView, icon: Texture2D = null, open_hint: String = "Open position") -> void:
	_bind_scene_nodes()
	name = ("PartySlot%d" if character != null else "EmptyPartySlot%d") % (slot_index + 1)
	_character_id = character.id if character != null else ""
	_number.text = str(slot_index + 1)
	UiSizing.minimum_size(self, Vector2(0.0, 40.0 if character == null else CharacterRow.PARTY_SLOT_HEIGHT))
	add_theme_stylebox_override(&"panel", OPEN_STYLE if character == null else CARD_STYLE)
	_portrait.visible = character != null
	_name.visible = character != null
	_inspect.visible = character != null
	_remove.visible = character != null
	_fit_width()
	if character == null:
		_summary.text = open_hint
		_summary.theme_type_variation = &"VaultStatusMuted"
		_summary.modulate = Color(1, 1, 1, 0.7)
		tooltip_text = "Open party position %d. Choose Add in Character Files, or drag a character here." % (slot_index + 1)
		return
	UiSizing.artwork(_portrait, portrait)
	UiSizing.artwork(_icon, icon)
	_fit_width()
	_portrait.tooltip_text = "%s's portrait" % character.name
	_name.text = character.name
	_summary.text = "Level %d %s %s" % [character.level, character.race_name, character.caste_name]
	_summary.modulate = Color.WHITE
	tooltip_text = CharacterRow.summary_text(character.name, character.level, character.race_name, character.caste_name, character, slot_index + 1)
	_inspect.tooltip_text = "Open %s's complete character record without changing party state." % character.name
	_inspect.accessibility_name = "Inspect %s" % character.name
	_remove.disabled = remove_availability == null or not remove_availability.enabled
	_remove.focus_mode = Control.FOCUS_ALL
	_remove.tooltip_text = remove_availability.reason if _remove.disabled and remove_availability != null else "Remove %s" % character.name
	_remove.accessibility_name = "Remove %s" % character.name
