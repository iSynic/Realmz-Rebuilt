## Exposes the persistent Inventory exit action from its reusable scene.

class_name InventoryDoneColumn
extends VBoxContainer


func done_button() -> Button:
	return get_node("InventoryDone") as Button
