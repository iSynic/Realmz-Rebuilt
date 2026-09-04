## Decodes inventory, Shop, Temple, and Bank request values.

class_name InteractionServiceValueDecoder
extends RefCounted


static func inventory_item(data: Variant) -> InteractionRequestValue.InventoryItem:
	var required := ["instanceId", "itemId", "name", "identified", "equipped", "charges", "sellPrice", "canSell", "sellReason", "canIdentify", "identifyReason"]
	var fields := required + ["iconResourceType", "iconId", "description", "weight", "facts"]
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, fields, required) or not InteractionValueDecoderSupport.strings(data, ["instanceId", "itemId", "name", "sellReason", "identifyReason"]) or not InteractionValueDecoderSupport.optional_string(data, "description") or not InteractionValueDecoderSupport.optional_int(data, "weight") or not InteractionValueDecoderSupport.ints(data, ["charges", "sellPrice"]) or not InteractionValueDecoderSupport.bools(data, ["identified", "equipped", "canSell", "canIdentify"]) or data.has("facts") and not data["facts"] is Array:
		return null
	if not InteractionValueDecoderSupport.optional_resource_key(data):
		return null
	var result := InteractionRequestValue.InventoryItem.new()
	result.instance_id = data["instanceId"]
	result.item_id = data["itemId"]
	result.name = data["name"]
	result.identified = data["identified"]
	result.equipped = data["equipped"]
	result.charges = int(data["charges"])
	result.sell_price = int(data["sellPrice"])
	result.can_sell = data["canSell"]
	result.sell_reason = data["sellReason"]
	result.can_identify = data["canIdentify"]
	result.identify_reason = data["identifyReason"]
	result.icon_resource_type = String(data.get("iconResourceType", "cicn"))
	result.icon_id = int(data.get("iconId", 0))
	result.description = String(data.get("description", ""))
	result.weight = int(data.get("weight", 0))
	for entry: Variant in data.get("facts", []):
		var parsed := InteractionCommonValueDecoder.item_detail_fact(entry)
		if parsed == null:
			return null
		result.facts.append(parsed)
	return result


static func shop_stock(data: Variant) -> InteractionRequestValue.ShopStock:
	var required := ["stockKey", "index", "itemId", "name", "quantity", "buyPrice", "canBuy", "buyReason"]
	var fields := required + ["category", "iconResourceType", "iconId", "description", "weight", "facts"]
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, fields, required) or not InteractionValueDecoderSupport.strings(data, ["stockKey", "itemId", "name", "buyReason"]) or not InteractionValueDecoderSupport.optional_string(data, "category") or not InteractionValueDecoderSupport.optional_string(data, "description") or not InteractionValueDecoderSupport.optional_int(data, "weight") or not InteractionValueDecoderSupport.ints(data, ["index", "quantity", "buyPrice"]) or not data["canBuy"] is bool or data.has("facts") and not data["facts"] is Array:
		return null
	if not InteractionValueDecoderSupport.optional_resource_key(data):
		return null
	var result := InteractionRequestValue.ShopStock.new()
	result.stock_key = data["stockKey"]
	result.index = int(data["index"])
	result.item_id = data["itemId"]
	result.name = data["name"]
	result.quantity = int(data["quantity"])
	result.buy_price = int(data["buyPrice"])
	result.can_buy = data["canBuy"]
	result.buy_reason = data["buyReason"]
	result.category = StringName(data.get("category", ""))
	result.icon_resource_type = String(data.get("iconResourceType", "cicn"))
	result.icon_id = int(data.get("iconId", 0))
	result.description = String(data.get("description", ""))
	result.weight = int(data.get("weight", 0))
	for entry: Variant in data.get("facts", []):
		var parsed := InteractionCommonValueDecoder.item_detail_fact(entry)
		if parsed == null:
			return null
		result.facts.append(parsed)
	return result


static func temple_service(data: Variant) -> InteractionRequestValue.TempleService:
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, ["id", "label", "description", "cost"], ["id", "label", "description", "cost"]) or not InteractionValueDecoderSupport.strings(data, ["id", "label", "description"]) or not InteractionValueDecoderSupport.ints(data, ["cost"]):
		return null
	var result := InteractionRequestValue.TempleService.new()
	result.id = data["id"]
	result.label = data["label"]
	result.description = data["description"]
	result.cost = int(data["cost"])
	return result


static func service_character(data: Variant, mode: StringName) -> InteractionRequestValue.ServiceCharacter:
	if not data is Dictionary:
		return null
	var result := InteractionRequestValue.ServiceCharacter.new()
	match mode:
		&"shop":
			if not _populate_shop_character(data, result):
				return null
		&"temple":
			if not _populate_temple_character(data, result):
				return null
		&"bank":
			if not _populate_bank_character(data, result):
				return null
		_:
			return null
	result.id = data["id"]
	result.name = data["name"]
	return result


static func _populate_shop_character(data: Dictionary, result: InteractionRequestValue.ServiceCharacter) -> bool:
	if not InteractionValueDecoderSupport.exact(data, ["id", "name", "portraitId", "load", "maximumLoad", "inventory"], ["id", "name", "inventory"]) or not InteractionValueDecoderSupport.strings(data, ["id", "name"]) or not InteractionValueDecoderSupport.optional_string(data, "portraitId") or not InteractionValueDecoderSupport.optional_int(data, "load") or not InteractionValueDecoderSupport.optional_int(data, "maximumLoad") or not data["inventory"] is Array:
		return false
	result.portrait_id = String(data.get("portraitId", ""))
	result.load = int(data.get("load", 0))
	result.maximum_load = int(data.get("maximumLoad", 0))
	for entry: Variant in data["inventory"]:
		var parsed := inventory_item(entry)
		if parsed == null:
			return false
		result.inventory.append(parsed)
	return true


static func _populate_temple_character(data: Dictionary, result: InteractionRequestValue.ServiceCharacter) -> bool:
	var fields := ["id", "name", "currentHealth", "maximumHealth", "personalGold", "availableGold", "load", "maximumLoad", "portraitId", "conditions"]
	if not InteractionValueDecoderSupport.exact(data, fields, fields) or not InteractionValueDecoderSupport.strings(data, ["id", "name", "portraitId"]) or not InteractionValueDecoderSupport.ints(data, ["currentHealth", "maximumHealth", "personalGold", "availableGold", "load", "maximumLoad"]) or not data["conditions"] is Array:
		return false
	result.portrait_id = data["portraitId"]
	result.current_health = int(data["currentHealth"])
	result.maximum_health = int(data["maximumHealth"])
	result.personal_gold = int(data["personalGold"])
	result.available_gold = int(data["availableGold"])
	result.load = int(data["load"])
	result.maximum_load = int(data["maximumLoad"])
	for entry: Variant in data["conditions"]:
		var parsed := InteractionCommonValueDecoder.condition(entry)
		if parsed == null:
			return false
		result.conditions.append(parsed)
	return true


static func _populate_bank_character(data: Dictionary, result: InteractionRequestValue.ServiceCharacter) -> bool:
	var fields := ["id", "name", "wealth", "load", "maximumLoad", "transfers"]
	if not InteractionValueDecoderSupport.exact(data, fields, fields) or not InteractionValueDecoderSupport.strings(data, ["id", "name"]) or not InteractionValueDecoderSupport.ints(data, ["load", "maximumLoad"]) or not data["transfers"] is Array:
		return false
	result.wealth = InteractionCommonValueDecoder.wealth(data["wealth"])
	if result.wealth == null:
		return false
	result.load = int(data["load"])
	result.maximum_load = int(data["maximumLoad"])
	for entry: Variant in data["transfers"]:
		var transfer := _transfer(entry)
		if transfer == null:
			return false
		result.transfers.append(transfer)
	return true


static func _transfer(data: Variant) -> InteractionRequestValue.Transfer:
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, ["denomination", "amount", "toPool", "toCharacter"], ["denomination", "amount", "toPool", "toCharacter"]) or not data["denomination"] is String or not InteractionValueDecoderSupport.whole(data["amount"]):
		return null
	var result := InteractionRequestValue.Transfer.new()
	result.denomination = StringName(data["denomination"])
	result.amount = int(data["amount"])
	result.to_pool = InteractionCommonValueDecoder.availability(data["toPool"])
	result.to_character = InteractionCommonValueDecoder.availability(data["toCharacter"])
	return result if result.to_pool != null and result.to_character != null else null
