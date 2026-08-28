class_name ClassicInventoryOperations
extends ClassicOpcodeHandler

var _content: RealmzContent
var _game_state: GameState
var _rules: RealmzRules


func _init(content: RealmzContent, game_state: GameState, rules: RealmzRules) -> void:
	_content = content
	_game_state = game_state
	_rules = rules


func opcode_ids() -> Array[int]:
	return [21, 22, 33, 36, 38, 49, 51, 60, 67, 91]


func execute(action: ClassicActionDefinition, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		21:
			return _branch_on_item(action)
		22:
			return _mutate_items(action)
		33:
			return _take_wealth(action)
		36:
			return toggle_equipment_storage(action.operand_id != 0)
		38:
			return _branch_on_item_result(action, context)
		49:
			return _configure_banking()
		51:
			return _mutate_shop(action)
		60:
			return _clear_character_money(action)
		67:
			return _branch_on_item_charges(action)
		91:
			return _drop_equipment()
	return super.execute(action, request_id, context)


func _take_wealth(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	var values := action.extra_code
	var signed_amount := action.operand_id if values.is_empty() else values[0]
	var amount := absi(signed_amount)
	var kind := WealthState.Kind.GEMS if signed_amount < 0 else WealthState.Kind.GOLD
	var paid := _rules.economy.take(_game_state.party, amount, kind)
	var events: Array[DomainEvent] = [DomainEvent.new(&"wealth_taken", {"amount": amount, "kind": kind, "paid": paid, "source": "classic"})]
	if not paid:
		events.append(DomainEvent.new(&"classic_notification_requested", {"text": "The party does not have enough gold.", "soundId": 6000, "source": "classic-opcode-33"}))
	return ScenarioRuntimeOperationResult.completed(paid, events)


func _branch_on_item(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 21 requires a five-value Extra Code row.")
	var values := action.extra_code
	var possessed := _party_has_classic_item(absi(values[0]))
	if possessed:
		return _branch_target_mode(values[1], values[3], action.gosub)
	match int(values[2]):
		0:
			return _branch_target_mode(values[1], values[4], action.gosub)
		1:
			return ScenarioRuntimeOperationResult.completed(false)
		2:
			var message := _content.message_by_id(values[4])
			if message == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic item branch references unavailable message %d." % values[4])
			return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-item-check"})], ScenarioVmDirective.finish())
	return ScenarioRuntimeOperationResult.failed(&"invalid_item_branch", "Classic item possession branch has an invalid failure mode.")


func _branch_on_item_result(action: ClassicActionDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 38 requires a five-value Extra Code row.")
	var possessed := _party_has_classic_item(absi(action.extra_code[0]))
	var test_mode := action.extra_code[1]
	if test_mode == 2 or test_mode == 0 and not possessed or test_mode == 1 and possessed:
		return _branch_from_values(action.extra_code, false, context)
	if test_mode not in [0, 1, 2]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_item_branch", "Classic item result branch has an invalid test mode.")
	return ScenarioRuntimeOperationResult.completed(false)


func _branch_on_item_charges(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 67 requires a five-value Extra Code row.")
	var definition := _content.item_by_classic_id(action.extra_code[0])
	var total_charges := 0
	if definition != null:
		for character: CharacterState in _game_state.party.characters():
			for instance: ItemInstance in character.inventory():
				if instance.definition_id == definition.id:
					total_charges += instance.charges
	var matched := total_charges >= action.extra_code[2]
	var target_id := action.extra_code[3] if matched else action.extra_code[4]
	var event := DomainEvent.new(&"item_charge_branch_checked", {"classicItemId": action.extra_code[0], "totalCharges": total_charges, "minimumCharges": action.extra_code[2], "matched": matched, "targetMode": action.extra_code[1], "targetId": target_id, "source": "classic"})
	var branch := _branch_to_destination(action.extra_code[1], target_id, action.gosub)
	branch.events.append(event)
	return branch


func _mutate_items(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 22 requires a five-value Extra Code row.")
	var source := _content.item_by_classic_id(absi(action.extra_code[0]))
	if source == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Classic item mutation references unavailable item %d." % action.extra_code[0])
	var operation := action.extra_code[2]
	var maximum := action.extra_code[1]
	if maximum < 0 or operation not in [1, 2, 3]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_item_mutation", "Classic item mutation has an invalid count or operation.")
	var replacement := _content.item_by_classic_id(absi(action.extra_code[4])) if operation == 3 else null
	if operation == 3 and replacement == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Classic item replacement is unavailable.")
	var changed := 0
	for character: CharacterState in _game_state.party.characters():
		var items := character.inventory()
		for index: int in range(items.size() - 1, -1, -1):
			if maximum > 0 and changed >= maximum:
				break
			var instance: ItemInstance = items[index]
			if instance.definition_id != source.id:
				continue
			match operation:
				1:
					_rules.inventory.remove_item(character, instance.id, source)
				2:
					var previous_weight := source.instance_weight(instance.charges)
					instance.charges = clampi(instance.charges + action.extra_code[3], -1, 32_767)
					character.carried_load = maxi(0, character.carried_load - previous_weight + source.instance_weight(instance.charges))
				3:
					var was_equipped := instance.equipped
					_rules.inventory.remove_item(character, instance.id, source)
					var replacement_instance := _rules.inventory.add_item(character, replacement, _game_state.next_instance_id("classic.replacement"), false)
					if replacement_instance == null:
						return ScenarioRuntimeOperationResult.failed(&"inventory_full", "Classic replacement item no longer fits the character inventory.")
					if was_equipped and _rules.inventory.can_equip(character, replacement):
						replacement_instance.equipped = true
			changed += 1
		if maximum > 0 and changed >= maximum:
			break
	return ScenarioRuntimeOperationResult.completed(changed, [DomainEvent.new(&"party_items_changed", {"itemId": source.id, "operation": operation, "changed": changed})])


func _party_has_classic_item(classic_item_id: int, minimum_charges: int = -1, equipped_only: bool = false) -> bool:
	var definition := _content.item_by_classic_id(classic_item_id)
	if definition == null:
		return false
	for character: CharacterState in _game_state.party.characters():
		for instance: ItemInstance in character.inventory():
			if instance.definition_id == definition.id and (minimum_charges < 0 or instance.charges >= minimum_charges) and (not equipped_only or instance.equipped):
				return true
	return false


func _branch_from_values(values: Array[int], gosub: bool, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	match values[2]:
		0:
			return _branch_xap(values[3], gosub)
		1, 2:
			return _branch_encounter_result(values[2], values[3], values[4], gosub, context)
		3:
			return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.finish())
	return ScenarioRuntimeOperationResult.failed(&"unsupported_branch_mode", "Classic branch mode %d is not available in this execution context." % values[2])


func _branch_encounter_result(mode: int, result_index: int, entry_cursor: int, gosub: bool, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	var kind := &"simple" if mode == 1 else &"complex"
	if context == null or context.encounter_kind != kind or context.encounter_id < 0:
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_context", "Classic branch mode %d requires an active %s Encounter result." % [mode, String(kind).capitalize()])
	if result_index < 0 or result_index > 3 or entry_cursor < 0 or entry_cursor > 7:
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_branch", "Classic encounter-result branches require result 0 through 3 and code cursor 0 through 7.")
	var program_id := "%s:%d:result:%d" % [String(kind), context.encounter_id, result_index]
	return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.branch_program_at(program_id, gosub, context, entry_cursor))


func _branch_target_mode(mode: int, target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	if mode == 0:
		return _branch_xap(target_id, gosub)
	return ScenarioRuntimeOperationResult.failed(&"unsupported_branch_target", "Classic branch target mode %d is not available in this execution context." % mode)


func _branch_to_destination(mode: int, target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	match mode:
		0: return _branch_xap(target_id, gosub)
		1: return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.enter_encounter(&"simple", target_id, gosub))
		2: return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.enter_encounter(&"complex", target_id, gosub))
	return ScenarioRuntimeOperationResult.failed(&"unsupported_branch_target", "Classic branch target mode %d is unavailable." % mode)


func _branch_xap(target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	if target_id == 0:
		return ScenarioRuntimeOperationResult.completed(false)
	return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.branch_xap(target_id, gosub))


func _configure_banking() -> ScenarioRuntimeOperationResult:
	_game_state.bank_available = true
	return ScenarioRuntimeOperationResult.completed(true, [
		DomainEvent.new(&"bank_available"),
		DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-bank-offer"}),
	])


func _mutate_shop(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 51 requires a five-value Extra Code row.")
	var shop := _content.shop_by_classic_id(absi(action.extra_code[0]))
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "Classic shop mutation references unavailable shop %d." % action.extra_code[0])
	var inflation := maxi(0, _game_state.shop_inflation(shop) + action.extra_code[1])
	_game_state.set_shop_inflation(shop, inflation)
	var stock_index := -1
	if action.extra_code[2] != 0:
		var item := _content.item_by_classic_id(absi(action.extra_code[2]))
		if item == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Classic shop mutation references unavailable item %d." % action.extra_code[2])
		stock_index = shop.item_ids().find(item.id)
		if stock_index < 0:
			return ScenarioRuntimeOperationResult.failed(&"shop_item_unavailable", "Classic shop mutation item is not stocked by the shop.")
		_game_state.set_shop_quantity(shop, stock_index, _game_state.shop_quantity(shop, stock_index) + action.extra_code[3])
	return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"shop_changed", {"shopId": shop.id, "inflationPercent": inflation, "stockIndex": stock_index, "quantity": _game_state.shop_quantity(shop, stock_index) if stock_index >= 0 else 0})])


func _clear_character_money(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 2:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 60 requires a five-value Extra Code row.")
	var classic_kind := action.extra_code[0]
	if classic_kind < 1 or classic_kind > 3:
		return ScenarioRuntimeOperationResult.failed(&"invalid_wealth_kind", "Classic opcode 60 references wealth kind %d outside 1 through 3." % classic_kind)
	var kind := (classic_kind - 1) as WealthState.Kind
	var targets := _game_state.party.characters() if action.extra_code[1] == 0 else _game_state.selected_characters()
	var removed := 0
	for character: CharacterState in targets:
		var amount := character.money.amount(kind)
		removed += amount
		character.carried_load = maxi(0, character.carried_load - amount * (15 if kind == WealthState.Kind.JEWELRY else 1))
		character.money.set_amount(kind, 0)
	return ScenarioRuntimeOperationResult.completed(removed, [DomainEvent.new(&"character_wealth_cleared", {"kind": kind, "amount": removed, "characterIds": targets.map(func(character: CharacterState) -> String: return character.id), "source": "classic"})])


func _drop_equipment() -> ScenarioRuntimeOperationResult:
	var dropped := 0
	for character: CharacterState in _game_state.party.characters():
		dropped += character.inventory().size()
		character.set_inventory([])
		character.carried_load = 0
	return ScenarioRuntimeOperationResult.completed(dropped, [DomainEvent.new(&"party_equipment_dropped", {"count": dropped, "source": "classic"})])


func toggle_equipment_storage(capture: bool) -> ScenarioRuntimeOperationResult:
	if capture:
		_rules.economy.pool_party_wealth(_game_state.party)
		var changed := _game_state.party.capture_equipment()
		if changed:
			for character: CharacterState in _game_state.party.characters():
				character.carried_load = 0
		return ScenarioRuntimeOperationResult.completed(changed, [DomainEvent.new(&"equipment_stored", {"changed": changed, "source": "classic"})])
	var restored := _game_state.party.restore_equipment()
	if restored:
		_recalculate_party_loads()
	return ScenarioRuntimeOperationResult.completed(restored, [DomainEvent.new(&"equipment_restored", {"changed": restored, "source": "classic"})])


func _recalculate_party_loads() -> void:
	for character: CharacterState in _game_state.party.characters():
		var total := character.money.gold + character.money.gems + character.money.jewelry * 15
		for instance: ItemInstance in character.inventory():
			var definition := _content.item_by_id(instance.definition_id)
			if definition != null:
				total += definition.instance_weight(instance.charges)
		character.carried_load = maxi(0, total)
