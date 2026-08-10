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
