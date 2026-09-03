## Exposes stable Inventory character, action, and selector regions to the binder.

class_name InventoryCommandRail
extends VBoxContainer


func character_record() -> VBoxContainer:
	return get_node("CharacterRecord") as VBoxContainer


func item_actions() -> VBoxContainer:
	return get_node("ItemActions") as VBoxContainer


func character_selector() -> VBoxContainer:
	return get_node("CharacterSelector") as VBoxContainer


func clear_dynamic_content() -> void:
	for host: VBoxContainer in [character_record(), item_actions(), character_selector()]:
		for child: Node in host.get_children():
			host.remove_child(child)
			child.queue_free()
