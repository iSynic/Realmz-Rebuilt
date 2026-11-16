## One listed draft change with its own Undo (disabled with a reason when it must wait).

class_name EditorChangeRow
extends VBoxContainer

signal undo_requested(index: int)

var _index := -1

@onready var _label: Label = %ChangeLabel
@onready var _detail: ArrowLabel = %Detail
@onready var _undo: Button = %Undo
@onready var _reason: Label = %Reason


func _ready() -> void:
	_undo.pressed.connect(func() -> void: undo_requested.emit(_index))


func bind(index: int, change: Dictionary) -> void:
	_index = index
	_label.text = String(change.label)
	_detail.set_arrow_text(String(change.detail), 13, &"VaultStatusGold")
	_label.tooltip_text = "%s · %s" % [_label.text, String(change.detail)]
	_undo.disabled = not bool(change.canUndo)
	_undo.tooltip_text = String(change.undoReason) if _undo.disabled else "Undo this change."
	_reason.text = String(change.undoReason)
	_reason.visible = _undo.disabled and not _reason.text.is_empty()
