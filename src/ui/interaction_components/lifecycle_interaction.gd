extends InteractionComponent

var _can_cancel: bool = false


func build(request: InteractionRequest) -> void:
	_can_cancel = false
	if request.kind != InteractionRequest.SESSION_LIFECYCLE:
		return
	var body := request.body as InteractionRequest.LifecycleRequestBody
	if body == null: return
	var compact_quit := body.operation == &"quit-application"
	if not compact_quit:
		var context := Label.new()
		context.name = "LifecycleConsequence"
		context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		context.text = "Saving is unavailable during battle." if body.in_combat else "Save first, or end this adventure without saving."
		add_child(context)
	var action_host: Container = self
	if compact_quit:
		var actions := HBoxContainer.new()
		actions.name = "LifecycleActions"
		actions.alignment = BoxContainer.ALIGNMENT_CENTER
		actions.add_theme_constant_override("separation", 8)
		add_child(actions)
		action_host = actions
	for option: InteractionRequestValue.LifecycleOption in body.options:
		var action := option.action
		var label := option.label.strip_edges()
		if action.is_empty() or label.is_empty():
			continue
		_can_cancel = _can_cancel or action == &"cancel"
		var button := add_response_to(action_host, label, InteractionResponse.LifecycleBody.new(action))
		if compact_quit:
			button.custom_minimum_size = Vector2(128.0 if action == &"save-and-quit" else 88.0, 38.0)
			button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if action in [&"save-and-end", &"save-and-quit"]:
			button.theme_type_variation = &"ClassicChoiceButton"
		elif action in [&"end-without-saving", &"quit-without-saving"]:
			button.add_theme_color_override("font_color", Color("d48a78"))
			button.add_theme_color_override("font_hover_color", Color("efaa98"))


func handle_back() -> bool:
	if not _can_cancel:
		return false
	response_body_submitted.emit(InteractionResponse.LifecycleBody.new(&"cancel"))
	return true
