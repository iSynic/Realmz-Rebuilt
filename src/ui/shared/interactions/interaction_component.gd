## Presents the dynamic interaction component interaction without owning gameplay state.

class_name InteractionComponent
extends VBoxContainer

const RESPONSE_BUTTON_SCENE_PATH := "res://src/ui/shared/interactions/interaction_response_button.tscn"

@export_file("*.tscn") var hint_scene_path := "res://src/ui/shared/interactions/interaction_hint.tscn"
@export_file("*.tscn") var character_option_scene_path := "res://src/ui/shared/interactions/interaction_character_option.tscn"

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


func set_layout_profile(_compact: bool) -> void:
	pass


func preferred_initial_focus() -> Control:
	return null


func add_response(label: String, body: InteractionResponse.Body, enabled: bool = true, reason: String = "") -> Button:
	return add_response_to(self, label, body, enabled, reason)


func add_response_to(parent: Container, label: String, body: InteractionResponse.Body, enabled: bool = true, reason: String = "") -> Button:
	var button := (load(RESPONSE_BUTTON_SCENE_PATH) as PackedScene).instantiate() as Button
	button.text = label
	button.disabled = not enabled
	button.tooltip_text = reason
	button.pressed.connect(func() -> void: response_body_submitted.emit(body))
	parent.add_child(button)
	return button


func add_hint(text: String) -> Label:
	var label := (load(hint_scene_path) as PackedScene).instantiate() as Label
	label.text = text
	add_child(label)
	return label


func character_option(value: Variant) -> OptionButton:
	var picker := (load(character_option_scene_path) as PackedScene).instantiate() as OptionButton
	if value is Array:
		for character: Variant in value:
			if character is Dictionary:
				picker.add_item(String(character.get("name", "Character")))
				picker.set_item_metadata(picker.item_count - 1, String(character.get("id", "")))
			elif character is InteractionRequestValue.ServiceCharacter:
				picker.add_item(character.name)
				picker.set_item_metadata(picker.item_count - 1, character.id)
	return picker
