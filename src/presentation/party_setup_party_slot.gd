class_name PartySetupPartySlot
extends PanelContainer

signal inspect_requested(character_id: String)
signal remove_requested(character_id: String)

const CharacterRow := preload("res://src/presentation/party_setup_character_row.gd")

var _character_id: String = ""
var _portrait: TextureRect
var _summary: Label
var _inspect: Button
var _remove: Button


func _init() -> void:
	custom_minimum_size.y = CharacterRow.ROW_HEIGHT
	add_theme_stylebox_override("panel", CharacterRow.row_style())
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new(); row.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_theme_constant_override("separation", 6); add_child(row)
	_portrait = TextureRect.new(); _portrait.name = "Portrait"; _portrait.custom_minimum_size = Vector2(CharacterRow.PORTRAIT_SIZE, CharacterRow.PORTRAIT_SIZE); _portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; _portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; _portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(_portrait)
	_summary = Label.new(); _summary.name = "Summary"; _summary.add_theme_font_size_override("font_size", 12); _summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; _summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; _summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _summary.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(_summary)
	_inspect = Button.new(); _inspect.name = "InspectPartyCharacter"; _inspect.pressed.connect(func() -> void: if not _character_id.is_empty(): inspect_requested.emit(_character_id)); row.add_child(_inspect)
	_remove = Button.new(); _remove.name = "RemovePartyCharacter"; _remove.pressed.connect(func() -> void: if not _character_id.is_empty(): remove_requested.emit(_character_id)); row.add_child(_remove)


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
	name = ("PartySlot%d" if character != null else "EmptyPartySlot%d") % (slot_index + 1)
	_character_id = character.id if character != null else ""
	_portrait.texture = portrait
	_portrait.tooltip_text = "%s's portrait" % character.name if character != null else ""
	if character == null:
		_summary.text = "%d. Empty position" % (slot_index + 1); _summary.modulate = Color("9aa0a8"); _inspect.visible = false; _remove.visible = false
		return
	_summary.text = CharacterRow._summary_text(character.name, character.level, character.race_name, character.caste_name, character, slot_index + 1); _summary.modulate = Color("e0e2e5")
	_inspect.visible = true; _inspect.text = "View" if compact else "Inspect"; _inspect.tooltip_text = "Open %s's complete character record without changing party state." % character.name
	_remove.visible = true; _remove.text = "−" if compact else "Remove"; _remove.disabled = remove_availability == null or not remove_availability.enabled; _remove.tooltip_text = remove_availability.reason if _remove.disabled and remove_availability != null else "Remove %s from the current party." % character.name
