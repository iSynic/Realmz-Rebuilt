## Strictly decodes lifecycle, service, and combat interaction request bodies.
class_name InteractionServiceRequestDecoder
extends RefCounted


static func parse(request_kind: StringName, payload: Dictionary) -> InteractionRequestBody:
	match request_kind:
		&"shop_action":
			var shop := ShopRequestBody.new()
			return shop if populate_shop(payload, shop) else null
		&"temple_action":
			var temple := TempleRequestBody.new()
			return temple if populate_temple(payload, temple) else null
		&"bank_action", &"pooled_wealth_departure":
			var bank := BankRequestBody.new()
			var departure := request_kind == &"pooled_wealth_departure"
			return bank if populate_bank(payload, departure, bank) else null
		&"combat_action":
			var combat := CombatRequestBody.new()
			return combat if populate_combat(payload, combat) else null
		&"session_lifecycle":
			var lifecycle := LifecycleRequestBody.new()
			return lifecycle if populate_lifecycle(payload, lifecycle) else null
	return null


static func populate_lifecycle(payload: Dictionary, result: Variant) -> bool:
	if not _fields_are_exact(payload, ["operation", "prompt", "hasActiveSession", "inCombat", "options"], ["operation", "prompt", "inCombat", "options"]): return false
	if not _required_strings(payload, ["operation", "prompt"]) or not payload["inCombat"] is bool or not payload["options"] is Array or not _optional_bools(payload, ["hasActiveSession"]): return false
	result.operation = StringName(payload["operation"])
	result.prompt = payload["prompt"]
	result.has_active_session = bool(payload.get("hasActiveSession", false))
	result.in_combat = payload["inCombat"]
	result.includes_active_session = payload.has("hasActiveSession")
	for entry: Variant in payload["options"]:
		var option := InteractionSelectionValueDecoder.lifecycle_option(entry)
		if option == null: return false
		result.options.append(option)
	return true


static func populate_shop(payload: Dictionary, result: Variant) -> bool:
	var fields: Array[String] = ["shopId", "inflationPercent", "partyGold", "identifyPrice", "stock", "characters", "acceptRanges", "actions"]
	if not _fields_are_exact(payload, fields, fields) or not _required_strings(payload, ["shopId"]): return false
	if not _required_ints(payload, ["inflationPercent", "partyGold", "identifyPrice"]) or not _required_arrays(payload, ["stock", "characters", "acceptRanges", "actions"]): return false
	result.shop_id = payload["shopId"]
	result.inflation_percent = int(payload["inflationPercent"])
	result.party_gold = int(payload["partyGold"])
	result.identify_price = int(payload["identifyPrice"])
	for entry: Variant in payload["stock"]:
		var stock := InteractionServiceValueDecoder.shop_stock(entry)
		if stock == null: return false
		result.stock.append(stock)
	for entry: Variant in payload["characters"]:
		var character := InteractionServiceValueDecoder.service_character(entry, &"shop")
		if character == null: return false
		result.characters.append(character)
	for entry: Variant in payload["acceptRanges"]:
		if not _whole_number(entry): return false
		result.accept_ranges.append(int(entry))
	if not _array_is_strings(payload["actions"]): return false
	result.actions = _strings(payload["actions"])
	return true


static func populate_temple(payload: Dictionary, result: Variant) -> bool:
	var fields: Array[String] = ["costPercent", "characters", "services", "pooledWealth", "bankAvailable", "selectedCharacterId", "actions"]
	if not _fields_are_exact(payload, fields, fields) or not _required_ints(payload, ["costPercent"]): return false
	if not _required_arrays(payload, ["characters", "services", "actions"]) or not payload["bankAvailable"] is bool or not payload["selectedCharacterId"] is String: return false
	result.cost_percent = int(payload["costPercent"])
	result.pooled_wealth = InteractionCommonValueDecoder.wealth(payload["pooledWealth"])
	if result.pooled_wealth == null: return false
	result.bank_available = payload["bankAvailable"]
	result.selected_character_id = payload["selectedCharacterId"]
	for entry: Variant in payload["characters"]:
		var character := InteractionServiceValueDecoder.service_character(entry, &"temple")
		if character == null: return false
		result.characters.append(character)
	for entry: Variant in payload["services"]:
		var service := InteractionServiceValueDecoder.temple_service(entry)
		if service == null: return false
		result.services.append(service)
	if not _array_is_strings(payload["actions"]): return false
	result.actions = _strings(payload["actions"])
	return true


static func populate_bank(payload: Dictionary, departure: bool, result: Variant) -> bool:
	var allowed: Array[String] = ["mode", "selectedCharacterId", "pooledWealth", "bankedWealth", "pool", "share", "characters", "actions"]
	var required: Array[String] = ["selectedCharacterId", "pooledWealth", "bankedWealth", "pool", "share", "characters"]
	if not departure: required.append("actions")
	if not _fields_are_exact(payload, allowed, required) or not payload["selectedCharacterId"] is String or not payload["characters"] is Array or not _optional_strings(payload, ["mode"]): return false
	if departure and String(payload.get("mode", "")) != "departure": return false
	result.mode = StringName(payload.get("mode", ""))
	result.has_mode = payload.has("mode")
	result.selected_character_id = payload["selectedCharacterId"]
	result.pooled_wealth = InteractionCommonValueDecoder.wealth(payload["pooledWealth"])
	result.banked_wealth = InteractionCommonValueDecoder.wealth(payload["bankedWealth"])
	result.pool = InteractionCommonValueDecoder.availability(payload["pool"])
	result.share = InteractionCommonValueDecoder.availability(payload["share"])
	if result.pooled_wealth == null or result.banked_wealth == null or result.pool == null or result.share == null: return false
	for entry: Variant in payload["characters"]:
		var character := InteractionServiceValueDecoder.service_character(entry, &"bank")
		if character == null: return false
		result.characters.append(character)
	if payload.has("actions"):
		if not _array_is_strings(payload["actions"]): return false
		result.actions = _strings(payload["actions"])
	return true


static func populate_combat(payload: Dictionary, result: Variant) -> bool:
	var fields: Array[String] = ["battleId", "round", "actorId", "attackUnitsRemaining", "movementRemaining", "enemiesRemaining", "actions", "weaponMode", "weaponSwitch", "rangedAttack", "retreat", "meleeAttackReason", "targets", "combatants", "movement", "spellCasts", "spellCastReason", "fastSpells", "itemCasts", "itemCastReason", "scrollCasts", "scrollCastReason", "autoTurn", "autoCharacterIds", "delay", "bandage", "turnUndead", "undo"]
	if not _fields_are_exact(payload, fields, fields): return false
	if not _required_strings(payload, ["battleId", "actorId", "weaponMode", "meleeAttackReason", "spellCastReason", "itemCastReason", "scrollCastReason"]): return false
	if not _required_ints(payload, ["round", "attackUnitsRemaining", "movementRemaining", "enemiesRemaining"]): return false
	if not _required_arrays(payload, ["actions", "targets", "combatants", "movement", "spellCasts", "fastSpells", "itemCasts", "scrollCasts", "autoCharacterIds"]): return false
	result.battle_id = payload["battleId"]
	result.round_number = int(payload["round"])
	result.actor_id = payload["actorId"]
	result.attack_units_remaining = int(payload["attackUnitsRemaining"])
	result.movement_remaining = int(payload["movementRemaining"])
	result.enemies_remaining = int(payload["enemiesRemaining"])
	result.weapon_mode = StringName(payload["weaponMode"])
	result.melee_attack_reason = payload["meleeAttackReason"]
	result.spell_cast_reason = payload["spellCastReason"]
	result.item_cast_reason = payload["itemCastReason"]
	result.scroll_cast_reason = payload["scrollCastReason"]
	if not _array_is_strings(payload["actions"]) or not _array_is_strings(payload["autoCharacterIds"]): return false
	result.actions = _strings(payload["actions"])
	result.auto_character_ids = _strings(payload["autoCharacterIds"])
	result.weapon_switch = InteractionCommonValueDecoder.availability(payload["weaponSwitch"])
	result.ranged_attack = InteractionCommonValueDecoder.availability(payload["rangedAttack"])
	result.retreat = InteractionCommonValueDecoder.availability(payload["retreat"])
	result.auto_turn = InteractionCommonValueDecoder.availability(payload["autoTurn"])
	result.delay = InteractionCommonValueDecoder.availability(payload["delay"])
	result.undo = InteractionCommonValueDecoder.availability(payload["undo"])
	if result.weapon_switch == null or result.ranged_attack == null or result.retreat == null or result.auto_turn == null or result.delay == null or result.undo == null: return false
	var bandage_parse: Variant = _parse_target_availability(payload["bandage"])
	var turn_parse: Variant = _parse_target_availability(payload["turnUndead"])
	if bandage_parse == null or turn_parse == null: return false
	result.bandage = bandage_parse[0]
	result.bandage_targets = bandage_parse[1]
	result.turn_undead = turn_parse[0]
	result.turn_undead_targets = turn_parse[1]
	if not _append_combat_entries(payload, result): return false
	return true


static func _append_combat_entries(payload: Dictionary, result: Variant) -> bool:
	for entry: Variant in payload["targets"]:
		var target := InteractionCombatValueDecoder.combat_target(entry)
		if target == null: return false
		result.targets.append(target)
	for entry: Variant in payload["combatants"]:
		var combatant := InteractionCombatValueDecoder.combatant(entry)
		if combatant == null: return false
		result.combatants.append(combatant)
	for entry: Variant in payload["movement"]:
		var movement := InteractionCombatValueDecoder.movement_option(entry)
		if movement == null: return false
		result.movement.append(movement)
	if not _append_casts(payload["spellCasts"], &"spell", result.spell_casts): return false
	if not _append_casts(payload["itemCasts"], &"item", result.item_casts): return false
	if not _append_casts(payload["scrollCasts"], &"scroll", result.scroll_casts): return false
	for entry: Variant in payload["fastSpells"]:
		var fast_spell := InteractionCombatValueDecoder.fast_spell(entry)
		if fast_spell == null: return false
		result.fast_spells.append(fast_spell)
	return true


static func _append_casts(entries: Array, source: StringName, destination: Variant) -> bool:
	for entry: Variant in entries:
		var cast := InteractionCombatValueDecoder.cast_option(entry, source)
		if cast == null: return false
		destination.append(cast)
	return true


static func _parse_target_availability(data: Variant) -> Variant:
	if not data is Dictionary or not _fields_are_exact(data, ["enabled", "reason", "targets"], ["enabled", "reason", "targets"]): return null
	if not data["enabled"] is bool or not data["reason"] is String or not data["targets"] is Array: return null
	var availability := InteractionCommonValueDecoder.availability({"enabled": data["enabled"], "reason": data["reason"]})
	var targets: Array[InteractionRequestValue.CombatTarget] = []
	for entry: Variant in data["targets"]:
		var target := InteractionCombatValueDecoder.combat_target(entry)
		if target == null: return null
		targets.append(target)
	return [availability, targets]


static func _required_arrays(data: Dictionary, fields: Array[String]) -> bool:
	for field: String in fields:
		if not data.get(field) is Array: return false
	return true


static func _array_is_strings(values: Variant) -> bool:
	if not values is Array: return false
	for value: Variant in values:
		if not value is String: return false
	return true


static func _fields_are_exact(data: Dictionary, allowed: Array[String], required: Array[String] = []) -> bool:
	for key: Variant in data.keys():
		if not key is String or not allowed.has(key): return false
	for key: String in required:
		if not data.has(key): return false
	return true


static func _required_strings(data: Dictionary, fields: Array[String]) -> bool:
	for field: String in fields:
		if not data.get(field) is String: return false
	return true


static func _required_ints(data: Dictionary, fields: Array[String]) -> bool:
	for field: String in fields:
		if not _whole_number(data.get(field)): return false
	return true


static func _optional_strings(data: Dictionary, fields: Array[String]) -> bool:
	for field: String in fields:
		if data.has(field) and not data[field] is String: return false
	return true


static func _optional_bools(data: Dictionary, fields: Array[String]) -> bool:
	for field: String in fields:
		if data.has(field) and not data[field] is bool: return false
	return true


static func _whole_number(value: Variant) -> bool:
	return value is int or value is float and is_finite(value) and value == floor(value)


static func _strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		if not value is String: return []
		result.append(value)
	return result
