## Owns the complete editor-authored Party Wealth and location-services layout.
class_name ServicesWorkspace
extends VBoxContainer

@export var money_character_row_scene: PackedScene
@export var money_transfer_row_scene: PackedScene
@export var location_service_row_scene: PackedScene
@export var service_action_button_scene: PackedScene


func prepare(compact: bool) -> void:
	visible = true
	_clear(character_rows())
	_clear(transfer_rows())
	_clear(location_service_rows())
	money_column().visible = true
	alternate_state().visible = false
	pool_summary().vertical = compact
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


func pool_pane() -> PanelContainer:
	return get_node("MoneyColumn/MoneyPoolPane") as PanelContainer


func pool_summary() -> BoxContainer:
	return get_node("MoneyColumn/MoneyPoolPane/Content/MoneyPoolSummary") as BoxContainer


func exchange_workspace() -> BoxContainer:
	return get_node("MoneyColumn/MoneyExchangeWorkspace") as BoxContainer


func party_pane() -> PanelContainer:
	return get_node("MoneyColumn/MoneyExchangeWorkspace/MoneyPartyPane") as PanelContainer


func character_rows() -> VBoxContainer:
	return get_node("MoneyColumn/MoneyExchangeWorkspace/MoneyPartyPane/Content/MoneyCharacterScroll/MoneyCharacterRows") as VBoxContainer


func swap_pane() -> PanelContainer:
	return get_node("MoneyColumn/MoneyExchangeWorkspace/MoneySwapPane") as PanelContainer


func character_picker() -> OptionButton:
	return get_node("MoneyColumn/MoneyExchangeWorkspace/MoneySwapPane/Content/MoneyExchangeScroll/MoneyExchangeBody/MoneyCharacterPicker") as OptionButton


func selected_summary() -> BoxContainer:
	return get_node("MoneyColumn/MoneyExchangeWorkspace/MoneySwapPane/Content/MoneyExchangeScroll/MoneyExchangeBody/MoneySelectedSummary") as BoxContainer


func transfer_rows() -> VBoxContainer:
	return get_node("MoneyColumn/MoneyExchangeWorkspace/MoneySwapPane/Content/MoneyExchangeScroll/MoneyExchangeBody/MoneyTransferGrid") as VBoxContainer


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
