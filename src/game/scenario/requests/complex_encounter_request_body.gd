## Carries the detached command surface for a Complex Encounter.

class_name ComplexEncounterRequestBody
extends InteractionRequestBody

var encounter_kind: StringName
var encounter_id: int
var prompt: String
var actions: Array[InteractionRequestValue.EncounterAction] = []
var characters: Array[InteractionRequestValue.NamedCharacter] = []
var items: Array[InteractionRequestValue.EncounterCatalogEntry] = []
var spells: Array[InteractionRequestValue.EncounterCatalogEntry] = []
var can_back_out: bool
var action_selection_count: int


func to_data() -> Dictionary:
	return {"encounterKind": String(encounter_kind), "encounterId": encounter_id, "prompt": prompt, "actions": actions.map(func(value: InteractionRequestValue.EncounterAction) -> Dictionary: return value.to_data()), "characters": characters.map(func(value: InteractionRequestValue.NamedCharacter) -> Dictionary: return value.to_data()), "items": items.map(func(value: InteractionRequestValue.EncounterCatalogEntry) -> Dictionary: return value.to_data()), "spells": spells.map(func(value: InteractionRequestValue.EncounterCatalogEntry) -> Dictionary: return value.to_data()), "canBackOut": can_back_out, "actionSelectionCount": action_selection_count}


func prompt_text() -> String:
	return prompt
