## Exposes stable Inventory character, action, and selector regions to the binder.

class_name InventoryCommandRail
extends VBoxContainer

var _item_actions: InventoryActionPanel


func character_record() -> VBoxContainer:
	return get_node("InventoryCharacterRecord") as VBoxContainer


func item_actions() -> InventoryActionPanel:
	if is_instance_valid(_item_actions):
		return _item_actions
	# The action deck lives beside the selected-item record, but the controller's
	# binding façade remains on the command rail for route and test stability.
	var workspace := get_parent().get_parent().get_parent()
	if workspace != null:
		_item_actions = workspace.get_node_or_null("InventoryItemInspector/InventoryItemInspectorContent/InventoryActionPanel") as InventoryActionPanel
	return _item_actions


func set_item_actions(panel: InventoryActionPanel) -> void:
	_item_actions = panel


func character_selector() -> InventoryCharacterSelector:
	return get_node("InventoryCharacterSelector") as InventoryCharacterSelector


func clear_dynamic_content() -> void:
	character_selector().clear_characters()
	var actions := item_actions()
	if actions != null:
		actions.show_selection_hint()
