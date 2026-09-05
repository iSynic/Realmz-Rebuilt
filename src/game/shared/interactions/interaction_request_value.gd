## Carries typed interaction request value data across the gameplay transaction boundary.

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
