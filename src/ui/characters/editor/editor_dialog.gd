## The editor's modal: leave, discard, conflict, Level Up, age change and spell choice.
## Three scene-authored buttons cover every dialog; Back always chooses the secondary one.

class_name EditorDialog
extends Control

signal chosen(action: StringName)

@export var row_scene: PackedScene
@export var choice_scene: PackedScene

var _actions := {}
var _back_action: StringName = &""
var _choice_level := 1

@onready var _title: Label = %Title
@onready var _message: Label = %Message
@onready var _rows: GridContainer = %Rows
@onready var _spell_area: VBoxContainer = %SpellArea
@onready var _spell_count: Label = %SpellCount
@onready var _preview_name: Label = %PreviewName
@onready var _preview_meta: Label = %PreviewMeta
@onready var _preview_facts: GridContainer = %Facts
@onready var _preview_text: Label = %PreviewText
@onready var _spell_choices: GridContainer = %SpellChoices
@onready var _choice_rail: HFlowContainer = %ChoiceRail
@onready var _warning: Label = %Warning
@onready var _buttons: Dictionary = {&"secondary": %Secondary, &"tertiary": %Tertiary, &"primary": %Primary}


func _ready() -> void:
	for role: StringName in _buttons:
		(_buttons[role] as Button).pressed.connect(_press.bind(role))


## `buttons` maps roles (&"secondary", &"tertiary", &"primary") to {id, text, disabled?}.
func open(title: String, message: String, rows: Array[Dictionary], buttons: Dictionary, warning: String = "") -> void:
	_title.text = title
	_message.text = message
	_message.visible = not message.is_empty()
	_bind_rows(rows)
	_spell_area.visible = false
	_warning.text = warning
	_warning.visible = not warning.is_empty()
	_actions.clear()
	for role: StringName in _buttons:
		var button := _buttons[role] as Button
		var spec := buttons.get(role, {}) as Dictionary
		button.visible = not spec.is_empty()
		if spec.is_empty():
			continue
		_actions[role] = spec.id
		button.text = String(spec.text)
		button.disabled = bool(spec.get("disabled", false))
	_back_action = _actions.get(&"secondary", &"")
	show()
	var focus := _buttons[&"primary"] as Button
	if not focus.visible or focus.disabled:
		focus = _buttons[&"secondary"] as Button
	focus.grab_focus.call_deferred()


## The post-Level Up spell choice over this caster's spells, filtered by the shared
## Spell Level rail. The editor charges no points; selections on hidden levels persist.
func open_spell_choice(title: String, message: String, spells: Array[Dictionary]) -> void:
	open(title, message, [], {&"secondary": {"id": &"keep_spells", "text": "Keep current spells"}, &"primary": {"id": &"confirm_spells", "text": "Confirm spells"}})
	for child: Node in _spell_choices.get_children():
		_spell_choices.remove_child(child)
		child.queue_free()
	var levels: Array[int] = []
	for spell: Dictionary in spells:
		if not levels.has(int(spell.level)):
			levels.append(int(spell.level))
		var choice := choice_scene.instantiate() as EditorSpellChoice
		choice.name = "Choice_%s" % String(spell.id).validate_node_name()
		_spell_choices.add_child(choice)
		choice.bind(spell, true)
		choice.toggled.connect(func(_pressed: bool) -> void: _refresh_count())
		choice.previewed.connect(_preview)
	levels.sort()
	_choice_level = levels[0] if not levels.is_empty() else 1
	for level: int in range(1, 8):
		ClassicSpellSelectionChrome.bind_level_button(_choice_rail.get_node("SpellLevel%d" % level) as Button, level, level == _choice_level, levels.has(level), _show_choice_level.bind(level, levels), "No level %d spells to choose." % level)
	_spell_area.visible = true
	_show_choice_level(_choice_level, levels)
	_refresh_count()


## Fits the spell choice inside 800x600: one list column, a shorter list and a narrower panel.
func apply_compact(compact: bool) -> void:
	_spell_choices.columns = 1 if compact else 2
	UiSizing.minimum_size(_spell_area, Vector2(640 if compact else 736, 0))
	UiSizing.minimum_size(%SpellListColumn as Control, Vector2(270 if compact else 420, 0))
	UiSizing.minimum_size(%SpellListScroll as Control, Vector2(0, 232 if compact else 340))


func selected_spells() -> Array[String]:
	var result: Array[String] = []
	for child: Node in _spell_choices.get_children():
		if (child as EditorSpellChoice).button_pressed:
			result.append(String((child as EditorSpellChoice).spell.id))
	return result


## Escape/Back chooses the visible secondary action; returns false when closed.
func handle_back() -> bool:
	if not visible:
		return false
	if _back_action != &"":
		_choose(_back_action)
	return true


func _bind_rows(rows: Array[Dictionary]) -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for row: Dictionary in rows:
		var instance := row_scene.instantiate() as EditorDialogRow
		_rows.add_child(instance)
		instance.bind(row)
	_rows.visible = not rows.is_empty()


func _show_choice_level(level: int, levels: Array[int]) -> void:
	_choice_level = level
	for index: int in range(1, 8):
		(_choice_rail.get_node("SpellLevel%d" % index) as Button).set_pressed_no_signal(index == level and levels.has(index))
	var first: EditorSpellChoice = null
	for child: Node in _spell_choices.get_children():
		var choice := child as EditorSpellChoice
		choice.visible = int(choice.spell.level) == level
		if choice.visible and first == null:
			first = choice
	if first != null:
		_preview(first)


## Shows one spell's facts at power 1 beside the list; choosing is a separate click.
func _preview(choice: EditorSpellChoice) -> void:
	var view := choice.spell.get("view") as SpellView
	_preview_name.text = String(choice.spell.name)
	_preview_text.text = String(choice.spell.description)
	_preview_meta.text = "Level %d · values at power 1" % int(choice.spell.level)
	_preview_facts.visible = view != null
	if view == null:
		return
	var cast_in := "Combat and camp" if view.castable_in_combat and view.castable_in_camp else "Combat" if view.castable_in_combat else "Camp" if view.castable_in_camp else "—"
	var values := {
		"Cost": "%d per power level" % SpellDetailFormatter.cast_cost(view, 1),
		"Target": SpellDetailFormatter.target_label(view),
		"Range": str(absi(view.range_min + view.range_max)),
		"Damage": SpellDetailFormatter.scaled_pair(view.damage_min, view.damage_max, view.power_damage_min, view.power_damage_max, 1),
		"Duration": SpellDetailFormatter.scaled_pair(view.duration_min, view.duration_max, view.power_duration_min, view.power_duration_max, 1, true),
		"Resist": SpellDetailFormatter.magic_resistance_label(view, 1),
		"Save": SpellDetailFormatter.saving_throw_label(view, 1),
		"CastIn": cast_in,
	}
	for key: String in values:
		(_preview_facts.get_node("%sValue" % key) as Label).text = String(values[key])


func _refresh_count() -> void:
	var count := selected_spells().size()
	_spell_count.text = "%d spell%s chosen" % [count, "" if count == 1 else "s"]


func _press(role: StringName) -> void:
	_choose(_actions.get(role, &""))


func _choose(action: StringName) -> void:
	hide()
	chosen.emit(action)
