class_name InteractionComponent
extends VBoxContainer

signal response_body_submitted(body: InteractionResponse.Body)
@warning_ignore("unused_signal")
signal combat_targeting_requested(request: CombatTargetingRequest)
@warning_ignore("unused_signal")
signal combat_targeting_confirm_requested
@warning_ignore("unused_signal")
signal combat_targeting_cancel_requested
@warning_ignore("unused_signal")
signal combat_targeting_rotate_requested
@warning_ignore("unused_signal")
signal combatant_focus_requested(combatant_id: String, play_sound: bool)
@warning_ignore("unused_signal")
signal reveal_friends_requested
@warning_ignore("unused_signal")
signal presentation_sound_requested(sound_id: int)
@warning_ignore("unused_signal")
signal presentation_status_requested(text: String, is_error: bool)
@warning_ignore("unused_signal")
signal combat_spellbook_requested(actor_id: String, options: Array[InteractionRequestValue.CastOption])
@warning_ignore("unused_signal")
signal combat_spellbook_closed
@warning_ignore("unused_signal")
signal side_workspace_requested(workspace: Control)
@warning_ignore("unused_signal")
signal side_workspace_closed
@warning_ignore("unused_signal")
signal encounter_dock_requested(workspace: Control)
@warning_ignore("unused_signal")
signal encounter_dock_closed
@warning_ignore("unused_signal")
signal application_workspace_requested(workspace: Control)
@warning_ignore("unused_signal")
signal application_workspace_closed


func build(_request: InteractionRequest) -> void:
	pass


func handle_back() -> bool:
	return false


func preferred_initial_focus() -> Control:
	return null


func add_response(label: String, body: InteractionResponse.Body, enabled: bool = true, reason: String = "") -> Button:
	return add_response_to(self, label, body, enabled, reason)


func add_response_to(parent: Container, label: String, body: InteractionResponse.Body, enabled: bool = true, reason: String = "") -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 36.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = not enabled
	button.tooltip_text = reason
	button.pressed.connect(func() -> void: response_body_submitted.emit(body))
	parent.add_child(button)
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
			elif character is InteractionRequestValue.ServiceCharacter:
				picker.add_item(character.name)
				picker.set_item_metadata(picker.item_count - 1, character.id)
	return picker
