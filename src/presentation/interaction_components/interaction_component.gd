class_name InteractionComponent
extends VBoxContainer

signal payload_submitted(payload: Dictionary)


func build(_request: InteractionRequest) -> void:
	pass


func add_response(label: String, payload: Dictionary, enabled: bool = true, reason: String = "") -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 36.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = not enabled
	button.tooltip_text = reason
	button.pressed.connect(func() -> void: payload_submitted.emit(payload))
	add_child(button)
	return button


func add_hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("d5b45d"))
	add_child(label)
	return label


func character_option(value: Variant) -> OptionButton:
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if value is Array:
		for character: Variant in value:
			if character is Dictionary:
				picker.add_item(String(character.get("name", "Character")))
				picker.set_item_metadata(picker.item_count - 1, String(character.get("id", "")))
	return picker
