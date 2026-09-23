## Exposes the persistent Inventory exit action from its reusable scene.

class_name InventoryDoneColumn
extends VBoxContainer


func done_button() -> Button:
	return get_node("InventoryDone") as Button


func shop_money_button() -> Button:
	return get_node("InventoryShopMoney") as Button


func shop_done_button() -> Button:
	return get_node("InventoryShopDone") as Button
