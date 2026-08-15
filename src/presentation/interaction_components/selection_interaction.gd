class_name SelectionInteraction
extends InteractionComponent

var _checks: Array[CheckButton] = []


func build(request: InteractionRequest) -> void:
	if request.kind == &"character_selection":
		_build_character_selection(request)
	else:
		_build_ally_selection(request)


func _build_character_selection(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.CharacterSelectionRequestBody
	if body == null: return
	var required := body.count
	var prompt := body.prompt
	if not prompt.is_empty():
		add_hint(prompt)
	add_hint("Choose %d character%s." % [required, "" if required == 1 else "s"])
	for entry: InteractionRequestValue.SelectionCandidate in body.eligible:
		_add_character_check(entry, false, false)
	var submit := Button.new()
	submit.text = "Choose"
	submit.pressed.connect(_submit_characters.bind(required))
	add_child(submit)


func _build_ally_selection(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.SelectionRequestBody
	if body == null: return
	var maximum := body.maximum
	var selected := body.selected_ids
	add_hint("Choose up to %d surviving allies. Required allies stay selected." % maximum)
	for entry: InteractionRequestValue.SelectionCandidate in body.candidates:
		var ally_id := entry.id
		var required := body.required_ids.has(ally_id)
		_add_character_check(entry, required or selected.has(ally_id), required)
	var submit := Button.new()
	submit.text = "Continue"
	submit.pressed.connect(_submit_allies.bind(maximum))
	add_child(submit)


func _add_character_check(entry: InteractionRequestValue.SelectionCandidate, selected: bool, required: bool) -> void:
	var check := CheckButton.new()
	var maximum_health := entry.maximum_health if entry.has_maximum_health else entry.current_health
	check.text = "%s • HP %d/%d%s" % [entry.name, entry.current_health, maximum_health, " • Required" if required else ""]
	check.set_meta("character_id", entry.id)
	check.button_pressed = selected
	check.disabled = required
	_checks.append(check)
	add_child(check)


func _submit_characters(required: int) -> void:
	var ids := _selected_ids()
	if ids.size() != required:
		add_hint("Choose exactly %d character%s." % [required, "" if required == 1 else "s"])
		return
	payload_submitted.emit({"characterIds": ids})


func _submit_allies(maximum: int) -> void:
	var ids := _selected_ids()
	if ids.size() > maximum:
		add_hint("Choose no more than %d allies." % maximum)
		return
	payload_submitted.emit({"selectedIds": ids})


func _selected_ids() -> Array[String]:
	var ids: Array[String] = []
	for check: CheckButton in _checks:
		if check.button_pressed:
			ids.append(String(check.get_meta("character_id")))
	return ids
