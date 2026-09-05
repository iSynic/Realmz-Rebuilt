## Exposes the stable selected-item narrative and fact regions.
class_name InventorySelectedItemRecord
extends BoxContainer

@export var fact_row_scene: PackedScene
@export var text_row_scene: PackedScene


func set_compact(compact: bool) -> void:
	vertical = false
	(get_node("Narrative") as VBoxContainer).custom_minimum_size.x = 350.0 if compact else 470.0


func empty_label() -> Label:
	return get_node("Empty") as Label


func narrative() -> VBoxContainer:
	return get_node("Narrative") as VBoxContainer


func item_icon() -> ClassicContentIcon:
	return get_node("Narrative/TitleRow/ContentIcon") as ClassicContentIcon


func fact_rows() -> VBoxContainer:
	return get_node("Facts/FactRows") as VBoxContainer


func properties() -> VBoxContainer:
	return get_node("Facts/Properties") as VBoxContainer


func restrictions() -> VBoxContainer:
	return get_node("Facts/Restrictions") as VBoxContainer


func show_empty(text: String) -> void:
	empty_label().text = text
	empty_label().visible = true
	narrative().visible = false
	(get_node("Facts") as VBoxContainer).visible = false


func show_record() -> void:
	empty_label().visible = false
	narrative().visible = true
	(get_node("Facts") as VBoxContainer).visible = true
	for host: Container in [fact_rows(), properties(), restrictions()]:
		for child: Node in host.get_children():
			host.remove_child(child)
			child.queue_free()
