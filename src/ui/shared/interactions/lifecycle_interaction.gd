## Binds host-supplied lifecycle actions to authored controls without owning gameplay state.

extends InteractionComponent

const LIFECYCLE_OPERATIONS: Array[StringName] = [&"end-adventure", &"quit-application"]

var _can_cancel: bool = false
var _button_actions: Dictionary = {}


func _ready() -> void:
	for button_name: String in ["LifecycleSaveAction", "LifecycleDiscardAction", "LifecycleCancelAction"]:
		var button := find_child(button_name, true, false) as Button
		assert(button != null, "Lifecycle action scene is missing its authored %s button." % button_name)
		button.pressed.connect(_submit_button_action.bind(button_name))


func build(request: InteractionRequest) -> void:
	_can_cancel = false
	_button_actions.clear()
	if request.kind != InteractionRequest.SESSION_LIFECYCLE:
		return
	var body := request.body as LifecycleRequestBody
	if body == null or body.operation not in LIFECYCLE_OPERATIONS:
		return
	var compact_quit := body.operation == &"quit-application"
	var context := %LifecycleConsequence as Label
	context.visible = not compact_quit
	if context.visible:
		context.text = "Saving is unavailable during battle." if body.in_combat else "Save first, or end this adventure without saving."
	var compact_actions := %LifecycleActions as HBoxContainer
	var vertical_actions := %LifecycleVerticalActions as VBoxContainer
	compact_actions.visible = compact_quit
	vertical_actions.visible = not compact_quit
	var action_host: Container = compact_actions if compact_quit else vertical_actions
	var save_button := %LifecycleSaveAction as Button
	var discard_button := %LifecycleDiscardAction as Button
	var cancel_button := %LifecycleCancelAction as Button
	_reset_action_buttons(action_host, [save_button, discard_button, cancel_button])
	for option: InteractionRequestValue.LifecycleOption in body.options:
		var action := option.action
		var label := option.label.strip_edges()
		if label.is_empty():
			continue
		var button: Button = null
		if (action == &"save-and-end" and not compact_quit) or (action == &"save-and-quit" and compact_quit):
			button = save_button
		elif (action == &"end-without-saving" and not compact_quit) or (action == &"quit-without-saving" and compact_quit):
			button = discard_button
		elif action == &"cancel":
			button = cancel_button
		else:
			# Unsupported request actions have no authored control and are skipped.
			continue
		if _button_actions.has(button.name):
			continue
		button.text = label
		button.visible = true
		_button_actions[button.name] = action
		_can_cancel = _can_cancel or action == &"cancel"
		if compact_quit:
			UiSizing.minimum_size(button, Vector2(128.0 if action == &"save-and-quit" else 88.0, 38.0))
			button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if action in [&"end-without-saving", &"quit-without-saving"]:
			button.add_theme_color_override("font_color", Color("d48a78"))
			button.add_theme_color_override("font_hover_color", Color("efaa98"))


func _reset_action_buttons(action_host: Container, buttons: Array[Button]) -> void:
	for button: Button in buttons:
		if button.get_parent() != action_host:
			var scene_owner := button.owner
			button.owner = null
			button.reparent(action_host)
			button.owner = scene_owner
		button.visible = false
		button.remove_theme_color_override("font_color")
		button.remove_theme_color_override("font_hover_color")
		button.custom_minimum_size = Vector2(0.0, 36.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _submit_button_action(button_name: String) -> void:
	if not _button_actions.has(button_name):
		return
	response_body_submitted.emit(InteractionResponse.LifecycleBody.new(_button_actions[button_name]))


func handle_back() -> bool:
	if not _can_cancel:
		return false
	response_body_submitted.emit(InteractionResponse.LifecycleBody.new(&"cancel"))
	return true
