## Retains required combat work separately from the committed feedback events.
class_name CombatPendingOperations
extends RefCounted

var death_macro: CombatDeathMacroRequest
var age_updates: Array[AgeUpdateRequestBody] = []


func finish_death_macro(combatant_id: String) -> String:
	if death_macro == null: return combatant_id
	if combatant_id.is_empty(): combatant_id = death_macro.combatant_id
	if death_macro.combatant_id == combatant_id: death_macro = null
	return combatant_id


func to_data() -> Dictionary:
	return {"deathMacro":null if death_macro == null else death_macro.to_data(),"ageUpdates":age_updates.map(func(update: AgeUpdateRequestBody) -> Dictionary: return update.to_data())}


static func from_data(value: Variant) -> CombatPendingOperations:
	if not value is Dictionary: return null
	var data: Dictionary = value
	if data.size() != 2 or not data.has_all(["deathMacro","ageUpdates"]) or not data["ageUpdates"] is Array: return null
	var result := CombatPendingOperations.new()
	if data["deathMacro"] != null:
		result.death_macro = CombatDeathMacroRequest.from_data(data["deathMacro"])
		if result.death_macro == null or result.death_macro.macro_id == 0: return null
	var updates: Array = data["ageUpdates"]
	if updates.size() > 6: return null
	for raw: Variant in updates:
		if not raw is Dictionary: return null
		var payload: Dictionary = raw
		var request := InteractionRequest.from_payload("combat.age-copy", InteractionRequest.AGE_UPDATE, payload)
		if request == null or not request.body is AgeUpdateRequestBody: return null
		result.age_updates.append(request.body as AgeUpdateRequestBody)
	return result
