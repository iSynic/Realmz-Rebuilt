class_name EncounterInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.ComplexEncounterRequestBody
	if body == null:
		return
	for entry: InteractionRequestValue.EncounterAction in body.actions:
		match entry.kind:
			"choice":
				_add_bitmap_response(&"encounter.action", entry.label, {"action": "choice", "slot": entry.slot})
			"back":
				_add_bitmap_response(&"encounter.stop", entry.label, {"action": "back"})
			"word":
				_add_word_action(entry)
			"item":
				_add_catalog_action("item", body.items, entry.label)
			"spell":
				_add_catalog_action("spell", body.spells, entry.label)
			"thief":
				_add_thief_action(body.characters, entry)


func _add_word_action(entry: InteractionRequestValue.EncounterAction) -> void:
	var word := LineEdit.new()
	word.placeholder_text = "Speak a word"
	add_child(word)
	var button := _bitmap_button(&"encounter.speak", entry.label)
	button.command_requested.connect(func(_command_id: StringName) -> void: payload_submitted.emit({"action": "word", "word": word.text}))
	add_child(button)


func _add_catalog_action(action: String, values: Array[InteractionRequestValue.EncounterCatalogEntry], label: String) -> void:
	var catalog := OptionButton.new()
	for entry: InteractionRequestValue.EncounterCatalogEntry in values:
		catalog.add_item(entry.name)
		catalog.set_item_metadata(catalog.item_count - 1, entry.classic_id)
	add_child(catalog)
	var asset_id := &"encounter.items" if action == "item" else &"command.spells"
	var button := _bitmap_button(asset_id, label)
	button.disabled = catalog.item_count == 0
	button.tooltip_text = "No eligible options were supplied." if button.disabled else ""
	button.command_requested.connect(func(_command_id: StringName) -> void:
		if catalog.item_count > 0:
			var payload := {"action": action}
			payload["classicItemId" if action == "item" else "classicSpellId"] = int(catalog.get_selected_metadata())
			payload_submitted.emit(payload)
	)
	add_child(button)


func _add_thief_action(characters: Array[InteractionRequestValue.NamedCharacter], entry: InteractionRequestValue.EncounterAction) -> void:
	var picker := OptionButton.new()
	for character: InteractionRequestValue.NamedCharacter in characters:
		picker.add_item(character.name)
		picker.set_item_metadata(picker.item_count - 1, character.id)
	add_child(picker)
	var button := _bitmap_button(&"encounter.skills", entry.label)
	button.disabled = picker.item_count == 0
	button.tooltip_text = "No eligible character was supplied." if button.disabled else ""
	button.command_requested.connect(func(_command_id: StringName) -> void:
		if picker.item_count > 0:
			payload_submitted.emit({"action": "thief", "actionIndex": entry.action_index, "characterId": String(picker.get_selected_metadata())})
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
