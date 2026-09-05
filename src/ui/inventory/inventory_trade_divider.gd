## Exposes the two-pack selectors and fixed Trade navigation actions.
class_name InventoryTradeDivider
extends PanelContainer

@export var portrait_button_scene: PackedScene


func portraits() -> GridContainer:
	return get_node("Content/InventoryTradePortraitMatrix") as GridContainer


func clear_portraits() -> void:
	for child: Node in portraits().get_children():
		portraits().remove_child(child)
		child.queue_free()


func money_button() -> Button:
	return get_node("Content/InventoryTradeMoney") as Button


func items_button() -> Button:
	return get_node("Content/InventoryTradeItems") as Button


func done_button() -> Button:
	return get_node("Content/InventoryTradeDone") as Button
