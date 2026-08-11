extends InteractionComponent


func build(request: InteractionRequest) -> void:
	if request.kind != InteractionRequest.SESSION_LIFECYCLE:
		return
	var options: Variant = request.payload.get("options", [])
	if not options is Array:
		return
	for option: Variant in options:
		if not option is Dictionary:
			continue
		var action := StringName(option.get("action", &""))
		var label := String(option.get("label", "")).strip_edges()
		if action.is_empty() or label.is_empty():
			continue
		add_response(label, {"action": action})
