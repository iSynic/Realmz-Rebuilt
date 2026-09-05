## Stores the mutable shop, temple, and bank facts for the current location.

class_name LocationServiceState
extends RefCounted

var active_shop_id: String = ""
var temple_available: bool = false
var temple_cost_percent: int = 100
var bank_available: bool = false

var _shop_accept_ranges: Array[int] = []
var _shop_quantity_overrides: Dictionary = {}
var _shop_inflation_overrides: Dictionary = {}
var _shop_buyback_overrides: Dictionary = {}
var _shop_buyback_slots: Dictionary = {}


func shop_quantity(shop: ShopDefinition, stock_index: int) -> int:
	var key := "%s:%d" % [shop.id, stock_index]
	return int(_shop_quantity_overrides.get(key, shop.quantity(stock_index)))


func set_shop_quantity(shop: ShopDefinition, stock_index: int, quantity: int) -> bool:
	if shop == null or stock_index < 0 or stock_index >= shop.item_ids().size():
		return false
	return set_shop_quantity_override("%s:%d" % [shop.id, stock_index], clampi(quantity, 0, 32_767))


func set_shop_quantity_override(key: String, quantity: int) -> bool:
	if key.is_empty() or quantity < 0 or quantity > 32_767:
		return false
	_shop_quantity_overrides[key] = quantity
	return true


func shop_quantity_overrides() -> Dictionary:
	return _sorted_dictionary(_shop_quantity_overrides)


func shop_buyback_quantity(shop_id: String, item_id: String) -> int:
	var shop_items: Variant = _shop_buyback_overrides.get(shop_id, {})
	return int(shop_items.get(item_id, 0)) if shop_items is Dictionary else 0


func set_shop_buyback_quantity(shop_id: String, item_id: String, quantity: int, slot: int = -1) -> bool:
	if shop_id.is_empty() or item_id.is_empty() or quantity < 0 or quantity > 32_767:
		return false
	var shop_items: Dictionary = (_shop_buyback_overrides.get(shop_id, {}) as Dictionary).duplicate()
	var shop_slots: Dictionary = (_shop_buyback_slots.get(shop_id, {}) as Dictionary).duplicate()
	if quantity == 0:
		shop_items.erase(item_id)
		shop_slots.erase(item_id)
	else:
		var retained_slot := slot if slot >= 0 else int(shop_slots.get(item_id, -1))
		if retained_slot < 0 or retained_slot > 999:
			return false
		shop_items[item_id] = quantity
		shop_slots[item_id] = retained_slot
	if shop_items.is_empty():
		_shop_buyback_overrides.erase(shop_id)
		_shop_buyback_slots.erase(shop_id)
	else:
		_shop_buyback_overrides[shop_id] = shop_items
		_shop_buyback_slots[shop_id] = shop_slots
	return true


func shop_buyback_items(shop_id: String) -> Dictionary:
	var items: Variant = _shop_buyback_overrides.get(shop_id, {})
	return items.duplicate() if items is Dictionary else {}


func shop_buyback_slot(shop_id: String, item_id: String) -> int:
	var slots: Variant = _shop_buyback_slots.get(shop_id, {})
	return int(slots.get(item_id, -1)) if slots is Dictionary else -1


func shop_buyback_overrides() -> Dictionary:
	return _sorted_nested_dictionary(_shop_buyback_overrides)


func shop_buyback_slot_overrides() -> Dictionary:
	return _sorted_nested_dictionary(_shop_buyback_slots)


func shop_inflation(shop: ShopDefinition) -> int:
	return int(_shop_inflation_overrides.get(shop.id, shop.inflation_percent))


func set_shop_inflation(shop: ShopDefinition, percent: int) -> bool:
	if shop == null:
		return false
	return set_shop_inflation_override(shop.id, percent)


func set_shop_inflation_override(shop_id: String, percent: int) -> bool:
	if shop_id.is_empty() or percent < 0 or percent > 32_767:
		return false
	_shop_inflation_overrides[shop_id] = percent
	return true


func shop_inflation_overrides() -> Dictionary:
	return _sorted_dictionary(_shop_inflation_overrides)


func set_active_shop(shop_id: String, accept_ranges: Array[int]) -> bool:
	if shop_id.is_empty() or accept_ranges.size() != 4:
		return false
	active_shop_id = shop_id
	_shop_accept_ranges = accept_ranges.duplicate()
	return true


func shop_accept_ranges() -> Array[int]:
	return _shop_accept_ranges.duplicate()


func set_active_temple(cost_percent: int) -> bool:
	if cost_percent < -32_768 or cost_percent > 32_767:
		return false
	temple_available = true
	temple_cost_percent = cost_percent
	return true


func clear() -> void:
	active_shop_id = ""
	_shop_accept_ranges.clear()
	temple_available = false
	temple_cost_percent = 100
	bank_available = false


static func _sorted_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = source.keys()
	keys.sort()
	for key: Variant in keys:
		result[key] = source[key]
	return result


static func _sorted_nested_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = source.keys()
	keys.sort()
	for key: Variant in keys:
		if source[key] is Dictionary:
			result[key] = _sorted_dictionary(source[key])
	return result
