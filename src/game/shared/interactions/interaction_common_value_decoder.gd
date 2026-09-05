## Decodes shared availability, wealth, condition, and item-fact request values.

class_name InteractionCommonValueDecoder
extends RefCounted


static func availability(data: Variant) -> InteractionRequestValue.Availability:
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, ["enabled", "reason", "targetMode", "nearestEnemyRange"], ["enabled", "reason"]) or not data["enabled"] is bool or not data["reason"] is String or not InteractionValueDecoderSupport.optional_string(data, "targetMode") or not InteractionValueDecoderSupport.optional_int(data, "nearestEnemyRange"):
		return null
	var result := InteractionRequestValue.Availability.new()
	result.enabled = data["enabled"]
	result.reason = data["reason"]
	result.target_mode = StringName(data.get("targetMode", ""))
	result.nearest_enemy_range = int(data.get("nearestEnemyRange", -1))
	return result


static func wealth(data: Variant) -> InteractionRequestValue.Wealth:
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, ["gold", "gems", "jewelry"], ["gold", "gems", "jewelry"]) or not InteractionValueDecoderSupport.ints(data, ["gold", "gems", "jewelry"]):
		return null
	var result := InteractionRequestValue.Wealth.new()
	result.gold = int(data["gold"])
	result.gems = int(data["gems"])
	result.jewelry = int(data["jewelry"])
	return result


static func condition(data: Variant) -> InteractionRequestValue.Condition:
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, ["index", "name", "value"], ["index", "name", "value"]) or not InteractionValueDecoderSupport.ints(data, ["index", "value"]) or not data["name"] is String:
		return null
	var result := InteractionRequestValue.Condition.new()
	result.index = int(data["index"])
	result.name = data["name"]
	result.value = int(data["value"])
	return result


static func item_detail_fact(data: Variant) -> InteractionRequestValue.ItemDetailFact:
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, ["label", "value"], ["label", "value"]) or not InteractionValueDecoderSupport.strings(data, ["label", "value"]):
		return null
	var result := InteractionRequestValue.ItemDetailFact.new()
	result.label = data["label"]
	result.value = data["value"]
	return result
