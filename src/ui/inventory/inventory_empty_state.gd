## Presents Inventory's authored empty or unavailable state and route exit.
class_name InventoryEmptyState
extends VBoxContainer


func bind(title: String, detail: String, show_done: bool) -> void:
	(get_node("Message/Content/Title") as Label).text = title
	(get_node("Message/Content/Detail") as Label).text = detail
	(get_node("Actions") as HBoxContainer).visible = show_done


func done_button() -> Button:
	return get_node("Actions/InventoryDoneColumn/InventoryDone") as Button
