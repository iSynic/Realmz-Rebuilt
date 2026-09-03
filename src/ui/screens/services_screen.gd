## Owns the stable Party Wealth panes and alternate empty-state region.
class_name ServicesScreen
extends ScreenFrame

const BODY_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody"


func prepare_for_render(compact: bool) -> void:
	_clear_children(pool_panel())
	_clear_children(party_panel())
	_clear_children(swap_panel())
	_clear_children(location_services_panel())
	_clear_children(_alternate_content())
	_money_column().visible = true
	_alternate_content().visible = false
	_exchange_area().vertical = compact
	party_panel().visible = not compact
	location_services_panel().visible = false


func prepare_alternate_layout() -> VBoxContainer:
	prepare_for_render(false)
	_money_column().visible = false
	var alternate := _alternate_content()
	alternate.visible = true
	return alternate


func pool_panel() -> PanelContainer:
	return get_node(BODY_PATH + "/MoneyColumn/MoneyPoolPanel") as PanelContainer


func party_panel() -> PanelContainer:
	return get_node(BODY_PATH + "/MoneyColumn/MoneyExchangeArea/MoneyPartyPanel") as PanelContainer


func swap_panel() -> PanelContainer:
	return get_node(BODY_PATH + "/MoneyColumn/MoneyExchangeArea/MoneySwapPanel") as PanelContainer


func location_services_panel() -> PanelContainer:
	return get_node(BODY_PATH + "/MoneyColumn/LocationServicesPanel") as PanelContainer


func show_location_services() -> void:
	location_services_panel().visible = true


func _money_column() -> VBoxContainer:
	return get_node(BODY_PATH + "/MoneyColumn") as VBoxContainer


func _exchange_area() -> BoxContainer:
	return get_node(BODY_PATH + "/MoneyColumn/MoneyExchangeArea") as BoxContainer


func _alternate_content() -> VBoxContainer:
	return get_node(BODY_PATH + "/ServicesAlternateContent") as VBoxContainer


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
