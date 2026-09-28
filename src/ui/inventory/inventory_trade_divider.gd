## Exposes the two-pack selectors and fixed Trade navigation actions.
class_name InventoryTradeDivider
extends PanelContainer

@export var portrait_button_scene: PackedScene


func portraits(left_side: bool) -> GridContainer:
	return get_node("Content/InventoryTradePortraitMatrix/LeftPortraits" if left_side else "Content/InventoryTradePortraitMatrix/RightPortraits") as GridContainer


func clear_portraits() -> void:
	for left_side: bool in [true, false]:
		var portrait_grid := portraits(left_side)
		for child: Node in portrait_grid.get_children():
			portrait_grid.remove_child(child)
			child.queue_free()


func money_button() -> Button:
	return get_node("Content/InventoryTradeMoney") as Button


func items_button() -> Button:
	return get_node("Content/InventoryTradeItems") as Button


func transfer_button() -> Button:
	return get_node("Content/InventoryTradeTransfer") as Button


func done_button() -> Button:
	return get_node("Content/InventoryTradeDone") as Button
