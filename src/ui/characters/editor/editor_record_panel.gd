## Record tab: age, gender, experience, prestige penalty, saving throws and skills.
## Age changes go through `age_requested` so a crossing of age groups is previewed first.

class_name EditorRecordPanel
extends ScrollContainer

signal command(operation: Dictionary)
signal number_requested(spec: Dictionary)
signal age_requested(years: int)


var _session: CharacterEditorSession

@onready var _male: Button = %Male
@onready var _female: Button = %Female
@onready var _gender_hint: Label = %GenderHint


func _ready() -> void:
	resized.connect(_fit_columns)
	for stepper: EditorStatStepper in _steppers():
		stepper.stepped.connect(_step.bind(stepper))
		stepper.edit_requested.connect(_request_number.bind(stepper))
	_male.pressed.connect(func() -> void: command.emit({"kind": &"gender", "value": 1}))
	_female.pressed.connect(func() -> void: command.emit({"kind": &"gender", "value": 2}))


func bind(session: CharacterEditorSession) -> void:
	_session = session
	var queries := session.queries
	var identity := queries.identity()
	_male.set_pressed_no_signal(identity.gender == 1)
	_female.set_pressed_no_signal(identity.gender == 2)
	_gender_hint.text = "Male or Female; no item limits gender"
	for stepper: EditorStatStepper in _steppers():
		var facts := _facts(stepper)
		var limits: Vector2i = facts.range
		var changed: bool = facts.value != facts.base
		var hint := String(facts.get("hint", "%d to %d" % [limits.x, limits.y]))
		if changed and not facts.has("hint"):
			hint = "was %d" % facts.base
		stepper.bind(String(facts.label), facts.value, hint, changed, String(facts.get("lock", "")), limits)
	_fit_columns()


## Reflows the stat grids to this tab's width.
func _fit_columns() -> void:
	var width := size.x - get_v_scroll_bar().size.x
	for grid: GridContainer in [%Life, %Saves, %Skills]:
		EditorStatStepper.fit_columns(grid, width)


## Label, value, base, range and hint for any stepper in this tab.
func _facts(stepper: EditorStatStepper) -> Dictionary:
	var queries := _session.queries
	if stepper.has_meta(&"kind"):
		var kind: StringName = stepper.get_meta(&"kind")
		var index: int = stepper.get_meta(&"index")
		var facts := queries.indexed(kind, index)
		facts["label"] = CharacterView.SAVE_NAMES[index] if kind == &"save" else CharacterView.ABILITY_NAMES[index]
		return facts
	var field: StringName = stepper.get_meta(&"field")
	if field == &"age":
		var age := queries.age()
		var limits: Vector2i = age.range
		return {"label": "Age", "value": age.years, "base": age.baseYears, "range": limits, "lock": age.lock,
			"hint": "%s · %s ages %d–%d" % [age.group, age.race, limits.x, limits.y]}
	var facts := queries.field(field)
	facts["label"] = CharacterEditLimits.LABELS[field]
	if field == &"experience":
		facts["hint"] = "−2.1 billion to 0 · %s" % String(queries.identity().experienceText).replace("XP to level", "to lvl")
	elif field == &"prestige_penalty":
		facts["hint"] = "0 to 2.1 billion · lowers prestige"
	if facts.value != facts.base:
		facts["hint"] = "was %s · %s" % [CharacterEditLimits.group_digits(facts.base), facts.get("hint", "")]
	return facts


func _step(delta: int, stepper: EditorStatStepper) -> void:
	var facts := _facts(stepper)
	var limits: Vector2i = facts.range
	_submit(stepper, clampi(int(facts.value) + delta, limits.x, limits.y))


func _request_number(stepper: EditorStatStepper) -> void:
	var facts := _facts(stepper)
	var operation := {"kind": &"age"} if stepper.get_meta(&"field", &"") == &"age" else _operation(stepper)
	number_requested.emit({"title": String(facts.label), "value": facts.value, "range": facts.range, "operation": operation})


func _submit(stepper: EditorStatStepper, value: int) -> void:
	if stepper.get_meta(&"field", &"") == &"age":
		age_requested.emit(value)
		return
	var operation := _operation(stepper)
	operation["value"] = value
	command.emit(operation)


func _operation(stepper: EditorStatStepper) -> Dictionary:
	if stepper.has_meta(&"kind"):
		return {"kind": stepper.get_meta(&"kind"), "index": stepper.get_meta(&"index")}
	return {"kind": &"field", "field": stepper.get_meta(&"field")}


func _steppers() -> Array[EditorStatStepper]:
	var result: Array[EditorStatStepper] = []
	for grid: Node in [%Life, %Saves, %Skills]:
		for child: Node in grid.get_children():
			if child is EditorStatStepper:
				result.append(child)
	return result
