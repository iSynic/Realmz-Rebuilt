## Applies the responsive scale policy to the authored battle command deck.

class_name BattleCommandScaleController
extends RefCounted

const COMMAND_BASE_SIZE_META: StringName = &"battle_command_base_size"
const COMMAND_FONT_SIZE := 12.0
const COMMAND_GROUP_HEIGHT := 100.0
const COMMAND_GROUP_SEPARATION := 6.0
const COMMAND_COLUMN_SEPARATION := 4.0
const COMMAND_ROW_SEPARATION := 3.0
const COMPACT_COMMAND_FONT_SIZE := 13.0
const COMPACT_COMMAND_GROUP_HEIGHT := 88.0
const COMPACT_COMMAND_GROUP_SEPARATION := 8.0
const COMPACT_COMMAND_COLUMN_SEPARATION := 1.0
const COMPACT_COMMAND_ROW_SEPARATION := 3.0
const COMPACT_COMMAND_HEIGHT := 26.0

## The combat HUD preference: in the modular layout each command group is a bucket whose
## heading folds it away. Which groups are folded is remembered for the session.
static var modular := false
static var folded: Dictionary = {0: true, 2: true}

var _scale := 1.0
var _compact := false
var _shelf: HBoxContainer
var _panels: Array[Control] = []
var _columns: Array[VBoxContainer] = []
var _headings: Array[Label] = []
var _rows: Array[HBoxContainer] = []
var _buttons: Array[Button] = []


static func standalone_profile(command_scale: float) -> UiLayoutProfile:
	return UiLayoutProfile.for_viewport(Vector2(1280, 720) * command_scale, PresentationSettings.UI_SCALE_AUTO)


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
		var heading := column.get_child(0) as Label
		_headings.append(heading)
		if not heading.has_meta(&"bucket_title"):
			heading.set_meta(&"bucket_title", heading.text)
			heading.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			heading.gui_input.connect(_on_heading_input.bind(_headings.size() - 1))
	apply()


func set_layout(value: float, compact: bool) -> void:
	_scale = clampf(value, 1.0, 3.0)
	_compact = compact
	apply()


func register_button(button: Button, base_size: Vector2) -> void:
	button.set_meta(COMMAND_BASE_SIZE_META, base_size)
	if not _buttons.has(button):
		_buttons.append(button)
	_apply_button(button)


func apply() -> void:
	if _shelf != null and is_instance_valid(_shelf):
		UiSizing.constant(_shelf, &"separation", roundi(COMPACT_COMMAND_GROUP_SEPARATION if _compact else COMMAND_GROUP_SEPARATION))
	for index: int in _panels.size():
		if is_instance_valid(_panels[index]):
			# A folded group is only as tall as its tab.
			var height := 0.0 if modular and RowFields.flag(folded, index) else COMPACT_COMMAND_GROUP_HEIGHT if _compact else COMMAND_GROUP_HEIGHT
			UiSizing.minimum_size(_panels[index], Vector2(0, height))
	for column: VBoxContainer in _columns:
		if is_instance_valid(column):
			UiSizing.constant(column, &"separation", roundi(COMPACT_COMMAND_COLUMN_SEPARATION if _compact else COMMAND_COLUMN_SEPARATION))
			(column.get_child(1) as HSeparator).visible = not _compact
	for heading: Label in _headings:
		if is_instance_valid(heading):
			UiSizing.font_size(heading, &"font_size", roundi(COMPACT_COMMAND_FONT_SIZE if _compact else COMMAND_FONT_SIZE))
	for row: HBoxContainer in _rows:
		if is_instance_valid(row):
			UiSizing.constant(row, &"separation", roundi(COMPACT_COMMAND_ROW_SEPARATION if _compact else COMMAND_ROW_SEPARATION))
	for button: Button in _buttons:
		_apply_button(button)
	_apply_buckets()
	if not modular and _panels.size() == 3 and is_instance_valid(_panels[0]) and is_instance_valid(_panels[2]):
		var view_panel := _panels[0]
		var tactics_panel := _panels[2]
		view_panel.custom_minimum_size.x = 0.0
		tactics_panel.custom_minimum_size.x = 0.0
		var side_width := maxf(view_panel.get_combined_minimum_size().x, tactics_panel.get_combined_minimum_size().x)
		UiSizing.minimum_size(view_panel, Vector2(side_width / _scale, view_panel.custom_minimum_size.y / _scale))
		UiSizing.minimum_size(tactics_panel, Vector2(side_width / _scale, tactics_panel.custom_minimum_size.y / _scale))


## Modular combat: a folded bucket shows only its heading as a tab; fixed combat shows every group.
func _apply_buckets() -> void:
	for index: int in _columns.size():
		var column := _columns[index]
		if not is_instance_valid(column) or index >= _headings.size(): continue
		var hidden := modular and RowFields.flag(folded, index)
		for child_index: int in range(1, column.get_child_count()):
			(column.get_child(child_index) as Control).visible = not hidden and (child_index != 1 or not _compact)
		var heading := _headings[index]
		var title: String = heading.get_meta(&"bucket_title", heading.text)
		heading.text = title if not modular else title + ("  ▸" if hidden else "  ▾")
		heading.mouse_filter = Control.MOUSE_FILTER_STOP if modular else Control.MOUSE_FILTER_IGNORE
		heading.tooltip_text = ("Show %s commands" if hidden else "Fold %s commands away") % title.capitalize() if modular else ""
		if modular and index < _panels.size() and is_instance_valid(_panels[index]): _panels[index].custom_minimum_size.x = 0.0


func _on_heading_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if modular and click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		folded[index] = not RowFields.flag(folded, index)
		apply()


func _apply_button(button: Button) -> void:
	if button == null or not is_instance_valid(button) or not button.has_meta(COMMAND_BASE_SIZE_META):
		return
	var base_size := button.get_meta(COMMAND_BASE_SIZE_META) as Vector2
	if _compact and base_size.y > 0.0:
		base_size.y = minf(base_size.y, COMPACT_COMMAND_HEIGHT)
	UiSizing.minimum_size(button, base_size)
	UiSizing.font_size(button, &"font_size", roundi(COMPACT_COMMAND_FONT_SIZE if _compact else COMMAND_FONT_SIZE))
	var profile := UiSizing.profile_for(button)
	var wrap := _compact and profile != null and profile.font_scale > profile.ui_scale
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	if wrap:
		var font := button.get_theme_font(&"font")
		var width := 0.0
		for word: String in button.text.split(" "):
			width = maxf(width, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size(&"font_size")).x)
		base_size.x = maxf(base_size.x, ceilf((width + button.get_theme_stylebox(&"normal").get_minimum_size().x) / profile.ui_scale))
		UiSizing.minimum_size(button, base_size)
