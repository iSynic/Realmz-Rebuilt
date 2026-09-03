## Exposes stable Inventory character, action, and selector regions to the binder.

class_name InventoryCommandRail
extends VBoxContainer


func character_record() -> VBoxContainer:
	return get_node("InventoryCharacterRecord") as VBoxContainer


func item_actions() -> InventoryActionPanel:
	return get_node("InventoryActionPanel") as InventoryActionPanel


func character_selector() -> InventoryCharacterSelector:
	return get_node("InventoryCharacterSelector") as InventoryCharacterSelector


func clear_dynamic_content() -> void:
	character_selector().clear_characters()
	item_actions().show_selection_hint()
