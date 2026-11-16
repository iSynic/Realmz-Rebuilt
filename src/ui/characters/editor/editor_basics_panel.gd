## Basics tab: attributes, stamina and spell points, armor, money and read-only key stats.
## Each scene-authored stepper names its field in `metadata/field`.

class_name EditorBasicsPanel
extends ScrollContainer

signal command(operation: Dictionary)
signal number_requested(spec: Dictionary)


var _session: CharacterEditorSession

@onready var _load_text: Label = %LoadText


func _ready() -> void:
	resized.connect(_fit_columns)
	for stepper: EditorStatStepper in _steppers():
		var field: StringName = stepper.get_meta(&"field")
		stepper.stepped.connect(_step.bind(field))
		stepper.edit_requested.connect(_request_number.bind(field))


func bind(session: CharacterEditorSession) -> void:
	_session = session
	var queries := session.queries
	for stepper: EditorStatStepper in _steppers():
		var field: StringName = stepper.get_meta(&"field")
		var facts := queries.field(field)
		var limits: Vector2i = facts.range
		stepper.bind(CharacterEditLimits.LABELS[field], facts.value, _hint(field, facts), facts.value != facts.base, facts.lock, limits)
	_load_text.text = "%s · Brawn sets the limit" % queries.load_text()
	var view := queries.character_view()
	for pair: Array in [["HandToHand", view.hand_to_hand], ["ToHit", view.to_hit], ["Dodge", view.dodge], ["Missile", view.missile], ["MagicResistance", view.magic_resistance], ["Attacks", view.normal_attacks], ["Movement", view.maximum_movement]]:
		(get_node("Content/KeyStats/Row/%s/Value" % pair[0]) as Label).text = ("%+d" % pair[1]) if pair[0] == "ToHit" else str(pair[1])
	_fit_columns()


## Reflows the stat grids to this tab's width.
func _fit_columns() -> void:
	var width := size.x - get_v_scroll_bar().size.x
	for grid: GridContainer in [%Attributes, %Vitals, %Money]:
		EditorStatStepper.fit_columns(grid, width)


func _hint(field: StringName, facts: Dictionary) -> String:
	var limits: Vector2i = facts.range
	# Classic's signed-short storage limits aren't game limits, so an open end isn't printed.
	var text := "%s–%s" % [CharacterEditLimits.group_digits(limits.x), CharacterEditLimits.group_digits(limits.y)]
	if limits.y >= 32767:
		text = "" if limits.x <= -32768 else "%s or more" % CharacterEditLimits.group_digits(limits.x)
	if field == &"brawn" and int(facts.magic) != 0:
		text += " (%+d magic)" % int(facts.magic)
	elif field == &"brawn":
		text += " now"
	elif field in CharacterEditLimits.MONEY:
		text += " · weight %d" % CharacterEditLimits.money_weight(field)
	if facts.value != facts.base:
		text = "was %s · %s" % [CharacterEditLimits.group_digits(facts.base), text] if not text.is_empty() else "was %s" % CharacterEditLimits.group_digits(facts.base)
	return text


func _step(delta: int, field: StringName) -> void:
	var facts := _session.queries.field(field)
	var limits: Vector2i = facts.range
	command.emit({"kind": &"field", "field": field, "value": clampi(int(facts.value) + delta, limits.x, limits.y)})


func _request_number(field: StringName) -> void:
	var facts := _session.queries.field(field)
	number_requested.emit({"title": CharacterEditLimits.LABELS[field], "value": facts.value, "range": facts.range, "operation": {"kind": &"field", "field": field}})


func _steppers() -> Array[EditorStatStepper]:
	var result: Array[EditorStatStepper] = []
	for grid: Node in [%Attributes, %Vitals, %Money]:
		for child: Node in grid.get_children():
			if child is EditorStatStepper:
				result.append(child)
	return result
