## Presents modal controller-only text editing without submitting the owning workflow.

class_name ControllerQwertyEditor
extends Control

## Modal presentation-only text editor for LineEdit and TextEdit targets.

signal completed
signal cancelled

const PAGE_NAMES: Array[String] = ["lowercase", "uppercase", "numbers", "punctuation", "accents"]
const PAGE_KEYS: Array[Array] = [
	["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "a", "s", "d", "f", "g", "h", "j", "k", "l", "z", "x", "c", "v", "b", "n", "m"],
	["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "A", "S", "D", "F", "G", "H", "J", "K", "L", "Z", "X", "C", "V", "B", "N", "M"],
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "+", "=", "_", "#", "%", "&", "*", "(", ")"],
	[".", ",", "!", "?", ":", ";", "'", "\"", "@", "/", "\\", "[", "]", "{", "}", "<", ">", "|", "~", "`"],
	["á", "é", "í", "ó", "ú", "à", "è", "ì", "ò", "ù", "ä", "ë", "ï", "ö", "ü", "ñ", "ç", "å", "ø", "ß"]
]

@onready var _draft_preview: TextEdit = %DraftPreview
@onready var _page_label: Label = %PageLabel
@onready var _caret_label: Label = %CaretLabel
@onready var _key_grid: GridContainer = %KeyGrid
@onready var _space_button: Button = %Space
@onready var _line_break_button: Button = $Card/Content/EditRow/LineBreak
@onready var _delete_button: Button = %Delete
@onready var _left_button: Button = %CaretLeft
@onready var _right_button: Button = %CaretRight
@onready var _previous_page_button: Button = %PreviousPage
@onready var _next_page_button: Button = %NextPage
@onready var _done_button: Button = %Done
@onready var _cancel_button: Button = %Cancel

var _target: Control
var _original_text: String = ""
var _draft_text: String = ""
var _caret_offset: int = 0
var _max_length: int = -1
var _page: int = 0
var _open: bool = false
var _focus_navigator := ControllerFocusNavigator.new()


func _ready() -> void:
	visible = false
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_space_button.pressed.connect(func() -> void: confirm_key(" "))
	_line_break_button.pressed.connect(func() -> void: confirm_key("\n"))
	_delete_button.pressed.connect(backspace)
	_left_button.pressed.connect(caret_left)
	_right_button.pressed.connect(caret_right)
	_previous_page_button.pressed.connect(previous_page)
	_next_page_button.pressed.connect(next_page)
	_done_button.pressed.connect(done)
	_cancel_button.pressed.connect(cancel)
	_rebuild_key_grid()


func open_for(field: Control) -> bool:
	if not (field is LineEdit or field is TextEdit):
		return false
	_target = field
	_original_text = String(field.get("text"))
	_draft_text = _original_text
	_caret_offset = _read_caret_offset(field, _draft_text)
	_max_length = (field as LineEdit).max_length if field is LineEdit else -1
	_page = 0
	_open = true
	visible = true
	_update_display()
	_focus_first_key.call_deferred()
	return true


func is_open() -> bool:
	return _open


func confirm_focused() -> bool:
	if not _open:
		return false
	var focused := get_viewport().gui_get_focus_owner()
	if focused is BaseButton and is_ancestor_of(focused) and not (focused as BaseButton).disabled:
		(focused as BaseButton).pressed.emit()
		return true
	return false


func confirm_key(key: String) -> void:
	if not _open or key.is_empty():
		return
	if key == "\n" and _target is LineEdit:
		return
	if _max_length >= 0 and _draft_text.length() >= _max_length:
		return
	_draft_text = _draft_text.insert(_caret_offset, key)
	_caret_offset += key.length()
	_update_display()


func move_direction(direction: Vector2) -> void:
	if not _open or direction.is_zero_approx():
		return
	_focus_navigator.move_geometric(self, Vector2i(signi(roundi(direction.x)), signi(roundi(direction.y))))


func previous_page() -> void:
	_page = posmod(_page - 1, PAGE_KEYS.size())
	_rebuild_key_grid()


func next_page() -> void:
	_page = (_page + 1) % PAGE_KEYS.size()
	_rebuild_key_grid()


func backspace() -> void:
	if not _open or _caret_offset <= 0:
		return
	_draft_text = _draft_text.erase(_caret_offset - 1, 1)
	_caret_offset -= 1
	_update_display()


func caret_left() -> void:
	_caret_offset = maxi(0, _caret_offset - 1)
	_update_display()


func caret_right() -> void:
	_caret_offset = mini(_draft_text.length(), _caret_offset + 1)
	_update_display()


func done() -> void:
	if not _open:
		return
	_write_target(_draft_text, _caret_offset)
	_open = false
	visible = false
	completed.emit()


func cancel() -> void:
	if not _open:
		return
	var restore_offset := 0
	if _target != null and is_instance_valid(_target):
		restore_offset = _read_caret_offset(_target, _original_text)
	_write_target(_original_text, restore_offset)
	_open = false
	visible = false
	cancelled.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_ESCAPE: cancel()
		KEY_ENTER, KEY_KP_ENTER: done()
		KEY_BACKSPACE: backspace()
		KEY_LEFT: caret_left()
		KEY_RIGHT: caret_right()
		KEY_PAGEUP: previous_page()
		KEY_PAGEDOWN: next_page()
		_: return
	get_viewport().set_input_as_handled()


func _rebuild_key_grid() -> void:
	if not is_node_ready():
		return
	for child: Node in _key_grid.get_children():
		child.queue_free()
	for key: String in PAGE_KEYS[_page]:
		var button := Button.new()
		button.text = key
		button.custom_minimum_size = Vector2(54.0, 38.0)
		button.focus_mode = Control.FOCUS_ALL
		var key_value := key
		button.pressed.connect(func() -> void: confirm_key(key_value))
		_key_grid.add_child(button)
	_page_label.text = PAGE_NAMES[_page]
	_focus_first_key.call_deferred()


func _update_display() -> void:
	if not is_node_ready():
		return
	_draft_preview.text = _draft_text
	_caret_label.text = "Caret %d / %d" % [_caret_offset, _draft_text.length()]
	_page_label.text = PAGE_NAMES[_page]


func _focus_first_key() -> void:
	if _open and _key_grid.get_child_count() > 0:
		(_key_grid.get_child(0) as Button).grab_focus()


func _read_caret_offset(field: Control, text: String) -> int:
	if field is LineEdit:
		return clampi((field as LineEdit).caret_column, 0, text.length())
	var editor := field as TextEdit
	var offset := 0
	var line := mini(editor.get_caret_line(), editor.get_line_count() - 1)
	for index: int in range(line):
		offset += editor.get_line(index).length() + 1
	return clampi(offset + editor.get_caret_column(), 0, text.length())


func _write_target(text: String, offset: int) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var previous_text := String(_target.get("text"))
	_target.set("text", text)
	if _target is LineEdit:
		var line_edit := _target as LineEdit
		line_edit.caret_column = clampi(offset, 0, text.length())
		if previous_text != text:
			line_edit.text_changed.emit(text)
	else:
		var editor := _target as TextEdit
		var remaining := clampi(offset, 0, text.length())
		var line := 0
		for part: String in text.split("\n"):
			if remaining <= part.length():
				break
			remaining -= part.length() + 1
			line += 1
		editor.set_caret_line(line)
		editor.set_caret_column(remaining)
		if previous_text != text:
			editor.text_changed.emit()
