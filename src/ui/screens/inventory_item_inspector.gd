## Exposes the stable selected-item record and Done action of Inventory.

class_name InventoryItemInspector
extends HBoxContainer


func record_host(compact: bool = false) -> BoxContainer:
	var wide := get_node("InventorySelectedItemRecord") as HBoxContainer
	var narrow := get_node("InventorySelectedItemRecordCompact") as VBoxContainer
	wide.visible = not compact
	narrow.visible = compact
	return narrow if compact else wide


func done_column() -> InventoryDoneColumn:
	return get_node("InventoryDoneColumn") as InventoryDoneColumn


func clear_dynamic_content() -> void:
	for host: BoxContainer in [get_node("InventorySelectedItemRecord") as HBoxContainer, get_node("InventorySelectedItemRecordCompact") as VBoxContainer]:
		for child: Node in host.get_children():
			host.remove_child(child)
			child.queue_free()
