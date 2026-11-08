## Repeats one held money-transfer button at classic Realmz speed.
##
## Castle swap.c repeats its Swap step for as long as the button is held, limited only by
## redrawing. The first step fires on press; a short pause keeps a tap to exactly one step,
## then the step repeats once per frame until release, disablement or hiding.
class_name MoneyHoldRepeat
extends RefCounted

const FIRST_REPEAT_DELAY := 0.35
const STEP_INTERVAL := 1.0 / 60.0

var _timer: Timer
var _button: Button
var _step: Callable
var _mouse_hold := false


func _init(timer: Timer) -> void:
	_timer = timer
	if not _timer.timeout.is_connected(_repeat):
		_timer.timeout.connect(_repeat)


## Connects hold-to-repeat once; step is called for every repeat and must read current request facts.
func attach(button: Button, step: Callable) -> void:
	button.set_meta(&"hold_to_repeat", true)
	button.button_down.connect(start.bind(button, step))
	button.button_up.connect(stop)


func start(button: Button, step: Callable) -> void:
	stop()
	_button = button
	_step = step
	# A rebound or briefly hidden button can miss its release, so a pointer hold also ends with the mouse button.
	_mouse_hold = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	step.call()
	if _held():
		_timer.start(FIRST_REPEAT_DELAY)


func stop() -> void:
	if is_instance_valid(_timer):
		_timer.stop()
	_button = null
	_step = Callable()


func _repeat() -> void:
	if not _held():
		stop()
		return
	_step.call()
	if _held():
		_timer.start(STEP_INTERVAL)


func _held() -> bool:
	if _mouse_hold and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return false
	return is_instance_valid(_button) and not _button.disabled and _button.is_visible_in_tree() and is_instance_valid(_timer) and _timer.is_inside_tree() and _step.is_valid()
