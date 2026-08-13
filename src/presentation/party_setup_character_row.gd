class_name PartySetupCharacterRow
extends PanelContainer

signal import_requested(character_id: String, revision_hash: String)

var character_id: String
var revision_hash: String
var import_enabled: bool = false
var _drag_label: String = ""


func configure(revision: CharacterVaultRevisionView, enabled: bool, reason: String, portrait: Texture2D = null) -> void:
	character_id = revision.character_id
	revision_hash = revision.revision_hash
	import_enabled = enabled
	custom_minimum_size.y = 60.0
	tooltip_text = "Add %s to the party. You can also drag this character into an empty party position." % revision.name if enabled else reason
	var race_name := revision.race_id.replace("_", " ").replace("-", " ").capitalize()
	var caste_name := revision.caste_id.replace("_", " ").replace("-", " ").capitalize()
	if revision.character != null:
		race_name = revision.character.race_name
		caste_name = revision.character.caste_name
	_drag_label = revision.name
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var portrait_view := TextureRect.new()
	portrait_view.name = "Portrait"
	portrait_view.custom_minimum_size = Vector2(48.0, 48.0)
	portrait_view.texture = portrait
	portrait_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_view.tooltip_text = "%s's portrait" % revision.name
	row.add_child(portrait_view)
	var summary := Label.new()
	summary.name = "Summary"
	summary.text = "%s\nLevel %d • %s / %s" % [revision.name, revision.level, race_name, caste_name]
	summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(summary)
	var add_button := Button.new()
	add_button.name = "AddCharacter"
	add_button.text = "Add"
	add_button.disabled = not enabled
	add_button.tooltip_text = tooltip_text
	add_button.pressed.connect(func() -> void: import_requested.emit(character_id, revision_hash))
	row.add_child(add_button)


func _get_drag_data(_position: Vector2) -> Variant:
	if not import_enabled:
		return null
	var preview := Label.new()
	preview.text = "Add • %s" % _drag_label
	preview.modulate = Color("d5b45d")
	set_drag_preview(preview)
	return {
		"kind": "party-setup-character",
		"characterId": character_id,
		"revisionHash": revision_hash,
	}
