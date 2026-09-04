## Exposes the authored Character Files browser and its reusable record scene.

extends VBoxContainer

@export var character_row_scene: PackedScene


func character_rows() -> VBoxContainer:
	return %StoredCharacterList as VBoxContainer
