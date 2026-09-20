## Exposes the stable selected-item record and Done action of Inventory.

class_name InventoryItemInspector
extends BoxContainer


func record() -> InventorySelectedItemRecord:
	return get_node("InventorySelectedItemRecord") as InventorySelectedItemRecord


func set_compact(compact: bool) -> void:
	vertical = compact
	record().set_compact(compact)


func record_host(compact: bool = false) -> BoxContainer:
	set_compact(compact)
	return record()


func item_actions() -> InventoryActionPanel:
	return get_node("InventoryActionPanel") as InventoryActionPanel


func done_column() -> InventoryDoneColumn:
	return get_node("InventoryDoneColumn") as InventoryDoneColumn


func clear_dynamic_content() -> void:
	record().show_empty("Select an item to inspect it.")
