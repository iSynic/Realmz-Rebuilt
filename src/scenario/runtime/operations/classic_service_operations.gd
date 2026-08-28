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


const SHOP_AVAILABLE_SOUND_ID := 30005


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


func execute(action: ClassicActionDefinition, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		6:
			return _configure_classic_shop(action.operand_id, request_id)
		32:
			return _configure_temple(action)
		73:
			return _configure_shop(action, request_id)
	return super.execute(action, request_id, context)


func resume(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	match continuation.kind:
		ScenarioRuntimeContinuation.CLASSIC_SHOP:
			return _resume_shop(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_TEMPLE:
			return _resume_temple(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_TEMPLE_EXIT:
			return _resume_temple_exit(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_BANKING:
			return _resume_banking(continuation, response, request_id)
	return ScenarioRuntimeOperationResult.failed(&"unknown_interaction_continuation", "Service continuation is unavailable.")


func request_shop_definition(shop: ShopDefinition, request_id: String, accept_ranges: Array[int] = []) -> ScenarioRuntimeOperationResult:
	if _game_state.bank_available:
		_rules.economy.bank_to_pool(_game_state.party)
	return ScenarioRuntimeOperationResult.waiting(
		shop_request(shop, request_id, accept_ranges),
		ScenarioRuntimeContinuation.shop(shop.id, accept_ranges),
		[DomainEvent.new(&"shop_opened", {"shopId": shop.id, "acceptRanges": accept_ranges.duplicate(), "bankAvailable": _game_state.bank_available})]
	)


func request_available_temple(request_id: String) -> ScenarioRuntimeOperationResult:
	if not _game_state.temple_available:
		return ScenarioRuntimeOperationResult.failed(&"temple_unavailable", "No Classic temple is available at this location.")
	if _game_state.bank_available:
		_rules.economy.bank_to_pool(_game_state.party)
	var characters := _game_state.party.characters()
	var selected_character_id := "" if characters.is_empty() else characters[0].id
	var continuation := ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE, _game_state.temple_cost_percent, _game_state.bank_available, selected_character_id)
	return ScenarioRuntimeOperationResult.waiting(temple_request(_game_state.temple_cost_percent, request_id, selected_character_id), continuation, [
		DomainEvent.new(&"temple_opened", {"costPercent": _game_state.temple_cost_percent, "bankAvailable": _game_state.bank_available}),
		DomainEvent.new(&"music_requested", {"musicId": 10, "source": "classic-temple"}),
		DomainEvent.new(&"sound_requested", {"soundId": 10105, "waitForCompletion": false, "source": "classic-temple-entry"}),
	])


func shop_request(shop: ShopDefinition, request_id: String, accept_ranges: Array[int] = []) -> InteractionRequest:
	var stock: Array[Dictionary] = []
	var characters: Array[Dictionary] = []
	var item_ids := shop.item_ids()
	for index: int in item_ids.size():
		var item := _content.item_by_id(item_ids[index])
		var quantity := _game_state.shop_quantity(shop, index)
		if item != null and quantity > 0:
			var slot := shop.stock_slot(index)
			stock.append(_shop_stock_view(item, "base:%d" % slot, slot, quantity, shop))
	var buyback_items := _game_state.shop_buyback_items(shop.id)
	var buyback_ids: Array = buyback_items.keys()
	buyback_ids.sort_custom(func(left: Variant, right: Variant) -> bool:
		return _game_state.shop_buyback_slot(shop.id, String(left)) < _game_state.shop_buyback_slot(shop.id, String(right))
	)
	for item_id: Variant in buyback_ids:
		var item := _content.item_by_id(String(item_id))
		if item != null:
			var slot := _game_state.shop_buyback_slot(shop.id, item.id)
			stock.append(_shop_stock_view(item, "buyback:%s" % item.id, slot, int(buyback_items[item_id]), shop))
	stock.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return int(left["index"]) < int(right["index"]))
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
			var presentation_definition: ItemDefinition = definition
			if not instance.equipped and not definition.cursed_item_id.is_empty():
				presentation_definition = _content.item_by_id(definition.cursed_item_id)
			var public_view := ItemView.new(instance, definition, presentation_definition, _content)
			var item_view := {
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
				"description": public_view.description,
				"weight": public_view.weight,
				"facts": public_view.facts.map(func(fact: ItemFactView) -> Dictionary: return {"label": fact.label, "value": fact.value}),
			}
			var visible_icon_id := definition.visible_icon_id(instance.identified)
			if visible_icon_id > 0:
				item_view["iconResourceType"] = "cicn"
				item_view["iconId"] = visible_icon_id
			inventory.append(item_view)
		characters.append({"id": character.id, "name": character.name, "portraitId": character.portrait_id, "load": character.carried_load, "maximumLoad": character.maximum_load, "inventory": inventory})
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
		var slot_text := stock_key.trim_prefix("base:")
		if not slot_text.is_valid_int():
			return null
		var index := shop.stock_index_at_slot(slot_text.to_int())
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


func _configure_classic_shop(classic_shop_id: int, request_id: String) -> ScenarioRuntimeOperationResult:
	var shop := _content.shop_by_classic_id(absi(classic_shop_id))
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "Classic opcode 6 references unavailable shop %d." % classic_shop_id)
	var accept_ranges: Array[int] = [0, 0, 0, 0]
	if not _game_state.set_active_shop(shop.id, accept_ranges):
		return ScenarioRuntimeOperationResult.failed(&"invalid_shop_configuration", "Classic opcode 6 shop configuration is invalid.")
	if classic_shop_id < 0:
		return request_shop_definition(shop, request_id, accept_ranges)
	return ScenarioRuntimeOperationResult.completed(shop.id, _shop_available_events(shop.id, accept_ranges))


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
	return ScenarioRuntimeOperationResult.completed(shop.id, _shop_available_events(shop.id, accept_ranges))


func _configure_temple(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if not _game_state.set_active_temple(action.operand_id):
		return ScenarioRuntimeOperationResult.failed(&"invalid_temple_cost", "Classic opcode 32 temple cost is outside signed 16-bit range.")
	return ScenarioRuntimeOperationResult.completed(action.operand_id, [
		DomainEvent.new(&"temple_available", {"costPercent": action.operand_id}),
		DomainEvent.new(&"sound_requested", {"soundId": 10105, "waitForCompletion": false, "source": "classic-temple-offer"}),
	])


func _resume_shop(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.ShopBody
	if response.kind != &"shop_action" or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop response requires an action string.")
	var service := continuation.body as ScenarioRuntimeContinuation.ServiceBody
	var shop := _content.shop_by_id(service.shop_id)
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "The pending shop is unavailable.")
	var operation := String(body.action)
	if operation == "leave":
		if _game_state.bank_available:
			_rules.economy.pool_to_bank(_game_state.party)
		return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"shop_closed", {"shopId": shop.id, "pooledWealthReturnedToBank": _game_state.bank_available})])
	var events: Array[DomainEvent] = []
	match operation:
		"buy":
			if body.character_id.is_empty() or body.stock_key.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop buy requires stock identity and characterId.")
			var stock_entry := resolve_shop_stock(shop, body.stock_key)
			if stock_entry == null or stock_entry.quantity < 1:
				return ScenarioRuntimeOperationResult.failed(&"shop_item_unavailable", "The selected shop item is out of stock.")
			var character := _game_state.party.character_by_id(body.character_id)
			var item := stock_entry.item
			if character == null or item == null or character.inventory().size() >= InventoryRules.MAX_ITEMS or character.carried_load + item.instance_weight(item.initial_charges) > character.maximum_load:
				return ScenarioRuntimeOperationResult.failed(&"inventory_full", "The selected character cannot carry this item.")
			var price := _rules.economy.shop_buy_price(item, _game_state.shop_inflation(shop))
			if not _rules.economy.take(_game_state.party, price, WealthState.Kind.GOLD):
				return ScenarioRuntimeOperationResult.failed(&"insufficient_gold", "The party cannot afford this item.")
			var instance := _rules.inventory.add_item(character, item, _game_state.next_instance_id("shop.item"), true)
			if instance == null:
				_game_state.party.pooled_wealth.gold += price
				return ScenarioRuntimeOperationResult.failed(&"inventory_full", "The item could not be added after purchase validation.")
			if stock_entry.kind == &"base":
				var stock_index := stock_entry.index
				_game_state.set_shop_quantity(shop, stock_index, _game_state.shop_quantity(shop, stock_index) - 1)
			else:
				_game_state.set_shop_buyback_quantity(shop.id, item.id, stock_entry.quantity - 1, _game_state.shop_buyback_slot(shop.id, item.id))
			events.append(DomainEvent.new(&"shop_item_bought", {"shopId": shop.id, "itemId": item.id, "instanceId": instance.id, "characterId": character.id, "price": price}))
		"sell":
			if body.character_id.is_empty() or body.instance_id.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop sell requires characterId and instanceId.")
			var character := _game_state.party.character_by_id(body.character_id)
			if character == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The shop sale character is unavailable.")
			var instance: ItemInstance = null
			for candidate: ItemInstance in character.inventory():
				if candidate.id == body.instance_id:
					instance = candidate
					break
			if instance == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_item_instance", "The sold item instance is unavailable.")
			var item := _content.item_by_id(instance.definition_id)
			if item == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_item", "The sold item definition is unavailable.")
			if instance.equipped:
				return ScenarioRuntimeOperationResult.failed(&"equipped_item", "Unequip this item before selling it.")
			var accept_ranges: Array[int] = []
			accept_ranges.assign(service.accept_ranges)
			if not ClassicServiceOperations.shop_accepts_item(item, accept_ranges):
				return ScenarioRuntimeOperationResult.failed(&"shop_rejects_item", "This shop does not accept the selected item.")
			var price := _rules.economy.shop_sell_price(item, instance, _game_state.shop_inflation(shop))
			if _rules.inventory.remove_item(character, instance.id, item) == null:
				return ScenarioRuntimeOperationResult.failed(&"shop_sale_failed", "The selected item could not be removed.")
			_game_state.party.pooled_wealth.gold += price
			var base_index := _matching_base_stock_index(shop, item.id)
			if base_index >= 0:
				_game_state.set_shop_quantity(shop, base_index, _game_state.shop_quantity(shop, base_index) + 1)
			else:
				var buyback_quantity := _game_state.shop_buyback_quantity(shop.id, item.id)
				var slot := _game_state.shop_buyback_slot(shop.id, item.id) if buyback_quantity > 0 else _first_empty_shop_slot(shop, item.classic_id)
				if slot >= 0: _game_state.set_shop_buyback_quantity(shop.id, item.id, buyback_quantity + 1, slot)
			events.append(DomainEvent.new(&"shop_item_sold", {"shopId": shop.id, "itemId": item.id, "instanceId": instance.id, "characterId": character.id, "price": price}))
		"identify":
			if body.character_id.is_empty() or body.instance_id.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop identification requires characterId and instanceId.")
			var character := _game_state.party.character_by_id(body.character_id)
			if character == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The identification character is unavailable.")
			var instance: ItemInstance = null
			for candidate: ItemInstance in character.inventory():
				if candidate.id == body.instance_id:
					instance = candidate
					break
			if instance == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_item_instance", "The identification item is unavailable.")
			if instance.identified:
				return ScenarioRuntimeOperationResult.failed(&"already_identified", "This item is already identified.")
			if not _rules.economy.take(_game_state.party, 20, WealthState.Kind.GOLD):
				return ScenarioRuntimeOperationResult.failed(&"insufficient_gold", "Identification costs 20 gold.")
			instance.identified = true
			events.append(DomainEvent.new(&"item_identified", {"shopId": shop.id, "instanceId": instance.id, "characterId": character.id, "price": 20, "source": "classic-shop"}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 683, "waitForCompletion": false, "source": "classic-shop-identify"}))
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_shop_action", "Shop action '%s' is unavailable." % operation)
	var ranges: Array[int] = []
	ranges.assign(service.accept_ranges)
	return ScenarioRuntimeOperationResult.waiting(shop_request(shop, request_id, ranges), continuation, events)


func _resume_temple(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.TempleBody
	if response.kind != InteractionRequest.TEMPLE or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Temple response requires an action.")
	var operation := String(body.action)
	var service := continuation.body as ScenarioRuntimeContinuation.ServiceBody
	var cost_percent := service.cost_percent
	var selected_character_id := service.selected_character_id
	if not body.character_id.is_empty():
		if _game_state.party.character_by_id(body.character_id) == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The selected temple character is unavailable.")
		selected_character_id = body.character_id
	var next_continuation := ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE, cost_percent, service.bank_available, selected_character_id)
	match operation:
		"leave":
			if service.bank_available:
				_rules.economy.pool_to_bank(_game_state.party)
				return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"temple_closed", {"pooledWealthReturnedToBank": true})])
			if _has_pooled_wealth():
				var prompt := "Pooled wealth remains. Return to the temple to distribute it before leaving?"
				var request := InteractionRequest.yes_no(request_id, prompt, "Return", "Leave it behind")
				return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE_EXIT, cost_percent, false, selected_character_id))
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"temple_closed", {"pooledWealthReturnedToBank": false})])
		"pool":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var pool_probe := _rules.economy.pool_probe(_game_state.party)
			if not pool_probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", pool_probe.reason)
			_rules.economy.pool_party_wealth(_game_state.party)
			_recalculate_party_movement()
			return ScenarioRuntimeOperationResult.waiting(temple_request(cost_percent, request_id, selected_character_id), next_continuation, [
				DomainEvent.new(&"wealth_pooled", {"source": "classic-temple"}),
				DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-temple-pool"}),
			])
		"share":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var share_probe := _rules.economy.share_probe(_game_state.party)
			if not share_probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", share_probe.reason)
			_rules.economy.share_pooled_wealth(_game_state.party)
			_recalculate_party_movement()
			return ScenarioRuntimeOperationResult.waiting(temple_request(cost_percent, request_id, selected_character_id), next_continuation, [
				DomainEvent.new(&"wealth_shared", {"source": "classic-temple", "remaining": _game_state.party.pooled_wealth.to_data()}),
				DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-temple-share"}),
			])
		"service":
			return _apply_temple_service(next_continuation, body, request_id)
	return ScenarioRuntimeOperationResult.failed(&"unknown_temple_action", "Temple action '%s' is unavailable." % operation)


func _apply_temple_service(continuation: ScenarioRuntimeContinuation, body: InteractionResponse.TempleBody, request_id: String) -> ScenarioRuntimeOperationResult:
	if body.character_id.is_empty() or body.service_id.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Temple service requires characterId and serviceId.")
	var character := _game_state.party.character_by_id(body.character_id)
	var service_id := StringName(body.service_id)
	if character == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_character", "Temple service target is unavailable.")
	if not TempleRules.SERVICE_IDS.has(service_id):
		return ScenarioRuntimeOperationResult.failed(&"unknown_temple_service", "Temple service '%s' is unavailable." % service_id)
	var service := continuation.body as ScenarioRuntimeContinuation.ServiceBody
	var cost := _rules.temple.service_cost(service_id, service.cost_percent)
	var next_continuation := ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE, service.cost_percent, service.bank_available, character.id)
	var events: Array[DomainEvent] = [DomainEvent.new(&"sound_requested", {"soundId": 10129, "waitForCompletion": false, "source": "classic-temple-service"})]
	if cost > _game_state.party.pooled_wealth.gold + character.money.gold:
		events.append(DomainEvent.new(&"temple_service_rejected", {"serviceId": String(service_id), "characterId": character.id, "cost": cost, "reason": "insufficient_gold"}))
		return ScenarioRuntimeOperationResult.waiting(temple_request(service.cost_percent, request_id, character.id), next_continuation, events)
	if not _rules.economy.take_from_pool_and_character(_game_state.party, character, cost, WealthState.Kind.GOLD):
		return ScenarioRuntimeOperationResult.failed(&"temple_payment_failed", "Temple payment could not be committed after affordability validation.")
	var result := _rules.temple.apply_service(character, service_id, _rng, _content.item_definitions())
	if result == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_temple_service", "Temple service '%s' is unavailable." % service_id)
	events.append(DomainEvent.new(&"temple_service_completed", result.to_event_data(character.id, cost)))
	return ScenarioRuntimeOperationResult.waiting(temple_request(service.cost_percent, request_id, character.id), next_continuation, events)


func _resume_temple_exit(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Temple exit requires a yes/no response.")
	if body.accepted:
		var service := continuation.body as ScenarioRuntimeContinuation.ServiceBody
		return ScenarioRuntimeOperationResult.waiting(
			temple_request(service.cost_percent, request_id, service.selected_character_id),
			ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE, service.cost_percent, false, service.selected_character_id),
			[DomainEvent.new(&"temple_exit_cancelled", {"reason": "pooled_wealth"})]
		)
	var discarded := _game_state.party.pooled_wealth.to_data()
	_game_state.party.pooled_wealth = WealthState.new()
	return ScenarioRuntimeOperationResult.completed(true, [
		DomainEvent.new(&"pooled_wealth_discarded", {"source": "classic-temple-exit", "wealth": discarded}),
		DomainEvent.new(&"temple_closed", {"pooledWealthReturnedToBank": false}),
	])


func _has_pooled_wealth() -> bool:
	return _game_state.party.pooled_wealth.gold != 0 or _game_state.party.pooled_wealth.gems != 0 or _game_state.party.pooled_wealth.jewelry != 0


func request_banking(request_id: String) -> ScenarioRuntimeOperationResult:
	_rules.economy.bank_to_pool(_game_state.party)
	return ScenarioRuntimeOperationResult.waiting(_bank_request(request_id), ScenarioRuntimeContinuation.banking(), [
		DomainEvent.new(&"bank_opened", {"pooledWealth": _game_state.party.pooled_wealth.to_data()}),
		DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-bank-swap-button"}),
		DomainEvent.new(&"sound_requested", {"soundId": 3003, "waitForCompletion": false, "stopExisting": true, "source": "classic-bank-swap-open"}),
	])


func _bank_request(request_id: String, selected_character_id: String = "") -> InteractionRequest:
	var characters: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		var transfers: Array[Dictionary] = []
		for denomination: String in ["gold", "gems", "jewelry"]:
			var kind := _wealth_kind(denomination)
			var amount := EconomyRules.classic_transfer_increment(kind as WealthState.Kind)
			var to_pool := _rules.economy.transfer_probe(_game_state.party, character, kind as WealthState.Kind, amount, false)
			var to_character := _rules.economy.transfer_probe(_game_state.party, character, kind as WealthState.Kind, amount, true)
			transfers.append({
				"denomination": denomination,
				"amount": amount,
				"toPool": _economy_probe_data(to_pool),
				"toCharacter": _economy_probe_data(to_character),
			})
		characters.append({
			"id": character.id,
			"name": character.name,
			"wealth": character.money.to_data(),
			"load": character.carried_load,
			"maximumLoad": character.maximum_load,
			"transfers": transfers,
		})
	if selected_character_id.is_empty() and not characters.is_empty():
		selected_character_id = String(characters[0]["id"])
	return InteractionRequest.from_payload(request_id, InteractionRequest.BANK, {
		"selectedCharacterId": selected_character_id,
		"pooledWealth": _game_state.party.pooled_wealth.to_data(),
		"bankedWealth": _game_state.party.banked_wealth.to_data(),
		"pool": _economy_probe_data(_rules.economy.pool_probe(_game_state.party)),
		"share": _economy_probe_data(_rules.economy.share_probe(_game_state.party)),
		"characters": characters,
		"actions": ["pool", "share", "to-pool", "to-character", "leave"],
	})


func _resume_banking(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.BankBody
	if response.kind != InteractionRequest.BANK or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Bank response requires an action.")
	var action := String(body.action)
	if action == "leave":
		return ScenarioRuntimeOperationResult.completed(true, [
			DomainEvent.new(&"bank_closed", {"pooledWealthReturnedToBank": false}),
			DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-bank-swap-done"}),
		])
	var selected_character_id := body.character_id
	var events: Array[DomainEvent] = []
	match action:
		"pool":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var probe := _rules.economy.pool_probe(_game_state.party)
			if not probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", probe.reason)
			_rules.economy.pool_party_wealth(_game_state.party)
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_pooled", {"source": "classic-bank", "wealth": _game_state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-bank-pool"}))
		"share":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var probe := _rules.economy.share_probe(_game_state.party)
			if not probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", probe.reason)
			_rules.economy.share_pooled_wealth(_game_state.party)
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_shared", {"source": "classic-bank", "remaining": _game_state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-bank-share"}))
		"to-pool", "to-character":
			if body.character_id.is_empty() or body.denomination.is_empty() or body.amount < 1:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Bank-backed Swap requires character, denomination, and amount.")
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var character := _game_state.party.character_by_id(body.character_id)
			var kind := _wealth_kind(body.denomination)
			var amount := body.amount
			if character == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The selected bank character is unavailable.")
			if kind < 0:
				return ScenarioRuntimeOperationResult.failed(&"unknown_wealth_kind", "The selected bank denomination is unavailable.")
			if amount != EconomyRules.classic_transfer_increment(kind as WealthState.Kind):
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_increment", "Classic Swap moves five gold or one gem or jewelry per action.")
			var to_character := action == "to-character"
			var probe := _rules.economy.transfer_probe(_game_state.party, character, kind as WealthState.Kind, amount, to_character)
			if not probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", probe.reason)
			var transferred := _rules.economy.transfer_pool_to_character(_game_state.party, character, kind as WealthState.Kind, amount) if to_character else _rules.economy.transfer_character_to_pool(_game_state.party, character, kind as WealthState.Kind, amount)
			if not transferred:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", "The selected bank transfer is no longer available.")
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_transferred", {"source": "classic-bank", "characterId": character.id, "direction": action, "kind": body.denomination, "amount": amount}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 10051 if to_character else 663, "waitForCompletion": false, "source": "classic-bank-swap"}))
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_bank_action", "Bank action '%s' is unavailable." % action)
	return ScenarioRuntimeOperationResult.waiting(_bank_request(request_id, selected_character_id), continuation, events)


static func _economy_probe_data(probe: EconomyActionProbe) -> Dictionary:
	return {"enabled": probe != null and probe.allowed, "reason": "" if probe != null and probe.allowed else "Action availability is unavailable." if probe == null else probe.reason}


static func _wealth_kind(value: String) -> int:
	match value:
		"gold": return WealthState.Kind.GOLD
		"gems": return WealthState.Kind.GEMS
		"jewelry": return WealthState.Kind.JEWELRY
	return -1


func _money_movement_context_error() -> String:
	for character: CharacterState in _game_state.party.characters():
		if _content.race_by_id(character.race_id) == null or _content.caste_by_id(character.caste_id) == null:
			return "Character '%s' has no package-backed race or class for Classic movement recalculation." % character.id
	return ""


func _recalculate_party_movement() -> void:
	for character: CharacterState in _game_state.party.characters():
		var race := _content.race_by_id(character.race_id)
		var caste := _content.caste_by_id(character.caste_id)
		_rules.characters.recalculate_movement(character, race, caste.movement_bonus)




func _shop_stock_view(item: ItemDefinition, stock_key: String, stock_index: int, quantity: int, shop: ShopDefinition) -> Dictionary:
	var price := _rules.economy.shop_buy_price(item, _game_state.shop_inflation(shop))
	var public_view := ItemView.new(ItemInstance.new("shop.preview", item.id, item.initial_charges, false, true), item, item, _content)
	var result := {
		"stockKey": stock_key,
		"index": stock_index,
		"itemId": item.id,
		"name": item.name,
		"quantity": quantity,
		"buyPrice": price,
		"canBuy": quantity > 0 and _rules.economy.available(_game_state.party, WealthState.Kind.GOLD) >= price,
		"buyReason": "Out of stock." if quantity < 1 else "The party cannot afford this item." if _rules.economy.available(_game_state.party, WealthState.Kind.GOLD) < price else "",
		"category": String(_shop_category(stock_index)),
		"description": public_view.description,
		"weight": public_view.weight,
		"facts": public_view.facts.map(func(fact: ItemFactView) -> Dictionary: return {"label": fact.label, "value": fact.value}),
	}
	var visible_icon_id := item.visible_icon_id(true)
	if visible_icon_id > 0:
		result["iconResourceType"] = "cicn"
		result["iconId"] = visible_icon_id
	return result


func _shop_available_events(shop_id: String, accept_ranges: Array[int]) -> Array[DomainEvent]:
	return [
		DomainEvent.new(&"shop_available", {"shopId": shop_id, "acceptRanges": accept_ranges}),
		DomainEvent.new(&"sound_requested", {"soundId": SHOP_AVAILABLE_SOUND_ID, "waitForCompletion": false, "stopExisting": true, "source": "classic-shop-offer"}),
	]


func _matching_base_stock_index(shop: ShopDefinition, item_id: String) -> int:
	var item_ids := shop.item_ids()
	for index: int in item_ids.size():
		if item_ids[index] == item_id and _game_state.shop_quantity(shop, index) > 0:
			return index
	return -1


func _first_empty_shop_slot(shop: ShopDefinition, classic_item_id: int) -> int:
	var start := (classic_item_id / 200) * 200
	if start < 0 or start > 800:
		return -1
	var occupied: Dictionary = {}
	for index: int in shop.item_ids().size():
		if _game_state.shop_quantity(shop, index) > 0: occupied[shop.stock_slot(index)] = true
	for item_id: Variant in _game_state.shop_buyback_items(shop.id): occupied[_game_state.shop_buyback_slot(shop.id, String(item_id))] = true
	for slot: int in range(start, start + 200):
		if not occupied.has(slot): return slot
	return -1


static func _shop_category(stock_index: int) -> StringName:
	if stock_index < 0:
		return &""
	match stock_index / 200:
		0: return &"weapons"
		1: return &"armor"
		2: return &"limb_armor"
		3: return &"magic"
		4: return &"supplies"
	return &""


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
