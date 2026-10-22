## Binds controller preference drafts and captured input to the retained editor.
## It owns the pending capture action and live-input text for its preferences owner.
class_name SystemControllerBindings
extends RefCounted

var capture_action: StringName = &""
var live_text: String = ""
var _owner_ref: WeakRef
func _init(owner: SystemScreenController) -> void: _owner_ref = weakref(owner)
func _owner() -> SystemScreenController: return _owner_ref.get_ref() as SystemScreenController
func receive_binding(action_id: StringName, descriptor: Dictionary) -> void:
	var draft := _owner().controller_draft
	if draft == null or action_id != capture_action: return
	var physical_key := "%s:%d:%d" % [descriptor["kind"], int(descriptor["code"]), int(descriptor["direction"])]
	draft.bindings = draft.bindings.filter(func(binding: Dictionary) -> bool:
		return StringName(binding["action"]) != action_id and "%s:%d:%d" % [binding["kind"], int(binding["code"]), int(binding["direction"])] != physical_key
	)
	draft.bindings.append(descriptor.duplicate(true))
	capture_action = &""
	_owner().refresh_controller_editor()
func cancel_binding_capture() -> void:
	capture_action = &""
	_owner().refresh_controller_editor()
func set_live_input(value: String) -> void:
	live_text = value
	var workspace := _owner().workspace
	if workspace == null: return
	var label := workspace.get_node_or_null("SystemWorkspaceBody/SystemWorkspaceTabs/Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Controller/ControllerSettings/Content/TuningColumn/LiveInput") as Label
	if label != null: label.text = "Live input • %s" % value
func bind_binding_list(bindings: VBoxContainer, conflicts: Array[Dictionary], reachable: bool, status: Label) -> void:
	var rows := bindings.get_node("BindingRows") as VBoxContainer
	for action_id: StringName in ControllerPreferences.ACTIONS:
		var button := rows.get_node("ControllerBinding_%s" % String(action_id).trim_prefix("realmz_controller_")) as Button
		SystemSignalBinding.clear_pressed(button)
		button.text = "%s  •  %s" % [_controller_action_label(action_id), _binding_summary(action_id)]
		button.pressed.connect(func() -> void:
			capture_action = action_id
			(bindings.get_node("BindingStatus") as Label).text = "Listening for %s… press East to cancel." % _controller_action_label(action_id)
			_owner().refresh_draft_footer()
			_owner().controller_binding_capture_requested.emit(action_id)
		)
	if capture_action.is_empty():
		status.text = "Rebind every missing required action before Apply." if not reachable else "%d binding conflict(s) must be resolved." % conflicts.size() if not conflicts.is_empty() else "Draft bindings are ready to apply."

func _binding_summary(action_id: StringName) -> String:
	var values: Array[String] = []
	for binding: Dictionary in _owner().controller_draft.bindings:
		if StringName(binding["action"]) == action_id:
			values.append("button %d" % int(binding["code"]) if binding["kind"] == ControllerPreferences.BINDING_BUTTON else "axis %d %s" % [int(binding["code"]), "+" if int(binding["direction"]) > 0 else "-"])
	return ", ".join(values) if not values.is_empty() else "UNBOUND"

static func _controller_action_label(action_id: StringName) -> String:
	return {&"realmz_controller_top_menu": "Pause (alternate)", &"realmz_controller_system": "Pause"}.get(action_id, String(action_id).trim_prefix("realmz_controller_").replace("_", " ").capitalize())
