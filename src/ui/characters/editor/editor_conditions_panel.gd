## Conditions tab: one scene-authored stepper per Classic character condition (40).
## Permanent race and class values (negative) stay locked.

class_name EditorConditionsPanel
extends ScrollContainer

signal command(operation: Dictionary)
signal number_requested(spec: Dictionary)

var _session: CharacterEditorSession
var _steppers: Array[EditorStatStepper] = []

@onready var _grid: GridContainer = %ConditionGrid


func bind(session: CharacterEditorSession) -> void:
	_session = session
	var rows := session.queries.conditions()
	for row: Dictionary in rows:
		var stepper := _steppers[int(row.index)]
		var locked: bool = row.locked
		var hint := "Permanent from race or class" if locked else ("was %d" % row.base if row.value != row.base else "0 to 32,767")
		stepper.bind(String(row.name), maxi(0, int(row.value)), hint, row.value != row.base, "Permanent · locked" if locked else "", CharacterEditLimits.CONDITION_RANGE)
		if locked:
			stepper.value_button.text = "Perm."
	_fit_columns()


func _ready() -> void:
	for child: Node in _grid.get_children():
		var stepper := child as EditorStatStepper
		var index := _steppers.size()
		stepper.stepped.connect(_step.bind(index))
		stepper.edit_requested.connect(_request_number.bind(index))
		_steppers.append(stepper)
	resized.connect(_fit_columns)


func _fit_columns() -> void:
	EditorStatStepper.fit_columns(_grid, size.x - get_v_scroll_bar().size.x)


func _step(delta: int, index: int) -> void:
	var row := _session.queries.conditions()[index]
	command.emit({"kind": &"condition", "index": index, "value": clampi(int(row.value) + delta, 0, CharacterEditLimits.CONDITION_RANGE.y)})


func _request_number(index: int) -> void:
	var row := _session.queries.conditions()[index]
	number_requested.emit({"title": String(row.name), "value": row.value, "range": CharacterEditLimits.CONDITION_RANGE, "operation": {"kind": &"condition", "index": index}})
