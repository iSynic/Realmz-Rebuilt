class_name EncounterInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	var actions: Variant = request.payload.get("actions", [])
	if not actions is Array:
		return
	for entry: Variant in actions:
		if not entry is Dictionary:
			continue
		var kind := String(entry.get("kind", ""))
		match kind:
			"choice":
				_add_bitmap_response(&"encounter.action", String(entry.get("label", "Choose")), {"action": "choice", "slot": int(entry.get("slot", 0))})
			"back":
				_add_bitmap_response(&"encounter.stop", String(entry.get("label", "Back out")), {"action": "back"})
			"word":
				_add_word_action(entry)
			"item":
				_add_catalog_action(request, "item", "classicItemId", "items", String(entry.get("label", "Use an item")))
			"spell":
				_add_catalog_action(request, "spell", "classicSpellId", "spells", String(entry.get("label", "Cast a spell")))
			"thief":
				_add_thief_action(request, entry)


func _add_word_action(entry: Dictionary) -> void:
	var word := LineEdit.new()
	word.placeholder_text = "Speak a word"
	add_child(word)
	var button := _bitmap_button(&"encounter.speak", String(entry.get("label", "Speak")))
	button.command_requested.connect(func(_command_id: StringName) -> void: payload_submitted.emit({"action": "word", "word": word.text}))
	add_child(button)


func _add_catalog_action(request: InteractionRequest, action: String, id_field: String, values_key: String, label: String) -> void:
	var catalog := OptionButton.new()
	var values: Variant = request.payload.get(values_key, [])
	if values is Array:
		for entry: Variant in values:
			if entry is Dictionary and entry.has(id_field):
				catalog.add_item(String(entry.get("name", "Option")))
				catalog.set_item_metadata(catalog.item_count - 1, int(entry[id_field]))
	add_child(catalog)
	var asset_id := &"encounter.items" if action == "item" else &"command.spells"
	var button := _bitmap_button(asset_id, label)
	button.disabled = catalog.item_count == 0
	button.tooltip_text = "No eligible options were supplied." if button.disabled else ""
	button.command_requested.connect(func(_command_id: StringName) -> void:
		if catalog.item_count > 0:
			var payload := {"action": action}
			payload[id_field] = int(catalog.get_selected_metadata())
			payload_submitted.emit(payload)
	)
	add_child(button)


func _add_thief_action(request: InteractionRequest, entry: Dictionary) -> void:
	var picker := character_option(request.payload.get("characters", []))
	add_child(picker)
	var button := _bitmap_button(&"encounter.skills", String(entry.get("label", "Thief action")))
	button.disabled = picker.item_count == 0
	button.tooltip_text = "No eligible character was supplied." if button.disabled else ""
	button.command_requested.connect(func(_command_id: StringName) -> void:
		if picker.item_count > 0:
			payload_submitted.emit({"action": "thief", "actionIndex": int(entry.get("actionIndex", 0)), "characterId": String(picker.get_selected_metadata())})
	)
	add_child(button)


func _add_bitmap_response(asset_id: StringName, label: String, payload: Dictionary) -> void:
	var row := HBoxContainer.new()
	var button := _bitmap_button(asset_id, label)
	button.command_requested.connect(func(_command_id: StringName) -> void: payload_submitted.emit(payload))
	row.add_child(button)
	var text := Label.new()
	text.text = label
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	add_child(row)


func _bitmap_button(asset_id: StringName, label: String) -> ClassicBitmapButton:
	var button := ClassicBitmapButton.new()
	button.configure({"id": asset_id, "asset_id": asset_id, "tooltip": label, "accelerator": ""}, 1)
	return button
