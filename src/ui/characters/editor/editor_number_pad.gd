## Typed number entry for the editor: keypad, keyboard and controller. A value outside
## the range stays open with the range explained; ± appears only for negative ranges.

class_name EditorNumberPad
extends Control

signal submitted(value: int)

var _range := Vector2i.ZERO
## The opening value is replaced by the first keypad digit, as a selected field would be.
var _replace_next := false

@onready var _title: Label = %Title
@onready var _field: LineEdit = %Field
@onready var _range_text: Label = %RangeText
@onready var _sign: Button = %Sign
@onready var _ok: Button = %Ok


func _ready() -> void:
	for digit: int in 10:
		var key := find_child("Key%d" % digit) as Button
		key.pressed.connect(_type.bind(str(digit)))
	_sign.pressed.connect(_switch_sign)
	(%Delete as Button).pressed.connect(_delete)
	_ok.pressed.connect(_submit)
	(%Cancel as Button).pressed.connect(hide)
	_field.text_submitted.connect(func(_text: String) -> void: _submit())
	_field.text_changed.connect(func(_text: String) -> void: _replace_next = false)


func open(title: String, value: int, limits: Vector2i) -> void:
	_range = limits
	_title.text = title
	_field.text = str(value)
	_range_text.text = "%s to %s" % [CharacterEditLimits.group_digits(limits.x), CharacterEditLimits.group_digits(limits.y)]
	_sign.visible = limits.x < 0
	_replace_next = true
	show()
	_field.grab_focus.call_deferred()
	_field.select_all.call_deferred()


func handle_back() -> bool:
	if not visible:
		return false
	hide()
	return true


func _type(digit: String) -> void:
	var text := "" if _replace_next or _field.text == "0" else _field.text
	_replace_next = false
	if text == "-0":
		text = "-"
	_field.text = text + digit
	_field.caret_column = _field.text.length()


func _switch_sign() -> void:
	_replace_next = false
	_field.text = _field.text.trim_prefix("-") if _field.text.begins_with("-") else "-" + _field.text
	_field.caret_column = _field.text.length()


func _delete() -> void:
	_field.text = "" if _replace_next else _field.text.left(_field.text.length() - 1)
	_replace_next = false
	_field.caret_column = _field.text.length()


func _submit() -> void:
	var text := _field.text.strip_edges().replace(",", "").replace("−", "-")
	var limits := "%s to %s" % [CharacterEditLimits.group_digits(_range.x), CharacterEditLimits.group_digits(_range.y)]
	if not text.is_valid_int():
		_range_text.text = "Enter a whole number from %s." % limits
		return
	var value := text.to_int()
	if value < _range.x or value > _range.y:
		var hint := " Experience counts up to 0, so enter it as a negative number." if _range.y == 0 and value > 0 else ""
		_range_text.text = "%s is outside %s.%s" % [CharacterEditLimits.group_digits(value), limits, hint]
		_field.grab_focus()
		return
	hide()
	submitted.emit(value)
