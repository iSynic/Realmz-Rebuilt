## Carries a Classic reward workflow through a scenario VM yield.

class_name ScenarioRewardContinuationBody
extends ScenarioRuntimeContinuationBody

var state: ClassicRewardState


func wire_payload() -> Dictionary:
	return {"state": state.to_data()}
