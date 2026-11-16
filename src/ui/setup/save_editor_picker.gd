## The save editor's chooser for a Character File or a traveling ally. Rows that can't be
## chosen stay listed, disabled, with their reason; focus shows that reason in full below.

class_name SaveEditorPicker
extends Control

signal chosen(id: String)

@export var row_scene: PackedScene

var _rows: Array[Dictionary] = []

@onready var _title: Label = %Title
@onready var _message: Label = %Message
@onready var _search: LineEdit = %Search
@onready var _list: VBoxContainer = %List
@onready var _empty: Label = %Empty
@onready var _detail: Label = %Detail


func _ready() -> void:
	(%Cancel as Button).pressed.connect(hide)
	_search.text_changed.connect(func(_text: String) -> void: _render())


## `rows`: {id, name, detail, reason}. A non-empty reason disables the row.
func open(title: String, message: String, rows: Array[Dictionary]) -> void:
	_title.text = title
	_message.text = message
	_rows = rows
	_search.text = ""
	_detail.text = ""
	show()
	_render()
	var first := _first_enabled()
	(first if first != null else %Cancel as Control).grab_focus.call_deferred()


## Escape/Back closes the picker; false when it was already closed.
func handle_back() -> bool:
	if not visible:
		return false
	hide()
	return true


func _render() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var filter := _search.text.strip_edges().to_lower()
	for row: Dictionary in _rows:
		if not filter.is_empty() and not String(row.name).to_lower().contains(filter):
			continue
		var reason := String(row.get("reason", ""))
		var button := row_scene.instantiate() as Button
		button.text = "%s   ·   %s" % [row.name, reason if not reason.is_empty() else String(row.get("detail", ""))]
		button.disabled = not reason.is_empty()
		button.tooltip_text = reason if not reason.is_empty() else String(row.get("detail", ""))
		var id := String(row.id)
		button.pressed.connect(func() -> void:
			hide()
			chosen.emit(id)
		)
		var detail := reason if not reason.is_empty() else String(row.get("detail", ""))
		button.focus_entered.connect(func() -> void: _detail.text = detail)
		button.mouse_entered.connect(func() -> void: _detail.text = detail)
		# A disabled row never takes focus; its reason stays on the row itself.
		button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
		_list.add_child(button)
	_empty.visible = _list.get_child_count() == 0


func _first_enabled() -> Button:
	for child: Node in _list.get_children():
		var button := child as Button
		if button != null and not button.disabled:
			return button
	return null
