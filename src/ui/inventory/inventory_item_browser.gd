## Exposes the stable headings and item-list host of the Inventory browser scene.

class_name InventoryItemBrowser
extends VBoxContainer

@export var item_row_scene: PackedScene


func title_label() -> Label:
	return get_node("Heading/Title") as Label


func count_label() -> Label:
	return get_node("Heading/Count") as Label


func item_scroll() -> ScrollContainer:
	return get_node("InventoryItemScroll") as ScrollContainer


func empty_label() -> Label:
	return get_node("Empty") as Label


func item_list() -> VBoxContainer:
	return get_node("InventoryItemScroll/ItemList") as VBoxContainer


func clear_dynamic_content() -> void:
	empty_label().visible = false
	for child: Node in item_list().get_children():
		item_list().remove_child(child)
		child.queue_free()
