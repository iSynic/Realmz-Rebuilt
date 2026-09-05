## Carries an exact character target selection for scenario or spell work.

class_name CharacterSelectionRequestBody
extends InteractionRequestBody

var prompt: String
var count: int = 1
var eligible: Array[InteractionRequestValue.SelectionCandidate] = []
var allow_dead: bool
var mode: StringName
var item_instance_id: String
var spell_id: String
var scroll_slot: int = -1
var spell_context: InteractionRequestValue.SpellTargetContext


func to_data() -> Dictionary:
	var data := {"count": count, "eligible": eligible.map(func(value: InteractionRequestValue.SelectionCandidate) -> Dictionary: return value.to_data())}
	if not prompt.is_empty(): data["prompt"] = prompt
	if allow_dead: data["allowDead"] = true
	if not mode.is_empty(): data["mode"] = String(mode)
	if not item_instance_id.is_empty(): data["itemInstanceId"] = item_instance_id
	if not spell_id.is_empty(): data["spellId"] = spell_id
	if scroll_slot >= 0: data["scrollSlot"] = scroll_slot
	if spell_context != null: data["spellContext"] = spell_context.to_data()
	return data


func prompt_text() -> String:
	return prompt
