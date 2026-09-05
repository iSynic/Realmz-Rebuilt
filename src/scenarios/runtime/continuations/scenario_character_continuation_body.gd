## Carries Classic character selection or ability-test progress.

class_name ScenarioCharacterContinuationBody
extends ScenarioRuntimeContinuationBody

var count: int
var allow_dead: bool
var invert: bool
var values: Array[int]
var gosub: bool


func wire_payload() -> Dictionary:
	if not values.is_empty():
		return {"values": values.duplicate(), "gosub": gosub}
	return {"count": count, "allowDead": allow_dead, "invert": invert}
