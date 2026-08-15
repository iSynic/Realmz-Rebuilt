class_name ClassicServiceOperations
extends ClassicOpcodeHandler

class ShopStockResolution:
	extends RefCounted

	var kind: StringName
	var index: int
	var item: ItemDefinition
	var quantity: int


	func _init(stock_kind: StringName, stock_index: int, definition: ItemDefinition, available: int) -> void:
		kind = stock_kind
		index = stock_index
		item = definition
		quantity = available


var _content: RealmzContent
var _game_state: GameState
var _rng: RealmzRng
var _rules: RealmzRules


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, rules: RealmzRules) -> void:
	_content = content
	_game_state = game_state
	_rng = rng
	_rules = rules


func opcode_ids() -> Array[int]:
	return [6, 32, 73]


func execute(action: ClassicActionDefinition, request_id: String, context: Dictionary) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		6:
			return _request_shop(action.operand_id, request_id)
		32:
			return _configure_temple(action)
		73:
			return _configure_shop(action, request_id)
	return super.execute(action, request_id, context)


func request_shop_definition(shop: ShopDefinition, request_id: String, accept_ranges: Array[int] = []) -> ScenarioRuntimeOperationResult:
	if _game_state.bank_available:
		_rules.economy.bank_to_pool(_game_state.party)
	return ScenarioRuntimeOperationResult.waiting(
		shop_request(shop, request_id, accept_ranges),
		ScenarioRuntimeContinuation.shop(shop.id, accept_ranges),
		[DomainEvent.new(&"shop_opened", {"shopId": shop.id, "acceptRanges": accept_ranges.duplicate(), "bankAvailable": _game_state.bank_available})]
	)


func shop_request(shop: ShopDefinition, request_id: String, accept_ranges: Array[int] = []) -> InteractionRequest:
	var stock: Array[Dictionary] = []
	var characters: Array[Dictionary] = []
	var item_ids := shop.item_ids()
	for index: int in item_ids.size():
		var item := _content.item_by_id(item_ids[index])
		if item != null:
			stock.append(_shop_stock_view(item, "base:%d" % index, index, _game_state.shop_quantity(shop, index), shop))
	var buyback_items := _game_state.shop_buyback_items(shop.id)
	var buyback_ids: Array = buyback_items.keys()
	buyback_ids.sort_custom(func(left: Variant, right: Variant) -> bool:
		var left_item := _content.item_by_id(String(left))
		var right_item := _content.item_by_id(String(right))
		return left_item != null and right_item != null and left_item.classic_id < right_item.classic_id
	)
	for item_id: Variant in buyback_ids:
		if item_ids.has(String(item_id)):
			continue
		var item := _content.item_by_id(String(item_id))
		if item != null:
			stock.append(_shop_stock_view(item, "buyback:%s" % item.id, -1, int(buyback_items[item_id]), shop))
	var party_gold := _rules.economy.available(_game_state.party, WealthState.Kind.GOLD)
	for character: CharacterState in _game_state.party.characters():
		var inventory: Array[Dictionary] = []
		for instance: ItemInstance in character.inventory():
			var definition := _content.item_by_id(instance.definition_id)
			if definition == null:
				continue
			var can_sell := not instance.equipped and shop_accepts_item(definition, accept_ranges)
			var sell_reason := ""
			if instance.equipped:
				sell_reason = "Unequip this item before selling it."
			elif not shop_accepts_item(definition, accept_ranges):
				sell_reason = "This shop does not accept this item."
			var can_identify := not instance.identified and party_gold >= 20
			var identify_reason := ""
			if instance.identified:
				identify_reason = "This item is already identified."
			elif party_gold < 20:
				identify_reason = "Identification costs 20 gold."
			inventory.append({
				"instanceId": instance.id,
				"itemId": definition.id,
				"name": definition.name if instance.identified else definition.unidentified_name,
				"identified": instance.identified,
				"equipped": instance.equipped,
				"charges": instance.charges,
				"sellPrice": _rules.economy.shop_sell_price(definition, instance, _game_state.shop_inflation(shop)),
				"canSell": can_sell,
				"sellReason": sell_reason,
				"canIdentify": can_identify,
				"identifyReason": identify_reason,
			})
		characters.append({"id": character.id, "name": character.name, "inventory": inventory})
	return InteractionRequest.from_payload(request_id, &"shop_action", {
		"shopId": shop.id,
		"inflationPercent": _game_state.shop_inflation(shop),
		"partyGold": party_gold,
		"identifyPrice": 20,
		"stock": stock,
		"characters": characters,
		"acceptRanges": accept_ranges.duplicate(),
		"actions": ["buy", "sell", "identify", "leave"],
	})


func resolve_shop_stock(shop: ShopDefinition, stock_key: String) -> ShopStockResolution:
	if stock_key.begins_with("base:"):
		var index_text := stock_key.trim_prefix("base:")
		if not index_text.is_valid_int():
			return null
		var index := index_text.to_int()
		var item_ids := shop.item_ids()
		if index < 0 or index >= item_ids.size():
			return null
		return ShopStockResolution.new(&"base", index, _content.item_by_id(item_ids[index]), _game_state.shop_quantity(shop, index))
	if stock_key.begins_with("buyback:"):
		var item_id := stock_key.trim_prefix("buyback:")
		var quantity := _game_state.shop_buyback_quantity(shop.id, item_id)
		if quantity < 1:
			return null
		return ShopStockResolution.new(&"buyback", -1, _content.item_by_id(item_id), quantity)
	return null


func temple_request(cost_percent: int, request_id: String, selected_character_id: String = "") -> InteractionRequest:
	var characters: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		var conditions: Array[Dictionary] = []
		for index: int in character.conditions.size():
			if character.conditions.value(index) != 0:
				conditions.append({"index": index, "name": _rules.temple.condition_name(index), "value": character.conditions.value(index)})
				if conditions.size() == 5:
					break
		characters.append({
			"id": character.id,
			"name": character.name,
			"currentHealth": character.current_health,
			"maximumHealth": character.maximum_health,
			"personalGold": character.money.gold,
			"availableGold": character.money.gold + _game_state.party.pooled_wealth.gold,
			"load": character.carried_load,
			"maximumLoad": character.maximum_load,
			"portraitId": character.portrait_id,
			"conditions": conditions,
		})
	return InteractionRequest.from_payload(request_id, InteractionRequest.TEMPLE, {
		"costPercent": cost_percent,
		"characters": characters,
		"services": _rules.temple.service_rows(cost_percent),
		"pooledWealth": _game_state.party.pooled_wealth.to_data(),
		"bankAvailable": _game_state.bank_available,
		"selectedCharacterId": selected_character_id,
		"actions": ["service", "pool", "share", "leave"],
	})


func _request_shop(classic_shop_id: int, request_id: String, accept_ranges: Array[int] = []) -> ScenarioRuntimeOperationResult:
	var shop := _content.shop_by_classic_id(absi(classic_shop_id))
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "Classic opcode 6 references unavailable shop %d." % classic_shop_id)
	return request_shop_definition(shop, request_id, accept_ranges)


func _configure_shop(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 73 requires a five-value Extra Code row.")
	var shop := _content.shop_by_classic_id(absi(action.extra_code[0]))
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "Classic opcode 73 references unavailable shop %d." % action.extra_code[0])
	var accept_ranges: Array[int] = [action.extra_code[1], action.extra_code[2], action.extra_code[3], action.extra_code[4]]
	if not _game_state.set_active_shop(shop.id, accept_ranges):
		return ScenarioRuntimeOperationResult.failed(&"invalid_shop_configuration", "Classic opcode 73 shop restrictions are invalid.")
	if action.extra_code[0] < 0:
		return _request_shop(action.extra_code[0], request_id, accept_ranges)
	return ScenarioRuntimeOperationResult.completed(shop.id, [DomainEvent.new(&"shop_available", {"shopId": shop.id, "acceptRanges": accept_ranges})])


func _configure_temple(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if not _game_state.set_active_temple(action.operand_id):
		return ScenarioRuntimeOperationResult.failed(&"invalid_temple_cost", "Classic opcode 32 temple cost is outside signed 16-bit range.")
	return ScenarioRuntimeOperationResult.completed(action.operand_id, [
		DomainEvent.new(&"temple_available", {"costPercent": action.operand_id}),
		DomainEvent.new(&"sound_requested", {"soundId": 10105, "waitForCompletion": false, "source": "classic-temple-offer"}),
	])


func _shop_stock_view(item: ItemDefinition, stock_key: String, stock_index: int, quantity: int, shop: ShopDefinition) -> Dictionary:
	var price := _rules.economy.shop_buy_price(item, _game_state.shop_inflation(shop))
	return {
		"stockKey": stock_key,
		"index": stock_index,
		"itemId": item.id,
		"name": item.name,
		"quantity": quantity,
		"buyPrice": price,
		"canBuy": quantity > 0 and _rules.economy.available(_game_state.party, WealthState.Kind.GOLD) >= price,
		"buyReason": "Out of stock." if quantity < 1 else "The party cannot afford this item." if _rules.economy.available(_game_state.party, WealthState.Kind.GOLD) < price else "",
	}


static func shop_accepts_item(item: ItemDefinition, accept_ranges: Array[int]) -> bool:
	if item == null or accept_ranges.is_empty():
		return accept_ranges.is_empty()
	if accept_ranges.size() != 4:
		return false
	var failures := 0
	if accept_ranges[0] != 0 and not (accept_ranges[0] <= item.classic_id and item.classic_id <= accept_ranges[1]):
		failures += 1
	if accept_ranges[2] != 0 and not (accept_ranges[2] <= item.classic_id and item.classic_id <= accept_ranges[3]):
		failures += 1
	return failures < 2
