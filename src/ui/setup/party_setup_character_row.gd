## Presents party setup character row through the Godot interface.

class_name PartySetupCharacterRow
extends PanelContainer

signal import_requested(character_id: String, revision_hash: String)

## Cards are the native portrait plus two pixels of padding; the name and identity each keep one
## line, truncated with an ellipsis, and the card tooltip carries the complete text.
const ROW_HEIGHT: float = 48.0
const PARTY_SLOT_HEIGHT: float = 48.0
const PORTRAIT_SIZE: float = 44.0
const ACTION_WIDTH: float = 58.0
## Narrower cards drop the tactical icon so the name and identity keep readable room.
const ICON_MINIMUM_CARD_WIDTH: float = 360.0
## Below this width action buttons use compact glyph labels; tooltips and accessible names stay full.
const COMPACT_CARD_WIDTH: float = 300.0
const DRAG_CURSOR_SHAPES: Array[Input.CursorShape] = [
	Input.CURSOR_ARROW,
	Input.CURSOR_DRAG,
	Input.CURSOR_CAN_DROP,
	Input.CURSOR_FORBIDDEN,
]

var character_id: String
var revision_hash: String
var import_enabled: bool = false
var _drag_label: String = ""
var _drag_portrait: Texture2D
var _drag_cursor_texture: Texture2D
var _drag_cursor_key: String = ""
var _drag_cursor_active: bool = false
var _portrait_view: TextureRect
var _icon_view: TextureRect
var _name: Label
var _summary: Label
var _in_party: Control
var _add_button: Button


func _request_import() -> void:
	import_requested.emit(character_id, revision_hash)


func _bind_scene_nodes() -> void:
	if _portrait_view != null:
		return
	_portrait_view = get_node("Row/Portrait") as TextureRect
	_icon_view = get_node("Row/TacticalIcon") as TextureRect
	_name = get_node("Row/Text/Name") as Label
	_summary = get_node("Row/Text/Summary") as Label
	_in_party = get_node("Row/InParty") as Control
	_add_button = get_node("Row/AddCharacter") as Button


## One stored character as its own card. A blocking eligibility reason replaces the identity
## line in red; party members show "In party" instead of Add. Add stays focusable when disabled.
func configure(revision: CharacterVaultRevisionView, enabled: bool, reason: String, portrait: Texture2D = null, icon: Texture2D = null, in_party: bool = false, blocked: bool = false) -> void:
	_bind_scene_nodes()
	character_id = revision.character_id
	revision_hash = revision.revision_hash
	import_enabled = enabled
	UiSizing.minimum_size(self, Vector2(0.0, ROW_HEIGHT))
	mouse_default_cursor_shape = Control.CURSOR_DRAG if enabled else Control.CURSOR_ARROW
	var race_name := revision.race_id.replace("_", " ").replace("-", " ").capitalize()
	var caste_name := revision.caste_id.replace("_", " ").replace("-", " ").capitalize()
	if revision.character != null:
		race_name = revision.character.race_name
		caste_name = revision.character.caste_name
	_drag_label = revision.name
	_drag_portrait = portrait
	_prepare_drag_cursor(revision.revision_hash, portrait)
	UiSizing.artwork(_portrait_view, portrait)
	UiSizing.artwork(_icon_view, icon)
	_fit_width()
	_portrait_view.tooltip_text = "%s's portrait" % revision.name
	_name.text = revision.name
	var identity := "Level %d %s %s" % [revision.level, race_name, caste_name]
	_summary.text = reason if blocked else identity
	_summary.theme_type_variation = &"VaultStatusBad" if blocked else &"VaultStatusMuted"
	_in_party.visible = in_party
	_add_button.visible = not in_party
	_add_button.disabled = not enabled
	_add_button.focus_mode = Control.FOCUS_ALL
	tooltip_text = ("Add %s to the party. You can also drag this card into the party." % revision.name if enabled else reason) + "
" + summary_text(revision.name, revision.level, race_name, caste_name, revision.character)
	_add_button.tooltip_text = tooltip_text
	_add_button.accessibility_name = "Add %s, %s%s" % [revision.name, identity, "" if enabled else ", unavailable: " + reason]


static func summary_text(character_name: String, level: int, race_name: String, caste_name: String, character: CharacterView = null, slot_number: int = 0) -> String:
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
	_start_drag_cursor()
	return drag_payload()


func drag_payload() -> Dictionary:
	return {
		"kind": "party-setup-character",
		"characterId": character_id,
		"revisionHash": revision_hash,
	}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drag_cursor()
	elif what == NOTIFICATION_RESIZED and _icon_view != null:
		_fit_width()


func _fit_width() -> void:
	_icon_view.visible = _icon_view.texture != null and size.x >= ICON_MINIMUM_CARD_WIDTH
	var compact := size.x < COMPACT_CARD_WIDTH
	_add_button.text = "+" if compact else "Add"
	_add_button.custom_minimum_size.x = 30.0 if compact else 52.0


func _exit_tree() -> void:
	_clear_drag_cursor()


func _start_drag_cursor() -> void:
	_clear_drag_cursor()
	if _drag_cursor_texture == null:
		return
	var hotspot := Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE) * 0.5
	for shape: Input.CursorShape in DRAG_CURSOR_SHAPES:
		Input.set_custom_mouse_cursor(_drag_cursor_texture, shape, hotspot)
	_drag_cursor_active = true


func _prepare_drag_cursor(prepared_revision_hash: String, portrait: Texture2D) -> void:
	var next_key := "%s:%d" % [prepared_revision_hash, portrait.get_instance_id() if portrait != null else 0]
	if next_key == _drag_cursor_key:
		return
	_clear_drag_cursor()
	_drag_cursor_key = next_key
	_drag_cursor_texture = _make_drag_cursor_texture()


func drag_cursor_prepared() -> bool:
	return _drag_cursor_texture != null


func drag_cursor_texture_identity() -> int:
	return _drag_cursor_texture.get_instance_id() if _drag_cursor_texture != null else 0


func _make_drag_cursor_texture() -> Texture2D:
	if _drag_portrait == null:
		return null
	var image := _drag_portrait.get_image()
	if image == null or image.is_empty() or image.get_width() > 256 or image.get_height() > 256:
		return null
	image = image.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color := image.get_pixel(x, y)
			color.a *= 0.62
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _clear_drag_cursor() -> void:
	if not _drag_cursor_active:
		return
	for shape: Input.CursorShape in DRAG_CURSOR_SHAPES:
		Input.set_custom_mouse_cursor(null, shape)
	_drag_cursor_active = false

