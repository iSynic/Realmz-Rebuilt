## One Classic library item the editor can add; a disabled Add shows why.

class_name EditorCatalogRow
extends VBoxContainer

signal add_requested(definition_id: String)

var _definition_id := ""

@onready var _name: Label = %ItemName
@onready var _weight: Label = %Weight
@onready var _add: Button = %Add
@onready var _reason: Label = %Reason


func _ready() -> void:
	_add.pressed.connect(func() -> void: add_requested.emit(_definition_id))


func bind(row: Dictionary) -> void:
	_definition_id = String(row.definitionId)
	_name.text = String(row.name)
	_weight.text = "wt %d" % int(row.weight)
	var reason := String(row.reason)
	_add.disabled = not reason.is_empty()
	_add.tooltip_text = reason if _add.disabled else "Add %s, identified and unequipped." % _name.text
	_name.tooltip_text = _add.tooltip_text
	_reason.text = reason
	_reason.visible = _add.disabled
