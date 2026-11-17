## Binds one stored character to its scene-authored Character Files row.
class_name VaultCharacterRow
extends Button

var character_id := ""

@onready var _content: Control = $RowContent
@onready var _selection_bar: ColorRect = $RowContent/SelectionBar
@onready var _portrait: TextureRect = $RowContent/StoredPortrait
@onready var _tactical_icon: TextureRect = $RowContent/StoredTacticalIcon
@onready var _name: Label = $RowContent/Summary/Name
@onready var _identity: Label = $RowContent/Summary/Identity
@onready var _wide_status: HBoxContainer = $RowContent/Status
@onready var _compact_status: HBoxContainer = $RowContent/Summary/CompactStatus


func _ready() -> void:
	# The row is a Button, so it grows with its wrapped content explicitly.
	_content.minimum_size_changed.connect(_fit_height)
	_fit_height()


func bind(entry: VaultEntry, portrait: Texture2D, tactical_icon: Texture2D, status_text: String, status_variation: StringName, compact: bool) -> void:
	character_id = entry.character_id
	name = "CharacterFile_%s" % entry.character_id.validate_node_name()
	_bind_texture(_portrait, portrait)
	_bind_texture(_tactical_icon, tactical_icon)
	_name.text = entry.display.name
	_identity.text = VaultDetailBinder.identity_text(entry.display)
	_wide_status.visible = not compact
	_compact_status.visible = compact
	for holder: HBoxContainer in [_wide_status, _compact_status]:
		var label := holder.get_node("Label") as Label
		label.text = status_text
		label.theme_type_variation = status_variation
		# The dot is authored white and tinted to the status colour from the theme.
		(holder.get_node("Dot") as Control).self_modulate = label.get_theme_color(&"font_color")
	tooltip_text = "%s • %s" % [entry.display.name, status_text]
	# The row's visible text lives in child labels, so assistive tools get one summary.
	accessibility_name = "%s, %s, %s" % [entry.display.name, _identity.text, status_text]


func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)
	_selection_bar.color.a = 1.0 if selected else 0.0


func _bind_texture(target: TextureRect, texture: Texture2D) -> void:
	target.texture = texture
	if texture != null:
		target.custom_minimum_size = texture.get_size()


func _fit_height() -> void:
	custom_minimum_size.y = maxf(60.0, _content.get_combined_minimum_size().y + 16.0)
