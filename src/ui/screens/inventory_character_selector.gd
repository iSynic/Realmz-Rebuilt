## Owns the retained party selector and its exported character-button component.
class_name InventoryCharacterSelector
extends PanelContainer

@export var character_button_scene: PackedScene


func characters() -> GridContainer:
	return get_node("Characters") as GridContainer


func clear_characters() -> void:
	for child: Node in characters().get_children():
		characters().remove_child(child)
		child.queue_free()
