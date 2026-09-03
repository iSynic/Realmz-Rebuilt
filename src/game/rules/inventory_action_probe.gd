class_name InventoryActionProbe
extends RefCounted

var allowed: bool
var reason: String


func _init(is_allowed: bool, disabled_reason: String = "") -> void:
	allowed = is_allowed
	reason = "" if allowed else disabled_reason


static func permit() -> InventoryActionProbe:
	return InventoryActionProbe.new(true)


static func block(disabled_reason: String) -> InventoryActionProbe:
	return InventoryActionProbe.new(false, disabled_reason)
