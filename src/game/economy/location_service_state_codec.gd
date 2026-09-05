## Preserves the flat save fields owned by LocationServiceState.

class_name LocationServiceStateCodec
extends RefCounted


static func write_availability_to(state: LocationServiceState, data: Dictionary) -> void:
	data["activeShopId"] = state.active_shop_id
	data["shopAcceptRanges"] = state.shop_accept_ranges()
	data["templeAvailable"] = state.temple_available
	data["templeCostPercent"] = state.temple_cost_percent
	data["bankAvailable"] = state.bank_available


static func write_collections_to(state: LocationServiceState, data: Dictionary) -> void:
	data["shopOverrides"] = state.shop_quantity_overrides()
	data["shopInflationOverrides"] = state.shop_inflation_overrides()
	data["shopBuybackOverrides"] = state.shop_buyback_overrides()
	data["shopBuybackSlots"] = state.shop_buyback_slot_overrides()


static func restore_availability(state: LocationServiceState, data: Dictionary) -> bool:
	if data.has("activeShopId") or data.has("shopAcceptRanges"):
		if not data.get("activeShopId") is String or not data.get("shopAcceptRanges") is Array:
			return false
		var ranges: Array[int] = []
		for value: Variant in data["shopAcceptRanges"]:
			var accepted := _signed_integer(value)
			if accepted < -32_768 or accepted > 32_767:
				return false
			ranges.append(accepted)
		if not String(data["activeShopId"]).is_empty() and not state.set_active_shop(data["activeShopId"], ranges):
			return false
		if String(data["activeShopId"]).is_empty() and not ranges.is_empty():
			return false
	if data.has("templeAvailable") or data.has("templeCostPercent") or data.has("bankAvailable"):
		if not data.get("templeAvailable") is bool or not data.get("bankAvailable") is bool:
			return false
		var percent := _signed_integer(data.get("templeCostPercent"))
		if percent < -32_768 or percent > 32_767:
			return false
		state.temple_available = data["templeAvailable"]
		state.temple_cost_percent = percent
		state.bank_available = data["bankAvailable"]
	return true


static func restore_collections(state: LocationServiceState, data: Dictionary) -> bool:
	if not data["shopOverrides"] is Dictionary or not data["shopInflationOverrides"] is Dictionary:
		return false
	if not _restore_shop_overrides(state, data):
		return false
	return _restore_buyback_overrides(state, data)


static func _restore_shop_overrides(state: LocationServiceState, data: Dictionary) -> bool:
	for key: Variant in data["shopOverrides"]:
		var quantity := _integer(data["shopOverrides"][key])
		if not key is String or not state.set_shop_quantity_override(key, quantity):
			return false
	for key: Variant in data["shopInflationOverrides"]:
		var inflation := _integer(data["shopInflationOverrides"][key])
		if not key is String or not state.set_shop_inflation_override(key, inflation):
			return false
	return true


static func _restore_buyback_overrides(state: LocationServiceState, data: Dictionary) -> bool:
	if data.has("shopBuybackOverrides"):
		if not data["shopBuybackOverrides"] is Dictionary or not data.get("shopBuybackSlots") is Dictionary:
			return false
		for shop_id: Variant in data["shopBuybackOverrides"]:
			if not _restore_buyback_shop(state, shop_id, data):
				return false
		return data["shopBuybackOverrides"].size() == data["shopBuybackSlots"].size()
	return not data.has("shopBuybackSlots") or (data["shopBuybackSlots"] is Dictionary and data["shopBuybackSlots"].is_empty())


static func _restore_buyback_shop(state: LocationServiceState, shop_id: Variant, data: Dictionary) -> bool:
	var items: Variant = data["shopBuybackOverrides"][shop_id]
	var slots: Variant = data["shopBuybackSlots"].get(shop_id)
	if not shop_id is String or shop_id.is_empty() or not items is Dictionary or not slots is Dictionary or items.size() != slots.size():
		return false
	for item_id: Variant in items:
		var quantity := _integer(items[item_id])
		var slot := _integer(slots.get(item_id))
		if not item_id is String or item_id.is_empty() or not slots.has(item_id) or quantity < 1 or quantity > 32_767 or slot < 0 or slot > 999:
			return false
		if not state.set_shop_buyback_quantity(shop_id, item_id, quantity, slot):
			return false
	return true


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
