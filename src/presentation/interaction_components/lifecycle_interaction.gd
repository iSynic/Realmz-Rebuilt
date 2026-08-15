extends InteractionComponent


func build(request: InteractionRequest) -> void:
	if request.kind != InteractionRequest.SESSION_LIFECYCLE:
		return
	var body := request.body as InteractionRequest.LifecycleRequestBody
	if body == null: return
	for option: InteractionRequestValue.LifecycleOption in body.options:
		var action := option.action
		var label := option.label.strip_edges()
		if action.is_empty() or label.is_empty():
			continue
		add_response(label, {"action": action})
