## One editable number in the character editor: caption, − value +, and a range hint.
## Holding − or + repeats with growing steps; pressing the value asks for typed entry.

class_name EditorStatStepper
extends PanelContainer

signal stepped(delta: int)
signal edit_requested

@export var normal_style: StyleBox
@export var changed_style: StyleBox

var _hold_direction := 0
var _repeats := 0
## True once a hold has repeated or been interrupted, so its release adds no extra step.
var _held := false

@onready var caption: Label = %Caption
@onready var minus: Button = %Minus
@onready var value_button: Button = %Value
@onready var plus: Button = %Plus
@onready var hint: Label = %Hint
@onready var _repeat: Timer = %Repeat


func _ready() -> void:
	for direction: int in [-1, 1]:
		var button: Button = minus if direction < 0 else plus
		button.button_down.connect(_hold.bind(direction))
		button.button_up.connect(_repeat.stop)
		button.pressed.connect(_tap.bind(direction))
	value_button.pressed.connect(edit_requested.emit)
	_repeat.timeout.connect(_repeat_step)


## `lock` disables editing and explains why; `changed` highlights an edited value.
func bind(caption_text: String, value: int, hint_text: String, changed: bool, lock: String, limits: Vector2i) -> void:
	caption.text = caption_text.to_upper()
	value_button.text = CharacterEditLimits.group_digits(value)
	hint.text = lock if not lock.is_empty() else hint_text
	hint.tooltip_text = hint.text
	var locked := not lock.is_empty()
	minus.disabled = locked or value <= limits.x
	plus.disabled = locked or value >= limits.y
	value_button.disabled = locked
	value_button.tooltip_text = lock if locked else "Type %s (%s to %s)" % [caption_text.to_lower(), CharacterEditLimits.group_digits(limits.x), CharacterEditLimits.group_digits(limits.y)]
	add_theme_stylebox_override(&"panel", changed_style if changed else normal_style)
	value_button.add_theme_color_override(&"font_color", Color(1.0, 0.878, 0.569) if changed else Color(0.925, 0.925, 0.89))
	value_button.add_theme_color_override(&"font_disabled_color", Color(0.55, 0.6, 0.62))
	set_meta(&"accessible_value", "%s %d" % [caption_text, value])


func _hold(direction: int) -> void:
	_hold_direction = direction
	_repeats = 0
	_held = false
	_repeat.start(0.45)


## A single tap steps by one unless holding already repeated.
func _tap(direction: int) -> void:
	_repeat.stop()
	if not _held:
		stepped.emit(direction)
	_repeats = 0
	_held = false


func _repeat_step() -> void:
	var held := minus if _hold_direction < 0 else plus
	# A dialog that takes focus (such as the age-group preview) ends the hold.
	_held = true
	if held.disabled or not held.is_pressed() or not held.has_focus():
		return
	_repeats += 1
	var size := 1 if _repeats < 10 else (10 if _repeats < 30 else 100)
	stepped.emit(_hold_direction * size)
	_repeat.start(0.07)


## Gives `grid` as many columns as whole tiles fit in `width`, up to the scene-authored
## column count, so stat grids reflow at enlarged text instead of widening the editor.
static func fit_columns(grid: GridContainer, width: float) -> void:
	if not grid.has_meta(&"authored_columns"):
		grid.set_meta(&"authored_columns", grid.columns)
	var tile := 0.0
	for child: Node in grid.get_children():
		if child is Control and (child as Control).visible:
			tile = maxf(tile, (child as Control).get_combined_minimum_size().x)
	if tile <= 0.0 or width <= 0.0:
		return
	var gap := float(grid.get_theme_constant(&"h_separation"))
	var authored_columns: int = grid.get_meta(&"authored_columns")
	var fit := clampi(floori((width + gap) / (tile + gap)), 1, authored_columns)
	# Balance the rows: six tiles that can't share one row become 3 + 3, not 5 + 1.
	var count := grid.get_child_count()
	var columns := ceili(float(count) / float(ceili(float(count) / float(fit)))) if count > 0 else fit
	if grid.columns != columns:
		grid.columns = columns
