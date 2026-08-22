extends InteractionComponent

var _can_cancel: bool = false


func build(request: InteractionRequest) -> void:
	_can_cancel = false
	if request.kind != InteractionRequest.SESSION_LIFECYCLE:
		return
	var body := request.body as InteractionRequest.LifecycleRequestBody
	if body == null: return
	var context := PanelContainer.new()
	context.name = "LifecycleConsequence"
	context.theme_type_variation = &"ClassicTextWell"
	context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(context)
	var context_column := VBoxContainer.new()
	context_column.add_theme_constant_override("separation", 4)
	context.add_child(context_column)
	var consequence := Label.new()
	consequence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	consequence.text = "The current adventure will close and Realmz Rebuilt will return to the front door." if body.operation == &"end-adventure" else "Realmz Rebuilt will close after this choice is completed."
	context_column.add_child(consequence)
	var save_status := Label.new()
	save_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_status.add_theme_color_override("font_color", Color("9aa0a8"))
	save_status.text = "Saving is unavailable while combat is being settled." if body.in_combat else "Choose a save option to validate current progress before leaving, or explicitly leave without saving."
	context_column.add_child(save_status)
	for option: InteractionRequestValue.LifecycleOption in body.options:
		var action := option.action
		var label := option.label.strip_edges()
		if action.is_empty() or label.is_empty():
			continue
		_can_cancel = _can_cancel or action == &"cancel"
		var button := add_response(label, InteractionResponse.LifecycleBody.new(action))
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
