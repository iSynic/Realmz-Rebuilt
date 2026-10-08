## Exposes the authored Character Files browser and its reusable record scene.

extends VBoxContainer

@export var character_row_scene: PackedScene


func character_rows() -> VBoxContainer:
	return %StoredCharacterList as VBoxContainer


func apply_ui_sizing(profile: UiLayoutProfile) -> void:
	var compact := profile.id == UiLayoutProfile.COMPACT
	(get_node("CharacterFilesHeading/HeadingContent") as BoxContainer).vertical = compact
	(get_node("CharacterFilesHeading/HeadingContent/Heading") as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if compact else TextServer.AUTOWRAP_OFF
