class_name EconomyRules
extends RefCounted


func pool_party_wealth(party: PartyState) -> bool:
	if not pool_probe(party).allowed:
		return false
	for character: CharacterState in party.characters():
		party.pooled_wealth.gold += character.money.gold
		party.pooled_wealth.gems += character.money.gems
		party.pooled_wealth.jewelry += character.money.jewelry
		character.carried_load = maxi(0, character.carried_load - character.money.gold - character.money.gems - character.money.jewelry * 15)
		character.money = WealthState.new()
	return true


func pool_probe(party: PartyState) -> EconomyActionProbe:
	if party == null:
		return EconomyActionProbe.new(false, "No party is available.")
	for character: CharacterState in party.characters():
		if character.money.gold > 0 or character.money.gems > 0 or character.money.jewelry > 0:
			return EconomyActionProbe.new(true)
	return EconomyActionProbe.new(false, "No adventurer carries wealth to pool.")


func take_from_pool_and_character(party: PartyState, character: CharacterState, amount: int, kind: WealthState.Kind) -> bool:
	if party == null or character == null:
		return false
	if amount < 0:
		party.pooled_wealth.add(kind, -amount)
		return true
	if amount > party.pooled_wealth.amount(kind) + character.money.amount(kind):
		return false
	var from_pool := mini(amount, party.pooled_wealth.amount(kind))
	party.pooled_wealth.add(kind, -from_pool)
	var from_character := amount - from_pool
	character.money.add(kind, -from_character)
	character.carried_load = maxi(0, character.carried_load - from_character * wealth_weight(kind))
	return true


func share_pooled_wealth(party: PartyState) -> bool:
	if not share_probe(party).allowed:
		return false
	var changed := false
	for kind: WealthState.Kind in [WealthState.Kind.JEWELRY, WealthState.Kind.GEMS, WealthState.Kind.GOLD]:
		var assigned := true
		while party.pooled_wealth.amount(kind) > 0 and assigned:
			assigned = false
			for character: CharacterState in party.characters():
				if party.pooled_wealth.amount(kind) < 1:
					break
				# FD-ECONOMY-003: Castle checks only current load here, so
				# jewelry can overload a recipient even though Swap rejects it.
				if character.carried_load + wealth_weight(kind) <= character.maximum_load:
					assigned = true
					changed = true
					character.money.add(kind, 1)
					character.carried_load += wealth_weight(kind)
					party.pooled_wealth.add(kind, -1)
	return changed


func share_probe(party: PartyState) -> EconomyActionProbe:
	if party == null:
		return EconomyActionProbe.new(false, "No party is available.")
	if party.pooled_wealth.gold < 1 and party.pooled_wealth.gems < 1 and party.pooled_wealth.jewelry < 1:
		return EconomyActionProbe.new(false, "The party wealth pool is empty.")
	for kind: WealthState.Kind in [WealthState.Kind.JEWELRY, WealthState.Kind.GEMS, WealthState.Kind.GOLD]:
		if party.pooled_wealth.amount(kind) < 1:
			continue
		for character: CharacterState in party.characters():
			if character.carried_load + wealth_weight(kind) <= character.maximum_load:
				return EconomyActionProbe.new(true)
	return EconomyActionProbe.new(false, "No adventurer can carry another pooled denomination.")


func transfer_probe(party: PartyState, character: CharacterState, kind: WealthState.Kind, amount: int, to_character: bool) -> EconomyActionProbe:
	if party == null or character == null:
		return EconomyActionProbe.new(false, "The selected adventurer is unavailable.")
	if amount != classic_transfer_increment(kind):
		return EconomyActionProbe.new(false, "The transfer does not use the Classic denomination increment.")
	if to_character:
		if party.pooled_wealth.amount(kind) < amount:
			return EconomyActionProbe.new(false, "The party pool does not contain that amount.")
		if character.carried_load + wealth_weight(kind) * amount > character.maximum_load:
			return EconomyActionProbe.new(false, "%s cannot carry that denomination." % character.name)
		return EconomyActionProbe.new(true)
	if character.money.amount(kind) < amount:
		return EconomyActionProbe.new(false, "%s does not carry that amount." % character.name)
	return EconomyActionProbe.new(true)


func transfer_pool_to_character(party: PartyState, character: CharacterState, kind: WealthState.Kind, amount: int) -> bool:
	if not transfer_probe(party, character, kind, amount, true).allowed:
		return false
	var added_load := wealth_weight(kind) * amount
	party.pooled_wealth.add(kind, -amount)
	character.money.add(kind, amount)
	character.carried_load += added_load
	return true


func transfer_character_to_pool(party: PartyState, character: CharacterState, kind: WealthState.Kind, amount: int) -> bool:
	if not transfer_probe(party, character, kind, amount, false).allowed:
		return false
	character.money.add(kind, -amount)
	character.carried_load = maxi(0, character.carried_load - wealth_weight(kind) * amount)
	party.pooled_wealth.add(kind, amount)
	return true


func bank_to_pool(party: PartyState) -> void:
	if party == null:
		return
	for kind: WealthState.Kind in [WealthState.Kind.GOLD, WealthState.Kind.GEMS, WealthState.Kind.JEWELRY]:
		party.pooled_wealth.add(kind, party.banked_wealth.amount(kind))
		party.banked_wealth.set_amount(kind, 0)


func pool_to_bank(party: PartyState) -> void:
	if party == null:
		return
	for kind: WealthState.Kind in [WealthState.Kind.GOLD, WealthState.Kind.GEMS, WealthState.Kind.JEWELRY]:
		party.banked_wealth.add(kind, party.pooled_wealth.amount(kind))
		party.pooled_wealth.set_amount(kind, 0)


static func wealth_weight(kind: WealthState.Kind) -> int:
	return 15 if kind == WealthState.Kind.JEWELRY else 1


static func classic_transfer_increment(kind: WealthState.Kind) -> int:
	return 5 if kind == WealthState.Kind.GOLD else 1


func take(party: PartyState, amount: int, kind: WealthState.Kind) -> bool:
	if amount < 0:
		return false
	var total_available := party.pooled_wealth.amount(kind)
	for character: CharacterState in party.characters():
		total_available += character.money.amount(kind)
	if amount > total_available:
		return false
	var from_pool := mini(amount, party.pooled_wealth.amount(kind))
	party.pooled_wealth.add(kind, -from_pool)
	var remaining := amount - from_pool
	var characters := party.characters()
	var index := 0
	while remaining > 0:
		var character := characters[index]
		if character.money.amount(kind) > 0:
			character.money.add(kind, -1)
			character.carried_load = maxi(0, character.carried_load - (15 if kind == WealthState.Kind.JEWELRY else 1))
			remaining -= 1
		index = (index + 1) % characters.size()
	return true


func available(party: PartyState, kind: WealthState.Kind) -> int:
	if party == null:
		return 0
	var result := party.pooled_wealth.amount(kind)
	for character: CharacterState in party.characters():
		result += character.money.amount(kind)
	return result


func item_price(item: ItemDefinition, shop: ShopDefinition, selling: bool = false) -> int:
	if item == null or shop == null:
		return 0
	return shop_sell_price(item, null, shop.inflation_percent) if selling else shop_buy_price(item, shop.inflation_percent)


func shop_buy_price(item: ItemDefinition, inflation_percent: int) -> int:
	if item == null:
		return 0
	return mini(32_000, int(float(absi(item.cost) * maxi(0, inflation_percent)) / 100.0))


func shop_sell_price(item: ItemDefinition, instance: ItemInstance, inflation_percent: int) -> int:
	if item == null:
		return 0
	var current_charges := item.initial_charges if instance == null else instance.charges
	var condition := 1.0
	if item.initial_charges > 0:
		condition = float(current_charges) / float(item.initial_charges)
	# Castle divides current charges by authored charges. A literal 0/0 reaches
	# nonportable float-to-short conversion; uncharged items retain full condition.
	var half_cost := absi(item.cost) / 2
	var conditioned_cost := absi(int(float(half_cost) * condition))
	var price := mini(32_000, int(float(conditioned_cost * mini(maxi(0, inflation_percent), 100)) / 100.0))
	if instance != null and not instance.identified:
		price /= 50
	return maxi(0, price)


func roll_treasure(treasure: TreasureDefinition, rng: RealmzRng) -> TreasureRoll:
	return TreasureRoll.new(_roll_signed(treasure.experience, rng, &"treasure.experience"), WealthState.new(_roll_signed(treasure.gold, rng, &"treasure.gold"), _roll_signed(treasure.gems, rng, &"treasure.gems"), _roll_signed(treasure.jewelry, rng, &"treasure.jewelry")), treasure.item_ids())


func _roll_signed(value: int, rng: RealmzRng, tag: StringName) -> int:
	return rng.draw(absi(value), tag) if value < 0 else maxi(0, value)
