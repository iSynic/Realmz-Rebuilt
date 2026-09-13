## Defines controller bindings and presentation-only input tuning.

class_name ControllerPreferences
extends RefCounted

const PROMPT_AUTO: String = "auto"
const PROMPT_XBOX: String = "xbox"
const PROMPT_PLAYSTATION: String = "playstation"
const PROMPT_SWITCH: String = "switch"
const PROMPT_GENERIC: String = "generic"
const PROMPT_FAMILIES: Array[String] = [PROMPT_AUTO, PROMPT_XBOX, PROMPT_PLAYSTATION, PROMPT_SWITCH, PROMPT_GENERIC]

const BINDING_BUTTON: String = "button"
const BINDING_AXIS: String = "axis"
const ACTIONS: Array[StringName] = [
	&"realmz_controller_confirm",
	&"realmz_controller_back",
	&"realmz_controller_action_radial",
	&"realmz_controller_workspace_radial",
	&"realmz_controller_section_previous",
	&"realmz_controller_section_next",
	&"realmz_controller_character_previous",
	&"realmz_controller_character_next",
	&"realmz_controller_inspect",
	&"realmz_controller_system",
	&"realmz_controller_up",
	&"realmz_controller_down",
	&"realmz_controller_left",
	&"realmz_controller_right",
	&"realmz_controller_scroll_up",
	&"realmz_controller_scroll_down",
	&"realmz_controller_scroll_left",
	&"realmz_controller_scroll_right",
]
const REQUIRED_ACTIONS: Array[StringName] = [
	&"realmz_controller_confirm",
	&"realmz_controller_back",
	&"realmz_controller_up",
	&"realmz_controller_down",
	&"realmz_controller_left",
	&"realmz_controller_right",
]

const DEFAULT_STICK_DEAD_ZONE: float = 0.25
const DEFAULT_RELEASE_HYSTERESIS: float = 0.08
const DEFAULT_REPEAT_INITIAL_MS: int = 350
const DEFAULT_REPEAT_INTERVAL_MS: int = 100

var prompt_family: String = PROMPT_AUTO
var left_stick_dead_zone: float = DEFAULT_STICK_DEAD_ZONE
var right_stick_dead_zone: float = DEFAULT_STICK_DEAD_ZONE
var release_hysteresis: float = DEFAULT_RELEASE_HYSTERESIS
var repeat_initial_ms: int = DEFAULT_REPEAT_INITIAL_MS
var repeat_interval_ms: int = DEFAULT_REPEAT_INTERVAL_MS
var bindings: Array[Dictionary] = default_bindings()


func duplicate_value() -> ControllerPreferences:
	return from_data(to_data())


func to_data() -> Dictionary:
	return {
		"promptFamily": prompt_family,
		"leftStickDeadZone": left_stick_dead_zone,
		"rightStickDeadZone": right_stick_dead_zone,
		"releaseHysteresis": release_hysteresis,
		"repeatInitialMs": repeat_initial_ms,
		"repeatIntervalMs": repeat_interval_ms,
		"bindings": bindings.duplicate(true),
	}


static func from_data(data: Variant) -> ControllerPreferences:
	if not data is Dictionary or not _data_is_valid(data):
		return null
	var value := ControllerPreferences.new()
	value.prompt_family = String(data["promptFamily"])
	value.left_stick_dead_zone = float(data["leftStickDeadZone"])
	value.right_stick_dead_zone = float(data["rightStickDeadZone"])
	value.release_hysteresis = float(data["releaseHysteresis"])
	value.repeat_initial_ms = int(data["repeatInitialMs"])
	value.repeat_interval_ms = int(data["repeatIntervalMs"])
	value.bindings.assign((data["bindings"] as Array).duplicate(true))
	return value


func required_navigation_is_reachable() -> bool:
	for action_id: StringName in REQUIRED_ACTIONS:
		if not bindings.any(func(binding: Dictionary) -> bool: return StringName(binding.get("action", "")) == action_id):
			return false
	return true


func conflicts() -> Array[Dictionary]:
	var owners: Dictionary = {}
	var result: Array[Dictionary] = []
	for binding: Dictionary in bindings:
		var physical_key := "%s:%d:%d" % [binding.get("kind", ""), int(binding.get("code", -1)), int(binding.get("direction", 0))]
		var action_id := StringName(binding.get("action", ""))
		if owners.has(physical_key) and owners[physical_key] != action_id:
			result.append({"binding": physical_key, "firstAction": owners[physical_key], "secondAction": action_id})
		else:
			owners[physical_key] = action_id
	return result


static func default_bindings() -> Array[Dictionary]:
	return [
		_button(&"realmz_controller_confirm", JOY_BUTTON_A),
		_button(&"realmz_controller_back", JOY_BUTTON_B),
		_button(&"realmz_controller_action_radial", JOY_BUTTON_X),
		_button(&"realmz_controller_workspace_radial", JOY_BUTTON_Y),
		_button(&"realmz_controller_section_previous", JOY_BUTTON_LEFT_SHOULDER),
		_button(&"realmz_controller_section_next", JOY_BUTTON_RIGHT_SHOULDER),
		_axis(&"realmz_controller_character_previous", JOY_AXIS_TRIGGER_LEFT, 1),
		_axis(&"realmz_controller_character_next", JOY_AXIS_TRIGGER_RIGHT, 1),
		_button(&"realmz_controller_inspect", JOY_BUTTON_RIGHT_STICK),
		_button(&"realmz_controller_system", JOY_BUTTON_START),
		_button(&"realmz_controller_up", JOY_BUTTON_DPAD_UP),
		_button(&"realmz_controller_down", JOY_BUTTON_DPAD_DOWN),
		_button(&"realmz_controller_left", JOY_BUTTON_DPAD_LEFT),
		_button(&"realmz_controller_right", JOY_BUTTON_DPAD_RIGHT),
		_axis(&"realmz_controller_up", JOY_AXIS_LEFT_Y, -1),
		_axis(&"realmz_controller_down", JOY_AXIS_LEFT_Y, 1),
		_axis(&"realmz_controller_left", JOY_AXIS_LEFT_X, -1),
		_axis(&"realmz_controller_right", JOY_AXIS_LEFT_X, 1),
		_axis(&"realmz_controller_scroll_up", JOY_AXIS_RIGHT_Y, -1),
		_axis(&"realmz_controller_scroll_down", JOY_AXIS_RIGHT_Y, 1),
		_axis(&"realmz_controller_scroll_left", JOY_AXIS_RIGHT_X, -1),
		_axis(&"realmz_controller_scroll_right", JOY_AXIS_RIGHT_X, 1),
	]


static func _button(action_id: StringName, code: JoyButton) -> Dictionary:
	return {"action": String(action_id), "kind": BINDING_BUTTON, "code": int(code), "direction": 0}


static func _axis(action_id: StringName, code: JoyAxis, direction: int) -> Dictionary:
	return {"action": String(action_id), "kind": BINDING_AXIS, "code": int(code), "direction": direction}


static func _data_is_valid(data: Dictionary) -> bool:
	if data.get("promptFamily") not in PROMPT_FAMILIES:
		return false
	for field: String in ["leftStickDeadZone", "rightStickDeadZone", "releaseHysteresis"]:
		if not data.get(field) is float:
			return false
	if float(data["leftStickDeadZone"]) < 0.1 or float(data["leftStickDeadZone"]) > 0.9 or float(data["rightStickDeadZone"]) < 0.1 or float(data["rightStickDeadZone"]) > 0.9:
		return false
	if float(data["releaseHysteresis"]) < 0.0 or float(data["releaseHysteresis"]) >= minf(float(data["leftStickDeadZone"]), float(data["rightStickDeadZone"])):
		return false
	if not _whole_number_in_range(data.get("repeatInitialMs"), 150, 1000) or not _whole_number_in_range(data.get("repeatIntervalMs"), 50, 500):
		return false
	if not data.get("bindings") is Array:
		return false
	for binding: Variant in data["bindings"]:
		if not _binding_is_valid(binding):
			return false
	var candidate := ControllerPreferences.new()
	candidate.bindings.assign((data["bindings"] as Array).duplicate(true))
	return candidate.required_navigation_is_reachable()


static func _binding_is_valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var binding := value as Dictionary
	if binding.size() != 4 or StringName(binding.get("action", "")) not in ACTIONS or binding.get("kind") not in [BINDING_BUTTON, BINDING_AXIS]:
		return false
	if not _whole_number_in_range(binding.get("code"), 0, 255) or not _whole_number_in_range(binding.get("direction"), -1, 1):
		return false
	return int(binding["direction"]) == 0 if binding["kind"] == BINDING_BUTTON else abs(int(binding["direction"])) == 1


static func _whole_number_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if not value is int and not value is float:
		return false
	return float(int(value)) == float(value) and int(value) >= minimum and int(value) <= maximum
