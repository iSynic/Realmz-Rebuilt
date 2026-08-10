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
			var recovery_characters: Array[Dictionary] = []
			for value: Dictionary in characters:
				var recovery_character: Dictionary = value.duplicate(true)
				recovery_character["enabled"] = true
				recovery_character["reason"] = ""
				recovery_characters.append(recovery_character)
			payload.merge({
				"mode": "fumbled-item-recovery",
				"item": {"instanceId": "item-fumbled", "definitionId": "classic.item.6", "name": "Sting +3", "charges": 7, "identified": true},
				"characters": recovery_characters,
				"remaining": 1,
			})
		InteractionRequest.WORD_AND_ACTION:
			payload.merge({"actions": [] if empty_values else [{"kind": "choice", "label": "Proceed", "slot": 0}, {"kind": "word", "label": "Speak"}], "characters": characters, "items": [], "spells": []})
		InteractionRequest.SHOP:
			payload.merge({"inflationPercent": 100, "partyGold": 25, "identifyPrice": 20, "characters": characters, "stock": [] if empty_values else [{"stockKey": "base:0", "index": 0, "name": "Potion", "buyPrice": 10, "quantity": 1, "canBuy": true, "buyReason": ""}]})
		InteractionRequest.TEMPLE:
			payload["characters"] = characters
		InteractionRequest.BANK:
			payload.merge({"carriedGold": 25, "bankedGold": 10})
		InteractionRequest.COMBAT:
			payload.merge({"round": 1, "actorId": "hero", "targets": [] if empty_values else [{"id": "monster", "name": "Goblin", "currentHealth": 4, "maximumHealth": 4}]})
	return InteractionRequest.new("fixture-%s-%s" % [kind, state], kind, payload)
