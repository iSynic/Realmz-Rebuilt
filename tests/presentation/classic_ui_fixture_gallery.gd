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
	InteractionRequest.SHOP,
	InteractionRequest.TEMPLE,
	InteractionRequest.BANK,
	InteractionRequest.COMBAT,
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
				"ageGroup": 2,
				"ageGroupName": "Young",
				"ageMinimumYears": 20,
				"ageMaximumYears": 39,
				"transition": 1,
				"appliedAgeGroup": 2,
				"changes": [1, 0, -1, 2, 0, 0, 5, -1, 1, 2, 3, 4, 5, 6, 7],
				"presentation": "classic-age-update",
				"soundId": 3002,
			})
		InteractionRequest.YES_NO:
			payload.merge({"yesLabel": "Yes", "noLabel": "No"})
		InteractionRequest.INDEXED_CHOICE, InteractionRequest.ENCOUNTER_CHOICE:
			payload.merge({"options": [] if empty_values else [{"label": "Proceed"}], "canBackOut": true})
		InteractionRequest.CHARACTER_SELECTION:
			payload.merge({"count": 1, "eligible": characters})
		InteractionRequest.ALLY_SELECTION:
			payload.merge({"maximum": 1, "selectedIds": [], "candidates": characters})
		InteractionRequest.TREASURE_DISTRIBUTION:
			payload = _treasure_payload(state, long_text)
		InteractionRequest.LEVEL_UP:
			payload = _level_payload(state, long_text)
		InteractionRequest.WORD_AND_ACTION:
			payload.merge({"actions": [] if empty_values else [{"kind": "choice", "label": "Proceed", "slot": 0}, {"kind": "word", "label": "Speak"}], "characters": characters, "items": [], "spells": []})
		InteractionRequest.SHOP:
			payload.merge({"inflationPercent": 100, "partyGold": 25, "identifyPrice": 20, "characters": characters, "stock": [] if empty_values else [{"stockKey": "base:0", "index": 0, "name": "Potion", "buyPrice": 10, "quantity": 1, "canBuy": true, "buyReason": ""}]})
		InteractionRequest.TEMPLE:
			payload["characters"] = characters
		InteractionRequest.BANK:
			payload.merge({"carriedGold": 25, "bankedGold": 10})
		InteractionRequest.COMBAT:
			payload.merge({
				"round": 1,
				"actorId": "hero",
				"actions": [] if empty_values else ["attack", "use_item", "finish"],
				"targets": [] if empty_values else [{"id": "monster", "name": "Goblin", "currentHealth": 4, "maximumHealth": 4}],
				"itemCasts": [] if empty_values else [{"itemInstanceId": "wand.instance", "itemId": "classic.item.41", "itemName": "Runed Wand", "charges": 3, "spellId": "classic.spell.1101", "spellName": "Flame", "power": 2, "targetId": "monster", "targetName": "Goblin", "targetCurrentHealth": 4, "targetMaximumHealth": 4, "targetMode": "combatant"}],
				"itemCastReason": "No carried item has a supported Classic combat use." if empty_values else "",
			})
	return InteractionRequest.new("fixture-%s-%s" % [kind, state], kind, payload)


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
		})
	if state == &"missing_media":
		return {
			"prompt": prompt,
			"mode": "fumbled-item-recovery",
			"item": {"instanceId": "item-fumbled", "definitionId": "classic.item.6", "name": "Sting +3", "charges": 7, "identified": true},
			"characters": characters,
			"remaining": 1,
		}
	var has_item := state not in [&"empty", &"loading", &"error"]
	var unidentified := state == &"unidentified"
	return {
		"prompt": prompt,
		"mode": "ordinary",
		"origin": "battle",
		"sourceId": "classic.battle.0",
		"experiencePool": 360,
		"experienceShare": 60,
		"wealth": {"gold": 125 if has_item else 0, "gems": 2 if has_item else 0, "jewelry": 1 if has_item else 0},
		"item": {"instanceId": "reward.item.1", "definitionId": "classic.item.901", "name": "Unknown wand" if unidentified else "Fixture Wand", "charges": 2, "identified": not unidentified, "magical": unidentified} if has_item else null,
		"remaining": 24 if state == &"oversized" else 1 if has_item else 0,
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
			spells.append({"id": "classic.spell.%d" % (1001 + index), "name": ("A spell with a deliberately extensive display name %d" % (index + 1)) if state == &"oversized" else "Spell %d" % (index + 1), "classicId": 1001 + index, "cost": 1 + index % 6, "selected": index == 0})
		return {"prompt": prompt, "mode": "spell-selection", "characterId": "hero", "characterName": "A deliberately long spellcaster name" if state == &"oversized" else "Hero", "pointTotal": 18, "spells": spells}
	if state in [&"empty", &"loading", &"error", &"unavailable"]:
		return {"prompt": prompt, "mode": "result", "characterId": "", "characterName": "", "level": 0, "gains": {}}
	return {"prompt": prompt, "mode": "result", "characterId": "hero", "characterName": "Hero", "level": 5, "gains": {"stamina": 8, "spellPoints": 3, "toHit": 2, "magicResistance": 1}}
