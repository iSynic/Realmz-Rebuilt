## Keeps a controller draft intact until the player chooses how to leave.
extends Control

var _apply: Callable
var _discard: Callable
var _continuation: Callable
var _restore_focus: WeakRef
var _focus := ControllerFocusNavigator.new()


func _ready() -> void:
	%Apply.pressed.connect(resolve.bind(&"apply"))
	%Discard.pressed.connect(resolve.bind(&"discard"))
	%KeepEditing.pressed.connect(resolve.bind(&"keep"))


func defer_if_dirty(preferences: SystemScreenController, continuation: Callable) -> bool:
	if not preferences.has_dirty_controller_draft(): return false
	open(preferences.apply_controller_draft, preferences.discard_controller_draft, continuation)
	return true


func open(apply: Callable, discard: Callable, continuation: Callable) -> void:
	if visible:
		return
	_apply = apply
	_discard = discard
	_continuation = continuation
	var focused := get_viewport().gui_get_focus_owner()
	_restore_focus = weakref(focused) if focused != null else null
	%Message.text = "Your controller changes have not been applied."
	show()
	%KeepEditing.grab_focus()


func resolve(choice: StringName) -> void:
	if choice == &"apply" and not bool(_apply.call()):
		%Message.text = "Resolve binding conflicts before applying, or keep editing."
		return
	if choice == &"discard":
		_discard.call()
	var continuation := _continuation
	_continuation = Callable()
	hide()
	if choice != &"keep":
		continuation.call()
	elif _restore_focus != null:
		var previous := _restore_focus.get_ref() as Control
		if is_instance_valid(previous) and previous.is_visible_in_tree():
			previous.grab_focus()


func handle_input(event: InputEvent) -> bool:
	if not visible:
		return false
	if event is InputEventKey and event.is_pressed() and event.keycode == KEY_ESCAPE:
		resolve(&"keep")
		get_viewport().set_input_as_handled()
	return true


func handle_controller(action: StringName, pressed: bool, direction: Vector2i = Vector2i.ZERO) -> bool:
	if not visible:
		return false
	if not pressed:
		return true
	if action == &"realmz_controller_back":
		resolve(&"keep")
	elif action == &"realmz_controller_confirm":
		var button := get_viewport().gui_get_focus_owner() as Button
		if button != null and is_ancestor_of(button): button.pressed.emit()
	elif direction != Vector2i.ZERO:
		_focus.focus_next(self, direction.x < 0 or direction.y < 0)
	return true
