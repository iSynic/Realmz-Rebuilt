## Owns the complete editor-authored Party Wealth and location-services layout.
class_name ServicesWorkspace
extends VBoxContainer

@export var money_character_row_scene: PackedScene
@export var money_transfer_row_scene: PackedScene
@export var location_service_row_scene: PackedScene
@export var service_action_button_scene: PackedScene


func prepare(compact: bool) -> void:
	visible = true
	_clear(location_service_rows())
	money_column().visible = true
	alternate_state().visible = false
	money_main().vertical = compact
	pool_summary().vertical = true
	exchange_workspace().vertical = compact
	party_pane().visible = not compact
	character_picker().visible = compact
	selected_summary().vertical = compact
	location_services_pane().visible = false


func show_alternate(title: String, detail: String) -> void:
	money_column().visible = false
	alternate_state().visible = true
	(alternate_state().get_node("Content/Title") as Label).text = title
	(alternate_state().get_node("Content/Detail") as Label).text = detail


func money_column() -> VBoxContainer:
	return get_node("MoneyColumn") as VBoxContainer


func money_main() -> BoxContainer:
	return get_node("MoneyColumn/MoneyMain") as BoxContainer


func pool_pane() -> PanelContainer:
	return get_node("MoneyColumn/MoneyMain/MoneyActionArea/MoneyExchangeWorkspace/MoneyPoolPane") as PanelContainer


func pool_summary() -> BoxContainer:
	return get_node("MoneyColumn/MoneyMain/MoneyActionArea/MoneyExchangeWorkspace/MoneyPoolPane/Content/MoneyPoolSummary") as BoxContainer


func exchange_workspace() -> BoxContainer:
	return get_node("MoneyColumn/MoneyMain/MoneyActionArea/MoneyExchangeWorkspace") as BoxContainer


func party_pane() -> PanelContainer:
	return get_node("MoneyColumn/MoneyMain/MoneyPartyArea/MoneyPartyPane") as PanelContainer


func character_rows() -> VBoxContainer:
	return get_node("MoneyColumn/MoneyMain/MoneyPartyArea/MoneyPartyPane/Content/MoneyCharacterScroll/MoneyCharacterRows") as VBoxContainer


func swap_pane() -> PanelContainer:
	return get_node("MoneyColumn/MoneyMain/MoneyActionArea/MoneyExchangeWorkspace/MoneySwapPane") as PanelContainer


func character_picker() -> OptionButton:
	return get_node("MoneyColumn/MoneyMain/MoneyActionArea/MoneyExchangeWorkspace/MoneySwapPane/Content/MoneyExchangeScroll/MoneyExchangeBody/MoneyCharacterPicker") as OptionButton


func selected_summary() -> BoxContainer:
	return get_node("MoneyColumn/MoneyMain/MoneyActionArea/MoneyExchangeWorkspace/MoneySwapPane/Content/MoneyExchangeScroll/MoneyExchangeBody/MoneySelectedSummary") as BoxContainer


func transfer_rows() -> VBoxContainer:
	return get_node("MoneyColumn/MoneyMain/MoneyActionArea/MoneyExchangeWorkspace/MoneySwapPane/Content/MoneyExchangeScroll/MoneyExchangeBody/MoneyTransferGrid") as VBoxContainer


func changing_pane() -> PanelContainer:
	return get_node("MoneyColumn/MoneyMain/MoneyActionArea/MoneyChangingPane") as PanelContainer


func changing_buttons() -> Array[Button]:
	return [get_node("MoneyColumn/MoneyMain/MoneyActionArea/MoneyChangingPane/Content/Actions/JewelryToGems") as Button, get_node("MoneyColumn/MoneyMain/MoneyActionArea/MoneyChangingPane/Content/Actions/GemsToGold") as Button, get_node("MoneyColumn/MoneyMain/MoneyActionArea/MoneyChangingPane/Content/Actions/GoldToGems") as Button]


func done_button() -> Button:
	return get_node("MoneyColumn/MoneyMain/MoneyPartyArea/MoneyDone") as Button


func repeat_timer() -> Timer:
	return get_node("MoneyRepeatTimer") as Timer


func location_services_pane() -> PanelContainer:
	return get_node("MoneyColumn/LocationServicePane") as PanelContainer


func location_service_rows() -> VBoxContainer:
	return get_node("MoneyColumn/LocationServicePane/Content/LocationServiceRows") as VBoxContainer


func alternate_state() -> PanelContainer:
	return get_node("ServicesAlternateState") as PanelContainer


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
