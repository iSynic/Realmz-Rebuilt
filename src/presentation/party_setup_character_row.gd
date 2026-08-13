class_name PartySetupCharacterRow
extends PanelContainer

signal import_requested(character_id: String, revision_hash: String)

const ROW_HEIGHT: float = 32.0
const PORTRAIT_SIZE: float = 26.0
const ACTION_WIDTH: float = 58.0

var character_id: String
var revision_hash: String
var import_enabled: bool = false
var _drag_label: String = ""


func configure(revision: CharacterVaultRevisionView, enabled: bool, reason: String, portrait: Texture2D = null) -> void:
	character_id = revision.character_id
	revision_hash = revision.revision_hash
	import_enabled = enabled
	custom_minimum_size.y = ROW_HEIGHT
	mouse_default_cursor_shape = Control.CURSOR_DRAG if enabled else Control.CURSOR_FORBIDDEN
	tooltip_text = "Add %s to the party. You can also drag this character into an empty party position." % revision.name if enabled else reason
	var race_name := revision.race_id.replace("_", " ").replace("-", " ").capitalize()
	var caste_name := revision.caste_id.replace("_", " ").replace("-", " ").capitalize()
	if revision.character != null:
		race_name = revision.character.race_name
		caste_name = revision.character.caste_name
	_drag_label = revision.name
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var portrait_view := TextureRect.new()
	portrait_view.name = "Portrait"
	portrait_view.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait_view.texture = portrait
	portrait_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_view.tooltip_text = "%s's portrait" % revision.name
	portrait_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait_view)
	var summary := Label.new()
	summary.name = "Summary"
	summary.text = _summary_text(revision.name, revision.level, race_name, caste_name, revision.character)
	summary.add_theme_font_size_override("font_size", 10)
	summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(summary)
	var add_button := Button.new()
	add_button.name = "AddCharacter"
	add_button.text = "Add"
	add_button.custom_minimum_size.x = ACTION_WIDTH
	add_button.disabled = not enabled
	add_button.tooltip_text = tooltip_text
	add_button.pressed.connect(func() -> void: import_requested.emit(character_id, revision_hash))
	row.add_child(add_button)


static func _summary_text(character_name: String, level: int, race_name: String, caste_name: String, character: CharacterView = null, slot_number: int = 0) -> String:
	var prefix := "%d. " % slot_number if slot_number > 0 else ""
	var identity := "%s%s • L%d • %s / %s" % [prefix, character_name, level, race_name, caste_name]
	if character == null:
		return identity
	return "%s\nST %d/%d  SP %d/%d  AR %d  Carry %d/%d" % [
		identity,
		character.current_health,
		character.maximum_health,
		character.spell_points,
		character.maximum_spell_points,
		character.armor,
		character.carried_load,
		character.maximum_load,
	]


func _get_drag_data(_position: Vector2) -> Variant:
	if not import_enabled:
		return null
	set_drag_preview(_drag_preview())
	return drag_payload()


func drag_payload() -> Dictionary:
	return {
		"kind": "party-setup-character",
		"characterId": character_id,
		"revisionHash": revision_hash,
	}


func _drag_preview() -> Control:
	var preview := Label.new()
	preview.text = "Add • %s" % _drag_label
	preview.modulate = Color("d5b45d")
	return preview
