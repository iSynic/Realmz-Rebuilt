class_name InteractionRequestValue
extends RefCounted


class Availability:
	extends RefCounted
	var enabled: bool
	var reason: String
	var target_mode: StringName
	var nearest_enemy_range: int = -1

	func to_data() -> Dictionary:
		var data := {"enabled": enabled, "reason": reason}
		if not target_mode.is_empty(): data["targetMode"] = String(target_mode)
		if nearest_enemy_range >= 0: data["nearestEnemyRange"] = nearest_enemy_range
		return data


class Wealth:
	extends RefCounted
	var gold: int
	var gems: int
	var jewelry: int

	func to_data() -> Dictionary:
		return {"gold": gold, "gems": gems, "jewelry": jewelry}


class Condition:
	extends RefCounted
	var index: int
	var name: String
	var value: int

	func to_data() -> Dictionary:
		return {"index": index, "name": name, "value": value}


class ItemDetailFact:
	extends RefCounted
	var label: String
	var value: String

	func to_data() -> Dictionary:
		return {"label": label, "value": value}


class InventoryItem:
	extends RefCounted
	var instance_id: String
	var item_id: String
	var name: String
	var identified: bool
	var equipped: bool
	var charges: int
	var sell_price: int
	var can_sell: bool
	var sell_reason: String
	var can_identify: bool
	var identify_reason: String
	var icon_resource_type: String = "cicn"
	var icon_id: int
	var description: String
	var weight: int
	var facts: Array[ItemDetailFact] = []

	func to_data() -> Dictionary:
		var data := {"instanceId": instance_id, "itemId": item_id, "name": name, "identified": identified, "equipped": equipped, "charges": charges, "sellPrice": sell_price, "canSell": can_sell, "sellReason": sell_reason, "canIdentify": can_identify, "identifyReason": identify_reason, "description": description, "weight": weight, "facts": facts.map(func(value: ItemDetailFact) -> Dictionary: return value.to_data())}
		if icon_id > 0:
			data["iconResourceType"] = icon_resource_type
			data["iconId"] = icon_id
		return data


class Transfer:
	extends RefCounted
	var denomination: StringName
	var amount: int
	var to_pool: Availability
	var to_character: Availability

	func to_data() -> Dictionary:
		return {"denomination": String(denomination), "amount": amount, "toPool": to_pool.to_data(), "toCharacter": to_character.to_data()}


class ServiceCharacter:
	extends RefCounted
	var id: String
	var name: String
	var portrait_id: String
	var current_health: int
	var maximum_health: int
	var personal_gold: int
	var available_gold: int
	var load: int
	var maximum_load: int
	var wealth: Wealth
	var conditions: Array[Condition] = []
	var inventory: Array[InventoryItem] = []
	var transfers: Array[Transfer] = []

	func to_shop_data() -> Dictionary:
		var data := {"id": id, "name": name, "load": load, "maximumLoad": maximum_load, "inventory": inventory.map(func(value: InventoryItem) -> Dictionary: return value.to_data())}
		if not portrait_id.is_empty(): data["portraitId"] = portrait_id
		return data

	func to_temple_data() -> Dictionary:
		return {"id": id, "name": name, "currentHealth": current_health, "maximumHealth": maximum_health, "personalGold": personal_gold, "availableGold": available_gold, "load": load, "maximumLoad": maximum_load, "portraitId": portrait_id, "conditions": conditions.map(func(value: Condition) -> Dictionary: return value.to_data())}

	func to_bank_data() -> Dictionary:
		return {"id": id, "name": name, "wealth": wealth.to_data(), "load": load, "maximumLoad": maximum_load, "transfers": transfers.map(func(value: Transfer) -> Dictionary: return value.to_data())}


class ShopStock:
	extends RefCounted
	var stock_key: String
	var index: int
	var item_id: String
	var name: String
	var quantity: int
	var buy_price: int
	var can_buy: bool
	var buy_reason: String
	var category: StringName
	var icon_resource_type: String = "cicn"
	var icon_id: int
	var description: String
	var weight: int
	var facts: Array[ItemDetailFact] = []

	func to_data() -> Dictionary:
		var data := {"stockKey": stock_key, "index": index, "itemId": item_id, "name": name, "quantity": quantity, "buyPrice": buy_price, "canBuy": can_buy, "buyReason": buy_reason, "description": description, "weight": weight, "facts": facts.map(func(value: ItemDetailFact) -> Dictionary: return value.to_data())}
		if not category.is_empty(): data["category"] = String(category)
		if icon_id > 0:
			data["iconResourceType"] = icon_resource_type
			data["iconId"] = icon_id
		return data


class TempleService:
	extends RefCounted
	var id: String
	var label: String
	var description: String
	var cost: int

	func to_data() -> Dictionary:
		return {"id": id, "label": label, "description": description, "cost": cost}


class CombatTarget:
	extends RefCounted
	var id: String
	var kind: StringName
	var name: String
	var current_health: int
	var maximum_health: int
	var hit_dice: int
	var magic_resistance: int
	var has_hit_dice: bool

	func to_data() -> Dictionary:
		var data := {"id": id, "kind": String(kind), "name": name, "currentHealth": current_health, "maximumHealth": maximum_health}
		if has_hit_dice:
			data["hitDice"] = hit_dice
			data["magicResistance"] = magic_resistance
		return data


class Combatant:
	extends RefCounted
	var id: String
	var kind: StringName
	var name: String
	var current_health: int
	var maximum_health: int
	var spell_points: int
	var maximum_spell_points: int
	var armor: int
	var magic_resistance: int
	var hit_dice: int
	var has_hit_dice: bool
	var attacks: String
	var movement: int
	var maximum_movement: int
	var traitor: bool
	var helpless: bool
	var conditions: Array[String] = []
	var items: Array[String] = []
	var attack_rows: Array[String] = []
	var immunities: Array[String] = []
	var vulnerabilities: Array[String] = []
	var weapon: String
	var weapon_charges: int = -1
	var has_weapon_charges: bool
	var range: int = -1
	var blocked: bool
	var has_position_facts: bool

	func to_data() -> Dictionary:
		var data := {"id": id, "kind": String(kind), "name": name, "currentHealth": current_health, "maximumHealth": maximum_health, "spellPoints": spell_points, "maximumSpellPoints": maximum_spell_points, "armor": armor, "magicResistance": magic_resistance, "attacks": attacks, "movement": movement, "maximumMovement": maximum_movement, "traitor": traitor, "helpless": helpless, "conditions": conditions.duplicate(), "items": items.duplicate(), "attackRows": attack_rows.duplicate()}
		if has_hit_dice: data["hitDice"] = hit_dice
		if not immunities.is_empty(): data["immunities"] = immunities.duplicate()
		if not vulnerabilities.is_empty(): data["vulnerabilities"] = vulnerabilities.duplicate()
		if not weapon.is_empty(): data["weapon"] = weapon
		if has_weapon_charges: data["weaponCharges"] = weapon_charges
		if has_position_facts:
			data["range"] = range
			data["blocked"] = blocked
		return data


class MovementOption:
	extends RefCounted
	var direction: Vector2i
	var destination: Vector2i
	var cost: int
	var enabled: bool
	var reason_code: StringName
	var reason: String
	var retreat: bool
	var forced_retreat: bool
	var attack_target_id: String
	var attack_target_name: String

	func to_data() -> Dictionary:
		return {"direction": [direction.x, direction.y], "destination": [destination.x, destination.y], "cost": cost, "enabled": enabled, "reasonCode": String(reason_code), "reason": reason, "retreat": retreat, "forcedRetreat": forced_retreat, "attackTargetId": attack_target_id, "attackTargetName": attack_target_name}


class CastOption:
	extends RefCounted
	var source_kind: StringName
	var spell_id: String
	var spell_name: String
	var power: int
	var cost: int
	var target_id: String
	var target_name: String
	var target_current_health: int
	var target_maximum_health: int
	var target_mode: StringName
	var maximum_targets: int = 1
	var target_candidates: Array[CombatTarget] = []
	var area_shape: int
	var default_target_coordinate: Vector2i
	var area_offsets: Array[Vector2i] = []
	var area_rotation_offsets: Array = []
	var legal_target_coordinates: Array[Vector2i] = []
	var item_instance_id: String
	var item_id: String
	var item_name: String
	var charges: int
	var power_staged: bool
	var scroll_slot: int = -1

	func to_data() -> Dictionary:
		var data := {"spellId": spell_id, "spellName": spell_name, "power": power, "targetId": target_id, "targetName": target_name, "targetCurrentHealth": target_current_health, "targetMaximumHealth": target_maximum_health, "targetMode": String(target_mode)}
		if source_kind == &"spell": data["cost"] = cost
		if source_kind == &"item":
			data["itemInstanceId"] = item_instance_id
			data["itemId"] = item_id
			data["itemName"] = item_name
			data["charges"] = charges
			data["powerStaged"] = power_staged
		if source_kind == &"scroll": data["scrollSlot"] = scroll_slot
		if target_mode in [&"sequence", &"coordinate_sequence"]:
			data["maximumTargets"] = maximum_targets
		if target_mode == &"sequence":
			data["targetCandidates"] = target_candidates.map(func(value: CombatTarget) -> Dictionary: return value.to_data())
		if target_mode == &"area":
			data["areaShape"] = area_shape
			data["defaultTargetCoordinate"] = [default_target_coordinate.x, default_target_coordinate.y]
			data["areaOffsets"] = area_offsets.map(func(value: Vector2i) -> Array[int]: return [value.x, value.y])
			data["areaRotationOffsets"] = area_rotation_offsets.map(func(offsets: Array) -> Array: return offsets.map(func(value: Vector2i) -> Array[int]: return [value.x, value.y]))
			data["legalTargetCoordinates"] = legal_target_coordinates.map(func(value: Vector2i) -> Array[int]: return [value.x, value.y])
		return data


class FastSpell:
	extends RefCounted
	var slot: int
	var spell_id: String
	var spell_name: String
	var power: int
	var enabled: bool
	var reason: String

	func to_data() -> Dictionary:
		return {"slot": slot, "spellId": spell_id, "spellName": spell_name, "power": power, "enabled": enabled, "reason": reason}


class RewardAssignment:
	extends RefCounted
	var character_id: String
	var enabled: bool
	var reason: String

	func to_data() -> Dictionary:
		return {"characterId": character_id, "enabled": enabled, "reason": reason}


class RewardFact:
	extends RefCounted
	var label: String
	var value: String

	func to_data() -> Dictionary:
		return {"label": label, "value": value}


class RewardItem:
	extends RefCounted
	var instance_id: String
	var definition_id: String
	var name: String
	var charges: int
	var identified: bool
	var magical: bool
	var has_magical: bool
	var icon_resource_type: String = "cicn"
	var icon_id: int
	var description: String
	var facts: Array[RewardFact] = []
	var assignments: Array[RewardAssignment] = []
	var has_assignments: bool

	func to_data() -> Dictionary:
		var data := {"instanceId": instance_id, "definitionId": definition_id, "name": name, "charges": charges, "identified": identified}
		if has_magical: data["magical"] = magical
		if icon_id > 0:
			data["iconResourceType"] = icon_resource_type
			data["iconId"] = icon_id
		data["description"] = description
		data["facts"] = facts.map(func(value: RewardFact) -> Dictionary: return value.to_data())
		if has_assignments:
			data["assignments"] = assignments.map(func(value: RewardAssignment) -> Dictionary: return value.to_data())
		return data


class RewardCharacter:
	extends RefCounted
	var id: String
	var name: String
	var enabled: bool
	var reason: String
	var current_health: int
	var maximum_health: int
	var has_health: bool
	var wealth: Wealth
	var can_take_gold: bool
	var can_take_gems: bool
	var can_take_jewelry: bool
	var gold_reason: String
	var gems_reason: String
	var jewelry_reason: String
	var item_count: int
	var maximum_movement: int
	var carried_load: int
	var maximum_load: int

	func to_data() -> Dictionary:
		var data := {"id": id, "name": name, "enabled": enabled, "reason": reason}
		if has_health:
			data["currentHealth"] = current_health
			data["maximumHealth"] = maximum_health
		else:
			data.merge({"wealth": wealth.to_data(), "canTakeGold": can_take_gold, "canTakeGems": can_take_gems, "canTakeJewelry": can_take_jewelry, "goldReason": gold_reason, "gemsReason": gems_reason, "jewelryReason": jewelry_reason, "itemCount": item_count, "maximumMovement": maximum_movement, "load": carried_load, "maximumLoad": maximum_load})
		return data


class RewardCaster:
	extends RefCounted
	var id: String
	var name: String
	var spell_points: int
	var cost: int

	func to_data() -> Dictionary:
		return {"id": id, "name": name, "spellPoints": spell_points, "cost": cost}


class RewardMethod:
	extends RefCounted
	var visible: bool
	var casters: Array[RewardCaster] = []
	var reason: String

	func to_data() -> Dictionary:
		return {"visible": visible, "casters": casters.map(func(value: RewardCaster) -> Dictionary: return value.to_data()), "reason": reason}


class LevelGains:
	extends RefCounted
	var stamina: int
	var spell_points: int
	var to_hit: int
	var magic_resistance: int

	func to_data() -> Dictionary:
		return {"stamina": stamina, "spellPoints": spell_points, "toHit": to_hit, "magicResistance": magic_resistance}


class SpellChoice:
	extends RefCounted
	var id: String
	var name: String
	var description: String
	var classic_id: int
	var cost: int
	var selected: bool

	func to_data() -> Dictionary:
		return {"id": id, "name": name, "description": description, "classicId": classic_id, "cost": cost, "selected": selected}


class EncounterAction:
	extends RefCounted
	var id: String
	var kind: StringName
	var label: String
	var slot: int = -1
	var action_index: int = -1

	func to_data() -> Dictionary:
		var data := {"id": id, "kind": String(kind), "label": label}
		if slot >= 0: data["slot"] = slot
		if action_index >= 0: data["actionIndex"] = action_index
		return data


class NamedCharacter:
	extends RefCounted
	var id: String
	var name: String
	var portrait_id: String

	func to_data() -> Dictionary: return {"id": id, "name": name, "portraitId": portrait_id}


class ThiefAction:
	extends RefCounted
	var index: int
	var label: String
	var value: int
	var enabled: bool
	var reason: String

	func to_data() -> Dictionary:
		return {"index": index, "label": label, "value": value, "enabled": enabled, "reason": reason}


class ThiefCharacter:
	extends RefCounted
	var id: String
	var name: String
	var portrait_id: String
	var actions: Array[ThiefAction] = []

	func to_data() -> Dictionary:
		return {"id": id, "name": name, "portraitId": portrait_id, "actions": actions.map(func(value: ThiefAction) -> Dictionary: return value.to_data())}


class EncounterCatalogEntry:
	extends RefCounted
	var classic_id: int
	var name: String
	var kind: StringName
	var character_id: String
	var instance_id: String
	var icon_resource_type: String
	var icon_id: int
	var charges: int
	var equipped: bool

	func to_data() -> Dictionary:
		var data := {"name": name, "characterId": character_id}
		data["classicItemId" if kind == &"item" else "classicSpellId"] = classic_id
		if kind == &"item":
			data.merge({"instanceId": instance_id, "iconResourceType": icon_resource_type, "iconId": icon_id, "charges": charges, "equipped": equipped})
		return data


class ChoiceOption:
	extends RefCounted
	var id: String
	var label: String
	var has_id: bool

	func to_data() -> Dictionary:
		var data := {"label": label}
		if has_id: data["id"] = id
		return data


class SelectionCandidate:
	extends RefCounted
	var id: String
	var name: String
	var current_health: int
	var maximum_health: int
	var classic_monster_id: int
	var required: bool
	var can_summon: int
	var has_current_health: bool
	var has_maximum_health: bool
	var has_ally_facts: bool

	func to_data() -> Dictionary:
		var data := {"id": id, "name": name}
		if has_current_health: data["currentHealth"] = current_health
		if has_maximum_health: data["maximumHealth"] = maximum_health
		if has_ally_facts: data.merge({"classicMonsterId": classic_monster_id, "required": required, "canSummon": can_summon})
		return data


class SpellTargetContext:
	extends RefCounted
	var actor_id: String
	var actor_name: String
	var spell_id: String
	var spell_name: String
	var description: String
	var icon_resource_type: String
	var icon_id: int
	var power: int
	var spell_point_cost: int
	var target_type: int
	var target_size: int
	var target_count: int
	var source_kind: StringName

	func to_data() -> Dictionary:
		return {"actorId": actor_id, "actorName": actor_name, "spellId": spell_id, "spellName": spell_name, "description": description, "iconResourceType": icon_resource_type, "iconId": icon_id, "power": power, "spellPointCost": spell_point_cost, "targetType": target_type, "targetSize": target_size, "targetCount": target_count, "sourceKind": String(source_kind)}


class LifecycleOption:
	extends RefCounted
	var action: StringName
	var label: String

	func to_data() -> Dictionary: return {"action": String(action), "label": label}


static func availability(data: Variant) -> Availability:
	if not data is Dictionary or not _exact(data, ["enabled", "reason", "targetMode", "nearestEnemyRange"], ["enabled", "reason"]) or not data["enabled"] is bool or not data["reason"] is String or not _optional_string(data, "targetMode") or not _optional_int(data, "nearestEnemyRange"):
		return null
	var result := Availability.new()
	result.enabled = data["enabled"]
	result.reason = data["reason"]
	result.target_mode = StringName(data.get("targetMode", ""))
	result.nearest_enemy_range = int(data.get("nearestEnemyRange", -1))
	return result


static func wealth(data: Variant) -> Wealth:
	if not data is Dictionary or not _exact(data, ["gold", "gems", "jewelry"], ["gold", "gems", "jewelry"]) or not _ints(data, ["gold", "gems", "jewelry"]): return null
	var result := Wealth.new()
	result.gold = int(data["gold"])
	result.gems = int(data["gems"])
	result.jewelry = int(data["jewelry"])
	return result


static func condition(data: Variant) -> Condition:
	if not data is Dictionary or not _exact(data, ["index", "name", "value"], ["index", "name", "value"]) or not _ints(data, ["index", "value"]) or not data["name"] is String: return null
	var result := Condition.new()
	result.index = int(data["index"])
	result.name = data["name"]
	result.value = int(data["value"])
	return result


static func inventory_item(data: Variant) -> InventoryItem:
	var required := ["instanceId", "itemId", "name", "identified", "equipped", "charges", "sellPrice", "canSell", "sellReason", "canIdentify", "identifyReason"]
	var fields := required + ["iconResourceType", "iconId", "description", "weight", "facts"]
	if not data is Dictionary or not _exact(data, fields, required) or not _strings(data, ["instanceId", "itemId", "name", "sellReason", "identifyReason"]) or not _optional_string(data, "description") or not _optional_int(data, "weight") or not _ints(data, ["charges", "sellPrice"]) or not _bools(data, ["identified", "equipped", "canSell", "canIdentify"]) or data.has("facts") and not data["facts"] is Array: return null
	if not _optional_resource_key(data): return null
	var result := InventoryItem.new()
	result.instance_id = data["instanceId"]; result.item_id = data["itemId"]; result.name = data["name"]
	result.identified = data["identified"]; result.equipped = data["equipped"]; result.charges = int(data["charges"]); result.sell_price = int(data["sellPrice"])
	result.can_sell = data["canSell"]; result.sell_reason = data["sellReason"]; result.can_identify = data["canIdentify"]; result.identify_reason = data["identifyReason"]
	result.icon_resource_type = String(data.get("iconResourceType", "cicn")); result.icon_id = int(data.get("iconId", 0))
	result.description = String(data.get("description", "")); result.weight = int(data.get("weight", 0))
	for entry: Variant in data.get("facts", []):
		var parsed := item_detail_fact(entry); if parsed == null: return null
		result.facts.append(parsed)
	return result


static func shop_stock(data: Variant) -> ShopStock:
	var required := ["stockKey", "index", "itemId", "name", "quantity", "buyPrice", "canBuy", "buyReason"]
	var fields := required + ["category", "iconResourceType", "iconId", "description", "weight", "facts"]
	if not data is Dictionary or not _exact(data, fields, required) or not _strings(data, ["stockKey", "itemId", "name", "buyReason"]) or not _optional_string(data, "category") or not _optional_string(data, "description") or not _optional_int(data, "weight") or not _ints(data, ["index", "quantity", "buyPrice"]) or not data["canBuy"] is bool or data.has("facts") and not data["facts"] is Array: return null
	if not _optional_resource_key(data): return null
	var result := ShopStock.new()
	result.stock_key = data["stockKey"]; result.index = int(data["index"]); result.item_id = data["itemId"]; result.name = data["name"]
	result.quantity = int(data["quantity"]); result.buy_price = int(data["buyPrice"]); result.can_buy = data["canBuy"]; result.buy_reason = data["buyReason"]
	result.category = StringName(data.get("category", ""))
	result.icon_resource_type = String(data.get("iconResourceType", "cicn")); result.icon_id = int(data.get("iconId", 0))
	result.description = String(data.get("description", "")); result.weight = int(data.get("weight", 0))
	for entry: Variant in data.get("facts", []):
		var parsed := item_detail_fact(entry); if parsed == null: return null
		result.facts.append(parsed)
	return result


static func item_detail_fact(data: Variant) -> ItemDetailFact:
	if not data is Dictionary or not _exact(data, ["label", "value"], ["label", "value"]) or not _strings(data, ["label", "value"]): return null
	var result := ItemDetailFact.new(); result.label = data["label"]; result.value = data["value"]; return result


static func temple_service(data: Variant) -> TempleService:
	if not data is Dictionary or not _exact(data, ["id", "label", "description", "cost"], ["id", "label", "description", "cost"]) or not _strings(data, ["id", "label", "description"]) or not _ints(data, ["cost"]): return null
	var result := TempleService.new(); result.id = data["id"]; result.label = data["label"]; result.description = data["description"]; result.cost = int(data["cost"]); return result


static func service_character(data: Variant, mode: StringName) -> ServiceCharacter:
	if not data is Dictionary: return null
	var result := ServiceCharacter.new()
	match mode:
		&"shop":
			if not _exact(data, ["id", "name", "portraitId", "load", "maximumLoad", "inventory"], ["id", "name", "inventory"]) or not _strings(data, ["id", "name"]) or not _optional_string(data, "portraitId") or not _optional_int(data, "load") or not _optional_int(data, "maximumLoad") or not data["inventory"] is Array: return null
			result.portrait_id = String(data.get("portraitId", ""))
			result.load = int(data.get("load", 0)); result.maximum_load = int(data.get("maximumLoad", 0))
			for entry: Variant in data["inventory"]:
				var parsed := inventory_item(entry); if parsed == null: return null
				result.inventory.append(parsed)
		&"temple":
			var fields := ["id", "name", "currentHealth", "maximumHealth", "personalGold", "availableGold", "load", "maximumLoad", "portraitId", "conditions"]
			if not _exact(data, fields, fields) or not _strings(data, ["id", "name", "portraitId"]) or not _ints(data, ["currentHealth", "maximumHealth", "personalGold", "availableGold", "load", "maximumLoad"]) or not data["conditions"] is Array: return null
			result.portrait_id = data["portraitId"]; result.current_health = int(data["currentHealth"]); result.maximum_health = int(data["maximumHealth"]); result.personal_gold = int(data["personalGold"]); result.available_gold = int(data["availableGold"]); result.load = int(data["load"]); result.maximum_load = int(data["maximumLoad"])
			for entry: Variant in data["conditions"]:
				var parsed := condition(entry); if parsed == null: return null
				result.conditions.append(parsed)
		&"bank":
			var fields := ["id", "name", "wealth", "load", "maximumLoad", "transfers"]
			if not _exact(data, fields, fields) or not _strings(data, ["id", "name"]) or not _ints(data, ["load", "maximumLoad"]) or not data["transfers"] is Array: return null
			result.wealth = wealth(data["wealth"]); if result.wealth == null: return null
			result.load = int(data["load"]); result.maximum_load = int(data["maximumLoad"])
			for entry: Variant in data["transfers"]:
				if not entry is Dictionary or not _exact(entry, ["denomination", "amount", "toPool", "toCharacter"], ["denomination", "amount", "toPool", "toCharacter"]) or not entry["denomination"] is String or not _whole(entry["amount"]): return null
				var transfer := Transfer.new(); transfer.denomination = StringName(entry["denomination"]); transfer.amount = int(entry["amount"]); transfer.to_pool = availability(entry["toPool"]); transfer.to_character = availability(entry["toCharacter"])
				if transfer.to_pool == null or transfer.to_character == null: return null
				result.transfers.append(transfer)
		_: return null
	result.id = data["id"]; result.name = data["name"]
	return result


static func combat_target(data: Variant) -> CombatTarget:
	if not data is Dictionary or not _exact(data, ["id", "kind", "name", "currentHealth", "maximumHealth", "hitDice", "magicResistance"], ["id", "name"]): return null
	if not _strings(data, ["id", "name"]) or not _optional_string(data, "kind") or not _optional_int(data, "currentHealth") or not _optional_int(data, "maximumHealth") or not _optional_int(data, "hitDice") or not _optional_int(data, "magicResistance"): return null
	var result := CombatTarget.new(); result.id = data["id"]; result.kind = StringName(data.get("kind", "")); result.name = data["name"]; result.current_health = int(data.get("currentHealth", 0)); result.maximum_health = int(data.get("maximumHealth", 0)); result.hit_dice = int(data.get("hitDice", 0)); result.magic_resistance = int(data.get("magicResistance", 0)); result.has_hit_dice = data.has("hitDice"); return result


static func combatant(data: Variant) -> Combatant:
	var allowed := ["id", "kind", "name", "currentHealth", "maximumHealth", "spellPoints", "maximumSpellPoints", "armor", "magicResistance", "hitDice", "attacks", "movement", "maximumMovement", "traitor", "helpless", "conditions", "items", "attackRows", "immunities", "vulnerabilities", "weapon", "weaponCharges", "range", "blocked"]
	var required := ["id", "kind", "name", "currentHealth", "maximumHealth", "spellPoints", "maximumSpellPoints", "armor", "magicResistance", "attacks", "movement", "maximumMovement", "traitor", "helpless", "conditions"]
	if not data is Dictionary or not _exact(data, allowed, required) or not _strings(data, ["id", "kind", "name"]) or not _ints(data, ["currentHealth", "maximumHealth", "spellPoints", "maximumSpellPoints", "armor", "magicResistance", "movement", "maximumMovement"]) or not data["attacks"] is String or not _bools(data, ["traitor", "helpless"]) or not _string_array(data["conditions"]): return null
	if not _optional_int(data, "hitDice") or not _optional_string(data, "weapon") or not _optional_int(data, "weaponCharges") or not _optional_int(data, "range") or data.has("blocked") and not data["blocked"] is bool or data.has("items") and not _string_array(data["items"]) or data.has("attackRows") and not _string_array(data["attackRows"]) or data.has("immunities") and not _string_array(data["immunities"]) or data.has("vulnerabilities") and not _string_array(data["vulnerabilities"]): return null
	var result := Combatant.new()
	result.id = data["id"]; result.kind = StringName(data["kind"]); result.name = data["name"]; result.current_health = int(data["currentHealth"]); result.maximum_health = int(data["maximumHealth"]); result.spell_points = int(data["spellPoints"]); result.maximum_spell_points = int(data["maximumSpellPoints"]); result.armor = int(data["armor"]); result.magic_resistance = int(data["magicResistance"]); result.attacks = data["attacks"]; result.movement = int(data["movement"]); result.maximum_movement = int(data["maximumMovement"]); result.traitor = data["traitor"]; result.helpless = data["helpless"]
	result.conditions = _string_values(data["conditions"]); result.items = _string_values(data.get("items", [])); result.attack_rows = _string_values(data.get("attackRows", [])); result.immunities = _string_values(data.get("immunities", [])); result.vulnerabilities = _string_values(data.get("vulnerabilities", [])); result.hit_dice = int(data.get("hitDice", 0)); result.has_hit_dice = data.has("hitDice"); result.weapon = String(data.get("weapon", "")); result.weapon_charges = int(data.get("weaponCharges", -1)); result.has_weapon_charges = data.has("weaponCharges"); result.range = int(data.get("range", -1)); result.blocked = bool(data.get("blocked", false)); result.has_position_facts = data.has("range")
	return result


static func movement_option(data: Variant) -> MovementOption:
	var fields := ["direction", "destination", "cost", "enabled", "reasonCode", "reason", "retreat", "forcedRetreat", "attackTargetId", "attackTargetName"]
	if not data is Dictionary or not _exact(data, fields, fields) or not _coordinate(data["direction"]) or not _coordinate(data["destination"]) or not _ints(data, ["cost"]) or not _bools(data, ["enabled", "retreat", "forcedRetreat"]) or not _strings(data, ["reasonCode", "reason", "attackTargetId", "attackTargetName"]): return null
	var result := MovementOption.new(); result.direction = _vector(data["direction"]); result.destination = _vector(data["destination"]); result.cost = int(data["cost"]); result.enabled = data["enabled"]; result.reason_code = StringName(data["reasonCode"]); result.reason = data["reason"]; result.retreat = data["retreat"]; result.forced_retreat = data["forcedRetreat"]; result.attack_target_id = data["attackTargetId"]; result.attack_target_name = data["attackTargetName"]; return result


static func fast_spell(data: Variant) -> FastSpell:
	var fields := ["slot", "spellId", "spellName", "power", "enabled", "reason"]
	if not data is Dictionary or not _exact(data, fields, fields) or not _ints(data, ["slot", "power"]) or not _strings(data, ["spellId", "spellName", "reason"]) or not data["enabled"] is bool: return null
	var result := FastSpell.new(); result.slot = int(data["slot"]); result.spell_id = data["spellId"]; result.spell_name = data["spellName"]; result.power = int(data["power"]); result.enabled = data["enabled"]; result.reason = data["reason"]; return result


static func cast_option(data: Variant, source_kind: StringName) -> CastOption:
	if not data is Dictionary: return null
	var common := ["spellId", "spellName", "power", "targetId", "targetName", "targetCurrentHealth", "targetMaximumHealth", "targetMode", "maximumTargets", "targetCandidates", "areaShape", "defaultTargetCoordinate", "areaOffsets", "areaRotationOffsets", "legalTargetCoordinates"]
	var allowed := common.duplicate()
	if source_kind == &"spell": allowed.append("cost")
	if source_kind == &"item": allowed.append_array(["itemInstanceId", "itemId", "itemName", "charges", "powerStaged"])
	if source_kind == &"scroll": allowed.append("scrollSlot")
	if not _exact(data, allowed, ["spellId", "spellName", "power", "targetId", "targetName", "targetCurrentHealth", "targetMaximumHealth", "targetMode"]): return null
	if not _strings(data, ["spellId", "spellName", "targetId", "targetName", "targetMode"]) or not _ints(data, ["power", "targetCurrentHealth", "targetMaximumHealth"]): return null
	var result := CastOption.new(); result.source_kind = source_kind; result.spell_id = data["spellId"]; result.spell_name = data["spellName"]; result.power = int(data["power"]); result.target_id = data["targetId"]; result.target_name = data["targetName"]; result.target_current_health = int(data["targetCurrentHealth"]); result.target_maximum_health = int(data["targetMaximumHealth"]); result.target_mode = StringName(data["targetMode"])
	if source_kind == &"spell":
		if not _whole(data.get("cost")): return null
		result.cost = int(data["cost"])
	elif source_kind == &"item":
		if not _strings(data, ["itemInstanceId", "itemId", "itemName"]) or not _ints(data, ["charges"]) or not data.get("powerStaged", false) is bool: return null
		result.item_instance_id = data["itemInstanceId"]; result.item_id = data["itemId"]; result.item_name = data["itemName"]; result.charges = int(data["charges"]); result.power_staged = bool(data.get("powerStaged", false))
	elif source_kind == &"scroll":
		if not _whole(data.get("scrollSlot")): return null
		result.scroll_slot = int(data["scrollSlot"])
	if result.target_mode in [&"sequence", &"coordinate_sequence"]:
		if not _whole(data.get("maximumTargets")): return null
		result.maximum_targets = int(data["maximumTargets"])
	if result.target_mode == &"sequence":
		if not data.get("targetCandidates") is Array: return null
		for candidate: Variant in data["targetCandidates"]:
			var parsed := combat_target(candidate); if parsed == null: return null
			result.target_candidates.append(parsed)
	elif result.target_mode == &"area":
		if not _whole(data.get("areaShape")) or not _coordinate(data.get("defaultTargetCoordinate")) or not data.get("areaOffsets") is Array or not data.get("legalTargetCoordinates") is Array: return null
		result.area_shape = int(data["areaShape"]); result.default_target_coordinate = _vector(data["defaultTargetCoordinate"])
		for coordinate: Variant in data["areaOffsets"]:
			if not _coordinate(coordinate): return null
			result.area_offsets.append(_vector(coordinate))
		if data.has("areaRotationOffsets"):
			if not data["areaRotationOffsets"] is Array: return null
			for rotation_offsets: Variant in data["areaRotationOffsets"]:
				if not rotation_offsets is Array: return null
				var parsed_offsets: Array[Vector2i] = []
				for coordinate: Variant in rotation_offsets:
					if not _coordinate(coordinate): return null
					parsed_offsets.append(_vector(coordinate))
				result.area_rotation_offsets.append(parsed_offsets)
		for coordinate: Variant in data["legalTargetCoordinates"]:
			if not _coordinate(coordinate): return null
			result.legal_target_coordinates.append(_vector(coordinate))
	return result


static func reward_item(data: Variant) -> RewardItem:
	var fields := ["instanceId", "definitionId", "name", "charges", "identified", "magical", "iconResourceType", "iconId", "description", "facts", "assignments"]
	if not data is Dictionary or not _exact(data, fields, ["instanceId", "definitionId", "name", "charges", "identified", "description", "facts"]) or not _strings(data, ["instanceId", "definitionId", "name", "description"]) or not _ints(data, ["charges"]) or not data["identified"] is bool or data.has("magical") and not data["magical"] is bool or not data["facts"] is Array: return null
	if not _optional_resource_key(data): return null
	var result := RewardItem.new(); result.instance_id = data["instanceId"]; result.definition_id = data["definitionId"]; result.name = data["name"]; result.charges = int(data["charges"]); result.identified = data["identified"]; result.magical = bool(data.get("magical", false)); result.has_magical = data.has("magical"); result.icon_resource_type = String(data.get("iconResourceType", "cicn")); result.icon_id = int(data.get("iconId", 0)); result.description = data["description"]; result.has_assignments = data.has("assignments")
	for entry: Variant in data["facts"]:
		if not entry is Dictionary or not _exact(entry, ["label", "value"], ["label", "value"]) or not _strings(entry, ["label", "value"]): return null
		var fact := RewardFact.new(); fact.label = entry["label"]; fact.value = entry["value"]; result.facts.append(fact)
	if result.has_assignments:
		if not data["assignments"] is Array: return null
		for entry: Variant in data["assignments"]:
			if not entry is Dictionary or not _exact(entry, ["characterId", "enabled", "reason"], ["characterId", "enabled", "reason"]) or not _strings(entry, ["characterId", "reason"]) or not entry["enabled"] is bool: return null
			var assignment := RewardAssignment.new(); assignment.character_id = entry["characterId"]; assignment.enabled = entry["enabled"]; assignment.reason = entry["reason"]; result.assignments.append(assignment)
	return result


static func reward_character(data: Variant, mode: StringName) -> RewardCharacter:
	if not data is Dictionary: return null
	var result := RewardCharacter.new()
	if mode == &"fumbled-item-recovery":
		var fields := ["id", "name", "currentHealth", "maximumHealth", "enabled", "reason"]
		if not _exact(data, fields, fields) or not _strings(data, ["id", "name", "reason"]) or not _ints(data, ["currentHealth", "maximumHealth"]) or not data["enabled"] is bool: return null
		result.current_health = int(data["currentHealth"]); result.maximum_health = int(data["maximumHealth"]); result.has_health = true
	elif mode == &"ordinary":
		var fields := ["id", "name", "enabled", "reason", "wealth", "canTakeGold", "canTakeGems", "canTakeJewelry", "goldReason", "gemsReason", "jewelryReason", "itemCount", "maximumMovement", "load", "maximumLoad"]
		if not _exact(data, fields, fields) or not _strings(data, ["id", "name", "reason", "goldReason", "gemsReason", "jewelryReason"]) or not _bools(data, ["enabled", "canTakeGold", "canTakeGems", "canTakeJewelry"]) or not _ints(data, ["itemCount", "maximumMovement", "load", "maximumLoad"]): return null
		result.wealth = wealth(data["wealth"]); if result.wealth == null: return null
		result.can_take_gold = data["canTakeGold"]; result.can_take_gems = data["canTakeGems"]; result.can_take_jewelry = data["canTakeJewelry"]; result.gold_reason = data["goldReason"]; result.gems_reason = data["gemsReason"]; result.jewelry_reason = data["jewelryReason"]
		result.item_count = int(data["itemCount"]); result.maximum_movement = int(data["maximumMovement"]); result.carried_load = int(data["load"]); result.maximum_load = int(data["maximumLoad"])
	else: return null
	result.id = data["id"]; result.name = data["name"]; result.enabled = data["enabled"]; result.reason = data["reason"]
	return result


static func reward_method(data: Variant) -> RewardMethod:
	if not data is Dictionary or not _exact(data, ["visible", "casters", "reason"], ["visible", "casters", "reason"]) or not data["visible"] is bool or not data["casters"] is Array or not data["reason"] is String: return null
	var result := RewardMethod.new(); result.visible = data["visible"]; result.reason = data["reason"]
	for entry: Variant in data["casters"]:
		if not entry is Dictionary or not _exact(entry, ["id", "name", "spellPoints", "cost"], ["id", "name", "spellPoints", "cost"]) or not _strings(entry, ["id", "name"]) or not _ints(entry, ["spellPoints", "cost"]): return null
		var caster := RewardCaster.new(); caster.id = entry["id"]; caster.name = entry["name"]; caster.spell_points = int(entry["spellPoints"]); caster.cost = int(entry["cost"]); result.casters.append(caster)
	return result


static func level_gains(data: Variant) -> LevelGains:
	var fields := ["stamina", "spellPoints", "toHit", "magicResistance"]
	if not data is Dictionary or not _exact(data, fields, fields) or not _ints(data, fields): return null
	var result := LevelGains.new(); result.stamina = int(data["stamina"]); result.spell_points = int(data["spellPoints"]); result.to_hit = int(data["toHit"]); result.magic_resistance = int(data["magicResistance"]); return result


static func spell_choice(data: Variant) -> SpellChoice:
	var fields := ["id", "name", "description", "classicId", "cost", "selected"]
	if not data is Dictionary or not _exact(data, fields, ["id", "name", "classicId", "cost", "selected"]) or not _strings(data, ["id", "name"]) or not _optional_string(data, "description") or not _ints(data, ["classicId", "cost"]) or not data["selected"] is bool: return null
	var result := SpellChoice.new(); result.id = data["id"]; result.name = data["name"]; result.description = String(data.get("description", "")); result.classic_id = int(data["classicId"]); result.cost = int(data["cost"]); result.selected = data["selected"]; return result


static func encounter_action(data: Variant) -> EncounterAction:
	if not data is Dictionary or not _exact(data, ["id", "kind", "label", "slot", "actionIndex"], ["id", "kind", "label"]) or not _strings(data, ["id", "kind", "label"]) or not _optional_int(data, "slot") or not _optional_int(data, "actionIndex"): return null
	var result := EncounterAction.new(); result.id = data["id"]; result.kind = StringName(data["kind"]); result.label = data["label"]; result.slot = int(data.get("slot", -1)); result.action_index = int(data.get("actionIndex", -1))
	if result.kind not in [&"choice", &"word", &"spell", &"item", &"thief", &"back"]: return null
	if result.kind == &"choice" and result.slot < 0: return null
	return result


static func named_character(data: Variant) -> NamedCharacter:
	if not data is Dictionary or not _exact(data, ["id", "name", "portraitId"], ["id", "name", "portraitId"]) or not _strings(data, ["id", "name", "portraitId"]): return null
	var result := NamedCharacter.new(); result.id = data["id"]; result.name = data["name"]; result.portrait_id = data["portraitId"]; return result


static func thief_action(data: Variant) -> ThiefAction:
	var fields := ["index", "label", "value", "enabled", "reason"]
	if not data is Dictionary or not _exact(data, fields, fields) or not _ints(data, ["index", "value"]) or not _strings(data, ["label", "reason"]) or not data["enabled"] is bool:
		return null
	var result := ThiefAction.new()
	result.index = int(data["index"])
	result.label = data["label"]
	result.value = int(data["value"])
	result.enabled = data["enabled"]
	result.reason = data["reason"]
	return result if result.index >= 0 and result.index < 8 else null


static func thief_character(data: Variant) -> ThiefCharacter:
	var fields := ["id", "name", "portraitId", "actions"]
	if not data is Dictionary or not _exact(data, fields, fields) or not _strings(data, ["id", "name", "portraitId"]) or not data["actions"] is Array:
		return null
	var result := ThiefCharacter.new()
	result.id = data["id"]
	result.name = data["name"]
	result.portrait_id = data["portraitId"]
	for entry: Variant in data["actions"]:
		var action := thief_action(entry)
		if action == null:
			return null
		result.actions.append(action)
	return result if not result.id.is_empty() else null


static func encounter_catalog_entry(data: Variant, kind: StringName) -> EncounterCatalogEntry:
	var id_field := "classicItemId" if kind == &"item" else "classicSpellId"
	var fields := [id_field, "name", "characterId"] if kind == &"spell" else [id_field, "name", "characterId", "instanceId", "iconResourceType", "iconId", "charges", "equipped"]
	if not data is Dictionary or not _exact(data, fields, fields) or not _whole(data[id_field]) or not _strings(data, ["name", "characterId"]): return null
	if kind == &"item" and (not _strings(data, ["instanceId", "iconResourceType"]) or not _ints(data, ["iconId", "charges"]) or not data["equipped"] is bool): return null
	var result := EncounterCatalogEntry.new(); result.classic_id = int(data[id_field]); result.name = data["name"]; result.kind = kind; result.character_id = data["characterId"]
	if kind == &"item": result.instance_id = data["instanceId"]; result.icon_resource_type = data["iconResourceType"]; result.icon_id = int(data["iconId"]); result.charges = int(data["charges"]); result.equipped = data["equipped"]
	return result if not result.character_id.is_empty() and (kind != &"item" or not result.instance_id.is_empty()) else null


static func choice_option(data: Variant) -> ChoiceOption:
	if not data is Dictionary or not _exact(data, ["id", "label"], ["label"]) or not data["label"] is String or not _optional_string(data, "id"): return null
	var result := ChoiceOption.new(); result.id = String(data.get("id", "")); result.label = data["label"]; result.has_id = data.has("id"); return result


static func selection_candidate(data: Variant) -> SelectionCandidate:
	var allowed := ["id", "name", "currentHealth", "maximumHealth", "classicMonsterId", "required", "canSummon"]
	if not data is Dictionary or not _exact(data, allowed, ["id", "name"]) or not _strings(data, ["id", "name"]) or not _optional_int(data, "currentHealth") or not _optional_int(data, "maximumHealth") or not _optional_int(data, "classicMonsterId") or not _optional_int(data, "canSummon") or data.has("required") and not data["required"] is bool: return null
	var result := SelectionCandidate.new(); result.id = data["id"]; result.name = data["name"]; result.current_health = int(data.get("currentHealth", 0)); result.maximum_health = int(data.get("maximumHealth", 0)); result.has_current_health = data.has("currentHealth"); result.has_maximum_health = data.has("maximumHealth")
	var ally_fields: bool = data.has("classicMonsterId") or data.has("required") or data.has("canSummon")
	if ally_fields and not (data.has("classicMonsterId") and data.has("required") and data.has("canSummon")): return null
	result.has_ally_facts = ally_fields; result.classic_monster_id = int(data.get("classicMonsterId", 0)); result.required = bool(data.get("required", false)); result.can_summon = int(data.get("canSummon", 0)); return result


static func spell_target_context(data: Variant) -> SpellTargetContext:
	var fields := ["actorId", "actorName", "spellId", "spellName", "description", "iconResourceType", "iconId", "power", "spellPointCost", "targetType", "targetSize", "targetCount", "sourceKind"]
	if not data is Dictionary or not _exact(data, fields, fields) or not _strings(data, ["actorId", "actorName", "spellId", "spellName", "description", "iconResourceType", "sourceKind"]) or not _ints(data, ["iconId", "power", "spellPointCost", "targetType", "targetSize", "targetCount"]): return null
	var result := SpellTargetContext.new()
	result.actor_id = data["actorId"]; result.actor_name = data["actorName"]; result.spell_id = data["spellId"]; result.spell_name = data["spellName"]; result.description = data["description"]; result.icon_resource_type = data["iconResourceType"]; result.icon_id = int(data["iconId"]); result.power = int(data["power"]); result.spell_point_cost = int(data["spellPointCost"]); result.target_type = int(data["targetType"]); result.target_size = int(data["targetSize"]); result.target_count = int(data["targetCount"]); result.source_kind = StringName(data["sourceKind"])
	if result.actor_id.is_empty() or result.spell_id.is_empty() or result.spell_name.is_empty() or result.power < 1 or result.power > 7 or result.spell_point_cost < 0 or result.target_count < 1 or result.source_kind not in [&"field-spell", &"scroll-use", &"item-use"]: return null
	return result


static func lifecycle_option(data: Variant) -> LifecycleOption:
	if not data is Dictionary or not _exact(data, ["action", "label"], ["action", "label"]) or not _strings(data, ["action", "label"]): return null
	var result := LifecycleOption.new(); result.action = StringName(data["action"]); result.label = data["label"]; return result


static func _exact(data: Dictionary, allowed: Array, required: Array = []) -> bool:
	for key: Variant in data:
		if not key is String or not allowed.has(key): return false
	for key: Variant in required:
		if not data.has(key): return false
	return true


static func _strings(data: Dictionary, fields: Array) -> bool:
	for field: Variant in fields:
		if not data.get(field) is String: return false
	return true


static func _ints(data: Dictionary, fields: Array) -> bool:
	for field: Variant in fields:
		if not _whole(data.get(field)): return false
	return true


static func _bools(data: Dictionary, fields: Array) -> bool:
	for field: Variant in fields:
		if not data.get(field) is bool: return false
	return true


static func _optional_string(data: Dictionary, field: String) -> bool:
	return not data.has(field) or data[field] is String


static func _optional_int(data: Dictionary, field: String) -> bool:
	return not data.has(field) or _whole(data[field])


static func _optional_resource_key(data: Dictionary) -> bool:
	if data.has("iconResourceType") != data.has("iconId"):
		return false
	if not data.has("iconId"):
		return true
	return data["iconResourceType"] is String and not String(data["iconResourceType"]).is_empty() and _whole(data["iconId"]) and int(data["iconId"]) > 0


static func _whole(value: Variant) -> bool:
	return value is int or value is float and is_finite(value) and value == floor(value)


static func _coordinate(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _whole(value[0]) and _whole(value[1])


static func _vector(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


static func _string_array(value: Variant) -> bool:
	if not value is Array: return false
	for entry: Variant in value:
		if not entry is String: return false
	return true


static func _string_values(value: Array) -> Array[String]:
	var result: Array[String] = []
	for entry: Variant in value: result.append(entry)
	return result
