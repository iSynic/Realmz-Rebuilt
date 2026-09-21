## Binds the explicit opposite-pack destination for Inventory Trade.
class_name InventoryTradeAccess
extends RefCounted


static func bind_explicit(
	button: Button,
	view: GameView,
	source: CharacterView,
	target: CharacterView,
	item_owner_id: String,
	item_instance_id: String,
	destination_confirmed: bool,
	clear_button: Callable,
	submit_transfer: Callable
) -> void:
	clear_button.call(button)
	var item_owner := InventoryViewQueries.character_by_id(view, item_owner_id)
	var item := InventoryViewQueries.item_by_id(item_owner, item_instance_id)
	var destination_id := target.id if item_owner != null and item_owner.id == source.id else source.id if item_owner != null and item_owner.id == target.id else ""
	var availability := InventoryViewQueries.trade_target(item, destination_id)
	button.disabled = not destination_confirmed or item == null or destination_id.is_empty() or availability == null or not availability.enabled
	button.tooltip_text = "Select an exact item and destination first." if not destination_confirmed or item == null or destination_id.is_empty() else "This item cannot be transferred there." if availability == null else availability.reason if not availability.enabled else "Transfer %s to %s." % [item.name, InventoryViewQueries.character_by_id(view, destination_id).name]
	if not button.disabled:
		button.pressed.connect(submit_transfer.bind(item.instance_id, item_owner.id, destination_id))
