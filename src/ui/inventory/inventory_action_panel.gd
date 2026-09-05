## Exposes the stable ordinary, encounter, and confirmation actions for one item.
class_name InventoryActionPanel
extends VBoxContainer


func selection_hint() -> Label:
	return get_node("SelectionHint") as Label


func action_dock() -> GridContainer:
	return get_node("InventoryActionDock") as GridContainer


func action_button(node_name: String) -> ClassicBitmapButton:
	return action_dock().get_node(node_name) as ClassicBitmapButton


func encounter_dock() -> GridContainer:
	return get_node("EncounterActionDock") as GridContainer


func encounter_button() -> ClassicBitmapButton:
	return encounter_dock().get_node("EncounterItemChoose") as ClassicBitmapButton


func operation_stage() -> PanelContainer:
	return get_node("InventoryOperationStage") as PanelContainer


func trade_status() -> Label:
	return get_node("TradeStatus") as Label


func show_selection_hint() -> void:
	selection_hint().visible = true
	action_dock().visible = false
	encounter_dock().visible = false
	operation_stage().visible = false
	trade_status().visible = false


func show_actions(encounter: bool) -> void:
	selection_hint().visible = false
	action_dock().visible = not encounter
	action_dock().columns = 4
	encounter_dock().visible = encounter
	operation_stage().visible = false
	trade_status().visible = false


func show_operation() -> void:
	selection_hint().visible = false
	action_dock().visible = false
	encounter_dock().visible = false
	operation_stage().visible = true
	trade_status().visible = false
