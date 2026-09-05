## Exposes one scene-authored drag-and-drop inventory ledger.
class_name InventoryTradeLedger
extends ClassicExchangeLedger

@export var item_row_scene: PackedScene
@export var empty_row_scene: PackedScene


func title_label() -> Label:
	return get_node("Content/Header/Title") as Label


func load_label() -> Label:
	return get_node("Content/Header/Load") as Label


func rows() -> VBoxContainer:
	return get_node("Content/ItemScroll/Items") as VBoxContainer


func clear_rows() -> void:
	for child: Node in rows().get_children():
		rows().remove_child(child)
		child.queue_free()
