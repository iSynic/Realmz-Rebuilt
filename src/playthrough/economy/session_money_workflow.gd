## Applies Classic pool, share, and denomination-transfer actions.
class_name SessionMoneyWorkflow
extends RefCounted


static func perform(context: SessionWorkflowContext, payload: EconomyIntentPayloads.Money) -> SessionWorkflowResult:
	var movement_error := _movement_context_error(context)
	if not movement_error.is_empty():
		return SessionWorkflowResult.failed(&"invalid_money_context", movement_error)
	var events: Array[DomainEvent] = []
	match payload.action:
		&"pool":
			var probe := context.rules.economy.pool_probe(context.state.party)
			if not probe.allowed:
				return SessionWorkflowResult.failed(&"money_action_unavailable", probe.reason)
			context.rules.economy.pool_party_wealth(context.state.party)
			events.append(DomainEvent.new(&"wealth_pooled", {"source": "classic-money", "wealth": context.state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-money-pool"}))
		&"share":
			var probe := context.rules.economy.share_probe(context.state.party)
			if not probe.allowed:
				return SessionWorkflowResult.failed(&"money_action_unavailable", probe.reason)
			context.rules.economy.share_pooled_wealth(context.state.party)
			events.append(DomainEvent.new(&"wealth_shared", {"source": "classic-money", "remaining": context.state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-money-share"}))
		&"to-pool", &"to-character":
			var character := context.state.party.character_by_id(payload.character_id)
			var kind := _money_kind(payload.denomination)
			if character == null:
				return SessionWorkflowResult.failed(&"unknown_character", "The selected money-transfer character is unavailable.")
			if kind < 0:
				return SessionWorkflowResult.failed(&"unknown_wealth_kind", "The selected denomination is unavailable.")
			var expected_amount := EconomyRules.classic_transfer_increment(kind as WealthState.Kind)
			if payload.amount != expected_amount:
				return SessionWorkflowResult.failed(&"invalid_money_increment", "Classic Swap moves five gold or one gem or jewelry per action.")
			var to_character := payload.action == &"to-character"
			var probe := context.rules.economy.transfer_probe(context.state.party, character, kind as WealthState.Kind, payload.amount, to_character)
			if not probe.allowed:
				return SessionWorkflowResult.failed(&"money_action_unavailable", probe.reason)
			var transferred := context.rules.economy.transfer_pool_to_character(context.state.party, character, kind as WealthState.Kind, payload.amount) if to_character else context.rules.economy.transfer_character_to_pool(context.state.party, character, kind as WealthState.Kind, payload.amount)
			if not transferred:
				return SessionWorkflowResult.failed(&"money_action_unavailable", "The selected wealth transfer is no longer available.")
			events.append(DomainEvent.new(&"wealth_transferred", {"source": "classic-money", "characterId": character.id, "direction": String(payload.action), "kind": payload.denomination, "amount": payload.amount}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 10051 if to_character else 663, "waitForCompletion": false, "source": "classic-money-swap"}))
		MoneyChangingRules.JEWELRY_TO_GEMS, MoneyChangingRules.GEMS_TO_GOLD, MoneyChangingRules.GOLD_TO_GEMS:
			var rate := MoneyChangingRules.rate(payload.action)
			if not payload.character_id.is_empty() or payload.denomination != String(rate.source) or payload.amount != rate.source_amount:
				return SessionWorkflowResult.failed(&"invalid_money_increment", "The money-changing amount does not match the Castle rate.")
			var probe := MoneyChangingRules.probe(context.state.party, changing_available(context), payload.action)
			if not probe.allowed:
				return SessionWorkflowResult.failed(&"money_action_unavailable", probe.reason)
			MoneyChangingRules.convert(context.state.party, true, payload.action)
			events.append(DomainEvent.new(&"wealth_changed", {"source": "classic-money", "action": String(payload.action), "from": String(rate.source), "spent": rate.source_amount, "to": String(rate.result), "received": rate.result_amount}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 10129, "waitForCompletion": payload.action == MoneyChangingRules.JEWELRY_TO_GEMS, "source": "classic-money-change"}))
		_:
			return SessionWorkflowResult.failed(&"unknown_money_action", "Money action '%s' is unavailable." % payload.action)
	_recalculate_party_movement(context)
	return SessionWorkflowResult.completed(events)


static func changing_available(context: SessionWorkflowContext) -> bool:
	var shop_id: String = context.state.location_services.active_shop_id
	return context.state.location_services.temple_available or not shop_id.is_empty() and context.content.economy.shop_by_id(shop_id) != null


static func _movement_context_error(context: SessionWorkflowContext) -> String:
	for character: CharacterState in context.state.party.characters():
		if context.content.characters.race_by_id(character.race_id) == null or context.content.characters.caste_by_id(character.caste_id) == null:
			return "Character '%s' has no package-backed race or class for Classic movement recalculation." % character.id
	return ""


static func _recalculate_party_movement(context: SessionWorkflowContext) -> void:
	for character: CharacterState in context.state.party.characters():
		var race := context.content.characters.race_by_id(character.race_id)
		var caste := context.content.characters.caste_by_id(character.caste_id)
		context.rules.characters.recalculate_movement(character, race, caste.movement_bonus)


static func _money_kind(value: String) -> int:
	match value:
		"gold": return WealthState.Kind.GOLD
		"gems": return WealthState.Kind.GEMS
		"jewelry": return WealthState.Kind.JEWELRY
	return -1
