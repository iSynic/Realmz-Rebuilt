## Presents party setup character row through the Godot interface.

class_name PartySetupCharacterRow
extends PanelContainer

signal import_requested(character_id: String, revision_hash: String)

const ROW_HEIGHT: float = 44.0
const PORTRAIT_SIZE: float = 44.0
const ACTION_WIDTH: float = 58.0
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
var _summary: Label
var _add_button: Button


func _request_import() -> void:
	import_requested.emit(character_id, revision_hash)


func _bind_scene_nodes() -> void:
	if _portrait_view != null:
		return
	_portrait_view = get_node("Row/Portrait") as TextureRect
	_summary = get_node("Row/Summary") as Label
	_add_button = get_node("Row/AddCharacter") as Button


func configure(revision: CharacterVaultRevisionView, enabled: bool, reason: String, portrait: Texture2D = null) -> void:
	_bind_scene_nodes()
	character_id = revision.character_id
	revision_hash = revision.revision_hash
	import_enabled = enabled
	custom_minimum_size.y = ROW_HEIGHT
	add_theme_stylebox_override("panel", row_style())
	mouse_default_cursor_shape = Control.CURSOR_DRAG if enabled else Control.CURSOR_FORBIDDEN
	tooltip_text = "Add %s to the party. You can also drag this character into an empty party position." % revision.name if enabled else reason
	var race_name := revision.race_id.replace("_", " ").replace("-", " ").capitalize()
	var caste_name := revision.caste_id.replace("_", " ").replace("-", " ").capitalize()
	if revision.character != null:
		race_name = revision.character.race_name
		caste_name = revision.character.caste_name
	_drag_label = revision.name
	_drag_portrait = portrait
	_prepare_drag_cursor(revision.revision_hash, portrait)
	_portrait_view.texture = portrait
	_portrait_view.tooltip_text = "%s's portrait" % revision.name
	_summary.text = summary_text(revision.name, revision.level, race_name, caste_name, revision.character)
	_add_button.disabled = not enabled
	_add_button.tooltip_text = tooltip_text


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


static func row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1a1e22")
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style
