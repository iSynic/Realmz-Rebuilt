## Exposes the stable selected-item record and Done action of Inventory.

class_name InventoryItemInspector
extends HBoxContainer


func record() -> InventorySelectedItemRecord:
	return get_node("InventorySelectedItemRecord") as InventorySelectedItemRecord


func record_host(compact: bool = false) -> BoxContainer:
	record().set_compact(compact)
	return record()


func done_column() -> InventoryDoneColumn:
	return get_node("InventoryDoneColumn") as InventoryDoneColumn


func clear_dynamic_content() -> void:
	record().show_empty("Select an item to inspect it.")
