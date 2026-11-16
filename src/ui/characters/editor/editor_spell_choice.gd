## One selectable spell in the editor: a check box and the spell's name on a card.
## Hover or focus asks the owner to preview it without changing the selection.

class_name EditorSpellChoice
extends Button

signal previewed(choice: EditorSpellChoice)

## The bound spell row: id, name, description, known, level and its detached view.
var spell: Dictionary = {}

@onready var _name: Label = %Name
@onready var _check: Control = %Check


func _ready() -> void:
	toggled.connect(func(_pressed: bool) -> void: _refresh())
	focus_entered.connect(func() -> void: previewed.emit(self))
	mouse_entered.connect(func() -> void: previewed.emit(self))
	_check.draw.connect(_draw_check)
	_refresh()


## Call after the choice is in the tree.
func bind(row: Dictionary, editable: bool) -> void:
	spell = row
	set_pressed_no_signal(bool(row.get("known", false)))
	disabled = not editable
	tooltip_text = String(row.get("name", ""))
	_refresh()


func _refresh() -> void:
	_name.text = String(spell.get("name", ""))
	_name.theme_type_variation = &"VaultStatusGold" if button_pressed else &"VaultText"
	_check.queue_redraw()


## Drawn rather than typed: no bundled font carries a check mark.
func _draw_check() -> void:
	var box := Rect2(Vector2.ZERO, _check.size).grow(-1.0)
	if not button_pressed:
		_check.draw_rect(box, _check.get_theme_color(&"font_color", &"VaultStatusMuted"), false, 1.5)
		return
	_check.draw_rect(box, _check.get_theme_color(&"font_color", &"VaultStatusGold"))
	var unit := box.size.x / 14.0
	var tick := PackedVector2Array([box.position + Vector2(3.0, 7.4) * unit, box.position + Vector2(6.0, 10.4) * unit, box.position + Vector2(11.2, 3.8) * unit])
	_check.draw_polyline(tick, _check.get_theme_color(&"font_color", &"VaultPromptGlyph"), maxf(2.0, 2.0 * unit))
