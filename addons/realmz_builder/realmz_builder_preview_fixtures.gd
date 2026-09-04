@tool
## Supplies deterministic detached requests to production UI binders in editor previews.

class_name RealmzBuilderPreviewFixtures
extends RefCounted

const SCREEN_FIXTURES := preload("res://addons/realmz_builder/realmz_builder_screen_preview_fixtures.gd")

const SUPPORTED_SURFACES: Array[String] = [
	"temple",
	"bank",
	"pick-lock",
	"lifecycle-prompts",
	"scrolling-text",
	"level-up",
	"encounter",
	"shop",
	"treasure",
	"combat-command-deck",
]


static func bind(surface: Node, surface_id: String, profile: String) -> bool:
	if SCREEN_FIXTURES.supports(surface_id):
		return SCREEN_FIXTURES.bind(surface, surface_id, profile)
	if surface == null or surface_id not in SUPPORTED_SURFACES or not surface.has_method("build"):
		return false
	var request := _request(surface_id, profile)
	if request == null:
		return false
	_configure(surface, surface_id, profile)
	surface.call("build", request)
	surface.set_meta("realmz_builder_profile", profile)
	return true


static func _configure(surface: Node, surface_id: String, profile: String) -> void:
	var compact := profile == "Compact"
	match surface_id:
		"temple": surface.call("configure", null, compact)
		"bank": surface.call("configure", compact)
		"pick-lock", "scrolling-text": surface.call("configure", null)
		"level-up": surface.call("configure", null, null)
		"encounter": surface.call("configure", null, null, compact)
		"shop": surface.call("configure", null, compact)
		"treasure": surface.call("configure", null, null, compact)
		"combat-command-deck": surface.call("configure", {}, 1.0)


static func _request(surface_id: String, profile: String) -> InteractionRequest:
	match surface_id:
		"temple": return InteractionRequest.new("builder.temple", InteractionRequest.TEMPLE, _temple_body(profile))
		"bank": return InteractionRequest.new("builder.bank", InteractionRequest.BANK, _bank_body(profile))
		"pick-lock": return InteractionRequest.new("builder.pick-lock", InteractionRequest.PICK_LOCK, _pick_lock_body(profile))
		"lifecycle-prompts": return InteractionRequest.new("builder.lifecycle", InteractionRequest.SESSION_LIFECYCLE, _lifecycle_body(profile))
		"scrolling-text": return InteractionRequest.new("builder.scrolling-text", InteractionRequest.ACKNOWLEDGE, _scrolling_text_body(profile))
		"level-up": return InteractionRequest.new("builder.level-up", InteractionRequest.LEVEL_UP, _level_up_body(profile))
		"encounter": return InteractionRequest.new("builder.encounter", InteractionRequest.WORD_AND_ACTION, _encounter_body(profile))
		"shop": return InteractionRequest.new("builder.shop", InteractionRequest.SHOP, _shop_body(profile))
		"treasure": return InteractionRequest.new("builder.treasure", InteractionRequest.TREASURE_DISTRIBUTION, _treasure_body(profile))
		"combat-command-deck": return InteractionRequest.new("builder.combat", InteractionRequest.COMBAT, _combat_body(profile))
	return null


static func _temple_body(profile: String) -> TempleRequestBody:
	var body := TempleRequestBody.new()
	body.cost_percent = 115
	body.pooled_wealth = _wealth(740, 4, 1)
	body.bank_available = true
	if profile != "Empty":
		body.characters = _characters(profile, false)
		body.services = _temple_services(profile)
		body.selected_character_id = body.characters[0].id
	return body


static func _bank_body(profile: String) -> BankRequestBody:
	var body := BankRequestBody.new()
	body.mode = &"bank"
	body.has_mode = true
	body.pooled_wealth = _wealth(740, 4, 1)
	body.banked_wealth = _wealth(2800, 12, 3)
	body.pool = _availability(profile != "Unavailable", "The party cannot pool wealth during this preview state.")
	body.share = _availability(profile != "Unavailable", "No adventurer can receive a share during this preview state.")
	if profile != "Empty":
		body.characters = _characters(profile, true)
		body.selected_character_id = body.characters[0].id
	return body


static func _characters(profile: String, include_transfers: bool) -> Array[InteractionRequestValue.ServiceCharacter]:
	var names: Array[String] = ["Kevlar", "Lothlorian", "Silver Leaf", "Traskelion", "Trevor", "Vormale"]
	var count := names.size() if profile == "Long Content" else 2
	var result: Array[InteractionRequestValue.ServiceCharacter] = []
	for index: int in count:
		var character := InteractionRequestValue.ServiceCharacter.new()
		character.id = "builder.character.%d" % index
		character.name = names[index]
		character.current_health = 18 + index * 3
		character.maximum_health = 42 + index * 4
		character.personal_gold = 80 + index * 25
		character.available_gold = 0 if profile == "Unavailable" else 820 + index * 60
		character.load = 440 + index * 45
		character.maximum_load = 1800 + index * 100
		character.wealth = _wealth(character.personal_gold, index + 1, index % 2)
		if index == 0:
			character.conditions.append(_condition(6, "Poisoned", 3))
			character.conditions.append(_condition(10, "Cursed", 1))
		if include_transfers:
			character.transfers = _transfers(profile)
		result.append(character)
	return result


static func _temple_services(profile: String) -> Array[InteractionRequestValue.TempleService]:
	var labels: Array[String] = ["Heal Wounds", "Cure Poison", "Remove Curse", "Restore Life", "Purify Spirit", "Renew Strength"]
	var count := labels.size() if profile == "Long Content" else 3
	var result: Array[InteractionRequestValue.TempleService] = []
	for index: int in count:
		var service := InteractionRequestValue.TempleService.new()
		service.id = "builder.service.%d" % index
		service.label = labels[index]
		service.description = (
			"The temple attendants explain the rite, its limits, and the exact offering required before the party proceeds."
			if profile == "Long Content"
			else "A source-priced temple service for the selected adventurer."
		)
		service.cost = 9999 if profile == "Unavailable" else 75 + index * 125
		result.append(service)
	return result


static func _transfers(profile: String) -> Array[InteractionRequestValue.Transfer]:
	var result: Array[InteractionRequestValue.Transfer] = []
	for denomination: StringName in [&"gold", &"gems", &"jewelry"]:
		var transfer := InteractionRequestValue.Transfer.new()
		transfer.denomination = denomination
		transfer.amount = 100 if denomination == &"gold" else 1
		transfer.to_pool = _availability(profile != "Unavailable", "The selected wealth cannot enter the pool.")
		transfer.to_character = _availability(profile != "Unavailable", "The selected adventurer has reached the load limit.")
		result.append(transfer)
	return result


static func _pick_lock_body(profile: String) -> PickLockRequestBody:
	var body := PickLockRequestBody.new()
	body.encounter_id = 19
	body.action_index = 6
	body.action_label = "Pick Lock" if profile != "Error" else "Mechanism unavailable"
	body.character_id = "builder.character.0"
	body.character_name = "Kevlar"
	body.chance_percent = 63 if profile != "Unavailable" else 0
	body.yellow_threshold = 18
	body.green_threshold = 24
	body.frame_rate = 12
	body.time_limit_frames = 48
	var tumbler_count := 6 if profile == "Long Content" else 3
	for frame_index: int in 49:
		var frame: Array = []
		for tumbler_index: int in tumbler_count:
			frame.append(mini(28, 3 + tumbler_index * 2 + frame_index / 3))
		body.frames.append(frame)
	return body


static func _lifecycle_body(profile: String) -> LifecycleRequestBody:
	var body := LifecycleRequestBody.new()
	body.operation = &"end-adventure"
	body.prompt = "The company is about to end this adventure."
	body.has_active_session = true
	body.includes_active_session = true
	body.in_combat = profile == "Unavailable"
	if profile != "Empty":
		body.options.append(_lifecycle_option(&"save-and-end", "Save and End Adventure"))
		body.options.append(_lifecycle_option(&"end-without-saving", "End Without Saving"))
		body.options.append(_lifecycle_option(&"cancel", "Return to the Realm"))
	return body


static func _scrolling_text_body(profile: String) -> AcknowledgeRequestBody:
	var body := AcknowledgeRequestBody.new()
	body.presentation = &"classic-scrolling-text"
	body.has_presentation = true
	body.prompt = "" if profile == "Empty" else (
		"The archivist could not recover this account. Return when the missing volume has been restored."
		if profile == "Error"
		else "A Chronicle of the Realm\n\nThe road bends north beneath a cold and watchful moon.\n\n" + "Company records, field notes, and travelers' warnings fill the remaining pages.\n".repeat(12)
		if profile == "Long Content"
		else "A Chronicle of the Realm\n\nThe road bends north beneath a cold and watchful moon."
	)
	return body


static func _level_up_body(profile: String) -> LevelUpRequestBody:
	var body := LevelUpRequestBody.new()
	body.mode = &"unknown" if profile == "Error" else &"spell-selection"
	body.prompt = "Choose the spells Kevlar will learn."
	body.character_id = "builder.character.0"
	body.character_name = "Kevlar"
	body.point_total = 2 if profile == "Unavailable" else 6
	if profile != "Empty" and profile != "Error":
		var spell_count := 12 if profile == "Long Content" else 4
		for index: int in spell_count:
			body.spells.append(_spell_choice(index, profile == "Unavailable"))
	return body


static func _encounter_body(profile: String) -> ComplexEncounterRequestBody:
	var body := ComplexEncounterRequestBody.new()
	body.encounter_kind = &"complex"
	body.encounter_id = 42
	body.prompt = "A wary gatekeeper bars the road and awaits the company's answer."
	body.can_back_out = true
	body.action_selection_count = 2
	if profile == "Empty" or profile == "Error":
		return body
	var choice_count := 8 if profile == "Long Content" else 3
	for index: int in choice_count:
		body.actions.append(_encounter_action("choice.%d" % index, &"choice", "Authored response %d" % (index + 1), index))
	for spec: Array in [["word", &"word", "Speak"], ["item", &"item", "Use Item"], ["spell", &"spell", "Cast Spell"], ["thief", &"thief", "Use Skill"], ["back", &"back", "Stop"]]:
		body.actions.append(_encounter_action(spec[0], spec[1], spec[2]))
	body.items.append(_encounter_catalog_item())
	body.spells.append(_encounter_catalog_spell())
	if profile == "Unavailable":
		body.items.clear()
		body.spells.clear()
	return body


static func _shop_body(profile: String) -> ShopRequestBody:
	var body := ShopRequestBody.new()
	body.shop_id = "builder.shop.0"
	body.inflation_percent = 110
	body.party_gold = 1240
	body.identify_price = 75
	body.accept_ranges.assign([1, 999])
	if profile == "Empty" or profile == "Error":
		return body
	body.characters = _characters(profile, false)
	for index: int in body.characters.size():
		body.characters[index].inventory.append(_inventory_item(index, profile == "Unavailable"))
	var stock_count := 12 if profile == "Long Content" else 4
	for index: int in stock_count:
		body.stock.append(_shop_stock(index, profile == "Unavailable"))
	return body


static func _treasure_body(profile: String) -> TreasureRequestBody:
	var body := TreasureRequestBody.new()
	body.mode = &"malformed" if profile == "Error" else &"ordinary"
	body.prompt = "The company has the pick of the recovered equipment."
	body.origin = &"battle"
	body.wealth = _wealth(850, 3, 1)
	body.has_share_capacity = profile != "Unavailable"
	if profile == "Error":
		return body
	body.characters = _reward_characters(profile)
	if profile != "Empty":
		var item_count := 14 if profile == "Long Content" else 4
		for index: int in item_count:
			body.items.append(_reward_item(index, body.characters, profile == "Unavailable"))
	body.has_items = true
	return body


static func _combat_body(profile: String) -> CombatRequestBody:
	var body := CombatRequestBody.new()
	body.battle_id = "builder.battle.46"
	body.round_number = 3
	body.actor_id = "builder.character.0"
	body.attack_units_remaining = 2
	body.movement_remaining = 5
	body.enemies_remaining = 3
	body.weapon_mode = &"melee"
	body.weapon_switch = _availability(profile != "Unavailable", "No alternate weapon is ready.")
	body.ranged_attack = _availability(profile != "Unavailable", "No missile weapon is ready.")
	body.retreat = _availability(profile != "Unavailable", "The company cannot retreat from this battle.")
	body.auto_turn = _availability(profile != "Unavailable", "Auto Turn is unavailable.")
	body.delay = _availability(profile != "Unavailable", "This combatant cannot delay.")
	body.bandage = _availability(profile != "Unavailable", "No bandage action is available.")
	body.turn_undead = _availability(profile != "Unavailable", "No undead are present.")
	body.undo = _availability(profile != "Unavailable", "There is no action to undo.")
	if profile == "Empty" or profile == "Error":
		return body
	body.actions.assign(["switch_weapon", "defend", "attack", "finish", "cast_spell", "use_item", "use_scroll", "retreat"])
	body.combatants = _combatants(profile)
	body.targets = _combat_targets(profile)
	body.bandage_targets = _combat_targets(profile)
	body.spell_casts.append(_cast_option(&"spell", "Flame Bolt"))
	body.item_casts.append(_cast_option(&"item", "Wand of Frost"))
	body.scroll_casts.append(_cast_option(&"scroll", "Protection"))
	return body


static func _spell_choice(index: int, unavailable: bool) -> InteractionRequestValue.SpellChoice:
	var spell := InteractionRequestValue.SpellChoice.new()
	spell.id = "builder.spell.%d" % index
	spell.name = ["Bless", "Flame Bolt", "Heal", "Shield", "Web", "Silence"][index % 6]
	spell.description = "A source-backed spell record presented through the ordinary level-up binder."
	spell.classic_id = 1101 + (index % 3) * 100 + index
	spell.cost = 8 if unavailable else 1 + index % 3
	spell.selected = index == 0 and not unavailable
	return spell


static func _encounter_action(id: String, kind: StringName, label: String, slot: int = -1) -> InteractionRequestValue.EncounterAction:
	var action := InteractionRequestValue.EncounterAction.new()
	action.id = id
	action.kind = kind
	action.label = label
	action.slot = slot
	return action


static func _encounter_catalog_item() -> InteractionRequestValue.EncounterCatalogEntry:
	var item := InteractionRequestValue.EncounterCatalogEntry.new()
	item.classic_id = 209
	item.name = "Silver Horn"
	item.kind = &"item"
	item.character_id = "builder.character.0"
	item.instance_id = "builder.item.0"
	item.charges = 3
	return item


static func _encounter_catalog_spell() -> InteractionRequestValue.EncounterCatalogEntry:
	var spell := InteractionRequestValue.EncounterCatalogEntry.new()
	spell.classic_id = 1101
	spell.name = "Bless"
	spell.kind = &"spell"
	spell.character_id = "builder.character.0"
	return spell


static func _inventory_item(index: int, unavailable: bool) -> InteractionRequestValue.InventoryItem:
	var item := InteractionRequestValue.InventoryItem.new()
	item.instance_id = "builder.inventory.%d" % index
	item.item_id = "classic.item.%d" % (800 + index)
	item.name = ["Longsword", "Shield", "Iron Rations", "Wand"][index % 4]
	item.identified = index % 2 == 0
	item.equipped = index < 2
	item.sell_price = 120 + index * 30
	item.can_sell = not unavailable
	item.sell_reason = "The shopkeeper will not buy this item." if unavailable else ""
	item.can_identify = not unavailable and not item.identified
	item.identify_reason = "This item cannot be identified here." if unavailable else ""
	item.description = "A carried item resolved through the active application and scenario catalogs."
	item.weight = 25
	return item


static func _shop_stock(index: int, unavailable: bool) -> InteractionRequestValue.ShopStock:
	var stock := InteractionRequestValue.ShopStock.new()
	stock.stock_key = "builder.stock.%d" % index
	stock.index = index
	stock.item_id = "classic.item.%d" % (810 + index)
	stock.name = ["Broadsword", "Chain Armor", "Healing Draught", "Torch"][index % 4]
	stock.quantity = 8 - index % 4
	stock.buy_price = 180 + index * 45
	stock.can_buy = not unavailable
	stock.buy_reason = "The company cannot afford this item." if unavailable else ""
	stock.category = [&"weapons", &"armor", &"magic", &"supplies"][index % 4]
	stock.description = "Ordinary shop stock bound through the production ledger."
	stock.weight = 30
	return stock


static func _reward_characters(profile: String) -> Array[InteractionRequestValue.RewardCharacter]:
	var result: Array[InteractionRequestValue.RewardCharacter] = []
	var count := 6 if profile == "Long Content" else 2
	for index: int in count:
		var character := InteractionRequestValue.RewardCharacter.new()
		character.id = "builder.character.%d" % index
		character.name = ["Kevlar", "Lothlorian", "Silver Leaf", "Traskelion", "Trevor", "Vormale"][index]
		character.enabled = profile != "Unavailable"
		character.reason = "This adventurer cannot carry another item." if not character.enabled else ""
		character.wealth = _wealth(40 + index * 10, index % 3, 0)
		character.can_take_gold = character.enabled
		character.can_take_gems = character.enabled
		character.can_take_jewelry = character.enabled
		character.maximum_load = 1800
		character.carried_load = 500 + index * 40
		result.append(character)
	return result


static func _reward_item(index: int, characters: Array[InteractionRequestValue.RewardCharacter], unavailable: bool) -> InteractionRequestValue.RewardItem:
	var item := InteractionRequestValue.RewardItem.new()
	item.instance_id = "builder.reward.%d" % index
	item.definition_id = "classic.item.%d" % (850 + index)
	item.name = ["Jeweled Sword", "Silver Shield", "Potion", "Ancient Scroll"][index % 4]
	item.charges = index % 5
	item.identified = index % 2 == 0
	item.magical = index % 3 == 0
	item.has_magical = true
	item.has_assignments = true
	item.description = "Spoils recovered from the field and ready for assignment."
	for character: InteractionRequestValue.RewardCharacter in characters:
		var assignment := InteractionRequestValue.RewardAssignment.new()
		assignment.character_id = character.id
		assignment.enabled = not unavailable
		assignment.reason = "No recipient has enough carrying capacity." if unavailable else ""
		item.assignments.append(assignment)
	return item


static func _combatants(profile: String) -> Array[InteractionRequestValue.Combatant]:
	var result: Array[InteractionRequestValue.Combatant] = []
	var count := 8 if profile == "Long Content" else 4
	for index: int in count:
		var combatant := InteractionRequestValue.Combatant.new()
		combatant.id = "builder.character.0" if index == 0 else "builder.combatant.%d" % index
		combatant.kind = &"party" if index < 2 else &"monster"
		combatant.name = ["Kevlar", "Silver Leaf", "Goblin Archer", "Goblin Shaman"][index % 4]
		combatant.current_health = 18 + index * 2
		combatant.maximum_health = 42 + index * 3
		combatant.armor = 8 + index
		combatant.magic_resistance = 5 + index
		combatant.attacks = "2"
		combatant.movement = 4
		combatant.maximum_movement = 6
		combatant.attack_rows.assign(["Longsword • 1d8", "Shield bash • 1d4"])
		result.append(combatant)
	return result


static func _combat_targets(profile: String) -> Array[InteractionRequestValue.CombatTarget]:
	var result: Array[InteractionRequestValue.CombatTarget] = []
	var count := 6 if profile == "Long Content" else 2
	for index: int in count:
		var target := InteractionRequestValue.CombatTarget.new()
		target.id = "builder.combatant.%d" % (index + 2)
		target.kind = &"monster"
		target.name = "Goblin %d" % (index + 1)
		target.current_health = 12 + index
		target.maximum_health = 20
		result.append(target)
	return result


static func _cast_option(source_kind: StringName, name: String) -> InteractionRequestValue.CastOption:
	var option := InteractionRequestValue.CastOption.new()
	option.source_kind = source_kind
	option.spell_id = "builder.spell.%s" % source_kind
	option.spell_name = name
	option.power = 4
	option.cost = 3
	option.target_id = "builder.combatant.2"
	option.target_name = "Goblin Archer"
	option.target_current_health = 14
	option.target_maximum_health = 20
	option.target_mode = &"automatic"
	option.item_instance_id = "builder.item.wand"
	option.item_id = "classic.item.900"
	option.item_name = name
	option.charges = 4
	option.scroll_slot = 0
	return option


static func _wealth(gold: int, gems: int, jewelry: int) -> InteractionRequestValue.Wealth:
	var wealth := InteractionRequestValue.Wealth.new()
	wealth.gold = gold
	wealth.gems = gems
	wealth.jewelry = jewelry
	return wealth


static func _availability(enabled: bool, reason: String) -> InteractionRequestValue.Availability:
	var availability := InteractionRequestValue.Availability.new()
	availability.enabled = enabled
	availability.reason = "" if enabled else reason
	return availability


static func _condition(index: int, label: String, value: int) -> InteractionRequestValue.Condition:
	var condition := InteractionRequestValue.Condition.new()
	condition.index = index
	condition.name = label
	condition.value = value
	return condition


static func _lifecycle_option(action: StringName, label: String) -> InteractionRequestValue.LifecycleOption:
	var option := InteractionRequestValue.LifecycleOption.new()
	option.action = action
	option.label = label
	return option
