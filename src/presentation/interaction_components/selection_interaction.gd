class_name SelectionInteraction
extends InteractionComponent

var _checks: Array[CheckButton] = []


func build(request: InteractionRequest) -> void:
	if request.kind == &"character_selection":
		_build_character_selection(request)
	else:
		_build_ally_selection(request)


func _build_character_selection(request: InteractionRequest) -> void:
	var required := int(request.payload.get("count", 1))
	var prompt := String(request.payload.get("prompt", ""))
	if not prompt.is_empty():
		add_hint(prompt)
	add_hint("Choose %d character%s." % [required, "" if required == 1 else "s"])
	var eligible: Variant = request.payload.get("eligible", [])
	if eligible is Array:
		for entry: Variant in eligible:
			if entry is Dictionary:
				_add_character_check(entry, false, false)
	var submit := Button.new()
	submit.text = "Choose"
	submit.pressed.connect(_submit_characters.bind(required))
	add_child(submit)


func _build_ally_selection(request: InteractionRequest) -> void:
	var maximum := int(request.payload.get("maximum", 0))
	var selected: Variant = request.payload.get("selectedIds", [])
	add_hint("Choose up to %d surviving allies. Required allies stay selected." % maximum)
	var candidates: Variant = request.payload.get("candidates", [])
	if candidates is Array:
		for entry: Variant in candidates:
			if not entry is Dictionary:
				continue
			var ally_id := String(entry.get("id", ""))
			var required := bool(entry.get("required", false))
			_add_character_check(entry, required or selected is Array and selected.has(ally_id), required)
	var submit := Button.new()
	submit.text = "Continue"
	submit.pressed.connect(_submit_allies.bind(maximum))
	add_child(submit)


func _add_character_check(entry: Dictionary, selected: bool, required: bool) -> void:
	var check := CheckButton.new()
	check.text = "%s • HP %d/%d%s" % [entry.get("name", "Character"), int(entry.get("currentHealth", 0)), int(entry.get("maximumHealth", entry.get("currentHealth", 0))), " • Required" if required else ""]
	check.set_meta("character_id", String(entry.get("id", "")))
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
