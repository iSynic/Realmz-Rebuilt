class_name SessionInteractionFactory
extends RefCounted


static func drop_item_confirmation(request_id: String, item_name: String) -> InteractionRequest:
	return InteractionRequest.yes_no(request_id, "Drop %s? The item will be lost." % item_name, "Drop", "Keep")


static func retreat_confirmation(request_id: String) -> InteractionRequest:
	return InteractionRequest.yes_no(request_id, "Will this character flee from battle?", "Embrace Cowardice", "Stay and Fight")


static func friendly_collision(request_id: String) -> InteractionRequest:
	return InteractionRequest.yes_no(request_id, "An ally occupies that battlefield position.", "Swap Positions", "Attack Friend")


static func character_spell_confirmation(request_id: String, remaining: int) -> InteractionRequest:
	return InteractionRequest.yes_no(request_id, "%d starting-spell selection points remain. Accept this character anyway?" % remaining, "Accept character", "Choose more spells")


static func character_vault_confirmation(request_id: String, character_name: String) -> InteractionRequest:
	return InteractionRequest.yes_no(request_id, "Publish %s as a reusable character-vault revision?" % character_name, "Publish to vault", "Keep in this party only")


static func pooled_wealth_departure_warning(request_id: String) -> InteractionRequest:
	return InteractionRequest.yes_no(request_id, "The party still has wealth in the shared pool. Distribute it before leaving?", "Distribute", "Leave it behind")


static func pooled_wealth_departure_distribution(state: GameState, request_id: String, selected_character_id: String = "") -> InteractionRequest:
	var economy := EconomyRules.new()
	var characters: Array[Dictionary] = []
	for character: CharacterState in state.party.characters():
		var transfers: Array[Dictionary] = []
		for denomination: String in ["gold", "gems", "jewelry"]:
			var kind := money_kind(denomination)
			var amount := EconomyRules.classic_transfer_increment(kind as WealthState.Kind)
			var to_pool := economy.transfer_probe(state.party, character, kind as WealthState.Kind, amount, false)
			var to_character := economy.transfer_probe(state.party, character, kind as WealthState.Kind, amount, true)
			transfers.append({"denomination": denomination, "amount": amount, "toPool": _economy_action_payload(to_pool), "toCharacter": _economy_action_payload(to_character)})
		characters.append({"id": character.id, "name": character.name, "wealth": character.money.to_data(), "load": character.carried_load, "maximumLoad": character.maximum_load, "transfers": transfers})
	if state.party.character_by_id(selected_character_id) == null and not characters.is_empty():
		selected_character_id = characters[0]["id"]
	return InteractionRequest.from_payload(request_id, InteractionRequest.POOLED_WEALTH_DEPARTURE, {
		"mode": "departure",
		"selectedCharacterId": selected_character_id,
		"pooledWealth": state.party.pooled_wealth.to_data(),
		"bankedWealth": state.party.banked_wealth.to_data(),
		"pool": _economy_action_payload(economy.pool_probe(state.party)),
		"share": _economy_action_payload(economy.share_probe(state.party)),
		"characters": characters,
	})


static func has_pooled_wealth(party: PartyState) -> bool:
	return party != null and (party.pooled_wealth.gold != 0 or party.pooled_wealth.gems != 0 or party.pooled_wealth.jewelry != 0)


static func money_kind(value: String) -> int:
	match value:
		"gold": return WealthState.Kind.GOLD
		"gems": return WealthState.Kind.GEMS
		"jewelry": return WealthState.Kind.JEWELRY
	return -1


static func _economy_action_payload(probe: EconomyActionProbe) -> Dictionary:
	return {"enabled": probe != null and probe.allowed, "reason": "" if probe != null and probe.allowed else "Action availability is unavailable." if probe == null else probe.reason}
