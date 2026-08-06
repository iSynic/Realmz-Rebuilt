class_name EconomyRules
extends RefCounted


func pool_party_wealth(party: PartyState) -> void:
	for character: CharacterState in party.characters():
		party.pooled_wealth.gold += character.money.gold
		party.pooled_wealth.gems += character.money.gems
		party.pooled_wealth.jewelry += character.money.jewelry
		character.carried_load = maxi(0, character.carried_load - character.money.gold - character.money.gems - character.money.jewelry * 15)
		character.money = WealthState.new()


func take(party: PartyState, amount: int, kind: WealthState.Kind) -> bool:
	if amount < 0:
		return false
	var available := party.pooled_wealth.amount(kind)
	for character: CharacterState in party.characters():
		available += character.money.amount(kind)
	if amount > available:
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


func item_price(item: ItemDefinition, shop: ShopDefinition, selling: bool = false) -> int:
	var multiplier := shop.inflation_percent
	if selling and multiplier > 100:
		multiplier = 100
	return mini(32_000, int(float(absi(item.cost) * multiplier) / 100.0))


func roll_treasure(treasure: TreasureDefinition, rng: RealmzRng) -> TreasureRoll:
	return TreasureRoll.new(_roll_signed(treasure.experience, rng, &"treasure.experience"), WealthState.new(_roll_signed(treasure.gold, rng, &"treasure.gold"), _roll_signed(treasure.gems, rng, &"treasure.gems"), _roll_signed(treasure.jewelry, rng, &"treasure.jewelry")), treasure.item_ids())


func _roll_signed(value: int, rng: RealmzRng, tag: StringName) -> int:
	return rng.draw(absi(value), tag) if value < 0 else maxi(0, value)
