## Keeps every item a party carries under its own identity. Each adventure numbers the items it
## hands out from 1 again ("shop.item.1"), while a Character File keeps the identities its items
## had in earlier adventures, so a joining character can carry one the party already holds.

class_name CarriedItemIdentities
extends RefCounted


## Gives every item `character` carries whose identity is in `taken`, or repeats one earlier in
## its own pack, a fresh identity, keeping the order its equipment was put on. Returns how many
## items were renamed.
static func make_unique(character: CharacterState, taken: Array[String]) -> int:
	var used: Dictionary[String, bool] = {}
	for instance_id: String in taken:
		used[instance_id] = true
	var inventory := character.inventory()
	var worn := _worn_in_order(character, inventory)
	var renamed := 0
	var sequence := 0
	for item: ItemInstance in inventory:
		if not used.has(item.id):
			used[item.id] = true
			continue
		sequence += 1
		while used.has("%s.carried.%d" % [character.id, sequence]):
			sequence += 1
		item.id = "%s.carried.%d" % [character.id, sequence]
		used[item.id] = true
		renamed += 1
	if renamed > 0:
		var order: Array[String] = []
		for item: ItemInstance in worn:
			order.append(item.id)
		character.equipment_order.set_exact(order, inventory)
	return renamed


## The equipped items in the order they were put on, matched to the items themselves so the
## order survives a rename even when two of them shared an identity.
static func _worn_in_order(character: CharacterState, inventory: Array[ItemInstance]) -> Array[ItemInstance]:
	var worn: Array[ItemInstance] = []
	for instance_id: String in character.equipment_order.resolved(inventory):
		for item: ItemInstance in inventory:
			if item.equipped and item.id == instance_id and not worn.has(item):
				worn.append(item)
				break
	for item: ItemInstance in inventory:
		if item.equipped and not worn.has(item):
			worn.append(item)
	return worn
