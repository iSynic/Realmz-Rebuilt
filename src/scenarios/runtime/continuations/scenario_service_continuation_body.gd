## Carries Classic shop, temple, or banking interaction state.

class_name ScenarioServiceContinuationBody
extends ScenarioRuntimeContinuationBody

var shop_id: String
var accept_ranges: Array[int]
var cost_percent: int
var bank_available: bool
var selected_character_id: String


func wire_payload() -> Dictionary:
	if not shop_id.is_empty():
		return {"shopId": shop_id, "acceptRanges": accept_ranges.duplicate()}
	return {"costPercent": cost_percent, "bankAvailable": bank_available, "selectedCharacterId": selected_character_id}
