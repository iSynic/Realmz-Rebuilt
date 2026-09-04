## Creates service-owned scenario runtime continuations.

class_name ScenarioServiceContinuations
extends RefCounted


static func shop(shop_id: String, accept_ranges: Array[int]) -> ScenarioRuntimeContinuation:
	var body := ScenarioServiceContinuationBody.new()
	body.shop_id = shop_id
	body.accept_ranges.assign(accept_ranges)
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_SHOP, body)


static func temple(kind: StringName, cost_percent: int, bank_available: bool, selected_character_id: String) -> ScenarioRuntimeContinuation:
	assert(kind in [ScenarioRuntimeContinuation.CLASSIC_TEMPLE, ScenarioRuntimeContinuation.CLASSIC_TEMPLE_EXIT])
	var body := ScenarioServiceContinuationBody.new()
	body.cost_percent = cost_percent
	body.bank_available = bank_available
	body.selected_character_id = selected_character_id
	return ScenarioRuntimeContinuation.new(kind, body)


static func banking() -> ScenarioRuntimeContinuation:
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_BANKING, ScenarioRuntimeContinuationBody.new())
