## Applies the responsive scale policy to the authored battle command deck.

class_name BattleCommandScaleController
extends RefCounted

const COMMAND_BASE_SIZE_META: StringName = &"battle_command_base_size"
const COMMAND_FONT_SIZE := 14.0
const COMMAND_GROUP_HEIGHT := 100.0
const COMMAND_GROUP_SEPARATION := 10.0
const COMMAND_COLUMN_SEPARATION := 4.0
const COMMAND_ROW_SEPARATION := 5.0

var _scale := 1.0
var _shelf: HBoxContainer
var _panels: Array[Control] = []
var _columns: Array[VBoxContainer] = []
var _headings: Array[Label] = []
var _rows: Array[HBoxContainer] = []
var _buttons: Array[Button] = []


func reset() -> void:
	_shelf = null
	_panels.clear()
	_columns.clear()
	_headings.clear()
	_rows.clear()
	_buttons.clear()


func configure(shelf: HBoxContainer, panels: Array[Control], columns: Array[VBoxContainer], rows: Array[HBoxContainer]) -> void:
	_shelf = shelf
	_panels.assign(panels)
	_columns.assign(columns)
	_rows.assign(rows)
	_headings.clear()
	for column: VBoxContainer in _columns:
		_headings.append(column.get_child(0) as Label)


func set_scale(value: float) -> void:
	_scale = clampf(value, 1.0, 2.0)
	apply()


func register_button(button: Button, base_size: Vector2) -> void:
	button.set_meta(COMMAND_BASE_SIZE_META, base_size)
	if not _buttons.has(button):
		_buttons.append(button)
	_apply_button(button)


func apply() -> void:
	if _shelf != null and is_instance_valid(_shelf):
		_shelf.add_theme_constant_override("separation", roundi(COMMAND_GROUP_SEPARATION * _scale))
	for panel: Control in _panels:
		if is_instance_valid(panel):
			panel.custom_minimum_size.y = COMMAND_GROUP_HEIGHT * _scale
	for column: VBoxContainer in _columns:
		if is_instance_valid(column):
			column.add_theme_constant_override("separation", roundi(COMMAND_COLUMN_SEPARATION * _scale))
	for heading: Label in _headings:
		if is_instance_valid(heading):
			heading.add_theme_font_size_override("font_size", roundi(COMMAND_FONT_SIZE * _scale))
	for row: HBoxContainer in _rows:
		if is_instance_valid(row):
			row.add_theme_constant_override("separation", roundi(COMMAND_ROW_SEPARATION * _scale))
	for button: Button in _buttons:
		_apply_button(button)


func _apply_button(button: Button) -> void:
	if button == null or not is_instance_valid(button) or not button.has_meta(COMMAND_BASE_SIZE_META):
		return
	var base_size := button.get_meta(COMMAND_BASE_SIZE_META) as Vector2
	button.custom_minimum_size = base_size * _scale
	button.add_theme_font_size_override("font_size", roundi(COMMAND_FONT_SIZE * _scale))
