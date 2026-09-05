## Creates inventory-owned targeting, confirmation, and item-program continuations.

class_name InventoryContinuations
extends RefCounted


static func item_target(body: TargetingContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"item-use-target-selection", body)


static func drop_confirmation(body: TargetingContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"drop-item-confirmation", body)


static func item_xap(body: ItemXapContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"item-xap", body)
