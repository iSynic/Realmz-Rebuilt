class_name ClassicUiFixtureGallery
extends RefCounted

const STATES: Array[StringName] = [&"nominal", &"empty", &"loading", &"error", &"unavailable", &"oversized", &"missing_media", &"unidentified", &"six_member"]
const INTERACTIONS: Array[StringName] = [
	InteractionRequest.ACKNOWLEDGE,
	InteractionRequest.AGE_UPDATE,
	InteractionRequest.YES_NO,
	InteractionRequest.INDEXED_CHOICE,
	InteractionRequest.ENCOUNTER_CHOICE,
	InteractionRequest.CHARACTER_SELECTION,
	InteractionRequest.ALLY_SELECTION,
	InteractionRequest.TREASURE_DISTRIBUTION,
	InteractionRequest.LEVEL_UP,
	InteractionRequest.WORD_AND_ACTION,
	InteractionRequest.PICK_LOCK,
	InteractionRequest.SHOP,
	InteractionRequest.TEMPLE,
	InteractionRequest.BANK,
	InteractionRequest.POOLED_WEALTH_DEPARTURE,
	InteractionRequest.COMBAT,
	InteractionRequest.SESSION_LIFECYCLE,
]

class FixtureCase extends RefCounted:
	var id: String
	var kind: StringName
	var state: StringName
	var oversized_text: String

	func _init(case_id: String, case_kind: StringName, case_state: StringName) -> void:
		id = case_id
		kind = case_kind
		state = case_state
		oversized_text = "A deliberately oversized Realmz presentation fixture. ".repeat(80) if state == &"oversized" else ""


static func screen_cases() -> Array[FixtureCase]:
	var result: Array[FixtureCase] = []
	for route: Dictionary in UiRouteCatalog.ROUTES:
		for state: StringName in STATES:
			result.append(FixtureCase.new("screen:%s:%s" % [route["id"], state], route["id"], state))
	return result


static func interaction_cases() -> Array[FixtureCase]:
	var result: Array[FixtureCase] = []
	for interaction: StringName in INTERACTIONS:
		for state: StringName in STATES:
			result.append(FixtureCase.new("interaction:%s:%s" % [interaction, state], interaction, state))
	return result


static func request_for(kind: StringName, state: StringName = &"nominal") -> InteractionRequest:
	var long_text := "An oversized Classic textbox sentence with wrapping and scroll reachability. ".repeat(40) if state == &"oversized" else "Choose an action."
	var empty_values: bool = state in [&"empty", &"loading", &"error", &"unavailable"]
	var characters: Array = [] if empty_values else [{"id": "hero", "name": "Hero", "currentHealth": 8, "maximumHealth": 10, "inventory": [{"instanceId": "item-1", "name": "Potion", "sellPrice": 5}]}]
	var payload: Dictionary = {"prompt": long_text}
	match kind:
		InteractionRequest.AGE_UPDATE:
			payload.merge({
				"prompt": "Hero has grown into the Young age group.",
				"characterId": "hero",
				"characterName": "A deliberately long adventurer name" if state == &"oversized" else "Hero",
				"raceId": "race.fixture",
				"raceName": "Human",
				"portraitId": "portrait.fixture",
				"combatIconId": "icon.fixture",
				"previousAgeDays": 19 * 365,
				"ageDays": 20 * 365,
				"previousAgeGroup": 1,
				"ageGroup": 2,
				"ageGroupName": "Young",
				"ageMinimumYears": 20,
				"ageMaximumYears": 39,
				"transition": 1,
				"appliedAgeGroup": 2,
				"changes": [1, 0, -1, 2, 0, 0, 5, -1, 1, 2, 3, 4, 5, 6, 7],
				"presentation": "classic-age-update",
				"soundId": 3002,
				"source": "classic",
			}, true)
		InteractionRequest.YES_NO:
			payload.merge({"yesLabel": "Yes", "noLabel": "No"})
		InteractionRequest.INDEXED_CHOICE, InteractionRequest.ENCOUNTER_CHOICE:
			payload.merge({"options": [] if empty_values else [{"label": "Proceed"}], "canBackOut": true})
		InteractionRequest.CHARACTER_SELECTION:
			payload["prompt"] = "Hero casts Magic Darts. Choose one target."; payload.merge({"count": 1, "eligible": [] if empty_values else [{"id": "hero", "name": "Hero", "currentHealth": 8, "maximumHealth": 10}], "mode": "field-spell", "spellId": "classic.spell.1107", "spellContext": {"actorId": "hero", "actorName": "Hero", "spellId": "classic.spell.1107", "spellName": "Magic Darts", "description": "A compact bolt of magical force for one target.", "iconResourceType": "cicn", "iconId": 0, "power": 3, "spellPointCost": 12, "targetType": 1, "targetSize": 0, "targetCount": 1, "sourceKind": "field-spell"}})
		InteractionRequest.ALLY_SELECTION:
			payload.merge({"maximum": 1, "selectedIds": [], "requiredIds": [], "candidates": [] if empty_values else [{"id": "ally", "name": "Allied Knight", "currentHealth": 8, "maximumHealth": 10, "classicMonsterId": 4, "required": false, "canSummon": 0}]})
		InteractionRequest.TREASURE_DISTRIBUTION:
			payload = _treasure_payload(state, long_text)
		InteractionRequest.LEVEL_UP:
			payload = _level_payload(state, long_text)
		InteractionRequest.WORD_AND_ACTION:
			payload.merge({"encounterKind": "complex", "encounterId": 1, "actions": [] if empty_values else [{"id": "choice:0", "kind": "choice", "label": "Bang on the door", "slot": 0}, {"id": "choice:1", "kind": "choice", "label": "Try and force the door", "slot": 1}, {"id": "word", "kind": "word", "label": "Speak"}, {"id": "item", "kind": "item", "label": "Use item"}, {"id": "spell", "kind": "spell", "label": "Cast spell"}, {"id": "thief", "kind": "thief", "label": "Use skill"}, {"id": "back", "kind": "back", "label": "Stop"}], "characters": [] if empty_values else [{"id": "hero", "name": "Hero", "portraitId": "portrait.classic.257"}, {"id": "mage", "name": "Mage", "portraitId": "portrait.classic.258"}], "items": [] if empty_values else [{"classicItemId": 805, "name": "Torch", "characterId": "hero", "instanceId": "torch.1", "iconResourceType": "cicn", "iconId": 805, "charges": 4, "equipped": false}, {"classicItemId": 6110, "name": "Runed wand", "characterId": "mage", "instanceId": "wand.1", "iconResourceType": "cicn", "iconId": 6110, "charges": 7, "equipped": true}], "spells": [] if empty_values else [{"classicSpellId": 1107, "name": "Magic Darts", "characterId": "hero"}, {"classicSpellId": 1306, "name": "Brimstones", "characterId": "mage"}], "canBackOut": true, "actionSelectionCount": 1})
		InteractionRequest.THIEF_ENCOUNTER:
			payload.merge({"encounterId": 1, "prompt": "Choose who will examine the mechanism.", "soundId": 0, "characters": [] if empty_values else [{"id": "hero", "name": "Hero", "portraitId": "portrait.fixture", "actions": [{"index": 0, "label": "Pick Lock", "value": 42, "enabled": true, "reason": ""}, {"index": 1, "label": "Disarm Trap", "value": 31, "enabled": true, "reason": ""}, {"index": 2, "label": "Climb", "value": 18, "enabled": false, "reason": "This action is unavailable here."}]}]})
		InteractionRequest.PICK_LOCK:
			var frames: Array[Array] = []
			for frame_index: int in 21:
				frames.append([40 + frame_index * 4, 72 + frame_index * 3, 104 + frame_index * 2])
			payload = {"encounterId": 1, "actionIndex": 2, "actionLabel": "Pick Lock", "characterId": "hero", "characterName": "Hero", "portraitId": "portrait.fixture", "chancePercent": 55, "yellowThreshold": 90, "greenThreshold": 145, "frameRate": 20, "timeLimitFrames": 40, "frames": frames}
		InteractionRequest.SHOP:
			payload = _shop_payload(empty_values)
		InteractionRequest.TEMPLE:
			payload = _temple_payload(empty_values)
		InteractionRequest.BANK, InteractionRequest.POOLED_WEALTH_DEPARTURE:
			payload = {
				"mode": "departure" if kind == InteractionRequest.POOLED_WEALTH_DEPARTURE else "bank",
				"selectedCharacterId": "hero",
				"pooledWealth": {"gold": 25, "gems": 2, "jewelry": 1},
				"bankedWealth": {"gold": 0, "gems": 0, "jewelry": 0},
				"pool": {"enabled": not empty_values, "reason": "No adventurer carries wealth to pool." if empty_values else ""},
				"share": {"enabled": not empty_values and state != &"capacity-blocked", "reason": "No adventurer can carry another pooled denomination." if state == &"capacity-blocked" else "The party wealth pool is empty." if empty_values else ""},
				"actions": ["pool", "share", "transfer", "leave"],
				"characters": [] if empty_values else [{"id": "hero", "name": characters[0].get("name", "Hero"), "wealth": {"gold": 5, "gems": 1, "jewelry": 0}, "load": 6, "maximumLoad": 20, "transfers": [
					{"denomination": "gold", "amount": 5, "toPool": {"enabled": true, "reason": ""}, "toCharacter": {"enabled": true, "reason": ""}},
					{"denomination": "gems", "amount": 1, "toPool": {"enabled": true, "reason": ""}, "toCharacter": {"enabled": true, "reason": ""}},
					{"denomination": "jewelry", "amount": 1, "toPool": {"enabled": false, "reason": "The character carries no jewelry."}, "toCharacter": {"enabled": state != &"capacity-blocked", "reason": "The character cannot carry that denomination." if state == &"capacity-blocked" else ""}},
				]}],
			}
		InteractionRequest.COMBAT:
			payload = _combat_payload(empty_values)
		InteractionRequest.SESSION_LIFECYCLE:
			var lifecycle_options: Array[Dictionary] = []
			if not empty_values:
				lifecycle_options.assign([
					{"action": "save-and-end", "label": "Save and end adventure"},
					{"action": "end-without-saving", "label": "End adventure without saving"},
					{"action": "cancel", "label": "Cancel"},
				])
			payload.merge({
				"operation": "end-adventure",
				"inCombat": false,
				"options": lifecycle_options,
			})
	return InteractionRequest.from_payload("fixture-%s-%s" % [kind, state], kind, payload)


static func payload_for(kind: StringName, state: StringName = &"nominal") -> Dictionary:
	var request := request_for(kind, state)
	return {} if request == null else request.body.to_data()


static func _shop_payload(empty_values: bool) -> Dictionary:
	var characters: Array[Dictionary] = []
	var stock: Array[Dictionary] = []
	if not empty_values:
		var names: Array[String] = ["Brom", "Sylva", "Nyx", "Durin", "Pip", "Lyra"]
		for index: int in names.size():
			characters.append({
				"id": "hero-%d" % index,
				"name": names[index],
				"inventory": [
					{"instanceId": "pack-%d-0" % index, "itemId": "classic.item.1", "name": "Long Sword", "sellPrice": 25, "identified": true, "equipped": index == 0, "charges": -1, "canSell": index != 0, "sellReason": "Unequip this item before selling it." if index == 0 else "", "canIdentify": false, "identifyReason": "This item is already identified."},
					{"instanceId": "pack-%d-1" % index, "itemId": "classic.item.40", "name": "Unknown wand", "sellPrice": 8, "identified": false, "equipped": false, "charges": 2, "canSell": true, "sellReason": "", "canIdentify": index != 5, "identifyReason": "Not enough gold." if index == 5 else ""},
				],
			})
		var stock_names: Array[String] = ["Potion", "Long Sword", "Leather Armor", "Holy Water", "Lock Picks", "Runed Wand"]
		for index: int in stock_names.size():
			var affordable := index < 4
			stock.append({"stockKey": "base:%d" % index, "index": index, "itemId": "classic.item.%d" % (index + 1), "name": stock_names[index], "buyPrice": 10 + index * 9, "quantity": 1 + index, "canBuy": affordable, "buyReason": "The party cannot afford this item." if not affordable else ""})
	return {
		"shopId": "classic.shop.0",
		"inflationPercent": 100,
		"partyGold": 25,
		"identifyPrice": 20,
		"characters": characters,
		"stock": stock,
		"acceptRanges": [0, 0, 0, 0, 0, 0],
		"actions": ["buy", "sell", "identify", "leave"],
	}


static func _temple_payload(empty_values: bool) -> Dictionary:
	return {
		"costPercent": 100,
		"selectedCharacterId": "" if empty_values else "hero",
		"pooledWealth": {"gold": 25, "gems": 0, "jewelry": 0},
		"bankAvailable": false,
		"characters": [] if empty_values else [{"id": "hero", "name": "Hero", "portraitId": "portrait.fixture", "currentHealth": 8, "maximumHealth": 10, "personalGold": 25, "availableGold": 50, "load": 6, "maximumLoad": 20, "conditions": []}],
		"services": [] if empty_values else [{"id": "heal-small", "label": "Heal Small Wounds", "description": "Restore stamina.", "cost": 10}],
		"actions": ["service", "pool", "leave"],
	}


static func _combat_payload(empty_values: bool) -> Dictionary:
	var unavailable := {"enabled": false, "reason": "Unavailable."}
	var movement_options: Array[Dictionary] = []
	if not empty_values:
		for direction: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
			movement_options.append({"direction": [direction.x, direction.y], "destination": [45 + direction.x, 45 + direction.y], "cost": 1, "enabled": true, "reasonCode": "", "reason": "", "retreat": false, "forcedRetreat": false, "attackTargetId": "monster" if direction == Vector2i(1, 0) else "", "attackTargetName": "Goblin" if direction == Vector2i(1, 0) else ""})
	return {
		"battleId": "classic.battle.0", "round": 1, "actorId": "hero", "attackUnitsRemaining": 4, "movementRemaining": 8, "enemiesRemaining": 1,
		"actions": [] if empty_values else ["cast_spell", "use_item", "defend", "finish"], "weaponMode": "melee",
		"weaponSwitch": unavailable.duplicate(), "rangedAttack": unavailable.duplicate(), "retreat": {"enabled": false, "reason": "Unavailable.", "nearestEnemyRange": 1},
		"meleeAttackReason": "", "targets": [] if empty_values else [{"id": "monster", "name": "Goblin", "currentHealth": 4, "maximumHealth": 4}],
		"combatants": [] if empty_values else [
			{"id": "hero", "kind": "character", "name": "Hero", "currentHealth": 8, "maximumHealth": 10, "spellPoints": 4, "maximumSpellPoints": 8, "armor": 6, "magicResistance": 10, "attacks": "2", "movement": 8, "maximumMovement": 10, "traitor": false, "helpless": false, "weapon": "Long Sword", "weaponCharges": -1, "conditions": ["Blessed"], "items": ["Long Sword • Equipped", "Potion • Carried • 2 charges"], "attackRows": ["Melee • Long Sword • 1–8 damage • 2 attacks"]},
			{"id": "monster", "kind": "monster", "name": "Goblin", "currentHealth": 4, "maximumHealth": 4, "spellPoints": 0, "maximumSpellPoints": 0, "armor": 2, "magicResistance": 0, "hitDice": 2, "attacks": "1", "movement": 6, "maximumMovement": 6, "traitor": false, "helpless": false, "weapon": "Short Sword", "weaponCharges": -1, "range": 2, "blocked": false, "conditions": [], "items": ["Short Sword • Equipped"], "attackRows": ["Attack 1 • 1–4 damage"], "immunities": [], "vulnerabilities": ["Heat"]},
		],
		"movement": movement_options, "spellCasts": [] if empty_values else [{"spellId": "classic.spell.1309", "spellName": "Plane of Force", "power": 1, "cost": 4, "targetId": "", "targetName": "Choose battlefield point", "targetCurrentHealth": -1, "targetMaximumHealth": -1, "targetMode": "area", "areaShape": 10, "defaultTargetCoordinate": [49, 45], "areaOffsets": [[-3, -1], [-2, -1], [-1, -1], [0, -1], [1, -1], [2, -1], [3, -1], [-3, 0], [-2, 0], [-1, 0], [0, 0], [1, 0], [2, 0], [3, 0]], "areaRotationOffsets": [[[-3, -1], [-2, -1], [-1, -1], [0, -1], [1, -1], [2, -1], [3, -1], [-3, 0], [-2, 0], [-1, 0], [0, 0], [1, 0], [2, 0], [3, 0]], [[3, -3], [2, -2], [3, -2], [1, -1], [2, -1], [0, 0], [1, 0], [-1, 1], [0, 1], [-2, 2], [-1, 2], [-3, 3], [-2, 3]], [[0, -3], [1, -3], [0, -2], [1, -2], [0, -1], [1, -1], [0, 0], [1, 0], [0, 1], [1, 1], [0, 2], [1, 2], [0, 3], [1, 3]], [[-3, -3], [-3, -2], [-2, -2], [-2, -1], [-1, -1], [-1, 0], [0, 0], [0, 1], [1, 1], [1, 2], [2, 2], [2, 3], [3, 3]]], "legalTargetCoordinates": []}], "spellCastReason": "No legal Classic combat spell is available." if empty_values else "", "fastSpells": [],
		"itemCasts": [] if empty_values else [{"itemInstanceId": "wand.instance", "itemId": "classic.item.41", "itemName": "Runed Wand", "charges": 3, "spellId": "classic.spell.1101", "spellName": "Flame", "power": 2, "targetId": "monster", "targetName": "Goblin", "targetCurrentHealth": 4, "targetMaximumHealth": 4, "targetMode": "combatant"}],
		"itemCastReason": "No carried item has a supported Classic combat use." if empty_values else "", "scrollCasts": [], "scrollCastReason": "No scroll is available.",
		"autoTurn": unavailable.duplicate(), "autoCharacterIds": [], "delay": unavailable.duplicate(),
		"bandage": {"enabled": false, "reason": "Unavailable.", "targets": []}, "turnUndead": {"enabled": false, "reason": "Unavailable.", "targets": []}, "undo": unavailable.duplicate(),
	}


static func _treasure_payload(state: StringName, prompt: String) -> Dictionary:
	var character_count := 6 if state in [&"oversized", &"six_member"] else 1
	var characters: Array[Dictionary] = []
	for index: int in character_count:
		var capacity_blocked := state == &"unavailable" or index == character_count - 1 and state == &"oversized"
		characters.append({
			"id": "hero-%d" % index,
			"name": ("An adventurer with an intentionally oversized name %d" % (index + 1)) if state == &"oversized" else "Hero" if character_count == 1 else "Hero %d" % (index + 1),
			"enabled": not capacity_blocked,
			"reason": "Inventory is full." if capacity_blocked else "",
			"wealth": {"gold": 5 if index == 0 else 0, "gems": 1 if index == 1 else 0, "jewelry": 1 if index == 2 else 0},
			"canTakeGold": not capacity_blocked,
			"canTakeGems": not capacity_blocked,
			"canTakeJewelry": not capacity_blocked,
			"goldReason": "The pool has fewer than 5 gold or the character cannot carry it.",
			"gemsReason": "The pool has no gems or the character cannot carry one.",
			"jewelryReason": "The pool has no jewelry or the character cannot carry one.",
			"itemCount": 4 + index,
			"maximumMovement": 12 - mini(index, 4),
			"load": 120 + index * 40,
			"maximumLoad": 2000,
		})
	if state == &"missing_media":
		var recovery_characters: Array[Dictionary] = []
		for index: int in character_count:
			recovery_characters.append({"id": "hero-%d" % index, "name": "Hero" if character_count == 1 else "Hero %d" % (index + 1), "currentHealth": 8, "maximumHealth": 10, "enabled": true, "reason": ""})
		return {
			"prompt": prompt,
			"mode": "fumbled-item-recovery",
			"item": {"instanceId": "item-fumbled", "definitionId": "classic.item.6", "name": "Sting +3", "charges": 7, "identified": true, "iconResourceType": "cicn", "iconId": 6, "description": "A recovered fumbled weapon.", "facts": [{"label": "Weight", "value": "10"}, {"label": "Charges", "value": "7"}]},
			"characters": recovery_characters,
			"remaining": 1,
		}
	var has_item := state not in [&"empty", &"loading", &"error"]
	var unidentified := state == &"unidentified"
	var item_count := 24 if state == &"oversized" else 1 if has_item else 0
	var items: Array[Dictionary] = []
	for item_index: int in item_count:
		var assignments: Array[Dictionary] = []
		for character: Dictionary in characters:
			assignments.append({"characterId": character["id"], "enabled": character["enabled"], "reason": character["reason"]})
		items.append({"instanceId": "reward.item.%d" % (item_index + 1), "definitionId": "classic.item.901", "name": "Unknown wand" if unidentified else "Fixture Wand %d" % (item_index + 1) if item_count > 1 else "Fixture Wand", "charges": 2, "identified": not unidentified, "magical": unidentified, "iconResourceType": "cicn", "iconId": 35 if unidentified else 40, "description": "Specials are unknown." if unidentified else "A compact fixture wand used to verify the Classic treasure inspector.", "facts": [{"label": "Weight", "value": "5"}, {"label": "Damage", "value": "?" if unidentified else "3–8"}, {"label": "Movement", "value": "?" if unidentified else "+2"}, {"label": "Magic resistance", "value": "?" if unidentified else "+5"}, {"label": "Spell points", "value": "?" if unidentified else "+12"}, {"label": "Charges", "value": "?" if unidentified else "2"}], "assignments": assignments})
	return {
		"prompt": prompt,
		"mode": "ordinary",
		"origin": "battle",
		"sourceId": "classic.battle.0",
		"experiencePool": 360,
		"experienceShare": 60,
		"wealth": {"gold": 125 if has_item else 0, "gems": 2 if has_item else 0, "jewelry": 1 if has_item else 0},
		"items": items,
		"remaining": item_count,
		"characters": characters,
		"hasShareCapacity": state != &"unavailable" and not characters.is_empty(),
		"detect": {"visible": unidentified, "casters": [{"id": "hero-0", "name": "Hero 1", "spellPoints": 30, "cost": 5}] if unidentified else [], "reason": "No living caster can detect magic."},
		"identify": {"visible": unidentified, "casters": [{"id": "hero-0", "name": "Hero 1", "spellPoints": 30, "cost": 25}] if unidentified else [], "reason": "No living caster can identify treasure."},
	}


static func _level_payload(state: StringName, prompt: String) -> Dictionary:
	if state in [&"unidentified", &"oversized"]:
		var spell_count := 36 if state == &"oversized" else 4
		var spells: Array[Dictionary] = []
		for index: int in spell_count:
			var classic_id := 1001 + index if state == &"oversized" else 1001 if index == 0 else 1101 + index * 100; spells.append({"id": "classic.spell.%d" % classic_id, "name": ("A spell with a deliberately extensive display name %d" % (index + 1)) if state == &"oversized" else "Spell %d" % (index + 1), "description": "Spell %d carries an exact application-owned description into the learning record." % (index + 1), "classicId": classic_id, "cost": 1 + index % 6, "selected": index == 0})
		return {"prompt": prompt, "mode": "spell-selection", "characterId": "hero", "characterName": "A deliberately long spellcaster name" if state == &"oversized" else "Hero", "pointTotal": 18, "spells": spells}
	if state in [&"empty", &"loading", &"error", &"unavailable"]:
		return {"prompt": prompt, "mode": "result", "characterId": "", "characterName": "", "level": 0, "gains": {"stamina": 0, "spellPoints": 0, "toHit": 0, "magicResistance": 0}}
	return {"prompt": prompt, "mode": "result", "characterId": "hero", "characterName": "Hero", "level": 5, "gains": {"stamina": 8, "spellPoints": 3, "toHit": 2, "magicResistance": 1}}
