class_name PartySetupCharacterRow
extends Button

signal import_requested(character_id: String, revision_hash: String)

var character_id: String
var revision_hash: String
var import_enabled: bool = false


func configure(revision: CharacterVaultRevisionView, enabled: bool, reason: String, combat_icon: Texture2D = null) -> void:
	character_id = revision.character_id
	revision_hash = revision.revision_hash
	import_enabled = enabled
	var race_name := revision.race_id.replace("_", " ").replace("-", " ").capitalize()
	var caste_name := revision.caste_id.replace("_", " ").replace("-", " ").capitalize()
	if revision.character != null:
		race_name = revision.character.race_name
		caste_name = revision.character.caste_name
	text = "%s\nLevel %d • %s / %s" % [revision.name, revision.level, race_name, caste_name]
	icon = combat_icon
	expand_icon = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_constant_override("icon_max_width", 48)
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size.y = 60.0
	disabled = not enabled
	tooltip_text = "Add %s to the party. You can also drag this character into an empty party slot." % revision.name if enabled else reason
	pressed.connect(func() -> void: import_requested.emit(character_id, revision_hash))


func _get_drag_data(_position: Vector2) -> Variant:
	if not import_enabled:
		return null
	var preview := Label.new()
	preview.text = text.get_slice("\n", 0)
	preview.modulate = Color("d5b45d")
	set_drag_preview(preview)
	return {
		"kind": "party-setup-character",
		"characterId": character_id,
		"revisionHash": revision_hash,
	}
