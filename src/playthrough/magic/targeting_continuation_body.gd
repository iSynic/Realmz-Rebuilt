## Carries field item and spell targeting or discard confirmation state.

class_name TargetingContinuationBody
extends SessionContinuationBody

var character_id: String
var instance_id: String
var spell_id: String
var power: int
var target_count: int
var starting_charges: int
var starting_spell_points: int
var scroll_slot: int


func wire_payload(kind: StringName) -> Dictionary:
	if kind == &"drop-item-confirmation":
		return {"kind": String(kind), "characterId": character_id, "instanceId": instance_id}
	if kind == &"scroll-discard-confirmation":
		return {"kind": String(kind), "characterId": character_id, "spellId": spell_id, "power": power, "scrollSlot": scroll_slot}
	var data := {"kind": String(kind), "characterId": character_id, "spellId": spell_id, "power": power, "targetCount": target_count}
	if kind == &"item-use-target-selection":
		data["instanceId"] = instance_id
		data["startingCharges"] = starting_charges
	elif kind == &"field-spell-target-selection":
		data["startingSpellPoints"] = starting_spell_points
	else:
		data["scrollSlot"] = scroll_slot
	return data
