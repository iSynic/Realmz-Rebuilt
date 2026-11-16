## Dresses, names and registers the battle deck's authored command buttons.
class_name BattleCommandBinder
extends RefCounted

const COMMAND_HEIGHT := 30.0
const VIEW_COMMAND_HEIGHT := 24.0
const PRIMARY_COLOR := Color("f0ce59")
const VIEW_COLOR := Color("63d8e7")
const TURN_COLOR := Color("8fe080")

## Every bound command in binding order; the controller radial lists them.
var buttons: Array[Button] = []
var _availability: BattleCommandAvailability
var _scaling: BattleCommandScaleController
var _submit: Callable


## `submit` receives the typed response body of a pressed gameplay command.
func _init(availability: BattleCommandAvailability, scaling: BattleCommandScaleController, submit: Callable) -> void:
	_availability = availability
	_scaling = scaling
	_submit = submit


func clear() -> void:
	buttons.clear()
	_availability.clear()


## A gameplay command that submits `body` when pressed.
func response(button: Button, command_name: String, label: String, body: InteractionResponse.Body, enabled: bool, reason: String) -> void:
	action(button, command_name, label, enabled, reason)
	button.pressed.connect(func() -> void: _submit.call(body))


## A gameplay command whose press the deck handles itself.
func action(button: Button, command_name: String, label: String, enabled: bool, reason: String) -> void:
	button.text = label
	button.disabled = not enabled
	button.tooltip_text = reason if not enabled else ""
	name_command(button, command_name)


## A View command: presentation only, so it stays available while a response resolves.
func view_action(button: Button, text: String, action_id: StringName, perform: Callable) -> void:
	button.name = "CombatPresentation%s" % String(action_id).to_pascal_case()
	button.text = text
	buttons.append(button)
	_scaling.register_button(button, Vector2(0.0, VIEW_COMMAND_HEIGHT))
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if action_id == &"reveal_friends":
		color(button, VIEW_COLOR)
	button.pressed.connect(perform.bind(action_id))


func name_command(button: Button, command_name: String) -> void:
	_availability.register_button(button)
	button.name = "CombatCommand%s" % command_name
	if not buttons.has(button):
		buttons.append(button)
	button.theme_type_variation = &"BattleCommandButton"
	_scaling.register_button(button, Vector2(0.0, COMMAND_HEIGHT))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func color(button: Button, value: Color) -> void:
	button.add_theme_color_override("font_color", value)
	button.add_theme_color_override("font_hover_color", value.lightened(0.22))
